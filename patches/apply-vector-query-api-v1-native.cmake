if(NOT DEFINED OPENCPN_ROOT)
  message(FATAL_ERROR "OPENCPN_ROOT is required, e.g. -DOPENCPN_ROOT=C:/Users/Johannes/source/OpenCPN")
endif()

file(TO_CMAKE_PATH "${OPENCPN_ROOT}" OPENCPN_ROOT)
set(HEADER "${OPENCPN_ROOT}/include/ocpn_plugin.h")
set(IMPL "${OPENCPN_ROOT}/gui/src/ocpn_plugin_gui.cpp")

foreach(PATH "${HEADER}" "${IMPL}")
  if(NOT EXISTS "${PATH}")
    message(FATAL_ERROR "OpenCPN source file not found: ${PATH}")
  endif()
endforeach()

# -----------------------------------------------------------------------------
# Public API declarations
# -----------------------------------------------------------------------------
file(READ "${HEADER}" H)

if(NOT H MATCHES "PI_VectorObjectV1")
  set(API_TYPES [===[
// ----------------------------------------------------------------------------
// Vector chart object query API v1
//
// All data passed across plugin boundaries is POD and borrowed only for the
// duration of the callback. Consumers must copy anything they want to retain.
// Geometry coordinates are WGS84 latitude/longitude decimal degrees.
// ----------------------------------------------------------------------------

enum PI_VectorGeometryTypeV1 : uint32_t {
  PI_VECTOR_GEOMETRY_UNKNOWN_V1 = 0,
  PI_VECTOR_GEOMETRY_POINT_V1 = 1,
  PI_VECTOR_GEOMETRY_LINE_V1 = 2,
  PI_VECTOR_GEOMETRY_AREA_V1 = 3
};

struct PI_VectorQueryV1 {
  uint32_t struct_size;
  double lat;
  double lon;
  double search_radius_pixels;
  const char *feature_filter_utf8;
};

struct PI_VectorPositionV1 {
  double lat;
  double lon;
};

struct PI_VectorPartV1 {
  uint32_t first_point;
  uint32_t point_count;
};

struct PI_VectorAttributeV1 {
  const char *name_utf8;
  const char *value_utf8;
};

struct PI_VectorObjectV1 {
  uint32_t struct_size;
  uint32_t geometry_type;
  const char *feature_class_utf8;
  const char *object_name_utf8;
  const PI_VectorPositionV1 *points;
  uint32_t point_count;
  const PI_VectorPartV1 *parts;
  uint32_t part_count;
  const PI_VectorAttributeV1 *attributes;
  uint32_t attribute_count;
};

typedef bool (*PI_VectorObjectSinkV1)(const PI_VectorObjectV1 *object,
                                      void *user_data);

// Query nearby vector-chart candidates on a canvas. The callback receives
// borrowed data which is valid only until the callback returns.
extern "C" DECL_EXP bool QueryVectorChartObjectsV1(
    int canvas_index, const PI_VectorQueryV1 *query,
    PI_VectorObjectSinkV1 sink, void *user_data);

]===])

  string(FIND "${H}" "// ----------------------------------------------------------------------------\n// PlugInChartBaseGLPlus2" API_INSERT)
  if(API_INSERT EQUAL -1)
    message(FATAL_ERROR "Could not locate PlugInChartBaseGLPlus2 anchor in ${HEADER}")
  endif()
  string(SUBSTRING "${H}" 0 ${API_INSERT} H_PREFIX)
  string(SUBSTRING "${H}" ${API_INSERT} -1 H_SUFFIX)
  set(H "${H_PREFIX}${API_TYPES}${H_SUFFIX}")
endif()

