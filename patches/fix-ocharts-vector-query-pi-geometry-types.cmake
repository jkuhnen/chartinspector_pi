if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()

file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()

file(READ "${CPP}" C)

# Fix 1: PI_S57Obj::geoPt is void*, not pt*.
set(OLD_GEOPT [===[
      for (int i = 0; i < obj->npt; ++i) {
        const double east = obj->geoPt[i].x * obj->x_rate + obj->x_origin;
        const double north = obj->geoPt[i].y * obj->y_rate + obj->y_origin;
]===])

set(NEW_GEOPT [===[
      const pt *geo = static_cast<const pt *>(obj->geoPt);
      for (int i = 0; i < obj->npt; ++i) {
        const double east = geo[i].x * obj->x_rate + obj->x_origin;
        const double north = geo[i].y * obj->y_rate + obj->y_origin;
]===])

string(FIND "${C}" "${OLD_GEOPT}" GEOPT_POS)
if(NOT GEOPT_POS EQUAL -1)
  string(REPLACE "${OLD_GEOPT}" "${NEW_GEOPT}" C "${C}")
  message(STATUS "Fixed PI_S57Obj::geoPt access")
else()
  string(FIND "${C}" "const pt *geo = static_cast<const pt *>(obj->geoPt);" GEOPT_DONE)
  if(GEOPT_DONE EQUAL -1)
    message(FATAL_ERROR "Could not locate PI_S57Obj geoPt access block")
  else()
    message(STATUS "PI_S57Obj::geoPt access already fixed")
  endif()
endif()

# Fix 2: PI_S57Obj::m_ls_list uses PI_line_segment_element.  This API-side
# structure contains a direct VBO offset/count and does not expose native
# line_segment_element pedge/pcs members.
set(OLD_VBO [===[
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
]===])

set(NEW_VBO [===[
      unsigned char *vbo =
          reinterpret_cast<unsigned char *>(obj->m_chart_context->vertex_buffer);
      PI_line_segment_element *ls = obj->m_ls_list;
      while (ls && points.size() < 65536) {
        float *src = reinterpret_cast<float *>(vbo + ls->vbo_offset);
        const int count = static_cast<int>(ls->n_points);

        if (src && count >= 2) {
          PI_VectorPartV1 part{};
          part.first_point = static_cast<uint32_t>(points.size());

          const bool reverse = (ls->type == TYPE_EE_REV);
          if (reverse) {
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
]===])

string(FIND "${C}" "${OLD_VBO}" VBO_POS)
if(NOT VBO_POS EQUAL -1)
  string(REPLACE "${OLD_VBO}" "${NEW_VBO}" C "${C}")
  message(STATUS "Fixed PI_line_segment_element VBO access")
else()
  string(FIND "${C}" "PI_line_segment_element *ls = obj->m_ls_list;" VBO_DONE)
  if(VBO_DONE EQUAL -1)
    message(FATAL_ERROR "Could not locate PI_S57Obj VBO block")
  else()
    message(STATUS "PI_line_segment_element VBO access already fixed")
  endif()
endif()

file(WRITE "${CPP}" "${C}")
message(STATUS "PI geometry type repair complete")
