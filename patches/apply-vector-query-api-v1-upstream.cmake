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
# Upstream-shaped Vector Object Query API v1
#
# Goals:
#   * generic OpenCPN plugin API, not Chart Inspector-specific
#   * ABI-safe POD/callback boundary
#   * native S-57 support in core
#   * optional GLPlus3 and ExtendedPlus3 chart-provider dispatch
#   * no STL/wx ownership across plugin DLL boundaries
#   * no provider-side feature filtering in v1
#
# This installer is intentionally idempotent so it can be iterated locally.
# -----------------------------------------------------------------------------

file(READ "${HEADER}" H)

# On current upstream master this proposal is expected to become the next
# plugin API minor version after 1.21. Do not downgrade or rewrite later APIs.
if(H MATCHES "#define API_VERSION_MAJOR 1\n#define API_VERSION_MINOR 21")
  string(REPLACE
    "#define API_VERSION_MAJOR 1\n#define API_VERSION_MINOR 21"
    "#define API_VERSION_MAJOR 1\n#define API_VERSION_MINOR 22"
    H "${H}")
  message(STATUS "Bumped experimental plugin API version 1.21 -> 1.22")
endif()

# Replace the earlier local prototype query structure if it is present. The
# upstream v1 contract intentionally omits feature_filter_utf8; filtering is a
# consumer policy and keeping it out makes provider implementations simpler.
string(REPLACE
"struct PI_VectorQueryV1 {\n  uint32_t struct_size;\n  double lat;\n  double lon;\n  double search_radius_pixels;\n  const char *feature_filter_utf8;\n};"
"struct PI_VectorQueryV1 {\n  uint32_t struct_size;\n  double lat;\n  double lon;\n  double search_radius_pixels;\n};"
H "${H}")

if(NOT H MATCHES "struct PI_VectorObjectV1")
  set(API_TYPES [===[

// ----------------------------------------------------------------------------
// Vector chart object query API v1
//
// All pointers supplied through PI_VectorObjectSinkV1 are borrowed and valid
// only until the callback returns. Consumers must copy retained data.
// Geometry coordinates are WGS84 decimal-degree latitude/longitude.
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

// Enumerate nearby vector-chart object candidates on a canvas. Returning true
// includes the valid case where no candidates are emitted. Returning false
// means the query is unsupported or could not be executed.
extern "C" DECL_EXP bool QueryVectorChartObjectsV1(
    int canvas_index, const PI_VectorQueryV1 *query,
    PI_VectorObjectSinkV1 sink, void *user_data);

]===])

  string(FIND "${H}" "// ----------------------------------------------------------------------------\n// PlugInChartBaseGLPlus2" API_INSERT)
  if(API_INSERT EQUAL -1)
    message(FATAL_ERROR "Could not locate PlugInChartBaseGLPlus2 declaration anchor in ${HEADER}")
  endif()
  string(SUBSTRING "${H}" 0 ${API_INSERT} PREFIX)
  string(SUBSTRING "${H}" ${API_INSERT} -1 SUFFIX)
  set(H "${PREFIX}${API_TYPES}${SUFFIX}")
endif()

