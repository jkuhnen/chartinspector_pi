if(NOT DEFINED OPENCPN_ROOT)
  message(FATAL_ERROR "OPENCPN_ROOT is required")
endif()
file(TO_CMAKE_PATH "${OPENCPN_ROOT}" OPENCPN_ROOT)
set(HEADER "${OPENCPN_ROOT}/include/ocpn_plugin.h")
if(NOT EXISTS "${HEADER}")
  message(FATAL_ERROR "Missing ${HEADER}")
endif()
file(READ "${HEADER}" H)

string(FIND "${H}" "PI_VECTOR_QUERY_GEOMETRY_POINT_V1" DONE)
if(NOT DONE EQUAL -1)
  message(STATUS "Interactive vector-query controls already installed")
  return()
endif()

set(OLD [===[
struct PI_VectorQueryV1 {
  uint32_t struct_size;
  double lat;
  double lon;
  double search_radius_pixels;
};
]===])

set(NEW [===[
// Optional query controls are appended to preserve the v1 ABI. Providers must
// use struct_size before reading them. A legacy-size query keeps the original
// behavior: all geometry types, full geometry, attributes, and provider limits.
enum PI_VectorQueryGeometryMaskV1 : uint32_t {
  PI_VECTOR_QUERY_GEOMETRY_POINT_V1 = 1u << 0,
  PI_VECTOR_QUERY_GEOMETRY_LINE_V1  = 1u << 1,
  PI_VECTOR_QUERY_GEOMETRY_AREA_V1  = 1u << 2,
  PI_VECTOR_QUERY_GEOMETRY_ALL_V1   = 0x7u
};

enum PI_VectorQueryFlagsV1 : uint32_t {
  PI_VECTOR_QUERY_SKIP_ATTRIBUTES_V1 = 1u << 0
};

struct PI_VectorQueryV1 {
  uint32_t struct_size;
  double lat;
  double lon;
  double search_radius_pixels;

  // Optional v1 tail fields. Zero means legacy/default behavior.
  uint32_t flags;
  uint32_t geometry_mask;
  uint32_t max_objects;
  uint32_t max_points_per_object;

  // Optional comma-separated exact S-57 feature acronyms to reject before
  // geometry extraction, e.g. "LNDARE,COALNE,DEPARE,DEPCNT".
  const char *exclude_feature_classes_utf8;
};
]===])

string(FIND "${H}" "${OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate PI_VectorQueryV1 in ${HEADER}")
endif()
string(REPLACE "${OLD}" "${NEW}" H "${H}")
file(WRITE "${HEADER}" "${H}")
message(STATUS "Installed interactive vector-query controls v1")
message(STATUS "  max_objects and max_points_per_object")
message(STATUS "  geometry mask and skip-attributes flag")
message(STATUS "  provider-side exact feature exclusion list")
message(STATUS "  ABI preserved through struct_size tail fields")
