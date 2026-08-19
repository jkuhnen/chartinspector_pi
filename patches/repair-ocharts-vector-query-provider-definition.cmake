if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()

file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CHART_CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CHART_CPP}")
  message(FATAL_ERROR "Missing ${CHART_CPP}")
endif()

file(READ "${CHART_CPP}" C)

# The previous repair adds PlugInChartBaseExtendedPlus3::QueryVectorObjectsV1,
# so a loose search for QueryVectorObjectsV1 is not sufficient.  Require the
# concrete eSENCChart definition here.
if(C MATCHES "bool[ \t\r\n]+eSENCChart::QueryVectorObjectsV1[ \t\r\n]*\\(")
  message(STATUS "eSENCChart::QueryVectorObjectsV1 definition already present")
  return()
endif()

foreach(INC "#include <algorithm>" "#include <cmath>" "#include <cstring>" "#include <string>" "#include <vector>")
  string(FIND "${C}" "${INC}" IPOS)
  if(IPOS EQUAL -1)
    # Use a stable local include as anchor; repeated insertions are harmlessly
    # avoided by the test above.
    string(REPLACE "#include <unordered_map>" "#include <unordered_map>\n${INC}" C "${C}")
  endif()
endforeach()

set(IMPL [===[

bool eSENCChart::QueryVectorObjectsV1(const PI_VectorQueryV1 *query,
                                      const PlugIn_ViewPort *viewport,
                                      PI_VectorObjectSinkV1 sink,
                                      void *user_data) {
  if (!query || query->struct_size < sizeof(PI_VectorQueryV1) || !viewport ||
      !sink || !std::isfinite(query->lat) || !std::isfinite(query->lon) ||
      !std::isfinite(query->search_radius_pixels) ||
      viewport->view_scale_ppm <= 0.0)
    return false;

  PlugIn_ViewPort vp = *viewport;
  const double radius_pixels =
      std::max(1.0, std::min(query->search_radius_pixels, 64.0));
  const float select_radius = static_cast<float>(
      radius_pixels / (viewport->view_scale_ppm * 1852.0 * 60.0));

  ListOfPI_S57Obj *objects = GetObjRuleListAtLatLon(
      static_cast<float>(query->lat), static_cast<float>(query->lon),
      select_radius, &vp);
  if (!objects) return true;

  bool keep_going = true;
  uint32_t emitted = 0;

  for (auto node = objects->GetFirst(); node && keep_going && emitted < 256;
       node = node->GetNext()) {
    PI_S57Obj *obj = node->GetData();
    if (!obj || !obj->FeatureName[0]) continue;

    uint32_t geometry_type = PI_VECTOR_GEOMETRY_UNKNOWN_V1;
    if (obj->Primitive_type == GEO_POINT)
      geometry_type = PI_VECTOR_GEOMETRY_POINT_V1;
    else if (obj->Primitive_type == GEO_LINE)
      geometry_type = PI_VECTOR_GEOMETRY_LINE_V1;
    else if (obj->Primitive_type == GEO_AREA)
      geometry_type = PI_VECTOR_GEOMETRY_AREA_V1;
    else
      continue;

    std::vector<PI_VectorPositionV1> points;
    std::vector<PI_VectorPartV1> parts;

    if (geometry_type == PI_VECTOR_GEOMETRY_POINT_V1) {
      if (std::isfinite(obj->m_lat) && std::isfinite(obj->m_lon))
        points.push_back({obj->m_lat, obj->m_lon});
    } else if (obj->geoPt && obj->npt >= 2 && obj->npt <= 16384) {
      const pt *source = static_cast<const pt *>(obj->geoPt);
      PI_VectorPartV1 part{};
      part.first_point = 0;
      for (int i = 0; i < obj->npt; ++i) {
        const double east = source[i].x * obj->x_rate + obj->x_origin;
        const double north = source[i].y * obj->y_rate + obj->y_origin;
        double lat = 0.0;
        double lon = 0.0;
        fromSM(east, north, obj->chart_ref_lat, obj->chart_ref_lon, &lat, &lon);
        if (!std::isfinite(lat) || !std::isfinite(lon)) continue;
        points.push_back({lat, lon});
        ++part.point_count;
      }
      if (part.point_count >= 2) parts.push_back(part);
    }

    if (points.empty() ||
        (geometry_type != PI_VECTOR_GEOMETRY_POINT_V1 && parts.empty()))
      continue;

    std::string feature(obj->FeatureName,
                        strnlen(obj->FeatureName, sizeof(obj->FeatureName)));
    if (feature.empty()) continue;

    wxString object_name;
    std::vector<std::string> attr_names;
    std::vector<std::string> attr_values;
    std::vector<PI_VectorAttributeV1> attrs;
    const int attr_count = std::max(0, std::min(obj->n_attr, 512));
    attr_names.reserve(attr_count);
    attr_values.reserve(attr_count);

    if (obj->att_array && obj->attVal) {
      for (int i = 0; i < attr_count; ++i) {
        char acronym[7] = {0};
        memcpy(acronym, obj->att_array + i * 6, 6);
        if (!acronym[0]) continue;
        wxString name = wxString::FromUTF8(acronym);
        wxString value = GetObjectAttributeValueAsString(obj, i, name);
        const wxCharBuffer value_utf8 = value.ToUTF8();
        attr_names.emplace_back(acronym);
        attr_values.emplace_back(value_utf8.data() ? value_utf8.data() : "");
        if (!strcmp(acronym, "OBJNAM") && object_name.IsEmpty())
          object_name = value;
        if (!strcmp(acronym, "NOBJNM") && object_name.IsEmpty())
          object_name = value;
      }
    }

    attrs.reserve(attr_names.size());
    for (size_t i = 0; i < attr_names.size(); ++i)
      attrs.push_back({attr_names[i].c_str(), attr_values[i].c_str()});

    const wxCharBuffer object_name_utf8 = object_name.ToUTF8();
    PI_VectorObjectV1 out{};
    out.struct_size = sizeof(out);
    out.geometry_type = geometry_type;
    out.feature_class_utf8 = feature.c_str();
    out.object_name_utf8 = object_name_utf8.data();
    out.points = points.data();
    out.point_count = static_cast<uint32_t>(points.size());
    out.parts = parts.empty() ? nullptr : parts.data();
    out.part_count = static_cast<uint32_t>(parts.size());
    out.attributes = attrs.empty() ? nullptr : attrs.data();
    out.attribute_count = static_cast<uint32_t>(attrs.size());

    ++emitted;
    keep_going = sink(&out, user_data);
  }

  objects->DeleteContents(true);
  delete objects;
  return true;
}

]===])

string(FIND "${C}" "ListOfPI_S57Obj *eSENCChart::GetObjRuleListAtLatLon" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate GetObjRuleListAtLatLon implementation anchor in ${CHART_CPP}")
endif()

string(SUBSTRING "${C}" 0 ${POS} PRE)
string(SUBSTRING "${C}" ${POS} -1 POST)
file(WRITE "${CHART_CPP}" "${PRE}${IMPL}${POST}")
message(STATUS "Installed concrete eSENCChart::QueryVectorObjectsV1 definition")
