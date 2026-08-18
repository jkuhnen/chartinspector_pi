if(NOT DEFINED OPENCPN_ROOT)
  message(FATAL_ERROR "OPENCPN_ROOT is required, e.g. -DOPENCPN_ROOT=C:/Users/Johannes/source/OpenCPN")
endif()

file(TO_CMAKE_PATH "${OPENCPN_ROOT}" OPENCPN_ROOT)
set(TARGET "${OPENCPN_ROOT}/gui/src/ocpn_plugin_gui.cpp")

if(NOT EXISTS "${TARGET}")
  message(FATAL_ERROR "OpenCPN source file not found: ${TARGET}")
endif()

file(READ "${TARGET}" SRC)

if(NOT SRC MATCHES "OCPNChartInspectorHitTestV5")
  message(FATAL_ERROR "Chart Inspector V5 hit test is not installed in ${TARGET}")
endif()

set(CHANGED FALSE)

string(FIND "${SRC}" "double ChartInspectorGeometryDistanceV5(\n    const ViewPort& viewport" POS_GEOMETRY_CONST)
if(NOT POS_GEOMETRY_CONST EQUAL -1)
  string(REPLACE
      "double ChartInspectorGeometryDistanceV5(\n    const ViewPort& viewport"
      "double ChartInspectorGeometryDistanceV5(\n    ViewPort& viewport"
      SRC "${SRC}")
  set(CHANGED TRUE)
endif()

string(FIND "${SRC}" "double ChartInspectorPointDistanceV5(const ViewPort& viewport" POS_POINT_CONST)
if(NOT POS_POINT_CONST EQUAL -1)
  string(REPLACE
      "double ChartInspectorPointDistanceV5(const ViewPort& viewport"
      "double ChartInspectorPointDistanceV5(ViewPort& viewport"
      SRC "${SRC}")
  set(CHANGED TRUE)
endif()

if(CHANGED)
  file(WRITE "${TARGET}" "${SRC}")
  message(STATUS "Fixed Chart Inspector V5 ViewPort const compatibility in ${TARGET}")
else()
  message(STATUS "Chart Inspector V5 ViewPort compatibility is already fixed.")
endif()
