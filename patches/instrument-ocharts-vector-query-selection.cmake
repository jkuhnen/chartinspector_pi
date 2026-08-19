if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()

file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()

file(READ "${CPP}" C)

string(FIND "${C}" "VECTOR_QUERY_DIAG_SELECTION_V1" DONE)
if(NOT DONE EQUAL -1)
  message(STATUS "Vector query selection diagnostics already installed")
  return()
endif()

set(ANCHOR [===[
    PI_S57Obj *obj = node->GetData();
    if (!obj || !obj->FeatureName[0]) continue;
]===])

set(REPL [===[
    PI_S57Obj *obj = node->GetData();
    if (!obj || !obj->FeatureName[0]) continue;

    // VECTOR_QUERY_DIAG_SELECTION_V1
    wxLogMessage(
        "OCHARTS_VECTOR_QUERY selected feature=%s prim=%d npt=%d geoPt=%p ls=%p ctx=%p",
        wxString::FromUTF8(obj->FeatureName), obj->Primitive_type, obj->npt,
        obj->geoPt, obj->m_ls_list, obj->m_chart_context);
]===])

string(FIND "${C}" "${ANCHOR}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate active QueryVectorObjectsV1 object loop")
endif()
string(REPLACE "${ANCHOR}" "${REPL}" C "${C}")

set(SKIP [===[
    if (points.empty() ||
        (geometry_type != PI_VECTOR_GEOMETRY_POINT_V1 && parts.empty()))
      continue;
]===])

set(SKIP_REPL [===[
    if (points.empty() ||
        (geometry_type != PI_VECTOR_GEOMETRY_POINT_V1 && parts.empty())) {
      wxLogMessage(
          "OCHARTS_VECTOR_QUERY dropped feature=%s prim=%d points=%u parts=%u geoPt=%p ls=%p ctx=%p",
          wxString::FromUTF8(obj->FeatureName), obj->Primitive_type,
          static_cast<unsigned>(points.size()),
          static_cast<unsigned>(parts.size()), obj->geoPt, obj->m_ls_list,
          obj->m_chart_context);
      continue;
    }
]===])

string(FIND "${C}" "${SKIP}" SKIP_POS)
if(SKIP_POS EQUAL -1)
  message(FATAL_ERROR "Could not locate active geometry drop guard")
endif()
string(REPLACE "${SKIP}" "${SKIP_REPL}" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed o-charts vector-query selection diagnostics")
message(STATUS "  logs selected PI_S57Obj before geometry extraction")
message(STATUS "  logs objects dropped for missing geometry")
