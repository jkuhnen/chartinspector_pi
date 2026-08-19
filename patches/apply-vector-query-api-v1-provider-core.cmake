if(NOT DEFINED OPENCPN_ROOT)
  message(FATAL_ERROR "OPENCPN_ROOT is required")
endif()

file(TO_CMAKE_PATH "${OPENCPN_ROOT}" OPENCPN_ROOT)
set(HEADER "${OPENCPN_ROOT}/include/ocpn_plugin.h")
set(IMPL "${OPENCPN_ROOT}/gui/src/ocpn_plugin_gui.cpp")

foreach(P "${HEADER}" "${IMPL}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Missing OpenCPN source file: ${P}")
  endif()
endforeach()

file(READ "${HEADER}" H)

if(NOT H MATCHES "PlugInChartBaseExtendedPlus3")
  set(PLUS3 [===[

// ----------------------------------------------------------------------------
// PlugInChartBaseExtendedPlus3
// Optional provider-side vector object query extension.
// ----------------------------------------------------------------------------
class DECL_EXP PlugInChartBaseExtendedPlus3 : public PlugInChartBaseExtendedPlus2 {
public:
  PlugInChartBaseExtendedPlus3();
  virtual ~PlugInChartBaseExtendedPlus3();

  virtual bool QueryVectorObjectsV1(const PI_VectorQueryV1 *query,
                                    const PlugIn_ViewPort *viewport,
                                    PI_VectorObjectSinkV1 sink,
                                    void *user_data);
};
]===])

  string(FIND "${H}" "class wxArrayOfS57attVal;" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate ExtendedPlus2 end anchor")
  endif()
  string(SUBSTRING "${H}" 0 ${POS} PRE)
  string(SUBSTRING "${H}" ${POS} -1 POST)
  set(H "${PRE}${PLUS3}\n${POST}")
  file(WRITE "${HEADER}" "${H}")
  message(STATUS "Added PlugInChartBaseExtendedPlus3 to ${HEADER}")
else()
  message(STATUS "PlugInChartBaseExtendedPlus3 already present")
endif()

file(READ "${IMPL}" C)

if(NOT C MATCHES "PlugInChartBaseExtendedPlus3::PlugInChartBaseExtendedPlus3")
  set(DEFAULT_IMPL [===[

PlugInChartBaseExtendedPlus3::PlugInChartBaseExtendedPlus3() = default;
PlugInChartBaseExtendedPlus3::~PlugInChartBaseExtendedPlus3() = default;

bool PlugInChartBaseExtendedPlus3::QueryVectorObjectsV1(
    const PI_VectorQueryV1 *query, const PlugIn_ViewPort *viewport,
    PI_VectorObjectSinkV1 sink, void *user_data) {
  (void)query;
  (void)viewport;
  (void)sink;
  (void)user_data;
  return false;
}

]===])
  string(FIND "${C}" "bool GetGlobalColor(wxString colorName, wxColour* pcolour)" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate GetGlobalColor anchor")
  endif()
  string(SUBSTRING "${C}" 0 ${POS} PRE)
  string(SUBSTRING "${C}" ${POS} -1 POST)
  set(C "${PRE}${DEFAULT_IMPL}${POST}")
endif()

set(OLD [===[
  auto *native_chart = dynamic_cast<s57chart *>(target_chart);
  if (!native_chart) {
    // Provider chart support is intentionally deferred to Plus3 implementation.
    return false;
  }
]===])
set(NEW [===[
  auto *native_chart = dynamic_cast<s57chart *>(target_chart);
  if (!native_chart) {
    auto *wrapper = dynamic_cast<ChartPlugInWrapper *>(target_chart);
    if (!wrapper) return false;

    auto *provider = dynamic_cast<PlugInChartBaseExtendedPlus3 *>(
        wrapper->GetPlugInChart());
    if (!provider) return false;

    PlugIn_ViewPort pi_vp = CreatePlugInViewportEx(viewport);
    return provider->QueryVectorObjectsV1(query, &pi_vp, sink, user_data);
  }
]===])

string(FIND "${C}" "${OLD}" OLD_POS)
if(NOT OLD_POS EQUAL -1)
  string(REPLACE "${OLD}" "${NEW}" C "${C}")
  message(STATUS "Enabled ExtendedPlus3 provider dispatch")
elseif(C MATCHES "dynamic_cast<PlugInChartBaseExtendedPlus3")
  message(STATUS "Provider dispatch already present")
else()
  message(FATAL_ERROR "Could not locate native-only QueryVectorChartObjectsV1 branch")
endif()

file(WRITE "${IMPL}" "${C}")
message(STATUS "OpenCPN vector query provider core patch installed")
