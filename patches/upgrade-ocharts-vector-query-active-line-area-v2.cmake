if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()
file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()
file(READ "${CPP}" C)

# The actually compiled provider is the one marked by our active-provider marker
# near the top of eSENCChart.cpp.  Older experimental full-provider code exists
# later inside #if 0 and must not be used as an edit anchor.
set(MARK "// VECTOR_QUERY_ACTIVE_PROVIDER_V1")
string(FIND "${C}" "${MARK}" START)
if(START EQUAL -1)
  message(FATAL_ERROR "Active provider marker not found")
endif()
string(FIND "${C}" "eSENCChart::eSENCChart()" END)
if(END EQUAL -1 OR END LESS START)
  message(FATAL_ERROR "Active provider end anchor not found")
endif()

set(IMPL [===[
// VECTOR_QUERY_ACTIVE_PROVIDER_V1
// VECTOR_QUERY_ACTIVE_LINE_AREA_V2
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
  const double radius_pixels = std::max(1.0, std::min(query->search_radius_pixels, 64.0));
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
    }
    else if (obj->geoPt && obj->npt >= 2 && obj->npt <= 65536) {
      PI_VectorPartV1 part{};
      part.first_point = 0;
      for (int i = 0; i < obj->npt; ++i) {
        const double east = obj->geoPt[i].x * obj->x_rate + obj->x_origin;
        const double north = obj->geoPt[i].y * obj->y_rate + obj->y_origin;
        double lat = 0.0, lon = 0.0;
        fromSM_Plugin(east, north, m_ref_lat, m_ref_lon, &lat, &lon);
        if (!std::isfinite(lat) || !std::isfinite(lon)) continue;
        points.push_back({lat, lon});
      }
      part.point_count = static_cast<uint32_t>(points.size());
      if (part.point_count >= 2) parts.push_back(part);
    }
    else if (obj->m_ls_list && obj->m_chart_context &&
             obj->m_chart_context->vertex_buffer) {
      unsigned char *vbo =
          reinterpret_cast<unsigned char *>(obj->m_chart_context->vertex_buffer);
      line_segment_element *ls = obj->m_ls_list;
      while (ls && points.size() < 65536) {
        float *src = nullptr;
        int count = 0;
        if ((ls->ls_type == TYPE_EE || ls->ls_type == TYPE_EE_REV) && ls->pedge) {
          src = reinterpret_cast<float *>(vbo + ls->pedge->vbo_offset);
          count = static_cast<int>(ls->pedge->nCount);
        }
        else if (ls->pcs) {
          src = reinterpret_cast<float *>(vbo + ls->pcs->vbo_offset);
          count = 2;
        }

        if (src && count >= 2) {
          PI_VectorPartV1 part{};
          part.first_point = static_cast<uint32_t>(points.size());
          if (ls->ls_type == TYPE_EE_REV) {
            for (int i = count - 1; i >= 0; --i) {
              double lat = 0.0, lon = 0.0;
              fromSM_Plugin(src[i * 2], src[i * 2 + 1], m_ref_lat, m_ref_lon,
                            &lat, &lon);
              if (std::isfinite(lat) && std::isfinite(lon))
                points.push_back({lat, lon});
            }
          } else {
            for (int i = 0; i < count; ++i) {
              double lat = 0.0, lon = 0.0;
              fromSM_Plugin(src[i * 2], src[i * 2 + 1], m_ref_lat, m_ref_lon,
                            &lat, &lon);
              if (std::isfinite(lat) && std::isfinite(lon))
                points.push_back({lat, lon});
            }
          }
          part.point_count = static_cast<uint32_t>(points.size()) - part.first_point;
          if (part.point_count >= 2) parts.push_back(part);
        }
        ls = ls->next;
      }
    }

    // Area hit-testing in o-charts can succeed using tessellation even when the
    // boundary representation is not copied into PI_S57Obj.  Emit the object
    // only when usable geometry is available; point behavior is unchanged.
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
        wxString attr_name = wxString::FromUTF8(acronym);
        wxString value = GetObjectAttributeValueAsString(obj, i, attr_name);
        wxCharBuffer value_utf8 = value.ToUTF8();
        attr_names.emplace_back(acronym);
        attr_values.emplace_back(value_utf8.data() ? value_utf8.data() : "");
        if ((!strcmp(acronym, "OBJNAM") || !strcmp(acronym, "NOBJNM")) &&
            object_name.IsEmpty() && !value.IsEmpty())
          object_name = value;
      }
    }

    attrs.reserve(attr_names.size());
    for (size_t i = 0; i < attr_names.size(); ++i)
      attrs.push_back({attr_names[i].c_str(), attr_values[i].c_str()});

    wxCharBuffer object_name_utf8 = object_name.ToUTF8();
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

string(SUBSTRING "${C}" 0 ${START} PRE)
string(SUBSTRING "${C}" ${END} -1 POST)
file(WRITE "${CPP}" "${PRE}${IMPL}${POST}")
message(STATUS "Upgraded ACTIVE o-charts provider to Point/Line/Area v2")
message(STATUS "  edit anchor: VECTOR_QUERY_ACTIVE_PROVIDER_V1")
message(STATUS "  geoPt + m_ls_list/VBO geometry paths enabled")
message(STATUS "  disabled legacy provider block left untouched")
