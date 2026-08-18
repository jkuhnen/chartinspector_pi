cmake_minimum_required(VERSION 3.15)

set(ROOT "${CMAKE_CURRENT_LIST_DIR}/..")
get_filename_component(ROOT "${ROOT}" ABSOLUTE)
set(CMAKE_FILE "${ROOT}/CMakeLists.txt")

if(NOT EXISTS "${CMAKE_FILE}")
  message(FATAL_ERROR "CMakeLists.txt not found: ${CMAKE_FILE}")
endif()

file(READ "${CMAKE_FILE}" C)

if(C MATCHES "add_library\\(vectorquery_test_pi")
  message(STATUS "vectorquery_test_pi target already installed")
  return()
endif()

set(BLOCK [===[

# -----------------------------------------------------------------------------
# Isolated QueryVectorChartObjectsV1 diagnostic consumer.
# This target deliberately does not change chartinspector_pi.
# -----------------------------------------------------------------------------
add_library(vectorquery_test_pi SHARED
    src/vectorquery_test_pi.cpp
)

target_link_libraries(vectorquery_test_pi PRIVATE
    ocpn::api
    ${wxWidgets_LIBRARIES}
)

target_include_directories(vectorquery_test_pi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

if(WIN32)
  target_link_libraries(vectorquery_test_pi PRIVATE windows::headers)
endif()

if(MSVC)
  target_compile_definitions(vectorquery_test_pi PRIVATE
      MAKING_PLUGIN
      __MSVC__
      _CRT_NONSTDC_NO_DEPRECATE
      _CRT_SECURE_NO_DEPRECATE
  )
  target_compile_options(vectorquery_test_pi PRIVATE /utf-8)
endif()

set_target_properties(vectorquery_test_pi PROPERTIES
    PREFIX ""
    OUTPUT_NAME "vectorquery_test_pi"
)
]===])

string(FIND "${C}" "set_target_properties(chartinspector_pi PROPERTIES" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate chartinspector target properties anchor")
endif()

string(SUBSTRING "${C}" 0 ${POS} PREFIX)
string(SUBSTRING "${C}" ${POS} -1 SUFFIX)
set(C "${PREFIX}${BLOCK}\n${SUFFIX}")
file(WRITE "${CMAKE_FILE}" "${C}")

message(STATUS "Installed isolated vectorquery_test_pi build target")
