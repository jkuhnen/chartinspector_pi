if(NOT DEFINED OPENCPN_ROOT)
  message(FATAL_ERROR "OPENCPN_ROOT is required, e.g. -DOPENCPN_ROOT=C:/Users/Johannes/source/OpenCPN")
endif()
if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required, e.g. -DOCHARTS_ROOT=C:/Users/Johannes/source/o-charts_pi")
endif()

file(TO_CMAKE_PATH "${OPENCPN_ROOT}" OPENCPN_ROOT)
file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)

set(OPENCPN_API "${OPENCPN_ROOT}/include/ocpn_plugin.h")
set(OCHARTS_API16 "${OCHARTS_ROOT}/api-16/ocpn_plugin.h")
set(OCHARTS_API17 "${OCHARTS_ROOT}/opencpn-libs/api-17/ocpn_plugin.h")
set(OCHARTS_CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
set(INSPECTOR_CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")

foreach(P "${OPENCPN_API}" "${OCHARTS_API16}" "${OCHARTS_API17}" "${OCHARTS_CPP}" "${INSPECTOR_CPP}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Required file not found: ${P}")
  endif()
endforeach()

# -----------------------------------------------------------------------------
# Public/bundled API: append a second flags bit without changing the struct ABI.
# -----------------------------------------------------------------------------
function(add_non_rendered_flag PATH)
  file(READ "${PATH}" H)
  if(H MATCHES "PI_VECTOR_QUERY_INCLUDE_NON_RENDERED_V1")
    message(STATUS "Non-rendered query flag already present in ${PATH}")
    return()
  endif()

  set(OLD [===[
enum PI_VectorQueryFlagsV1 : uint32_t {
  PI_VECTOR_QUERY_SKIP_ATTRIBUTES_V1 = 1u << 0
};
]===])
  set(NEW [===[
enum PI_VectorQueryFlagsV1 : uint32_t {
  PI_VECTOR_QUERY_SKIP_ATTRIBUTES_V1       = 1u << 0,
  PI_VECTOR_QUERY_INCLUDE_NON_RENDERED_V1 = 1u << 1
};
]===])

  string(FIND "${H}" "${OLD}" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate PI_VectorQueryFlagsV1 in ${PATH}")
  endif()
  string(REPLACE "${OLD}" "${NEW}" H "${H}")
  file(WRITE "${PATH}" "${H}")
  message(STATUS "Added PI_VECTOR_QUERY_INCLUDE_NON_RENDERED_V1 to ${PATH}")
endfunction()

add_non_rendered_flag("${OPENCPN_API}")
add_non_rendered_flag("${OCHARTS_API16}")
add_non_rendered_flag("${OCHARTS_API17}")

# -----------------------------------------------------------------------------
# o-charts provider: when requested, bypass S-52 ObjectRenderCheck while keeping
# the existing geometric hit test. This includes objects hidden by current
# presentation rules (for example SCAMIN/display category) if they are present
# in the provider's razRules.
#
# eSENCChart.cpp currently contains two QueryVectorObjectsV1 implementations in
# separate compilation regions. The replacements below intentionally update all
# matching provider bodies so the two paths stay synchronized.
# -----------------------------------------------------------------------------
file(READ "${OCHARTS_CPP}" C)

if(NOT C MATCHES "VECTOR_QUERY_INCLUDE_NON_RENDERED_V1")
  set(FLAGS [===[
  const uint32_t query_flags = has_flags ? query->flags : 0u;
]===])
  set(FLAGS_NEW [===[
  const uint32_t query_flags = has_flags ? query->flags : 0u;

  // VECTOR_QUERY_INCLUDE_NON_RENDERED_V1
  const bool include_non_rendered =
      (query_flags & PI_VECTOR_QUERY_INCLUDE_NON_RENDERED_V1) != 0;
  auto rule_is_queryable = [&](ObjRazRules *rule) {
    if (!rule || !rule->obj) return false;
    return include_non_rendered || ps52plib->ObjectRenderCheck(rule);
  };
]===])

  string(FIND "${C}" "${FLAGS}" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate query_flags in ${OCHARTS_CPP}")
  endif()
  string(REPLACE "${FLAGS}" "${FLAGS_NEW}" C "${C}")

  # All selection checks inside the vector-query provider use one of these
  # forms. Restrict replacements to the exact expressions used by the provider.
  string(REPLACE "ps52plib->ObjectRenderCheck(top) &&"
                 "rule_is_queryable(top) &&" C "${C}")
  string(REPLACE "ps52plib->ObjectRenderCheck(child) &&"
                 "rule_is_queryable(child) &&" C "${C}")

  file(WRITE "${OCHARTS_CPP}" "${C}")
  message(STATUS "Enabled INCLUDE_NON_RENDERED selection in both o-charts provider paths")
else()
  message(STATUS "o-charts INCLUDE_NON_RENDERED provider support already installed")
endif()

# -----------------------------------------------------------------------------
# Chart Inspector hover/highlight query: request non-rendered candidates while
# still skipping attributes for the fast geometry-only hover path.
# -----------------------------------------------------------------------------
file(READ "${INSPECTOR_CPP}" P)

if(P MATCHES "CHARTINSPECTOR_VECTOR_HOVER_V1")
  if(NOT P MATCHES "CI_INCLUDE_NON_RENDERED")
    string(REPLACE
      "constexpr uint32_t CI_SKIP_ATTRIBUTES = 1u;\nconstexpr uint32_t CI_GEOMETRY_ALL = 7u;"
      "constexpr uint32_t CI_SKIP_ATTRIBUTES = 1u;\nconstexpr uint32_t CI_INCLUDE_NON_RENDERED = 1u << 1;\nconstexpr uint32_t CI_GEOMETRY_ALL = 7u;"
      P "${P}")

    string(REPLACE
      "q.flags = CI_SKIP_ATTRIBUTES; q.geometry_mask = CI_GEOMETRY_ALL;"
      "q.flags = CI_SKIP_ATTRIBUTES | CI_INCLUDE_NON_RENDERED; q.geometry_mask = CI_GEOMETRY_ALL;"
      P "${P}")

    if(NOT P MATCHES "CI_INCLUDE_NON_RENDERED")
      message(FATAL_ERROR "Could not enable non-rendered flag in Chart Inspector hover query")
    endif()
    file(WRITE "${INSPECTOR_CPP}" "${P}")
    message(STATUS "Chart Inspector hover query now includes non-rendered objects")
  else()
    message(STATUS "Chart Inspector non-rendered hover query already installed")
  endif()
else()
  message(WARNING "CHARTINSPECTOR_VECTOR_HOVER_V1 is not applied to src/chartinspector_pi.cpp; provider/API support was installed, but the hover caller was left unchanged")
endif()

message(STATUS "Vector query non-rendered upgrade v1 complete")
message(STATUS "  API flag bit: 1 << 1")
message(STATUS "  default behavior unchanged unless the caller sets the flag")
message(STATUS "  o-charts still requires DoesLatLonSelectObject for geometric selection")
