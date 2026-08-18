cmake_minimum_required(VERSION 3.16)

project(chartinspector_pi VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(OPENCPN_SOURCE_DIR "" CACHE PATH "Path to the OpenCPN source tree")

if(NOT OPENCPN_SOURCE_DIR)
  message(FATAL_ERROR "Set OPENCPN_SOURCE_DIR to an OpenCPN source tree containing include/ocpn_plugin.h")
endif()

if(NOT EXISTS "${OPENCPN_SOURCE_DIR}/include/ocpn_plugin.h")
  message(FATAL_ERROR "OPENCPN_SOURCE_DIR does not point to a valid OpenCPN source tree")
endif()

find_package(wxWidgets REQUIRED COMPONENTS core base)
include(${wxWidgets_USE_FILE})

add_library(chartinspector_pi MODULE
  src/chartinspector_pi.cpp
)

target_include_directories(chartinspector_pi PRIVATE
  "${OPENCPN_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_link_libraries(chartinspector_pi PRIVATE ${wxWidgets_LIBRARIES})

set_target_properties(chartinspector_pi PROPERTIES
  PREFIX ""
)
