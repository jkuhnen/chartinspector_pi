if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()

file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CHART_CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CHART_CPP}")
  message(FATAL_ERROR "Missing ${CHART_CPP}")
endif()

file(READ "${CHART_CPP}" C)

set(START_MARKER "// VECTOR_QUERY_ACTIVE_PROVIDER_V1")
string(FIND "${C}" "${START_MARKER}" START)
if(START EQUAL -1)
  message(FATAL_ERROR "Active point provider marker not found. Apply repair-ocharts-vector-query-provider-active.cmake first.")
endif()

string(FIND "${C}" "eSENCChart::eSENCChart()" END)
if(END EQUAL -1 OR END LESS START)
  message(FATAL_ERROR "Could not locate eSENCChart constructor after active provider")
endif()

foreach(INC "#include <cstring>" "#include <string>" "#include <vector>")
  string(FIND "${C}" "${INC}" IPOS)
  if(IPOS EQUAL -1)
    string(REPLACE "#include <unordered_map>" "#include <unordered_map>\n${INC}" C "${C}")
    string(FIND "${C}" "${START_MARKER}" START)
    string(FIND "${C}" "eSENCChart::eSENCChart()" END)
  endif()
endforeach()

set(IMPL [===[
// VECTOR_QUERY_ACTIVE_PROVIDER_V1
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
  for (auto node = objects->GetFirst(); node && keep_going;
       node = node->GetNext()) {
    PI_S57Obj *obj = node->GetData();
    if (!obj || !obj->FeatureName[0] || obj->Primitive_type != GEO_POINT)
      continue;
    if (!std::isfinite(obj->m_lat) || !std::isfinite(obj->m_lon))
      continue;

    PI_VectorPositionV1 point{obj->m_lat, obj->m_lon};
    std::string feature(obj->FeatureName,
                        strnlen(obj->FeatureName, sizeof(obj->FeatureName)));
    if (feature.empty()) continue;

    wxString object_name;
    std::vector<std::string> attribute_names;
    std::vector<std::string> attribute_values;
    std::vector<PI_VectorAttributeV1> attributes;

    if (obj->att_array && obj->attVal && obj->n_attr > 0) {
      const int count = std::min(obj->n_attr, 512);
      attribute_names.reserve(count);
      attribute_values.reserve(count);

      for (int i = 0; i < count; ++i) {
        char acronym[7] = {0};
        memcpy(acronym, obj->att_array + i * 6, 6);
        if (!acronym[0]) continue;

        wxString attr_name = wxString::FromUTF8(acronym);
        wxString attr_value = GetObjectAttributeValueAsString(obj, i, attr_name);
        wxCharBuffer value_utf8 = attr_value.ToUTF8();

        attribute_names.emplace_back(acronym);
        attribute_values.emplace_back(value_utf8.data() ? value_utf8.data() : "");

        if ((!strcmp(acronym, "OBJNAM") || !strcmp(acronym, "NOBJNM")) &&
            object_name.IsEmpty() && !attr_value.IsEmpty())
          object_name = attr_value;
      }
    }

    attributes.reserve(attribute_names.size());
    for (size_t i = 0; i < attribute_names.size(); ++i)
      attributes.push_back({attribute_names[i].c_str(), attribute_values[i].c_str()});

    wxCharBuffer object_name_utf8 = object_name.ToUTF8();

    PI_VectorObjectV1 out{};
    out.struct_size = sizeof(out);
    out.geometry_type = PI_VECTOR_GEOMETRY_POINT_V1;
    out.feature_class_utf8 = feature.c_str();
    out.object_name_utf8 = object_name_utf8.data();
    out.points = &point;
    out.point_count = 1;
    out.parts = nullptr;
    out.part_count = 0;
    out.attributes = attributes.empty() ? nullptr : attributes.data();
    out.attribute_count = static_cast<uint32_t>(attributes.size());

    keep_going = sink(&out, user_data);
  }

  objects->DeleteContents(true);
  delete objects;
  return true;
}


]===])

string(SUBSTRING "${C}" 0 ${START} PRE)
string(SUBSTRING "${C}" ${END} -1 POST)
file(WRITE "${CHART_CPP}" "${PRE}${IMPL}${POST}")
message(STATUS "Upgraded active o-charts point provider with S-57 attributes and object names")
