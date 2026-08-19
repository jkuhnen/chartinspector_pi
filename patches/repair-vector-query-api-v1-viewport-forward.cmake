if(NOT DEFINED OPENCPN_ROOT)
  message(FATAL_ERROR "OPENCPN_ROOT is required")
endif()

file(TO_CMAKE_PATH "${OPENCPN_ROOT}" OPENCPN_ROOT)
set(IMPL "${OPENCPN_ROOT}/gui/src/ocpn_plugin_gui.cpp")

if(NOT EXISTS "${IMPL}")
  message(FATAL_ERROR "OpenCPN source file not found: ${IMPL}")
endif()

file(READ "${IMPL}" C)

set(DECL "static PlugIn_ViewPort CreatePlugInViewportEx(const ViewPort& vp);")

if(C MATCHES "static PlugIn_ViewPort CreatePlugInViewportEx\\(const ViewPort& vp\\);" )
  message(STATUS "CreatePlugInViewportEx forward declaration already present")
else()
  set(ANCHOR "extern arrayofCanvasPtr g_canvasArray;  // FIXME (leamas) find new home")
  string(FIND "${C}" "${ANCHOR}" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate g_canvasArray anchor in ${IMPL}")
  endif()

  string(REPLACE
    "${ANCHOR}"
    "${ANCHOR}\n\n${DECL}"
    C "${C}")

  file(WRITE "${IMPL}" "${C}")
  message(STATUS "Added CreatePlugInViewportEx forward declaration in ${IMPL}")
endif()
