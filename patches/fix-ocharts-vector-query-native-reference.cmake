if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()
file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()
file(READ "${CPP}" C)

string(FIND "${C}" "// VECTOR_QUERY_NATIVE_S57_V3" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Native S57 vector query v3 marker not found")
endif()

set(OLD1 [===[
        append_sm(points, east, north,
                  obj->m_chart_context ? obj->m_chart_context->ref_lat : m_ref_lat,
                  obj->m_chart_context ? obj->m_chart_context->ref_lon : m_ref_lon);
]===])
set(NEW1 [===[
        append_sm(points, east, north, m_ref_lat, m_ref_lon);
]===])
string(REPLACE "${OLD1}" "${NEW1}" C "${C}")

string(REPLACE "obj->m_chart_context->ref_lat,\n                      obj->m_chart_context->ref_lon" "m_ref_lat,\n                      m_ref_lon" C "${C}")
string(REPLACE "obj->m_chart_context->ref_lat,\n                        obj->m_chart_context->ref_lon" "m_ref_lat,\n                        m_ref_lon" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Fixed native vector-query SM reference to eSENCChart::m_ref_lat/m_ref_lon")
message(STATUS "  VBO/edge coordinates now converted using chart reference origin")
