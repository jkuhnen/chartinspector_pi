if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()
file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(API_H "${OCHARTS_ROOT}/api-16/ocpn_plugin.h")
set(CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
foreach(P "${API_H}" "${CPP}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Missing ${P}")
  endif()
endforeach()

file(READ "${API_H}" A)
if(NOT A MATCHES "PI_VECTOR_QUERY_GEOMETRY_POINT_V1")
  set(OLD [===[
struct PI_VectorQueryV1 {
  uint32_t struct_size;
  double lat;
  double lon;
  double search_radius_pixels;
};
]===])
  set(NEW [===[
enum PI_VectorQueryGeometryMaskV1 : uint32_t {
  PI_VECTOR_QUERY_GEOMETRY_POINT_V1 = 1u << 0,
  PI_VECTOR_QUERY_GEOMETRY_LINE_V1  = 1u << 1,
  PI_VECTOR_QUERY_GEOMETRY_AREA_V1  = 1u << 2,
  PI_VECTOR_QUERY_GEOMETRY_ALL_V1   = 0x7u
};
enum PI_VectorQueryFlagsV1 : uint32_t {
  PI_VECTOR_QUERY_SKIP_ATTRIBUTES_V1 = 1u << 0
};
struct PI_VectorQueryV1 {
  uint32_t struct_size;
  double lat;
  double lon;
  double search_radius_pixels;
  uint32_t flags;
  uint32_t geometry_mask;
  uint32_t max_objects;
  uint32_t max_points_per_object;
  const char *exclude_feature_classes_utf8;
};
]===])
  string(FIND "${A}" "${OLD}" P)
  if(P EQUAL -1)
    message(FATAL_ERROR "Could not locate bundled PI_VectorQueryV1")
  endif()
  string(REPLACE "${OLD}" "${NEW}" A "${A}")
  file(WRITE "${API_H}" "${A}")
endif()

file(READ "${CPP}" C)
string(FIND "${C}" "// VECTOR_QUERY_NATIVE_S57_V3" PROVIDER)
if(PROVIDER EQUAL -1)
  message(FATAL_ERROR "Native S57 provider v3 not found")
endif()
string(FIND "${C}" "// VECTOR_QUERY_INTERACTIVE_CONTROLS_V1" DONE)
if(NOT DONE EQUAL -1)
  message(STATUS "o-charts interactive vector-query controls already installed")
  return()
endif()

# Legacy prefix ends immediately before flags. This accepts both old callers
# and the extended structure without requiring sizeof(new struct).
set(OLD_VALIDATE [===[
  if (!query || query->struct_size < sizeof(PI_VectorQueryV1) || !viewport ||
      !sink || !std::isfinite(query->lat) || !std::isfinite(query->lon) ||
]===])
set(NEW_VALIDATE [===[
  const uint32_t legacy_query_size =
      static_cast<uint32_t>(offsetof(PI_VectorQueryV1, flags));
  if (!query || query->struct_size < legacy_query_size || !viewport ||
      !sink || !std::isfinite(query->lat) || !std::isfinite(query->lon) ||
]===])
string(FIND "${C}" "${OLD_VALIDATE}" P)
if(P EQUAL -1)
  message(FATAL_ERROR "Could not locate native provider validation")
endif()
string(REPLACE "${OLD_VALIDATE}" "${NEW_VALIDATE}" C "${C}")

set(RADIUS [===[
  const double radius_pixels =
      std::max(1.0, std::min(query->search_radius_pixels, 64.0));
]===])
set(CONTROLS [===[
  // VECTOR_QUERY_INTERACTIVE_CONTROLS_V1
  const bool has_flags = query->struct_size >=
      offsetof(PI_VectorQueryV1, geometry_mask);
  const bool has_geometry_mask = query->struct_size >=
      offsetof(PI_VectorQueryV1, max_objects);
  const bool has_max_objects = query->struct_size >=
      offsetof(PI_VectorQueryV1, max_points_per_object);
  const bool has_max_points = query->struct_size >=
      offsetof(PI_VectorQueryV1, exclude_feature_classes_utf8);
  const bool has_excludes = query->struct_size >= sizeof(PI_VectorQueryV1);

  const uint32_t query_flags = has_flags ? query->flags : 0u;
  const uint32_t geometry_mask =
      (has_geometry_mask && query->geometry_mask)
          ? query->geometry_mask : PI_VECTOR_QUERY_GEOMETRY_ALL_V1;
  const uint32_t object_limit =
      (has_max_objects && query->max_objects)
          ? std::min(query->max_objects, 256u) : 256u;
  const uint32_t point_limit =
      (has_max_points && query->max_points_per_object)
          ? std::max(2u, std::min(query->max_points_per_object, 65536u))
          : 65536u;
  const char *exclude_classes =
      (has_excludes && query->exclude_feature_classes_utf8)
          ? query->exclude_feature_classes_utf8 : "";

  auto feature_excluded = [&](const char *feature) {
    if (!feature || !*feature || !exclude_classes || !*exclude_classes)
      return false;
    const size_t flen = strlen(feature);
    const char *p = exclude_classes;
    while (*p) {
      while (*p == ',' || *p == ' ' || *p == '\t') ++p;
      const char *start = p;
      while (*p && *p != ',') ++p;
      const char *end = p;
      while (end > start && (end[-1] == ' ' || end[-1] == '\t')) --end;
      if (static_cast<size_t>(end - start) == flen &&
          !strncmp(start, feature, flen))
        return true;
      if (*p == ',') ++p;
    }
    return false;
  };

  const double radius_pixels =
      std::max(1.0, std::min(query->search_radius_pixels, 64.0));
]===])
string(FIND "${C}" "${RADIUS}" P)
if(P EQUAL -1)
  message(FATAL_ERROR "Could not locate radius block")
endif()
string(REPLACE "${RADIUS}" "${CONTROLS}" C "${C}")

string(REPLACE "if (selected.size() < 256) selected.push_back(obj);"
               "if (selected.size() < object_limit && !feature_excluded(obj->FeatureName)) selected.push_back(obj);"
               C "${C}")
string(REPLACE "selected.size() < 256" "selected.size() < object_limit" C "${C}")
string(REPLACE "emitted >= 256" "emitted >= object_limit" C "${C}")

set(GEOM_ANCHOR [===[
    uint32_t geometry_type = PI_VECTOR_GEOMETRY_UNKNOWN_V1;
]===])
set(GEOM_REPL [===[
    uint32_t geometry_type = PI_VECTOR_GEOMETRY_UNKNOWN_V1;
]===])
# Insert mask check after primitive classification.
set(AFTER_CLASS [===[
    else
      continue;

    std::vector<PI_VectorPositionV1> points;
]===])
set(AFTER_CLASS_REPL [===[
    else
      continue;

    const uint32_t geometry_bit =
        geometry_type == PI_VECTOR_GEOMETRY_POINT_V1
            ? PI_VECTOR_QUERY_GEOMETRY_POINT_V1
            : (geometry_type == PI_VECTOR_GEOMETRY_LINE_V1
                   ? PI_VECTOR_QUERY_GEOMETRY_LINE_V1
                   : PI_VECTOR_QUERY_GEOMETRY_AREA_V1);
    if (!(geometry_mask & geometry_bit)) continue;

    std::vector<PI_VectorPositionV1> points;
]===])
string(FIND "${C}" "${AFTER_CLASS}" P)
if(P EQUAL -1)
  message(FATAL_ERROR "Could not locate geometry classification tail")
endif()
string(REPLACE "${AFTER_CLASS}" "${AFTER_CLASS_REPL}" C "${C}")

# Stop extracting as soon as the requested point budget is reached. This is a
# transport/highlight budget, not a topology-preserving full-geometry mode.
string(REPLACE "points.size() < 65536" "points.size() < point_limit" C "${C}")
string(REPLACE "obj->npt <= 65536" "obj->npt <= 65536" C "${C}")

# For direct geoPt geometry, sample uniformly instead of copying thousands of
# points only to discard them in the consumer.
set(GEOPT_LOOP [===[
      for (int i = 0; i < obj->npt; ++i) {
        const double east = obj->geoPt[i].x * obj->x_rate + obj->x_origin;
        const double north = obj->geoPt[i].y * obj->y_rate + obj->y_origin;
        append_sm(points, east, north, m_ref_lat, m_ref_lon);
      }
]===])
set(GEOPT_SAMPLE [===[
      const uint32_t wanted = std::min<uint32_t>(point_limit,
                                                 static_cast<uint32_t>(obj->npt));
      for (uint32_t oi = 0; oi < wanted; ++oi) {
        const int i = wanted <= 1 ? 0 : static_cast<int>(
            (static_cast<uint64_t>(oi) * (obj->npt - 1)) / (wanted - 1));
        const double east = obj->geoPt[i].x * obj->x_rate + obj->x_origin;
        const double north = obj->geoPt[i].y * obj->y_rate + obj->y_origin;
        append_sm(points, east, north, m_ref_lat, m_ref_lon);
      }
]===])
string(FIND "${C}" "${GEOPT_LOOP}" P)
if(NOT P EQUAL -1)
  string(REPLACE "${GEOPT_LOOP}" "${GEOPT_SAMPLE}" C "${C}")
endif()

# Attributes are optional for fast hover/highlight queries.
string(REPLACE "if (obj->att_array && obj->attVal) {"
               "if (!(query_flags & PI_VECTOR_QUERY_SKIP_ATTRIBUTES_V1) && obj->att_array && obj->attVal) {"
               C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed o-charts interactive vector-query controls v1")
message(STATUS "  feature exclusion occurs before geometry extraction")
message(STATUS "  object and point budgets enforced provider-side")
message(STATUS "  attributes can be skipped for hover/highlight queries")
