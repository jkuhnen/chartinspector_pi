if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required")
endif()

file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CHART_CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CHART_CPP}")
  message(FATAL_ERROR "Missing ${CHART_CPP}")
endif()

file(READ "${CHART_CPP}" C)

if(C MATCHES "VECTOR_QUERY_ACTIVE_PROVIDER_V1")
  message(STATUS "Active vector query provider already installed")
  return()
endif()

foreach(INC "#include <cmath>" "#include <cstring>" "#include <vector>")
  string(FIND "${C}" "${INC}" IPOS)
  if(IPOS EQUAL -1)
    string(REPLACE "#include <unordered_map>" "#include <unordered_map>\n${INC}" C "${C}")
  endif()
endforeach()

set(IMPL [===[

// VECTOR_QUERY_ACTIVE_PROVIDER_V1
bool eSENCChart::QueryVectorObjectsV1(const PI_VectorQueryV1 *query,
                                      const PlugIn_ViewPort *viewport,
                                      PI_VectorObjectSinkV1 sink,
                                      void *user_data) {
  if (!query || query->struct_size < sizeof(PI_VectorQueryV1) || !viewport ||
      !sink || !std::isfinite(query->lat) || !std::isfinite(query->lon) ||
      !std::isfinite(query->search_radius_pixels) ||
      viewport->view_scale_ppm <= 0.0)
    return false;

  PlugIn_ViewPort vp = *viewport;
  const double radius_pixels =
      std::max(1.0, std::min(query->search_radius_pixels, 64.0));
  const float select_radius = static_cast<float>(
      radius_pixels / (viewport->view_scale_ppm * 1852.0 * 60.0));

  ListOfPI_S57Obj *objects = GetObjRuleListAtLatLon(
      static_cast<float>(query->lat), static_cast<float>(query->lon),
      select_radius, &vp);
  if (!objects) return true;

  bool keep_going = true;
  for (auto node = objects->GetFirst(); node && keep_going;
       node = node->GetNext()) {
    PI_S57Obj *obj = node->GetData();
    if (!obj || !obj->FeatureName[0] || obj->Primitive_type != GEO_POINT)
      continue;
    if (!std::isfinite(obj->m_lat) || !std::isfinite(obj->m_lon))
      continue;

    PI_VectorPositionV1 point{obj->m_lat, obj->m_lon};
    std::string feature(obj->FeatureName,
                        strnlen(obj->FeatureName, sizeof(obj->FeatureName)));
    if (feature.empty()) continue;

    PI_VectorObjectV1 out{};
    out.struct_size = sizeof(out);
    out.geometry_type = PI_VECTOR_GEOMETRY_POINT_V1;
    out.feature_class_utf8 = feature.c_str();
    out.object_name_utf8 = nullptr;
    out.points = &point;
    out.point_count = 1;
    out.parts = nullptr;
    out.part_count = 0;
    out.attributes = nullptr;
    out.attribute_count = 0;

    keep_going = sink(&out, user_data);
  }

  objects->DeleteContents(true);
  delete objects;
  return true;
}

]===])

# Insert immediately before the real constructor. This is an active compilation
# region and avoids the earlier GetObjRuleListAtLatLon occurrence inside #if 0.
string(FIND "${C}" "eSENCChart::eSENCChart()" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate active eSENCChart constructor anchor")
endif()
string(SUBSTRING "${C}" 0 ${POS} PRE)
string(SUBSTRING "${C}" ${POS} -1 POST)
file(WRITE "${CHART_CPP}" "${PRE}${IMPL}${POST}")
message(STATUS "Installed active point-only eSENCChart::QueryVectorObjectsV1 provider")
