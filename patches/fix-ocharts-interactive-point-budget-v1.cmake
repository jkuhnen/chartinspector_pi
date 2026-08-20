if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()
file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()
file(READ "${CPP}" C)

string(FIND "${C}" "// VECTOR_QUERY_INTERACTIVE_CONTROLS_V1" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Interactive vector-query controls v1 not found")
endif()

string(FIND "${C}" "// VECTOR_QUERY_STRICT_POINT_BUDGET_V1" DONE)
if(NOT DONE EQUAL -1)
  message(STATUS "Strict interactive point budget already installed")
  return()
endif()

# Make append_sm itself enforce the budget. This is the authoritative guard,
# so inner edge/VBO loops cannot overshoot after entering with points.size()
# below the limit.
set(OLD_APPEND [===[
  auto append_sm = [&](std::vector<PI_VectorPositionV1> &points,
                       double east, double north, double ref_lat,
                       double ref_lon) {
    double lat = 0.0, lon = 0.0;
]===])
set(NEW_APPEND [===[
  // VECTOR_QUERY_STRICT_POINT_BUDGET_V1
  auto append_sm = [&](std::vector<PI_VectorPositionV1> &points,
                       double east, double north, double ref_lat,
                       double ref_lon) {
    if (points.size() >= point_limit) return;
    double lat = 0.0, lon = 0.0;
]===])
string(FIND "${C}" "${OLD_APPEND}" P)
if(P EQUAL -1)
  message(FATAL_ERROR "Could not locate append_sm helper")
endif()
string(REPLACE "${OLD_APPEND}" "${NEW_APPEND}" C "${C}")

# Do not create additional parts once the point budget is exhausted.
string(REPLACE
  "for (line_segment_element *ls = obj->m_ls_list;\n           ls && points.size() < point_limit; ls = ls->next) {"
  "for (line_segment_element *ls = obj->m_ls_list;\n           ls && points.size() < point_limit; ls = ls->next) {"
  C "${C}")

# Protect native edge inner loops too. append_sm is the final guard, while
# these conditions avoid unnecessary coordinate conversions after saturation.
string(REPLACE
  "for (int i = count - 1; i >= 0; --i)"
  "for (int i = count - 1; i >= 0 && points.size() < point_limit; --i)"
  C "${C}")
string(REPLACE
  "for (int i = 0; i < count; ++i)"
  "for (int i = 0; i < count && points.size() < point_limit; ++i)"
  C "${C}")
string(REPLACE
  "ip < edge->nCount && points.size() < 65536; ++ip)"
  "ip < edge->nCount && points.size() < point_limit; ++ip)"
  C "${C}")
string(REPLACE
  "ip < edge->nCount && points.size() < point_limit; ++ip)"
  "ip < edge->nCount && points.size() < point_limit; ++ip)"
  C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed strict o-charts interactive point budget")
message(STATUS "  append_sm hard-stops at max_points_per_object")
message(STATUS "  inner VBO/edge loops stop when the budget is exhausted")
