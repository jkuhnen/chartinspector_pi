if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()
file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()
file(READ "${CPP}" C)

string(FIND "${C}" "// VECTOR_QUERY_LINE_GEOMETRY_DIAG_V1" DONE)
if(NOT DONE EQUAL -1)
  message(STATUS "o-charts line geometry diagnostics already installed")
  return()
endif()

set(ANCHOR [===[
    // VECTOR_QUERY_FINAL_CLAMP_V1
]===])

set(DIAG [===[
    // VECTOR_QUERY_LINE_GEOMETRY_DIAG_V1
    if (geometry_type == PI_VECTOR_GEOMETRY_LINE_V1) {
      const double ctx_ref_lat = obj->m_chart_context
                                     ? obj->m_chart_context->ref_lat
                                     : 0.0;
      const double ctx_ref_lon = obj->m_chart_context
                                     ? obj->m_chart_context->ref_lon
                                     : 0.0;
      wxLogMessage(
          "OCHARTS_LINE_DIAG feature=%s points=%u parts=%u npt=%d ls=%p idx=%d "
          "chart_ref=%.8f,%.8f ctx_ref=%.8f,%.8f rate=%.9g,%.9g origin=%.3f,%.3f",
          wxString::FromUTF8(obj->FeatureName),
          static_cast<unsigned>(points.size()),
          static_cast<unsigned>(parts.size()), obj->npt, obj->m_ls_list,
          obj->m_n_lsindex, m_ref_lat, m_ref_lon, ctx_ref_lat, ctx_ref_lon,
          obj->x_rate, obj->y_rate, obj->x_origin, obj->y_origin);

      // Inspect the first native VBO segment, if this object uses m_ls_list.
      if (obj->m_ls_list && obj->m_chart_context &&
          obj->m_chart_context->vertex_buffer) {
        line_segment_element *ls = obj->m_ls_list;
        unsigned char *vbo = reinterpret_cast<unsigned char *>(
            obj->m_chart_context->vertex_buffer);
        float *src = nullptr;
        int count = 0;
        if ((ls->ls_type == TYPE_EE || ls->ls_type == TYPE_EE_REV) &&
            ls->pedge) {
          src = reinterpret_cast<float *>(vbo + ls->pedge->vbo_offset);
          count = static_cast<int>(ls->pedge->nCount);
        } else if (ls->pcs) {
          src = reinterpret_cast<float *>(vbo + ls->pcs->vbo_offset);
          count = 2;
        }
        if (src && count > 0) {
          const int raw_count = std::min(count, 5);
          for (int i = 0; i < raw_count; ++i) {
            double lat_chart = 0.0, lon_chart = 0.0;
            double lat_ctx = 0.0, lon_ctx = 0.0;
            fromSM_Plugin(src[i * 2], src[i * 2 + 1], m_ref_lat, m_ref_lon,
                          &lat_chart, &lon_chart);
            if (obj->m_chart_context)
              fromSM_Plugin(src[i * 2], src[i * 2 + 1], ctx_ref_lat,
                            ctx_ref_lon, &lat_ctx, &lon_ctx);
            wxLogMessage(
                "OCHARTS_LINE_DIAG vbo feature=%s i=%d raw=%.3f,%.3f "
                "chartLL=%.8f,%.8f ctxLL=%.8f,%.8f type=%d count=%d",
                wxString::FromUTF8(obj->FeatureName), i, src[i * 2],
                src[i * 2 + 1], lat_chart, lon_chart, lat_ctx, lon_ctx,
                ls->ls_type, count);
          }
        }
      }

      // Inspect the first lsindex edge/node coordinates, if available.
      if (obj->m_n_lsindex > 0 && obj->m_lsindex_array &&
          obj->m_chart_context && obj->m_chart_context->m_pve_hash &&
          obj->m_chart_context->m_pvc_hash) {
        int *idx = &obj->m_lsindex_array[0];
        const unsigned int inode = static_cast<unsigned int>(idx[0]);
        const unsigned int enode = static_cast<unsigned int>(idx[1]);
        const unsigned int jnode = static_cast<unsigned int>(idx[2]);
        wxLogMessage("OCHARTS_LINE_DIAG lsindex feature=%s inode=%u enode=%u jnode=%u",
                     wxString::FromUTF8(obj->FeatureName), inode, enode, jnode);
        if (enode) {
          auto *ve_hash = obj->m_chart_context->m_pve_hash;
          auto it = ve_hash->find(enode);
          if (it != ve_hash->end() && it->second && it->second->pPoints) {
            VE_Element *edge = it->second;
            const unsigned int raw_count = std::min<unsigned int>(edge->nCount, 5u);
            for (unsigned int i = 0; i < raw_count; ++i) {
              const double east = edge->pPoints[i * 2];
              const double north = edge->pPoints[i * 2 + 1];
              double lat_chart = 0.0, lon_chart = 0.0;
              double lat_ctx = 0.0, lon_ctx = 0.0;
              fromSM_Plugin(east, north, m_ref_lat, m_ref_lon,
                            &lat_chart, &lon_chart);
              fromSM_Plugin(east, north, ctx_ref_lat, ctx_ref_lon,
                            &lat_ctx, &lon_ctx);
              wxLogMessage(
                  "OCHARTS_LINE_DIAG edge feature=%s i=%u raw=%.3f,%.3f "
                  "chartLL=%.8f,%.8f ctxLL=%.8f,%.8f n=%u",
                  wxString::FromUTF8(obj->FeatureName), i, east, north,
                  lat_chart, lon_chart, lat_ctx, lon_ctx, edge->nCount);
            }
          }
        }
      }

      const unsigned int out_count =
          std::min<unsigned int>(static_cast<unsigned int>(points.size()), 5u);
      for (unsigned int i = 0; i < out_count; ++i) {
        wxLogMessage("OCHARTS_LINE_DIAG out feature=%s i=%u ll=%.8f,%.8f",
                     wxString::FromUTF8(obj->FeatureName), i,
                     points[i].lat, points[i].lon);
      }
    }

    // VECTOR_QUERY_FINAL_CLAMP_V1
]===])

string(FIND "${C}" "${ANCHOR}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate VECTOR_QUERY_FINAL_CLAMP_V1 anchor")
endif()
string(REPLACE "${ANCHOR}" "${DIAG}" C "${C}")
file(WRITE "${CPP}" "${C}")
message(STATUS "Installed o-charts line geometry diagnostics v1")
message(STATUS "  logs chart/context reference origins")
message(STATUS "  logs first native VBO and lsindex edge coordinates")
message(STATUS "  logs first five emitted line positions")
