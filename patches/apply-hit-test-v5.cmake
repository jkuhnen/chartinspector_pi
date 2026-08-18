if(NOT DEFINED OPENCPN_ROOT)
  message(FATAL_ERROR "OPENCPN_ROOT is required, e.g. -DOPENCPN_ROOT=C:/Users/Johannes/source/OpenCPN")
endif()

file(TO_CMAKE_PATH "${OPENCPN_ROOT}" OPENCPN_ROOT)
set(TARGET "${OPENCPN_ROOT}/gui/src/ocpn_plugin_gui.cpp")

if(NOT EXISTS "${TARGET}")
  message(FATAL_ERROR "OpenCPN source file not found: ${TARGET}")
endif()

file(READ "${TARGET}" SRC)

if(SRC MATCHES "OCPNChartInspectorHitTestV5")
  message(STATUS "Chart Inspector V5 hit test is already installed.")
  return()
endif()

if(NOT SRC MATCHES "OCPNChartInspectorHitTestV4")
  message(FATAL_ERROR "V4 hit test was not found. Install V4 first.")
endif()

foreach(INCLUDE_LINE "#include <cmath>" "#include <limits>" "#include <vector>")
  string(FIND "${SRC}" "${INCLUDE_LINE}" INCLUDE_POS)
  if(INCLUDE_POS EQUAL -1)
    string(REPLACE "#include <cstring>" "#include <cstring>\n${INCLUDE_LINE}" SRC "${SRC}")
  endif()
endforeach()

string(FIND "${SRC}" "#include \"model/georef.h\"" GEOREF_POS)
if(GEOREF_POS EQUAL -1)
  string(REPLACE "#include \"chartbase.h\"" "#include \"chartbase.h\"\n#include \"model/georef.h\"" SRC "${SRC}")
endif()

