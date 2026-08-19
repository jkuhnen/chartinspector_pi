if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()
file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()
file(READ "${CPP}" C)

set(OLD [===[
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
]===])

set(NEW [===[
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
    } else if (obj->m_n_lsindex > 0 && obj->m_lsindex_array &&
               obj->m_chart_context && obj->m_chart_context->m_pve_hash &&
               obj->m_chart_context->m_pvc_hash) {
      auto ve_hash = obj->m_chart_context->m_pve_hash;
      auto vc_hash = obj->m_chart_context->m_pvc_hash;
      const double ref_lat = obj->m_chart_context->ref_lat;
      const double ref_lon = obj->m_chart_context->ref_lon;

      auto append_sm = [&](double east, double north) {
        double lat = 0.0, lon = 0.0;
        fromSM(east, north, ref_lat, ref_lon, &lat, &lon);
        if (!std::isfinite(lat) || !std::isfinite(lon)) return;
        if (!points.empty()) {
          const auto &last = points.back();
          if (std::fabs(last.lat - lat) < 1e-10 &&
              std::fabs(last.lon - lon) < 1e-10) return;
        }
        points.push_back({lat, lon});
      };

      for (int iseg = 0; iseg < obj->m_n_lsindex && points.size() < 65536;
           ++iseg) {
        int *idx = &obj->m_lsindex_array[iseg * 3];
        const unsigned int inode = static_cast<unsigned int>(idx[0]);
        const unsigned int enode = static_cast<unsigned int>(idx[1]);
        const unsigned int jnode = static_cast<unsigned int>(idx[2]);

        PI_VectorPartV1 part{};
        part.first_point = static_cast<uint32_t>(points.size());

        if (inode) {
          auto it = vc_hash->find(inode);
          if (it != vc_hash->end() && it->second && it->second->pPoint)
            append_sm(it->second->pPoint[0], it->second->pPoint[1]);
        }
        if (enode) {
          auto it = ve_hash->find(enode);
          if (it != ve_hash->end() && it->second && it->second->pPoints) {
            VE_Element *edge = it->second;
            for (unsigned int ip = 0; ip < edge->nCount && points.size() < 65536;
                 ++ip)
              append_sm(edge->pPoints[ip * 2], edge->pPoints[ip * 2 + 1]);
          }
        }
        if (jnode) {
          auto it = vc_hash->find(jnode);
          if (it != vc_hash->end() && it->second && it->second->pPoint)
            append_sm(it->second->pPoint[0], it->second->pPoint[1]);
        }

        part.point_count = static_cast<uint32_t>(points.size()) - part.first_point;
        if (part.point_count >= 2) parts.push_back(part);
      }
    }
]===])

string(FIND "${C}" "m_chart_context->m_pve_hash" ALREADY)
string(FIND "${C}" "else if (obj->m_n_lsindex > 0" HAS_PATCH)
if(NOT HAS_PATCH EQUAL -1)
  message(STATUS "o-charts edge geometry fallback already installed")
  return()
endif()
string(FIND "${C}" "${OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Expected active QueryVectorObjectsV1 geoPt block not found; refusing blind edit")
endif()
string(REPLACE "${OLD}" "${NEW}" C "${C}")
file(WRITE "${CPP}" "${C}")
message(STATUS "Installed o-charts Vector Query edge geometry fallback v1")
message(STATUS "  source: m_lsindex_array + VC/VE chart-context hashes")
message(STATUS "  line/area parts: one part per S-57 edge segment")
