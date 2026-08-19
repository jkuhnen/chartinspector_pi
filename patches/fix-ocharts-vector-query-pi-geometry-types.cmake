if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()
file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()
file(READ "${CPP}" C)

# PI_S57Obj::geoPt is void*, unlike native S57Obj::geoPt.
string(REPLACE
"        const double east = obj->geoPt[i].x * obj->x_rate + obj->x_origin;\n        const double north = obj