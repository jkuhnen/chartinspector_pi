if(NOT DEFINED OPENCPN_ROOT)
  message(FATAL_ERROR "OPENCPN_ROOT is required, e.g. -DOPENCPN_ROOT=C:/Users/Johannes/source/OpenCPN")
endif()

file(TO_CMAKE_PATH "${OPENCPN_ROOT}" OPENCPN_ROOT)
set(SHIM "${OPENCPN_ROOT}/cli/api_shim.cpp")
set(IMPL "${OPENCPN_ROOT}/gui/src/ocpn_plugin_gui.cpp")

foreach(PATH "${SHIM}" "${IMPL}")
  if(NOT EXISTS "${PATH}")
    message(FATAL_ERROR "OpenCPN source file not found: ${PATH}")
  endif()
endforeach()

# An earlier repair version installed the Plus3 defaults in cli/api_shim.cpp.
# That source is not linked into the normal OpenCPN GUI executable on Windows,
# so remove that stale block if present. The native installer below will place
# the implementation in gui/src/ocpn_plugin_gui.cpp, which is part of opencpn.
file(READ "${SHIM}" S)
set(OLD_PLUS3_IMPL [===[

// ----------------------------------------------------------------------------
// PlugInChartBaseGLPlus3
// ----------------------------------------------------------------------------
PlugInChartBaseGLPlus3::PlugInChartBaseGLPlus3() {}
PlugInChartBaseGLPlus3::~PlugInChartBaseGLPlus3() {}

bool PlugInChartBaseGLPlus3::QueryVectorObjectsV1(
    const PI_VectorQueryV1 *query, const PlugIn_ViewPort *viewport,
    PI_VectorObjectSinkV1 sink, void *user_data) {
  (void)query;
  (void)viewport;
  (void)sink;
  (void)user_data;
  return false;
}

]===])
string(FIND "${S}" "${OLD_PLUS3_IMPL}" OLD_POS)
if(NOT OLD_POS EQUAL -1)
  string(REPLACE "${OLD_PLUS3_IMPL}" "" S "${S}")
  file(WRITE "${SHIM}" "${S}")
  message(STATUS "Removed stale PlugInChartBaseGLPlus3 implementation from ${SHIM}")
endif()

# Remove the obsolete marker used by the previous workaround. It fooled the
# native installer into thinking the Plus3 methods were already implemented in
# ocpn_plugin_gui.cpp, which produced unresolved externals at link time.
file(READ "${IMPL}" C)
set(OLD_MARKER "// PlugInChartBaseGLPlus3::PlugInChartBaseGLPlus3 is implemented in cli/api_shim.cpp")
string(REPLACE "${OLD_MARKER}\n" "" C "${C}")
string(REPLACE "${OLD_MARKER}\r\n" "" C "${C}")
file(WRITE "${IMPL}" "${C}")
message(STATUS "Prepared ${IMPL} for native Plus3 implementation")

# Re-run the native installer. It now sees no fake Plus3 marker and installs
# constructor, destructor and QueryVectorObjectsV1 into the GUI target source,
# together with the native S-57 vector query implementation.
include("${CMAKE_CURRENT_LIST_DIR}/apply-vector-query-api-v1-native.cmake")
