if(NOT DEFINED OPENCPN_ROOT)
  message(FATAL_ERROR "OPENCPN_ROOT is required, e.g. -DOPENCPN_ROOT=C:/Users/Johannes/source/OpenCPN")
endif()

file(TO_CMAKE_PATH "${OPENCPN_ROOT}" OPENCPN_ROOT)
set(TARGET "${OPENCPN_ROOT}/gui/src/ocpn_plugin_gui.cpp")

if(NOT EXISTS "${TARGET}")
  message(FATAL_ERROR "OpenCPN source file not found: ${TARGET}")
endif()

file(READ "${TARGET}" SRC)

if(NOT SRC MATCHES "OCPNChartInspectorHitTestV5")
  message(FATAL_ERROR "Chart Inspector V5 hit test is not installed in ${TARGET}")
endif()

set(OLD [=[bool ChartInspectorPluginGeometryV5(PI_S57Obj* obj,
                                    ChartInspectorGeometryV5* geometry) {
  if (!obj || !geometry) return false;
  geometry->latlon.clear();
  geometry->parts.clear();

  chart_context* context =
      reinterpret_cast<chart_context*>(obj->m_chart_context);
  const double ref_lat = context ? context->ref_lat : obj->chart_ref_lat;
  const double ref_lon = context ? context->ref_lon : obj->chart_ref_lon;

  if (obj->geoPt && obj->npt >= 2) {
    const pt* source = reinterpret_cast<const pt*>(obj->geoPt);
    ChartInspectorBeginPartV5(geometry);
    for (int i = 0; i < obj->npt; ++i) {
      const double east = source[i].x * obj->x_rate + obj->x_origin;
      const double north = source[i].y * obj->y_rate + obj->y_origin;
      double lat = 0.0;
      double lon = 0.0;
      fromSM(east, north, ref_lat, ref_lon, &lat, &lon);
      ChartInspectorAppendLLV5(geometry, lat, lon);
    }
    return geometry->latlon.size() >= 4;
  }

  if (!context || !context->vertex_buffer) return false;
  const unsigned char* vertex_buffer =
      reinterpret_cast<const unsigned char*>(context->vertex_buffer);
  PI_line_segment_element* segment = obj->m_ls_list;
  while (segment) {
    if (segment->n_points >= 2) {
      const float* points = reinterpret_cast<const float*>(
          vertex_buffer + segment->vbo_offset);
      ChartInspectorAppendSMPartV5(
          geometry, points, static_cast<int>(segment->n_points), ref_lat,
          ref_lon);
    }
    segment = segment->next;
  }
  return geometry->latlon.size() >= 4;
}]=])

set(NEW [=[bool ChartInspectorPluginGeometryV5(PI_S57Obj* obj,
                                    ChartInspectorGeometryV5* geometry) {
  if (!obj || !geometry) return false;
  geometry->latlon.clear();
  geometry->parts.clear();

  // PI_S57Obj::m_chart_context and m_ls_list belong to the chart provider.
  // Their internal backing storage is not part of the stable plugin ABI and
  // must not be dereferenced here.  Use only the public, copied geoPt geometry.
  // Providers which do not expose geoPt simply do not participate in V5
  // geometry-aware line/area picking yet; V4 remains available as fallback.
  if (!obj->geoPt || obj->npt < 2 || obj->npt > 4096) return false;

  const double ref_lat = obj->chart_ref_lat;
  const double ref_lon = obj->chart_ref_lon;
  if (!std::isfinite(ref_lat) || !std::isfinite(ref_lon) ||
      !std::isfinite(obj->x_rate) || !std::isfinite(obj->y_rate) ||
      !std::isfinite(obj->x_origin) || !std::isfinite(obj->y_origin))
    return false;

  const pt* source = reinterpret_cast<const pt*>(obj->geoPt);
  ChartInspectorBeginPartV5(geometry);
  for (int i = 0; i < obj->npt; ++i) {
    const double east = source[i].x * obj->x_rate + obj->x_origin;
    const double north = source[i].y * obj->y_rate + obj->y_origin;
    if (!std::isfinite(east) || !std::isfinite(north)) {
      geometry->latlon.clear();
      geometry->parts.clear();
      return false;
    }
    double lat = 0.0;
    double lon = 0.0;
    fromSM(east, north, ref_lat, ref_lon, &lat, &lon);
    if (!std::isfinite(lat) || !std::isfinite(lon)) {
      geometry->latlon.clear();
      geometry->parts.clear();
      return false;
    }
    ChartInspectorAppendLLV5(geometry, lat, lon);
  }
  return geometry->latlon.size() >= 4;
}]=])

string(FIND "${SRC}" "${OLD}" POS_OLD)
if(NOT POS_OLD EQUAL -1)
  string(REPLACE "${OLD}" "${NEW}" SRC "${SRC}")
  file(WRITE "${TARGET}" "${SRC}")
  message(STATUS "Guarded Chart Inspector V5 plugin geometry access in ${TARGET}")
elseif(SRC MATCHES "PI_S57Obj::m_chart_context and m_ls_list belong to the chart provider")
  message(STATUS "Chart Inspector V5 plugin geometry guard is already installed.")
else()
  message(FATAL_ERROR "Could not locate the V5 plugin geometry function to patch.")
endif()