set(V5_CODE [===[

namespace {

struct ChartInspectorGeometryV5 {
  std::vector<double> latlon;  // lat, lon pairs
  std::vector<int> parts;      // point index where each independent line starts
};

void ChartInspectorBeginPartV5(ChartInspectorGeometryV5* geometry) {
  if (!geometry) return;
  geometry->parts.push_back(static_cast<int>(geometry->latlon.size() / 2));
}

void ChartInspectorAppendLLV5(ChartInspectorGeometryV5* geometry, double lat,
                              double lon) {
  if (!geometry) return;
  geometry->latlon.push_back(lat);
  geometry->latlon.push_back(lon);
}

void ChartInspectorAppendSMPartV5(ChartInspectorGeometryV5* geometry,
                                  const float* points, int count,
                                  double ref_lat, double ref_lon) {
  if (!geometry || !points || count < 2) return;
  ChartInspectorBeginPartV5(geometry);
  for (int i = 0; i < count; ++i) {
    double lat = 0.0;
    double lon = 0.0;
    fromSM(points[i * 2], points[i * 2 + 1], ref_lat, ref_lon, &lat, &lon);
    ChartInspectorAppendLLV5(geometry, lat, lon);
  }
}

bool ChartInspectorNativeGeometryV5(s57chart* chart, S57Obj* obj,
                                    ChartInspectorGeometryV5* geometry) {
  if (!chart || !obj || !geometry) return false;
  geometry->latlon.clear();
  geometry->parts.clear();

  if (obj->geoPt && obj->npt >= 2) {
    ChartInspectorBeginPartV5(geometry);
    for (int i = 0; i < obj->npt; ++i) {
      const double east = obj->geoPt[i].x * obj->x_rate + obj->x_origin;
      const double north = obj->geoPt[i].y * obj->y_rate + obj->y_origin;
      double lat = 0.0;
      double lon = 0.0;
      fromSM(east, north, chart->ref_lat, chart->ref_lon, &lat, &lon);
      ChartInspectorAppendLLV5(geometry, lat, lon);
    }
    return geometry->latlon.size() >= 4;
  }

  unsigned char* vertex_buffer =
      reinterpret_cast<unsigned char*>(chart->GetLineVertexBuffer());
  line_segment_element* segment = obj->m_ls_list;
  while (segment && vertex_buffer) {
    size_t offset = 0;
    int count = 0;
    if ((segment->ls_type == TYPE_EE) ||
        (segment->ls_type == TYPE_EE_REV)) {
      if (segment->pedge) {
        offset = segment->pedge->vbo_offset;
        count = static_cast<int>(segment->pedge->nCount);
      }
    } else if (segment->pcs) {
      offset = static_cast<size_t>(segment->pcs->vbo_offset);
      count = 2;
    }
    if (count >= 2) {
      const float* points =
          reinterpret_cast<const float*>(vertex_buffer + offset);
      ChartInspectorAppendSMPartV5(geometry, points, count, chart->ref_lat,
                                   chart->ref_lon);
    }
    segment = segment->next;
  }
  return geometry->latlon.size() >= 4;
}

bool ChartInspectorPluginGeometryV5(PI_S57Obj* obj,
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
}

double ChartInspectorSegmentDistanceV5(double px, double py, double ax,
                                       double ay, double bx, double by,
                                       double* t_out) {
  const double vx = bx - ax;
  const double vy = by - ay;
  const double length2 = vx * vx + vy * vy;
  double t = 0.0;
  if (length2 > 1e-9) {
    t = ((px - ax) * vx + (py - ay) * vy) / length2;
    if (t < 0.0) t = 0.0;
    if (t > 1.0) t = 1.0;
  }
  if (t_out) *t_out = t;
  const double dx = px - (ax + t * vx);
  const double dy = py - (ay + t * vy);
  return std::sqrt(dx * dx + dy * dy);
}

double ChartInspectorGeometryDistanceV5(
    const ViewPort& viewport, double cursor_lat, double cursor_lon,
    const ChartInspectorGeometryV5& geometry, bool close_parts,
    double* nearest_lat, double* nearest_lon) {
  if (geometry.latlon.size() < 4 || geometry.parts.empty())
    return std::numeric_limits<double>::infinity();

  const wxPoint cursor = viewport.GetPixFromLL(cursor_lat, cursor_lon);
  double best = std::numeric_limits<double>::infinity();
  double best_lat = cursor_lat;
  double best_lon = cursor_lon;
  const int point_count = static_cast<int>(geometry.latlon.size() / 2);

  for (size_t part_index = 0; part_index < geometry.parts.size(); ++part_index) {
    const int start = geometry.parts[part_index];
    const int end = part_index + 1 < geometry.parts.size()
                        ? geometry.parts[part_index + 1]
                        : point_count;
    if (end - start < 2) continue;

    auto test_segment = [&](int ia, int ib) {
      const double alat = geometry.latlon[ia * 2];
      const double alon = geometry.latlon[ia * 2 + 1];
      const double blat = geometry.latlon[ib * 2];
      const double blon = geometry.latlon[ib * 2 + 1];
      const wxPoint a = viewport.GetPixFromLL(alat, alon);
      const wxPoint b = viewport.GetPixFromLL(blat, blon);
      double t = 0.0;
      const double distance = ChartInspectorSegmentDistanceV5(
          cursor.x, cursor.y, a.x, a.y, b.x, b.y, &t);
      if (distance < best) {
        best = distance;
        best_lat = alat + (blat - alat) * t;
        best_lon = alon + (blon - alon) * t;
      }
    };

    for (int i = start; i + 1 < end; ++i) test_segment(i, i + 1);
    if (close_parts && end - start > 2) test_segment(end - 1, start);
  }

  if (nearest_lat) *nearest_lat = best_lat;
  if (nearest_lon) *nearest_lon = best_lon;
  return best;
}

double ChartInspectorPointDistanceV5(const ViewPort& viewport,
                                     double cursor_lat, double cursor_lon,
                                     double object_lat, double object_lon) {
  const wxPoint cursor = viewport.GetPixFromLL(cursor_lat, cursor_lon);
  const wxPoint object = viewport.GetPixFromLL(object_lat, object_lon);
  const double dx = static_cast<double>(cursor.x - object.x);
  const double dy = static_cast<double>(cursor.y - object.y);
  return std::sqrt(dx * dx + dy * dy);
}

bool ChartInspectorBetterCandidateV5(double distance, int priority,
                                     double best_distance,
                                     int best_priority) {
  if (distance < best_distance - 0.25) return true;
  return std::fabs(distance - best_distance) <= 0.25 &&
         priority > best_priority;
}

}  // namespace

extern "C" DECL_EXP bool OCPNChartInspectorHitTestV5(
    int canvas_index, double lat, double lon, double radius_pixels,
    const char* feature_filter, char* feature, int feature_size,
    char* object_name, int object_name_size, char* attributes,
    int attributes_size, int* primitive_type, double* marker_lat,
    double* marker_lon, double* geometry_lat_lon,
    int geometry_capacity_points, int* geometry_point_count, int* part_offsets,
    int part_capacity, int* part_count) {
  if (!feature || feature_size <= 0 || !object_name || object_name_size <= 0 ||
      !attributes || attributes_size <= 0 || !primitive_type || !marker_lat ||
      !marker_lon || !geometry_point_count || !part_count)
    return false;

  feature[0] = '\0';
  object_name[0] = '\0';
  attributes[0] = '\0';
  *primitive_type = 1;
  *geometry_point_count = 0;
  *part_count = 0;

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

  const double candidate_radius_pixels = std::max(radius_pixels, 16.0);
  const float select_radius = static_cast<float>(
      candidate_radius_pixels / (viewport.view_scale_ppm * 1852.0 * 60.0));

  double best_distance = std::numeric_limits<double>::infinity();
  int best_priority = -1;
  int best_primitive = 1;
  double best_marker_lat = lat;
  double best_marker_lon = lon;
  char best_feature[32] = {0};
  char best_name[128] = {0};
  wxString best_attributes;
  ChartInspectorGeometryV5 best_geometry;

  auto consider_native = [&](s57chart* chart, S57Obj* obj) {
    if (!chart || !obj ||
        !ChartInspectorFilterMatch(feature_filter, obj->FeatureName))
      return;

    const int primitive = ChartInspectorPrimitiveType(obj->Primitive_type);
    const int priority =
        ChartInspectorV3Priority(obj->FeatureName, obj->Primitive_type);
    double distance = std::numeric_limits<double>::infinity();
    double nearest_lat = obj->m_lat;
    double nearest_lon = obj->m_lon;
    ChartInspectorGeometryV5 geometry;

    if (primitive == 1) {
      distance = ChartInspectorPointDistanceV5(viewport, lat, lon, obj->m_lat,
                                               obj->m_lon);
    } else if (ChartInspectorNativeGeometryV5(chart, obj, &geometry)) {
      distance = ChartInspectorGeometryDistanceV5(
          viewport, lat, lon, geometry, primitive == 3, &nearest_lat,
          &nearest_lon);
    }

    if (distance > radius_pixels + 0.5 ||
        !ChartInspectorBetterCandidateV5(distance, priority, best_distance,
                                         best_priority))
      return;

    best_distance = distance;
    best_priority = priority;
    best_primitive = primitive;
    best_marker_lat = primitive == 1 ? obj->m_lat : nearest_lat;
    best_marker_lon = primitive == 1 ? obj->m_lon : nearest_lon;
    ChartInspectorCopyString(best_feature, sizeof(best_feature),
                             obj->FeatureName);
    wxString name = obj->GetAttrValueAsString("OBJNAM");
    if (name.IsEmpty()) name = obj->GetAttrValueAsString("NOBJNM");
    const wxCharBuffer name_utf8 = name.ToUTF8();
    ChartInspectorCopyString(best_name, sizeof(best_name), name_utf8.data());
    best_attributes = ChartInspectorFormatAttributes(obj);
    best_geometry = geometry;
  };

  auto consider_plugin = [&](PI_S57Obj* obj) {
    if (!obj || !ChartInspectorFilterMatch(feature_filter, obj->FeatureName))
      return;

    const int primitive = ChartInspectorPrimitiveType(obj->Primitive_type);
    const int priority =
        ChartInspectorV3Priority(obj->FeatureName, obj->Primitive_type);
    double distance = std::numeric_limits<double>::infinity();
    double nearest_lat = obj->m_lat;
    double nearest_lon = obj->m_lon;
    ChartInspectorGeometryV5 geometry;

    if (primitive == 1) {
      distance = ChartInspectorPointDistanceV5(viewport, lat, lon, obj->m_lat,
                                               obj->m_lon);
    } else if (ChartInspectorPluginGeometryV5(obj, &geometry)) {
      distance = ChartInspectorGeometryDistanceV5(
          viewport, lat, lon, geometry, primitive == 3, &nearest_lat,
          &nearest_lon);
    }

    if (distance > radius_pixels + 0.5 ||
        !ChartInspectorBetterCandidateV5(distance, priority, best_distance,
                                         best_priority))
      return;

    best_distance = distance;
    best_priority = priority;
    best_primitive = primitive;
    best_marker_lat = primitive == 1 ? obj->m_lat : nearest_lat;
    best_marker_lon = primitive == 1 ? obj->m_lon : nearest_lon;
    ChartInspectorCopyString(best_feature, sizeof(best_feature),
                             obj->FeatureName);
    best_name[0] = '\0';
    best_attributes = ChartInspectorFormatAttributes(obj);
    best_geometry = geometry;
  };

  if (auto* native_chart = dynamic_cast<s57chart*>(target_chart)) {
    ListOfObjRazRules* rules = native_chart->GetObjRuleListAtLatLon(
        static_cast<float>(lat), static_cast<float>(lon), select_radius,
        &viewport, MASK_ALL);
    if (rules) {
      for (auto* node = rules->GetFirst(); node; node = node->GetNext()) {
        ObjRazRules* rule = node->GetData();
        if (rule) consider_native(native_chart, rule->obj);
      }
      rules->Clear();
      delete rules;
    }
  } else if (auto* plugin_chart =
                 dynamic_cast<ChartPlugInWrapper*>(target_chart)) {
    if (s_ppim) {
      ListOfPI_S57Obj* objects = s_ppim->GetPlugInObjRuleListAtLatLon(
          plugin_chart, static_cast<float>(lat), static_cast<float>(lon),
          select_radius, viewport);
      if (objects) {
        for (auto* node = objects->GetFirst(); node; node = node->GetNext())
          consider_plugin(node->GetData());
        objects->Clear();
        delete objects;
      }
    }
  }

  if (best_priority < 0) return false;

  ChartInspectorCopyString(feature, feature_size, best_feature);
  ChartInspectorCopyString(object_name, object_name_size, best_name);
  const wxCharBuffer attrs_utf8 = best_attributes.ToUTF8();
  ChartInspectorCopyString(attributes, attributes_size, attrs_utf8.data());
  *primitive_type = best_primitive;
  *marker_lat = best_marker_lat;
  *marker_lon = best_marker_lon;

  if (geometry_lat_lon && geometry_capacity_points > 0 &&
      best_geometry.latlon.size() >= 4) {
    const int available_points =
        static_cast<int>(best_geometry.latlon.size() / 2);
    const int copy_points = std::min(available_points, geometry_capacity_points);
    for (int i = 0; i < copy_points; ++i) {
      geometry_lat_lon[i * 2] = best_geometry.latlon[i * 2];
      geometry_lat_lon[i * 2 + 1] = best_geometry.latlon[i * 2 + 1];
    }
    *geometry_point_count = copy_points;

    if (part_offsets && part_capacity > 0) {
      int copied_parts = 0;
      for (size_t i = 0; i < best_geometry.parts.size() &&
                         copied_parts < part_capacity;
           ++i) {
        if (best_geometry.parts[i] >= copy_points) break;
        part_offsets[copied_parts++] = best_geometry.parts[i];
      }
      *part_count = copied_parts;
    }
  }

  return true;
}
]===])

string(FIND "${SRC}" "bool GetGlobalColor(wxString colorName, wxColour* pcolour)" POS_GLOBAL_COLOR)
if(POS_GLOBAL_COLOR EQUAL -1)
  message(FATAL_ERROR "Could not find GetGlobalColor anchor in ${TARGET}")
endif()

string(REPLACE
  "bool GetGlobalColor(wxString colorName, wxColour* pcolour)"
  "${V5_CODE}\nbool GetGlobalColor(wxString colorName, wxColour* pcolour)"
  SRC "${SRC}")

file(WRITE "${TARGET}" "${SRC}")
message(STATUS "Installed Chart Inspector V5 geometry-aware hit test in ${TARGET}")
