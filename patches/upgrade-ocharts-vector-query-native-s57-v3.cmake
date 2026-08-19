if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()

file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()

file(READ "${CPP}" C)

set(MARK "// VECTOR_QUERY_ACTIVE_PROVIDER_V1")
string(FIND "${C}" "${MARK}" START)
if(START EQUAL -1)
  message(FATAL_ERROR "Active vector query provider marker not found")
endif()
string(FIND "${C}" "eSENCChart::eSENCChart()" END)
if(END EQUAL -1 OR END LESS START)
  message(FATAL_ERROR "Could not locate end of active vector query provider")
endif()

set(IMPL [===[
// VECTOR_QUERY_ACTIVE_PROVIDER_V1
// VECTOR_QUERY_NATIVE_S57_V3
bool eSENCChart::QueryVectorObjectsV1(const PI_VectorQueryV1 *query,
                                      const PlugIn_ViewPort *viewport,
                                      PI_VectorObjectSinkV1 sink,
                                      void *user_data) {
  if (!query || query->struct_size < sizeof(PI_VectorQueryV1) || !viewport ||
      !sink || !std::isfinite(query->lat) || !std::isfinite(query->lon) ||
      !std::isfinite(query->search_radius_pixels) ||
      viewport->view_scale_ppm <= 0.0)
    return false;

  PlugIn_ViewPort pivp = *viewport;
  ViewPort cvp = CreateCompatibleViewport(pivp);
  PrepareForRender(&cvp, ps52plib);

  const double radius_pixels =
      std::max(1.0, std::min(query->search_radius_pixels, 64.0));
  const float select_radius = static_cast<float>(
      radius_pixels / (viewport->view_scale_ppm * 1852.0 * 60.0));

  std::vector<S57Obj *> selected;
  selected.reserve(64);

  auto add_selected = [&](S57Obj *obj) {
    if (!obj) return;
    for (S57Obj *existing : selected)
      if (existing == obj) return;
    if (selected.size() < 256) selected.push_back(obj);
  };

  for (int prio = 0; prio < PRIO_NUM && selected.size() < 256; ++prio) {
    const int point_type =
        (ps52plib->m_nSymbolStyle == SIMPLIFIED) ? 0 : 1;
    ObjRazRules *top = razRules[prio][point_type];
    while (top && selected.size() < 256) {
      if (top->obj && top->obj->npt == 1 &&
          ps52plib->ObjectRenderCheck(top) &&
          DoesLatLonSelectObject(static_cast<float>(query->lat),
                                 static_cast<float>(query->lon),
                                 select_radius, top->obj))
        add_selected(top->obj);

      for (ObjRazRules *child = top->child;
           child && selected.size() < 256; child = child->next) {
        if (child->obj && ps52plib->ObjectRenderCheck(child) &&
            DoesLatLonSelectObject(static_cast<float>(query->lat),
                                   static_cast<float>(query->lon),
                                   select_radius, child->obj))
          add_selected(child->obj);
      }
      top = top->next;
    }

    const int area_boundary_type =
        (ps52plib->m_nBoundaryStyle == PLAIN_BOUNDARIES) ? 3 : 4;
    top = razRules[prio][area_boundary_type];
    while (top && selected.size() < 256) {
      if (top->obj && ps52plib->ObjectRenderCheck(top) &&
          DoesLatLonSelectObject(static_cast<float>(query->lat),
                                 static_cast<float>(query->lon),
                                 select_radius, top->obj))
        add_selected(top->obj);
      top = top->next;
    }

    top = razRules[prio][2];
    while (top && selected.size() < 256) {
      if (top->obj && ps52plib->ObjectRenderCheck(top) &&
          DoesLatLonSelectObject(static_cast<float>(query->lat),
                                 static_cast<float>(query->lon),
                                 select_radius, top->obj))
        add_selected(top->obj);
      top = top->next;
    }
  }

  auto append_sm = [&](std::vector<PI_VectorPositionV1> &points,
                       double east, double north, double ref_lat,
                       double ref_lon) {
    double lat = 0.0, lon = 0.0;
    fromSM_Plugin(east, north, ref_lat, ref_lon, &lat, &lon);
    if (!std::isfinite(lat) || !std::isfinite(lon)) return;
    if (!points.empty()) {
      const auto &last = points.back();
      if (std::fabs(last.lat - lat) < 1e-10 &&
          std::fabs(last.lon - lon) < 1e-10)
        return;
    }
    points.push_back({lat, lon});
  };

  bool keep_going = true;
  uint32_t emitted = 0;

  for (S57Obj *obj : selected) {
    if (!keep_going || emitted >= 256 || !obj || !obj->FeatureName[0]) break;

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
    } else if (obj->geoPt && obj->npt >= 2 && obj->npt <= 65536) {
      PI_VectorPartV1 part{};
      part.first_point = 0;
      for (int i = 0; i < obj->npt; ++i) {
        const double east = obj->geoPt[i].x * obj->x_rate + obj->x_origin;
        const double north = obj->geoPt[i].y * obj->y_rate + obj->y_origin;
        append_sm(points, east, north,
                  obj->m_chart_context ? obj->m_chart_context->ref_lat : m_ref_lat,
                  obj->m_chart_context ? obj->m_chart_context->ref_lon : m_ref_lon);
      }
      part.point_count = static_cast<uint32_t>(points.size());
      if (part.point_count >= 2) parts.push_back(part);
    } else if (obj->m_ls_list && obj->m_chart_context &&
               obj->m_chart_context->vertex_buffer) {
      unsigned char *vbo = reinterpret_cast<unsigned char *>(
          obj->m_chart_context->vertex_buffer);
      for (line_segment_element *ls = obj->m_ls_list;
           ls && points.size() < 65536; ls = ls->next) {
        float *src = nullptr;
        int count = 0;
        bool reverse = false;

        if ((ls->ls_type == TYPE_EE || ls->ls_type == TYPE_EE_REV) &&
            ls->pedge) {
          src = reinterpret_cast<float *>(vbo + ls->pedge->vbo_offset);
          count = static_cast<int>(ls->pedge->nCount);
          reverse = (ls->ls_type == TYPE_EE_REV);
        } else if (ls->pcs) {
          src = reinterpret_cast<float *>(vbo + ls->pcs->vbo_offset);
          count = 2;
        }

        if (!src || count < 2) continue;

        PI_VectorPartV1 part{};
        part.first_point = static_cast<uint32_t>(points.size());
        if (reverse) {
          for (int i = count - 1; i >= 0; --i)
            append_sm(points, src[i * 2], src[i * 2 + 1],
                      obj->m_chart_context->ref_lat,
                      obj->m_chart_context->ref_lon);
        } else {
          for (int i = 0; i < count; ++i)
            append_sm(points, src[i * 2], src[i * 2 + 1],
                      obj->m_chart_context->ref_lat,
                      obj->m_chart_context->ref_lon);
        }
        part.point_count =
            static_cast<uint32_t>(points.size()) - part.first_point;
        if (part.point_count >= 2) parts.push_back(part);
      }
    } else if (obj->m_n_lsindex > 0 && obj->m_lsindex_array &&
               obj->m_chart_context && obj->m_chart_context->m_pve_hash &&
               obj->m_chart_context->m_pvc_hash) {
      auto *ve_hash = obj->m_chart_context->m_pve_hash;
      auto *vc_hash = obj->m_chart_context->m_pvc_hash;
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
            append_sm(points, it->second->pPoint[0], it->second->pPoint[1],
                      obj->m_chart_context->ref_lat,
                      obj->m_chart_context->ref_lon);
        }
        if (enode) {
          auto it = ve_hash->find(enode);
          if (it != ve_hash->end() && it->second && it->second->pPoints) {
            VE_Element *edge = it->second;
            for (unsigned int ip = 0;
                 ip < edge->nCount && points.size() < 65536; ++ip)
              append_sm(points, edge->pPoints[ip * 2], edge->pPoints[ip * 2 + 1],
                        obj->m_chart_context->ref_lat,
                        obj->m_chart_context->ref_lon);
          }
        }
        if (jnode) {
          auto it = vc_hash->find(jnode);
          if (it != vc_hash->end() && it->second && it->second->pPoint)
            append_sm(points, it->second->pPoint[0], it->second->pPoint[1],
                      obj->m_chart_context->ref_lat,
                      obj->m_chart_context->ref_lon);
        }

        part.point_count =
            static_cast<uint32_t>(points.size()) - part.first_point;
        if (part.point_count >= 2) parts.push_back(part);
      }
    }

    if (points.empty() ||
        (geometry_type != PI_VECTOR_GEOMETRY_POINT_V1 && parts.empty())) {
      wxLogMessage("OCHARTS_VECTOR_QUERY native_drop feature=%s prim=%d npt=%d ls=%p idx=%d",
                   wxString::FromUTF8(obj->FeatureName), obj->Primitive_type,
                   obj->npt, obj->m_ls_list, obj->m_n_lsindex);
      continue;
    }

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
        S57attVal *att = obj->attVal->Item(i);
        wxString value = GetAttributeValueAsString(att, attr_name);
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

    wxLogMessage("OCHARTS_VECTOR_QUERY native_emit feature=%s prim=%d points=%u parts=%u",
                 wxString::FromUTF8(obj->FeatureName), obj->Primitive_type,
                 static_cast<unsigned>(points.size()),
                 static_cast<unsigned>(parts.size()));

    ++emitted;
    keep_going = sink(&out, user_data);
  }

  return true;
}

]===])

string(SUBSTRING "${C}" 0 ${START} PRE)
string(SUBSTRING "${C}" ${END} -1 POST)
file(WRITE "${CPP}" "${PRE}${IMPL}${POST}")
message(STATUS "Installed native S57 vector query provider v3")
message(STATUS "  selection: ObjRazRules/S57Obj directly")
message(STATUS "  geometry: geoPt + native m_ls_list/VBO + lsindex/hash fallback")
message(STATUS "  PI_S57Obj clone path bypassed for QueryVectorObjectsV1")