if(NOT H MATCHES "class DECL_EXP PlugInChartBaseGLPlus3")
  set(GL_PLUS3 [===[

// ----------------------------------------------------------------------------
// PlugInChartBaseGLPlus3
// Optional vector-object query extension for GL chart providers.
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

  string(FIND "${H}" "// ----------------------------------------------------------------------------\n// PlugInChartBaseExtended" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate GL provider declaration insertion anchor")
  endif()
  string(SUBSTRING "${H}" 0 ${POS} PREFIX)
  string(SUBSTRING "${H}" ${POS} -1 SUFFIX)
  set(H "${PREFIX}${GL_PLUS3}\n${SUFFIX}")
endif()

if(NOT H MATCHES "class DECL_EXP PlugInChartBaseExtendedPlus3")
  set(EXT_PLUS3 [===[

// ----------------------------------------------------------------------------
// PlugInChartBaseExtendedPlus3
// Optional vector-object query extension for Extended chart providers.
// ----------------------------------------------------------------------------
class DECL_EXP PlugInChartBaseExtendedPlus3
    : public PlugInChartBaseExtendedPlus2 {
public:
  PlugInChartBaseExtendedPlus3();
  virtual ~PlugInChartBaseExtendedPlus3();

  virtual bool QueryVectorObjectsV1(const PI_VectorQueryV1 *query,
                                    const PlugIn_ViewPort *viewport,
                                    PI_VectorObjectSinkV1 sink,
                                    void *user_data);
};
]===])

  # Existing OpenCPN headers place forward declarations for PI S-57 helper
  # arrays immediately after the Extended chart-provider hierarchy.
  string(FIND "${H}" "class wxArrayOfS57attVal;" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate Extended provider declaration insertion anchor")
  endif()
  string(SUBSTRING "${H}" 0 ${POS} PREFIX)
  string(SUBSTRING "${H}" ${POS} -1 SUFFIX)
  set(H "${PREFIX}${EXT_PLUS3}\n${SUFFIX}")
endif()

file(WRITE "${HEADER}" "${H}")

# -----------------------------------------------------------------------------
# Core implementation
# -----------------------------------------------------------------------------
file(READ "${IMPL}" C)

foreach(INCLUDE_LINE
        "#include <algorithm>"
        "#include <cmath>"
        "#include <cstring>"
        "#include <set>"
        "#include <string>"
        "#include <vector>")
  string(FIND "${C}" "${INCLUDE_LINE}" INCLUDE_POS)
  if(INCLUDE_POS EQUAL -1)
    string(REPLACE "#include <vector>" "#include <vector>\n${INCLUDE_LINE}" C "${C}")
  endif()
endforeach()

string(FIND "${C}" "#include \"model/georef.h\"" GEOREF_POS)
if(GEOREF_POS EQUAL -1)
  string(REPLACE "#include \"model/gui_vars.h\""
                 "#include \"model/gui_vars.h\"\n#include \"model/georef.h\""
                 C "${C}")
endif()

if(NOT C MATCHES "PlugInChartBaseGLPlus3::PlugInChartBaseGLPlus3")
  set(GL_DEFAULTS [===[

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
  string(FIND "${C}" "bool GetGlobalColor(wxString colorName, wxColour* pcolour)" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate GetGlobalColor implementation anchor")
  endif()
  string(SUBSTRING "${C}" 0 ${POS} PREFIX)
  string(SUBSTRING "${C}" ${POS} -1 SUFFIX)
  set(C "${PREFIX}${GL_DEFAULTS}${SUFFIX}")
endif()

if(NOT C MATCHES "PlugInChartBaseExtendedPlus3::PlugInChartBaseExtendedPlus3")
  set(EXT_DEFAULTS [===[

PlugInChartBaseExtendedPlus3::PlugInChartBaseExtendedPlus3() = default;
PlugInChartBaseExtendedPlus3::~PlugInChartBaseExtendedPlus3() = default;

bool PlugInChartBaseExtendedPlus3::QueryVectorObjectsV1(
    const PI_VectorQueryV1 *query, const PlugIn_ViewPort *viewport,
    PI_VectorObjectSinkV1 sink, void *user_data) {
  (void)query;
  (void)viewport;
  (void)sink;
  (void)user_data;
  return false;
}

]===])
  string(FIND "${C}" "bool GetGlobalColor(wxString colorName, wxColour* pcolour)" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate GetGlobalColor implementation anchor")
  endif()
  string(SUBSTRING "${C}" 0 ${POS} PREFIX)
  string(SUBSTRING "${C}" ${POS} -1 SUFFIX)
  set(C "${PREFIX}${EXT_DEFAULTS}${SUFFIX}")
endif()

# Upgrade the earlier native-only prototype by removing its feature-filter
# helper and filter call if present. The helper can remain harmlessly in a
# previously patched local tree, but the final query path must not depend on it.
string(REPLACE
"    if (!VectorQueryFilterMatchV1(query->feature_filter_utf8,\n                                  obj->FeatureName))\n      continue;\n"
""
C "${C}")

if(NOT C MATCHES "QueryVectorChartObjectsV1\\(")
  set(QUERY_IMPL [===[

namespace {

constexpr uint32_t kVectorQueryMaxCandidatesV1 = 256;
constexpr uint32_t kVectorQueryMaxPointsV1 = 16384;
constexpr uint32_t kVectorQueryMaxPartsV1 = 1024;
constexpr uint32_t kVectorQueryMaxAttributesV1 = 512;

struct VectorQueryGeometryV1 {
  std::vector<PI_VectorPositionV1> points;
  std::vector<PI_VectorPartV1> parts;
};

void VectorQueryBeginPartV1(VectorQueryGeometryV1 *geometry) {
  PI_VectorPartV1 part{};
  part.first_point = static_cast<uint32_t>(geometry->points.size());
  geometry->parts.push_back(part);
}

void VectorQueryAppendPointV1(VectorQueryGeometryV1 *geometry, double lat,
                              double lon) {
  if (!std::isfinite(lat) || !std::isfinite(lon)) return;
  if (geometry->points.size() >= kVectorQueryMaxPointsV1) return;
  geometry->points.push_back({lat, lon});
  if (!geometry->parts.empty()) ++geometry->parts.back().point_count;
}

uint32_t VectorQueryGeometryTypeV1(const S57Obj *obj) {
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

bool VectorQueryNativeGeometryV1(s57chart *chart, S57Obj *obj,
                                 VectorQueryGeometryV1 *geometry) {
  if (obj->Primitive_type == GEO_POINT) {
    VectorQueryAppendPointV1(geometry, obj->m_lat, obj->m_lon);
    return geometry->points.size() == 1;
  }

  if (obj->geoPt && obj->npt >= 2 &&
      obj->npt <= static_cast<int>(kVectorQueryMaxPointsV1)) {
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
  int guard = 0;

  while (segment && vertex_buffer && guard++ < 4096 &&
         geometry->points.size() < kVectorQueryMaxPointsV1 &&
         geometry->parts.size() < kVectorQueryMaxPartsV1) {
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

    if (count >= 2 &&
        count <= static_cast<int>(kVectorQueryMaxPointsV1) &&
        geometry->points.size() + static_cast<size_t>(count) <=
            kVectorQueryMaxPointsV1) {
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
      if (!geometry->parts.empty() &&
          geometry->parts.back().point_count < 2)
        geometry->parts.pop_back();
    }
    segment = segment->next;
  }

  return geometry->points.size() >= 2 && !geometry->parts.empty();
}

bool VectorQueryEmitNativeObjectV1(s57chart *chart, S57Obj *obj,
                                   PI_VectorObjectSinkV1 sink,
                                   void *user_data) {
  const uint32_t geometry_type = VectorQueryGeometryTypeV1(obj);
  if (geometry_type == PI_VECTOR_GEOMETRY_UNKNOWN_V1) return true;

  VectorQueryGeometryV1 geometry;
  if (!VectorQueryNativeGeometryV1(chart, obj, &geometry)) return true;

  std::string feature(obj->FeatureName,
                      strnlen(obj->FeatureName, sizeof(obj->FeatureName)));
  if (feature.empty()) return true;

  wxString object_name = obj->GetAttrValueAsString("OBJNAM");
  if (object_name.IsEmpty()) object_name = obj->GetAttrValueAsString("NOBJNM");
  const wxCharBuffer object_name_utf8 = object_name.ToUTF8();

  std::vector<std::string> attr_names;
  std::vector<std::string> attr_values;
  std::vector<PI_VectorAttributeV1> attributes;
  const int attr_count =
      std::max(0, std::min(obj->n_attr,
                           static_cast<int>(kVectorQueryMaxAttributesV1)));
  attr_names.reserve(attr_count);
  attr_values.reserve(attr_count);

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

struct VectorQueryProviderForwardV1 {
  PI_VectorObjectSinkV1 sink;
  void *user_data;
  uint32_t emitted;
};

bool VectorQueryProviderSinkV1(const PI_VectorObjectV1 *object,
                               void *user_data) {
  auto *forward = static_cast<VectorQueryProviderForwardV1 *>(user_data);
  if (!forward || !forward->sink || !object) return false;
  if (forward->emitted >= kVectorQueryMaxCandidatesV1) return false;
  if (object->struct_size < sizeof(PI_VectorObjectV1)) return true;
  if (!object->feature_class_utf8 || !object->feature_class_utf8[0]) return true;
  if (object->geometry_type < PI_VECTOR_GEOMETRY_POINT_V1 ||
      object->geometry_type > PI_VECTOR_GEOMETRY_AREA_V1)
    return true;
  if (object->point_count > kVectorQueryMaxPointsV1 ||
      object->part_count > kVectorQueryMaxPartsV1 ||
      object->attribute_count > kVectorQueryMaxAttributesV1)
    return true;
  if (object->point_count && !object->points) return true;
  if (object->part_count && !object->parts) return true;
  if (object->attribute_count && !object->attributes) return true;

  for (uint32_t i = 0; i < object->point_count; ++i) {
    if (!std::isfinite(object->points[i].lat) ||
        !std::isfinite(object->points[i].lon))
      return true;
  }
  for (uint32_t i = 0; i < object->part_count; ++i) {
    const PI_VectorPartV1 &part = object->parts[i];
    if (part.first_point > object->point_count ||
        part.point_count > object->point_count - part.first_point)
      return true;
  }

  ++forward->emitted;
  return forward->sink(object, forward->user_data);
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
  if (!target_chart) return false;

  if (auto *native_chart = dynamic_cast<s57chart *>(target_chart)) {
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
    uint32_t emitted_count = 0;
    for (auto *node = rules->GetFirst(); node && keep_going;
         node = node->GetNext()) {
      ObjRazRules *rule = node->GetData();
      S57Obj *obj = rule ? rule->obj : nullptr;
      if (!obj || emitted.count(obj)) continue;
      emitted.insert(obj);
      if (emitted_count++ >= kVectorQueryMaxCandidatesV1) break;
      keep_going = VectorQueryEmitNativeObjectV1(native_chart, obj, sink,
                                                 user_data);
    }

    rules->Clear();
    delete rules;
    return true;
  }

  auto *wrapper = dynamic_cast<ChartPlugInWrapper *>(target_chart);
  if (!wrapper) return false;

  PlugIn_ViewPort pi_vp = CreatePlugInViewportEx(viewport);
  VectorQueryProviderForwardV1 forward{sink, user_data, 0};

  if (auto *provider_gl = dynamic_cast<PlugInChartBaseGLPlus3 *>(
          wrapper->GetPlugInChart())) {
    return provider_gl->QueryVectorObjectsV1(
        query, &pi_vp, VectorQueryProviderSinkV1, &forward);
  }

  if (auto *provider_ext = dynamic_cast<PlugInChartBaseExtendedPlus3 *>(
          wrapper->GetPlugInChart())) {
    return provider_ext->QueryVectorObjectsV1(
        query, &pi_vp, VectorQueryProviderSinkV1, &forward);
  }

  return false;
}
]===])

  string(FIND "${C}" "bool GetGlobalColor(wxString colorName, wxColour* pcolour)" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate QueryVectorChartObjectsV1 insertion anchor")
  endif()
  string(SUBSTRING "${C}" 0 ${POS} PREFIX)
  string(SUBSTRING "${C}" ${POS} -1 SUFFIX)
  set(C "${PREFIX}${QUERY_IMPL}\n${SUFFIX}")
else()
  # Upgrade the provider dispatch in an already patched prototype tree if it is
  # still native-only. This keeps local development moving without requiring a
  # complete source reset.
  set(NATIVE_ONLY [===[
  auto *native_chart = dynamic_cast<s57chart *>(target_chart);
  if (!native_chart) {
    // Provider chart support is intentionally deferred to Plus3 implementation.
    return false;
  }
]===])
  if(C MATCHES "Provider chart support is intentionally deferred")
    message(WARNING "Existing prototype QueryVectorChartObjectsV1 detected. For a clean upstream-shaped implementation, apply this script to a clean OpenCPN master checkout. The existing local prototype will not be fully rewritten automatically.")
  endif()
endif()

file(WRITE "${IMPL}" "${C}")

message(STATUS "Installed upstream-shaped Vector Object Query API v1")
message(STATUS "  consumer: QueryVectorChartObjectsV1")
message(STATUS "  native provider: S-57")
message(STATUS "  plugin providers: GLPlus3 + ExtendedPlus3")
message(STATUS "  provider ABI: POD + borrowed callback data")
