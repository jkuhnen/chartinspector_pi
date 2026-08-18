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

  // Objects returned by a plugin chart's GetObjRuleListAtLatLon() can be
  // lightweight clones.  Do not dereference provider-owned chart context or
  // segment-list pointers here.  Only use direct copied geometry when present.
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
}

]=])

string(SUBSTRING "${SRC}" 0 ${START_POS} PREFIX)
string(SUBSTRING "${SRC}" ${END_POS} -1 SUFFIX)
set(SRC "${PREFIX}${REPLACEMENT}${SUFFIX}")

file(WRITE "${TARGET}" "${SRC}")
message(STATUS "Rolled back Chart Inspector V5 plugin geometry to safe clone-only access in ${TARGET}")
