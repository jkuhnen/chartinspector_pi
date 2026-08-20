if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()
file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()
file(READ "${CPP}" C)

string(FIND "${C}" "// VECTOR_QUERY_INTERACTIVE_CONTROLS_V1" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Interactive vector-query controls v1 not found")
endif()
string(FIND "${C}" "// VECTOR_QUERY_FINAL_CLAMP_V1" DONE)
if(NOT DONE EQUAL -1)
  message(STATUS "Final interactive geometry clamp already installed")
  return()
endif()

set(ANCHOR [===[
    if (points.empty() ||
        (geometry_type != PI_VECTOR_GEOMETRY_POINT_V1 && parts.empty())) {
]===])

set(REPL [===[
    // VECTOR_QUERY_FINAL_CLAMP_V1
    // Some provider geometry paths can append whole native parts before their
    // inner loop observes the interactive point budget. Clamp the finished
    // transport geometry here as an authoritative final guard and repair the
    // part ranges to remain within the truncated points array.
    if (points.size() > point_limit) {
      points.resize(point_limit);
      std::vector<PI_VectorPartV1> clamped_parts;
      clamped_parts.reserve(parts.size());
      for (const auto &part : parts) {
        if (part.first_point >= point_limit) break;
        PI_VectorPartV1 cp = part;
        const uint32_t available = point_limit - cp.first_point;
        cp.point_count = std::min(cp.point_count, available);
        if (cp.point_count >= 2) clamped_parts.push_back(cp);
      }
      parts.swap(clamped_parts);
    }

    if (points.empty() ||
        (geometry_type != PI_VECTOR_GEOMETRY_POINT_V1 && parts.empty())) {
]===])

string(FIND "${C}" "${ANCHOR}" A)
if(A EQUAL -1)
  message(FATAL_ERROR "Could not locate geometry validation guard")
endif()
string(REPLACE "${ANCHOR}" "${REPL}" C "${C}")
file(WRITE "${CPP}" "${C}")
message(STATUS "Installed final o-charts interactive geometry clamp")
message(STATUS "  emitted point_count is now guaranteed <= max_points_per_object")
message(STATUS "  part ranges are repaired after truncation")
