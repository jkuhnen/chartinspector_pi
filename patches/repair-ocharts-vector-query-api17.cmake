if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required, e.g. -DOCHARTS_ROOT=C:/Users/Johannes/source/o-charts_pi")
endif()

file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)

# o-charts 2.2.1 selects PKG_API_LIB=api-17 in Plugin.cmake.  The active
# header comes from the opencpn-libs submodule, not the repository's legacy
# api-16 directory.
set(CANDIDATES
  "${OCHARTS_ROOT}/opencpn-libs/api-17/ocpn_plugin.h"
  "${OCHARTS_ROOT}/api-17/ocpn_plugin.h"
)

set(API_H "")
foreach(P IN LISTS CANDIDATES)
  if(EXISTS "${P}")
    set(API_H "${P}")
    break()
  endif()
endforeach()

if(API_H STREQUAL "")
  message(FATAL_ERROR
    "Could not find active o-charts api-17/ocpn_plugin.h. Run: git submodule update --init opencpn-libs")
endif()

file(READ "${API_H}" A)

if(NOT A MATCHES "struct PI_VectorObjectV1")
  set(API_TYPES [===[

// Experimental OpenCPN Vector Object Query API v1 compile shim.
// Remove this local copy once the API is published in opencpn-libs.
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
]===])

  string(FIND "${A}" "class PI_S57Obj;" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate PI_S57Obj declaration in ${API_H}")
  endif()
  string(SUBSTRING "${A}" 0 ${POS} PRE)
  string(SUBSTRING "${A}" ${POS} -1 POST)
  set(A "${PRE}${API_TYPES}\n${POST}")
  message(STATUS "Installed Vector Query v1 POD types in active api-17 header")
else()
  message(STATUS "Vector Query v1 POD types already present in active api-17 header")
endif()

if(NOT A MATCHES "class DECL_EXP PlugInChartBaseExtendedPlus3")
  set(PLUS3 [===[

// Optional vector-object query extension for Extended chart providers.
// This declaration must remain ABI-identical to the experimental OpenCPN
// core declaration used for the local integration test.
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

  string(FIND "${A}" "class wxArrayOfS57attVal;" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate ExtendedPlus2 insertion anchor in ${API_H}")
  endif()
  string(SUBSTRING "${A}" 0 ${POS} PRE)
  string(SUBSTRING "${A}" ${POS} -1 POST)
  set(A "${PRE}${PLUS3}\n${POST}")
  message(STATUS "Installed PlugInChartBaseExtendedPlus3 in active api-17 header")
else()
  message(STATUS "PlugInChartBaseExtendedPlus3 already present in active api-17 header")
endif()

file(WRITE "${API_H}" "${A}")

# o-charts' bundled API support library does not yet contain Plus3 symbols.
# Provide the three default methods in the provider DLL for this local
# experimental build. The class declaration itself stays identical to core.
set(CHART_CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CHART_CPP}")
  message(FATAL_ERROR "Missing ${CHART_CPP}")
endif()
file(READ "${CHART_CPP}" C)

if(NOT C MATCHES "PlugInChartBaseExtendedPlus3::PlugInChartBaseExtendedPlus3")
  set(DEFAULTS [===[

// Experimental API-v1 provider base definitions.  These are local build
// support until opencpn-libs ships the corresponding API library symbols.
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

  string(FIND "${C}" "eSENCChart::eSENCChart()" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate eSENCChart constructor anchor in ${CHART_CPP}")
  endif()
  string(SUBSTRING "${C}" 0 ${POS} PRE)
  string(SUBSTRING "${C}" ${POS} -1 POST)
  set(C "${PRE}${DEFAULTS}${POST}")
  file(WRITE "${CHART_CPP}" "${C}")
  message(STATUS "Installed local Plus3 default method definitions")
else()
  message(STATUS "Local Plus3 default method definitions already present")
endif()

message(STATUS "Repaired o-charts Vector Query API header selection")
message(STATUS "  active header: ${API_H}")