if(NOT H MATCHES "PlugInChartBaseGLPlus3")
  set(PLUS3 [===[

// ----------------------------------------------------------------------------
// PlugInChartBaseGLPlus3
// Optional provider-side vector-object geometry query extension.
// ----------------------------------------------------------------------------
class DECL_EXP PlugInChartBaseGLPlus3 : public PlugInChartBaseGLPlus2 {
public:
  PlugInChartBaseGLPlus3();
  virtual ~PlugInChartBaseGLPlus3();

  virtual bool QueryVectorObjectsV1(const PI_VectorQueryV1 *query,
                                    const PlugIn_ViewPort *viewport,
                                    PI_VectorObjectSinkV1 sink,
                                    void *user_data);
};
]===])

  string(FIND "${H}" "// ----------------------------------------------------------------------------\n// PlugInChartBaseExtended" PLUS3_INSERT)
  if(PLUS3_INSERT EQUAL -1)
    message(FATAL_ERROR "Could not locate PlugInChartBaseExtended anchor in ${HEADER}")
  endif()
  string(SUBSTRING "${H}" 0 ${PLUS3_INSERT} H_PREFIX)
  string(SUBSTRING "${H}" ${PLUS3_INSERT} -1 H_SUFFIX)
  set(H "${H_PREFIX}${PLUS3}\n${H_SUFFIX}")
endif()

file(WRITE "${HEADER}" "${H}")

# -----------------------------------------------------------------------------
# Core implementation: native S-57 only for the first prototype.
# Plugin chart providers are deliberately NOT queried yet.
# -----------------------------------------------------------------------------
file(READ "${IMPL}" C)

foreach(INCLUDE_LINE "#include <algorithm>" "#include <cmath>" "#include <set>" "#include <string>" "#include <vector>")
  string(FIND "${C}" "${INCLUDE_LINE}" INCLUDE_POS)
  if(INCLUDE_POS EQUAL -1)
    string(REPLACE "#include <vector>" "#include <vector>\n${INCLUDE_LINE}" C "${C}")
  endif()
endforeach()

string(FIND "${C}" "#include \"model/georef.h\"" GEOREF_POS)
if(GEOREF_POS EQUAL -1)
  string(REPLACE "#include \"model/gui_vars.h\"" "#include \"model/gui_vars.h\"\n#include \"model/georef.h\"" C "${C}")
endif()

if(NOT C MATCHES "PlugInChartBaseGLPlus3::PlugInChartBaseGLPlus3")
  set(PLUS3_IMPL [===[

PlugInChartBaseGLPlus3::PlugInChartBaseGLPlus3() = default;
PlugInChartBaseGLPlus3::~PlugInChartBaseGLPlus3() = default;

bool PlugInChartBaseGLPlus3::QueryVectorObjectsV1(
    const PI_VectorQueryV1 *query, const PlugIn_ViewPort *viewport,
    PI_VectorObjectSinkV1 sink, void *user_data) {
  (void)query;
  (void)viewport;
  (void)sink;
  (void)user_data;
  return false;
}
]===])

  string(FIND "${C}" "PlugInChartBaseGLPlus2::PlugInChartBaseGLPlus2" PLUS2_IMPL)
  if(PLUS2_IMPL EQUAL -1)
    message(FATAL_ERROR "Could not locate PlugInChartBaseGLPlus2 implementation anchor in ${IMPL}")
  endif()
  # Put the Plus3 default methods immediately before Plus2 implementation.
  string(SUBSTRING "${C}" 0 ${PLUS2_IMPL} C_PREFIX)
  string(SUBSTRING "${C}" ${PLUS2_IMPL} -1 C_SUFFIX)
  set(C "${C_PREFIX}${PLUS3_IMPL}\n${C_SUFFIX}")
endif()

