if(NOT DEFINED OPENCPN_ROOT)
  message(FATAL_ERROR "OPENCPN_ROOT is required, e.g. -DOPENCPN_ROOT=C:/Users/Johannes/source/OpenCPN")
endif()

file(TO_CMAKE_PATH "${OPENCPN_ROOT}" OPENCPN_ROOT)
set(TARGET "${OPENCPN_ROOT}/gui/src/ocpn_plugin_gui.cpp")

if(NOT EXISTS "${TARGET}")
  message(FATAL_ERROR "OpenCPN source file not found: ${TARGET}")
endif()

file(READ "${TARGET}" SRC)

# Prepare explicit includes used by the V5 geometry code.  The underlying V5
# installer also checks for these, but older patched source trees don't always
# contain the anchors it uses for insertion.  This wrapper makes installation
# deterministic across the OpenCPN trees used for Chart Inspector testing.
foreach(INCLUDE_LINE "#include <algorithm>" "#include <cmath>" "#include <limits>")
  string(FIND "${SRC}" "${INCLUDE_LINE}" POS)
  if(POS EQUAL -1)
    string(REPLACE "#include <vector>" "${INCLUDE_LINE}\n#include <vector>" SRC "${SRC}")
  endif()
endforeach()

string(FIND "${SRC}" "#include \"model/georef.h\"" POS_GEOREF)
if(POS_GEOREF EQUAL -1)
  string(REPLACE "#include \"model/gui_vars.h\""
                 "#include \"model/georef.h\"\n#include \"model/gui_vars.h\""
                 SRC "${SRC}")
endif()

string(FIND "${SRC}" "#include \"s57chart.h\"" POS_S57CHART)
if(POS_S57CHART EQUAL -1)
  string(REPLACE "#include \"s52plib.h\""
                 "#include \"s52plib.h\"\n#include \"s57chart.h\""
                 SRC "${SRC}")
endif()

file(WRITE "${TARGET}" "${SRC}")

include("${CMAKE_CURRENT_LIST_DIR}/apply-hit-test-v5.cmake")
