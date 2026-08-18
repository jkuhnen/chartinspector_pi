if(NOT DEFINED OPENCPN_ROOT)
  message(FATAL_ERROR "OPENCPN_ROOT is required, e.g. -DOPENCPN_ROOT=C:/Users/Johannes/source/OpenCPN")
endif()

file(TO_CMAKE_PATH "${OPENCPN_ROOT}" OPENCPN_ROOT)
set(TARGET "${OPENCPN_ROOT}/gui/src/ocpn_plugin_gui.cpp")

if(NOT EXISTS "${TARGET}")
  message(FATAL_ERROR "OpenCPN source file not found: ${TARGET}")
endif()

file(READ "${TARGET}" SRC)

if(SRC MATCHES "OCPNChartInspectorHitTestV4")
  message(STATUS "Chart Inspector V4 hit test is already installed.")
  return()
endif()

if(NOT SRC MATCHES "OCPNChartInspectorHitTestV3")
  message(FATAL_ERROR "V3 hit test was not found. Install V3 first.")
endif()

set(V4_CODE [===[

extern "C" DECL_EXP bool OCPNChartInspectorHitTestV4(
    int canvas_index, double lat, double lon, double radius_pixels,
    const char* feature_filter, char* feature, int feature_size,
    char* object_name, int object_name_size, char* attributes,
    int attributes_size, int* primitive_type, double* marker_lat,
    double* marker_lon) {
  if (!feature || feature_size <= 0 || !object_name || object_name_size <= 0 ||
      !attributes || attributes_size <= 0 || !primitive_type || !marker_lat ||
      !marker_lon)
    return false;

  // Native S-57 already honours MASK_ALL in V3. Keep that tested path.
  if (canvas_index < 0 ||
      static_cast<size_t>(canvas_index) >= g_canvasArray.GetCount())
    return false;

  ChartCanvas* cc = g_canvasArray.Item(canvas_index);
  if (!cc) return false;
  ViewPort& viewport = cc->GetVP();
  if (!viewport.IsValid() || viewport.view_scale_ppm <= 0.0) return false;

  const wxPoint calc_point = viewport.GetPixFromLL(lat, lon);
  ChartBase* target_chart = nullptr;
  if (cc->m_singleChart &&
      cc->m_singleChart->GetChartFamily() == CHART_FAMILY_VECTOR) {
    target_chart = cc->m_singleChart;
  } else if (viewport.b_quilt && cc->m_pQuilt) {
    target_chart = cc->m_pQuilt->GetChartAtPix(viewport, calc_point);
  }
  if (!target_chart || target_chart->GetChartFamily() != CHART_FAMILY_VECTOR)
    return false;

  auto* plugin_chart = dynamic_cast<ChartPlugInWrapper*>(target_chart);
  if (!plugin_chart) {
    return OCPNChartInspectorHitTestV3(
        canvas_index, lat, lon, radius_pixels, feature_filter, feature,
        feature_size, object_name, object_name_size, attributes,
        attributes_size, primitive_type, marker_lat, marker_lon);
  }

  // First use the exact user-configured radius. This keeps point/line picking
  // tight and preserves the V3 behaviour.
  if (OCPNChartInspectorHitTestV3(
          canvas_index, lat, lon, radius_pixels, feature_filter, feature,
          feature_size, object_name, object_name_size, attributes,
          attributes_size, primitive_type, marker_lat, marker_lon)) {
    if (*primitive_type != 1) return true;

    // A point has priority in V3. Keep it only when it is genuinely inside the
    // configured radius; otherwise allow the area fallback below.
    const wxPoint object_point = viewport.GetPixFromLL(*marker_lat, *marker_lon);
    const double dx = static_cast<double>(object_point.x - calc_point.x);
    const double dy = static_cast<double>(object_point.y - calc_point.y);
    if (std::sqrt(dx * dx + dy * dy) <= radius_pixels + 0.5) return true;
  }

  if (!s_ppim) return false;

  // Some vector chart plugins are more reliable for polygon selection with the
  // same 16-pixel query radius traditionally used by OpenCPN's S-57 helpers.
  // This wider query is ONLY used for areas, so it cannot make buoy/point hover
  // feel loose.
  const double area_radius_pixels = std::max(16.0, radius_pixels);
  const float area_select_radius = static_cast<float>(
      area_radius_pixels / (viewport.view_scale_ppm * 1852.0 * 60.0));

  ListOfPI_S57Obj* objects = s_ppim->GetPlugInObjRuleListAtLatLon(
      plugin_chart, static_cast<float>(lat), static_cast<float>(lon),
      area_select_radius, viewport);
  if (!objects) return false;

  PI_S57Obj* best = nullptr;
  int best_priority = -1;
  for (auto* node = objects->GetFirst(); node; node = node->GetNext()) {
    PI_S57Obj* obj = node->GetData();
    if (!obj || obj->Primitive_type != GEO_AREA) continue;
    if (!ChartInspectorFilterMatch(feature_filter, obj->FeatureName)) continue;

    const int priority = ChartInspectorV3Priority(obj->FeatureName,
                                                  obj->Primitive_type);
    if (priority > best_priority) {
      best_priority = priority;
      best = obj;
    }
  }

  bool found = false;
  if (best) {
    ChartInspectorCopyString(feature, feature_size, best->FeatureName);
    object_name[0] = '\0';
    const wxString attr_text = ChartInspectorFormatAttributes(best);
    const wxCharBuffer utf8 = attr_text.ToUTF8();
    ChartInspectorCopyString(attributes, attributes_size, utf8.data());
    *primitive_type = 3;
    *marker_lat = lat;
    *marker_lon = lon;
    found = true;
  }

  objects->Clear();
  delete objects;
  return found;
}
]===])

string(FIND "${SRC}" "bool GetGlobalColor(wxString colorName, wxColour* pcolour)" POS_GLOBAL_COLOR)
if(POS_GLOBAL_COLOR EQUAL -1)
  message(FATAL_ERROR "Could not find GetGlobalColor anchor in ${TARGET}")
endif()

string(REPLACE
  "bool GetGlobalColor(wxString colorName, wxColour* pcolour)"
  "${V4_CODE}\nbool GetGlobalColor(wxString colorName, wxColour* pcolour)"
  SRC "${SRC}")

file(WRITE "${TARGET}" "${SRC}")
message(STATUS "Installed Chart Inspector V4 hit test in ${TARGET}")
