if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()

file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()

file(READ "${CPP}" C)

set(ANCHOR [===[
        cobj->m_lat = pObj->m_lat;
        cobj->m_lon = pObj->m_lon;

        cobj->geoPt = (pt *)pObj->geoPt;
]===])

set(REPLACEMENT [===[
        cobj->m_lat = pObj->m_lat;
        cobj->m_lon = pObj->m_lon;

        // Preserve borrowed geometry/transforms in the PI_S57Obj clone used by
        // QueryVectorObjectsV1.  o-charts keeps an API-compatible legacy line
        // segment list alongside the native renderer list specifically for
        // plugin-facing geometry access.
        cobj->x_rate = pObj->x_rate;
        cobj->y_rate = pObj->y_rate;
        cobj->x_origin = pObj->x_origin;
        cobj->y_origin = pObj->y_origin;
        cobj->m_n_lsindex = pObj->m_n_lsindex;
        cobj->m_lsindex_array = pObj->m_lsindex_array;
        cobj->m_n_edge_max_points = pObj->m_n_edge_max_points;
        cobj->m_ls_list = pObj->m_ls_list_legacy;
        cobj->m_chart_context = pObj->m_chart_context;

        cobj->geoPt = (pt *)pObj->geoPt;
]===])

string(FIND "${C}" "cobj->m_ls_list = pObj->m_ls_list_legacy;" DONE)
if(NOT DONE EQUAL -1)
  message(STATUS "PI_S57Obj query clone geometry already preserved")
  return()
endif()

string(FIND "${C}" "${ANCHOR}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate active PI_S57Obj clone anchor")
endif()

string(REPLACE "${ANCHOR}" "${REPLACEMENT}" C "${C}")
file(WRITE "${CPP}" "${C}")
message(STATUS "Preserved PI_S57Obj clone transforms and legacy line geometry")
message(STATUS "  m_ls_list <- S57Obj::m_ls_list_legacy")
message(STATUS "  m_chart_context and transform coefficients borrowed from native object")