if(NOT C MATCHES "QueryVectorChartObjectsV1\\(")
  set(QUERY_IMPL [===[

namespace {

struct VectorQueryGeometryV1 {
  std::vector<PI_VectorPositionV1> points;
  std::vector<PI_VectorPartV1> parts;
};

bool VectorQueryFilterMatchV1(const char *filter, const char *feature) {
  if (!feature || !feature[0]) return false;
  if (!filter || !filter[0]) return true;

  wxString candidate = wxString::FromUTF8(feature).Upper();
  wxStringTokenizer tokens(wxString::FromUTF8(filter), ",; \t\r\n",
                           wxTOKEN_STRTOK);
  while (tokens.HasMoreTokens()) {
    wxString token = tokens.GetNextToken().Upper();
    token.Trim(true);
    token.Trim(false);
    if (token.IsEmpty()) continue;
    if (token.EndsWith("*")) {
      token.RemoveLast();
      if (!token.IsEmpty() && candidate.StartsWith(token)) return true;
    } else if (candidate == token) {
      return true;
    }
  }
  return false;
}

void VectorQueryBeginPartV1(VectorQueryGeometryV1 *geometry) {
  if (!geometry) return;
  PI_VectorPartV1 part{};
  part.first_point = static_cast<uint32_t>(geometry->points.size());
  part.point_count = 0;
  geometry->parts.push_back(part);
}

void VectorQueryAppendPointV1(VectorQueryGeometryV1 *geometry, double lat,
                              double lon) {
  if (!geometry || !std::isfinite(lat) || !std::isfinite(lon)) return;
  geometry->points.push_back({lat, lon});
  if (!geometry->parts.empty()) ++geometry->parts.back().point_count;
}

void VectorQueryAppendSMPartV1(VectorQueryGeometryV1 *geometry,
                               const float *points, int count,
                               double ref_lat, double ref_lon) {
  if (!geometry || !points || count < 2) return;
  VectorQueryBeginPartV1(geometry);
  for (int i = 0; i < count; ++i) {
    double lat = 0.0;
    double lon = 0.0;
    fromSM(points[i * 2], points[i * 2 + 1], ref_lat, ref_lon, &lat, &lon);
    VectorQueryAppendPointV1(geometry, lat, lon);
  }
  if (!geometry->parts.empty() && geometry->parts.back().point_count < 2)
    geometry->parts.pop_back();
}

bool VectorQueryNativeGeometryV1(s57chart *chart, S57Obj *obj,
                                 VectorQueryGeometryV1 *geometry) {
  if (!chart || !obj || !geometry) return false;
  geometry->points.clear();
  geometry->parts.clear();

  if (obj->Primitive_type == GEO_POINT) {
    VectorQueryAppendPointV1(geometry, obj->m_lat, obj->m_lon);
    return geometry->points.size() == 1;
  }

  if (obj->geoPt && obj->npt >= 2 && obj->npt <= 16384) {
    VectorQueryBeginPartV1(geometry);
    for (int i = 0; i < obj->npt; ++i) {
      const double east = obj->geoPt[i].x * obj->x_rate + obj->x_origin;
      const double north = obj->geoPt[i].y * obj->y_rate + obj->y_origin;
      double lat = 0.0;
      double lon = 0.0;
      fromSM(east, north, chart->ref_lat, chart->ref_lon, &lat, &lon);
      VectorQueryAppendPointV1(geometry, lat, lon);
    }
    if (geometry->points.size() >= 2) return true;
    geometry->points.clear();
    geometry->parts.clear();
  }

  unsigned char *vertex_buffer =
      reinterpret_cast<unsigned char *>(chart->GetLineVertexBuffer());
  line_segment_element *segment = obj->m_ls_list;
  int segment_guard = 0;
  while (segment && vertex_buffer && segment_guard++ < 4096 &&
         geometry->points.size() < 16384) {
    size_t offset = 0;
    int count = 0;
    bool reverse = false;

    if ((segment->ls_type == TYPE_EE) ||
        (segment->ls_type == TYPE_EE_REV)) {
      if (segment->pedge) {
        offset = segment->pedge->vbo_offset;
        count = static_cast<int>(segment->pedge->nCount);
        reverse = segment->ls_type == TYPE_EE_REV;
      }
    } else if (segment->pcs) {
      offset = static_cast<size_t>(segment->pcs->vbo_offset);
      count = 2;
    }

    if (count >= 2 && count <= 16384 &&
        geometry->points.size() + static_cast<size_t>(count) <= 16384) {
      const float *source =
          reinterpret_cast<const float *>(vertex_buffer + offset);
      VectorQueryBeginPartV1(geometry);
      if (reverse) {
        for (int i = count - 1; i >= 0; --i) {
          double lat = 0.0;
          double lon = 0.0;
          fromSM(source[i * 2], source[i * 2 + 1], chart->ref_lat,
                 chart->ref_lon, &lat, &lon);
          VectorQueryAppendPointV1(geometry, lat, lon);
        }
      } else {
        for (int i = 0; i < count; ++i) {
          double lat = 0.0;
          double lon = 0.0;
          fromSM(source[i * 2], source[i * 2 + 1], chart->ref_lat,
                 chart->ref_lon, &lat, &lon);
          VectorQueryAppendPointV1(geometry, lat, lon);
        }
      }
      if (!geometry->parts.empty() && geometry->parts.back().point_count < 2)
        geometry->parts.pop_back();
    }
    segment = segment->next;
  }

  return geometry->points.size() >= 2 && !geometry->parts.empty();
}

uint32_t VectorQueryGeometryTypeV1(const S57Obj *obj) {
  if (!obj) return PI_VECTOR_GEOMETRY_UNKNOWN_V1;
  switch (obj->Primitive_type) {
    case GEO_POINT:
      return PI_VECTOR_GEOMETRY_POINT_V1;
    case GEO_LINE:
      return PI_VECTOR_GEOMETRY_LINE_V1;
    case GEO_AREA:
      return PI_VECTOR_GEOMETRY_AREA_V1;
    default:
      return PI_VECTOR_GEOMETRY_UNKNOWN_V1;
  }
}

bool VectorQueryEmitNativeObjectV1(s57chart *chart, S57Obj *obj,
                                   PI_VectorObjectSinkV1 sink,
                                   void *user_data) {
  if (!chart || !obj || !sink) return true;

  VectorQueryGeometryV1 geometry;
  if (!VectorQueryNativeGeometryV1(chart, obj, &geometry)) return true;

  const uint32_t geometry_type = VectorQueryGeometryTypeV1(obj);
  if (geometry_type == PI_VECTOR_GEOMETRY_UNKNOWN_V1) return true;

  std::string feature(obj->FeatureName,
                      strnlen(obj->FeatureName, sizeof(obj->FeatureName)));
  if (feature.empty()) return true;

  wxString object_name = obj->GetAttrValueAsString("OBJNAM");
  if (object_name.IsEmpty()) object_name = obj->GetAttrValueAsString("NOBJNM");
  const wxCharBuffer object_name_utf8 = object_name.ToUTF8();

  std::vector<std::string> attr_names;
  std::vector<std::string> attr_values;
  std::vector<PI_VectorAttributeV1> attributes;
  const int attr_count = std::max(0, std::min(obj->n_attr, 512));
  attr_names.reserve(attr_count);
  attr_values.reserve(attr_count);
  attributes.reserve(attr_count);

  if (obj->att_array && obj->attVal) {
    for (int i = 0; i < attr_count; ++i) {
      char acronym[7] = {0};
      memcpy(acronym, obj->att_array + i * 6, 6);
      if (!acronym[0]) continue;
      wxString value = obj->GetAttrValueAsString(acronym);
      const wxCharBuffer value_utf8 = value.ToUTF8();
      attr_names.emplace_back(acronym);
      attr_values.emplace_back(value_utf8.data() ? value_utf8.data() : "");
    }
  }

  attributes.reserve(attr_names.size());
  for (size_t i = 0; i < attr_names.size(); ++i)
    attributes.push_back({attr_names[i].c_str(), attr_values[i].c_str()});

  PI_VectorObjectV1 result{};
  result.struct_size = sizeof(result);
  result.geometry_type = geometry_type;
  result.feature_class_utf8 = feature.c_str();
  result.object_name_utf8 = object_name_utf8.data();
  result.points = geometry.points.empty() ? nullptr : geometry.points.data();
  result.point_count = static_cast<uint32_t>(geometry.points.size());
  result.parts = geometry.parts.empty() ? nullptr : geometry.parts.data();
  result.part_count = static_cast<uint32_t>(geometry.parts.size());
  result.attributes = attributes.empty() ? nullptr : attributes.data();
  result.attribute_count = static_cast<uint32_t>(attributes.size());

  return sink(&result, user_data);
}

}  // namespace

extern "C" DECL_EXP bool QueryVectorChartObjectsV1(
    int canvas_index, const PI_VectorQueryV1 *query,
    PI_VectorObjectSinkV1 sink, void *user_data) {
  if (!query || query->struct_size < sizeof(PI_VectorQueryV1) || !sink)
    return false;
  if (!std::isfinite(query->lat) || !std::isfinite(query->lon) ||
      !std::isfinite(query->search_radius_pixels))
    return false;
  if (canvas_index < 0 ||
      static_cast<size_t>(canvas_index) >= g_canvasArray.GetCount())
    return false;

  ChartCanvas *canvas = g_canvasArray.Item(canvas_index);
  if (!canvas) return false;
  ViewPort &viewport = canvas->GetVP();
  if (!viewport.IsValid() || viewport.view_scale_ppm <= 0.0) return false;

  const wxPoint query_pixel = viewport.GetPixFromLL(query->lat, query->lon);
  ChartBase *target_chart = nullptr;
  if (canvas->m_singleChart &&
      canvas->m_singleChart->GetChartFamily() == CHART_FAMILY_VECTOR) {
    target_chart = canvas->m_singleChart;
  } else if (viewport.b_quilt && canvas->m_pQuilt) {
    target_chart = canvas->m_pQuilt->GetChartAtPix(viewport, query_pixel);
  }

  auto *native_chart = dynamic_cast<s57chart *>(target_chart);
  if (!native_chart) {
    // Provider chart support is intentionally deferred to Plus3 implementation.
    return false;
  }

  const double radius_pixels =
      std::max(1.0, std::min(query->search_radius_pixels, 64.0));
  const float select_radius = static_cast<float>(
      radius_pixels / (viewport.view_scale_ppm * 1852.0 * 60.0));

  ListOfObjRazRules *rules = native_chart->GetObjRuleListAtLatLon(
      static_cast<float>(query->lat), static_cast<float>(query->lon),
      select_radius, &viewport, MASK_ALL);
  if (!rules) return true;

  std::set<S57Obj *> emitted;
  bool keep_going = true;
  int emitted_count = 0;
  for (auto *node = rules->GetFirst(); node && keep_going;
       node = node->GetNext()) {
    ObjRazRules *rule = node->GetData();
    S57Obj *obj = rule ? rule->obj : nullptr;
    if (!obj || emitted.count(obj)) continue;
    emitted.insert(obj);

    if (!VectorQueryFilterMatchV1(query->feature_filter_utf8,
                                  obj->FeatureName))
      continue;
    if (++emitted_count > 256) break;

    keep_going = VectorQueryEmitNativeObjectV1(native_chart, obj, sink,
                                               user_data);
  }

  rules->Clear();
  delete rules;
  return true;
}
]===])

  # Insert before GetGlobalColor, keeping the exported API close to other
  # plugin-callable GUI/core functions.
  string(FIND "${C}" "bool GetGlobalColor(wxString colorName, wxColour* pcolour)" QUERY_INSERT)
  if(QUERY_INSERT EQUAL -1)
    message(FATAL_ERROR "Could not locate GetGlobalColor anchor in ${IMPL}")
  endif()
  string(SUBSTRING "${C}" 0 ${QUERY_INSERT} C_PREFIX)
  string(SUBSTRING "${C}" ${QUERY_INSERT} -1 C_SUFFIX)
  set(C "${C_PREFIX}${QUERY_IMPL}\n${C_SUFFIX}")
endif()

file(WRITE "${IMPL}" "${C}")

message(STATUS "Installed Vector Object Query API v1 declarations in ${HEADER}")
message(STATUS "Installed native S-57 QueryVectorChartObjectsV1 implementation in ${IMPL}")
message(STATUS "Plugin-chart provider support is intentionally not enabled yet.")
