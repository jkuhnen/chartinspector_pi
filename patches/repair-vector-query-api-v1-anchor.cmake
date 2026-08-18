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

# The first installer run already added the public declarations to
# include/ocpn_plugin.h before failing. The default implementation for chart
# provider extension classes lives in cli/api_shim.cpp, just like Plus2.
file(READ "${SHIM}" S)
if(NOT S MATCHES "PlugInChartBaseGLPlus3::PlugInChartBaseGLPlus3")
  set(PLUS3_IMPL [===[

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

  string(FIND "${S}" "PlugInChartBaseGLPlus2::PlugInChartBaseGLPlus2" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate PlugInChartBaseGLPlus2 implementation in ${SHIM}")
  endif()
  string(SUBSTRING "${S}" 0 ${POS} PREFIX)
  string(SUBSTRING "${S}" ${POS} -1 SUFFIX)
  set(S "${PREFIX}${PLUS3_IMPL}${SUFFIX}")
  file(WRITE "${SHIM}" "${S}")
  message(STATUS "Installed PlugInChartBaseGLPlus3 default implementation in ${SHIM}")
else()
  message(STATUS "PlugInChartBaseGLPlus3 default implementation already present.")
endif()

# The original installer checks for this implementation in ocpn_plugin_gui.cpp.
# Add an explicit location marker so the repaired run skips that obsolete
# anchor check and continues with the native S-57 query implementation.
file(READ "${IMPL}" C)
set(MARKER "// PlugInChartBaseGLPlus3::PlugInChartBaseGLPlus3 is implemented in cli/api_shim.cpp")
string(FIND "${C}" "${MARKER}" MARKER_POS)
if(MARKER_POS EQUAL -1)
  string(REPLACE "#include <vector>" "#include <vector>\n${MARKER}" C "${C}")
  file(WRITE "${IMPL}" "${C}")
  message(STATUS "Installed Plus3 implementation-location marker in ${IMPL}")
endif()

include("${CMAKE_CURRENT_LIST_DIR}/apply-vector-query-api-v1-native.cmake")
