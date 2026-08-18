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

set(START_MARKER "bool ChartInspectorPluginGeometryV5(PI_S57Obj* obj,")
set(END_MARKER "double ChartInspectorSegmentDistanceV5(")
string(FIND "${SRC}" "${START_MARKER}" START_POS)
string(FIND "${SRC}" "${END_MARKER}" END_POS)

if(START_POS EQUAL -1 OR END_POS EQUAL -1 OR END_POS LESS START_POS)
  message(FATAL_ERROR "Could not locate ChartInspectorPluginGeometryV5 in ${TARGET}")
endif()

set(REPLACEMENT [=[bool ChartInspectorPluginGeometryV5(PI_S57Obj* obj,
                                    ChartInspectorGeometryV5* geometry) {
  if (!obj || !geometry) return false;
  geometry->latlon.clear();
  geometry->parts.clear();

  // Convert the provider-owned PI_S57Obj through OpenCPN's own compatibility
  // adapter. This is the same adapter used by the core when rendering plugin
  // charts and respects the provider's advertised PLIB capabilities.
  S57Obj compatible;
  chart_context compatible_context{};
  CreateCompatibleS57Object(obj, &compatible, &compatible_context);

  chart_context* context = compatible.m_chart_context;
  if (!context) return false;

  const double ref_lat = context->ref_lat;
  const double ref_lon = context->ref_lon;
  if (!std::isfinite(ref_lat) || !std::isfinite(ref_lon)) return false;

  // Some providers expose a direct point array. Prefer it when available.
  if (compatible.geoPt && compatible.npt >= 2 && compatible.npt <= 4096) {
    ChartInspectorBeginPartV5(geometry);
    for (int i = 0; i < compatible.npt; ++i) {
      const double east =
          compatible.geoPt[i].x * compatible.x_rate + compatible.x_origin;
      const double north =
          compatible.geoPt[i].y * compatible.y_rate + compatible.y_origin;
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
    if (geometry->latlon.size() >= 4) return true;
    geometry->latlon.clear();
    geometry->parts.clear();
  }

  // Modern o-charts advertises PLIB_CAPS_OBJSEGLIST and stores line/area
  // geometry in a shared vertex buffer. CreateCompatibleS57Object exposes
  // that through m_ls_list_legacy plus a compatible chart_context.
  PI_line_segment_element* segment = compatible.m_ls_list_legacy;
  const unsigned char* vertex_buffer =
      reinterpret_cast<const unsigned char*>(context->vertex_buffer);
  if (!segment || !vertex_buffer) return false;

  int segment_count = 0;
  int total_points = 0;
  while (segment && segment_count < 1024 && total_points < 4096) {
    ++segment_count;
    const size_t count = segment->n_points;
    if (count >= 2 && count <= 4096 && total_points + static_cast<int>(count) <= 4096) {
      const float* points = reinterpret_cast<const float*>(
          vertex_buffer + segment->vbo_offset);
      if (!points) return false;
      ChartInspectorAppendSMPartV5(
          geometry, points, static_cast<int>(count), ref_lat, ref_lon);
      total_points += static_cast<int>(count);
    }
    segment = segment->next;
  }

  return geometry->latlon.size() >= 4;
}

]=])

string(SUBSTRING "${SRC}" 0 ${START_POS} PREFIX)
string(SUBSTRING "${SRC}" ${END_POS} -1 SUFFIX)
set(SRC "${PREFIX}${REPLACEMENT}${SUFFIX}")

file(WRITE "${TARGET}" "${SRC}")
message(STATUS "Installed Chart Inspector V5 provider-compatible geometry adapter in ${TARGET}")
