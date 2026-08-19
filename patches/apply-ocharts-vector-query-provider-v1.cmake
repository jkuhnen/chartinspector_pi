if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required, e.g. -DOCHARTS_ROOT=C:/Users/Johannes/source/o-charts_pi")
endif()

file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CHART_H "${OCHARTS_ROOT}/src/eSENCChart.h")
set(CHART_CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
set(API_H "${OCHARTS_ROOT}/api-16/ocpn_plugin.h")

foreach(P "${CHART_H}" "${CHART_CPP}" "${API_H}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Required o-charts file not found: ${P}")
  endif()
endforeach()

# -----------------------------------------------------------------------------
# Local compile shim for the experimental OpenCPN API.
# This is only needed while o-charts still carries a bundled ocpn_plugin.h.
# The eventual upstream provider PR should target the released API header.
# -----------------------------------------------------------------------------
file(READ "${API_H}" A)

if(NOT A MATCHES "struct PI_VectorObjectV1")
  set(API_TYPES [===[

// Experimental OpenCPN Vector Object Query API v1 compile shim.
enum PI_VectorGeometryTypeV1 : uint32_t {
  PI_VECTOR_GEOMETRY_UNKNOWN_V1 = 0,
  PI_VECTOR_GEOMETRY_POINT_V1 = 1,
  PI_VECTOR_GEOMETRY_LINE_V1 = 2,
  PI_VECTOR_GEOMETRY_AREA_V1 = 3
};

struct PI_VectorQueryV1 {
  uint32_t struct_size;
  double lat;
  double lon;
  double search_radius_pixels;
};

struct PI_VectorPositionV1 {
  double lat;
  double lon;
};

struct PI_VectorPartV1 {
  uint32_t first_point;
  uint32_t point_count;
};

struct PI_VectorAttributeV1 {
  const char *name_utf8;
  const char *value_utf8;
};

struct PI_VectorObjectV1 {
  uint32_t struct_size;
  uint32_t geometry_type;
  const char *feature_class_utf8;
  const char *object_name_utf8;
  const PI_VectorPositionV1 *points;
  uint32_t point_count;
  const PI_VectorPartV1 *parts;
  uint32_t part_count;
  const PI_VectorAttributeV1 *attributes;
  uint32_t attribute_count;
};

typedef bool (*PI_VectorObjectSinkV1)(const PI_VectorObjectV1 *object,
                                      void *user_data);
]===])

  string(FIND "${A}" "class PI_S57Obj;" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate PI_S57Obj declaration in ${API_H}")
  endif()
  string(SUBSTRING "${A}" 0 ${POS} PRE)
  string(SUBSTRING "${A}" ${POS} -1 POST)
  set(A "${PRE}${API_TYPES}\n${POST}")
endif()

if(NOT A MATCHES "class DECL_EXP PlugInChartBaseExtendedPlus3")
  set(PLUS3 [===[

class DECL_EXP PlugInChartBaseExtendedPlus3
    : public PlugInChartBaseExtendedPlus2 {
public:
  PlugInChartBaseExtendedPlus3();
  virtual ~PlugInChartBaseExtendedPlus3();

  virtual bool QueryVectorObjectsV1(const PI_VectorQueryV1 *query,
                                    const PlugIn_ViewPort *viewport,
                                    PI_VectorObjectSinkV1 sink,
                                    void *user_data) {
    (void)query;
    (void)viewport;
    (void)sink;
    (void)user_data;
    return false;
  }
};
]===])

  string(FIND "${A}" "class wxArrayOfS57attVal;" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate Extended provider insertion anchor in ${API_H}")
  endif()
  string(SUBSTRING "${A}" 0 ${POS} PRE)
  string(SUBSTRING "${A}" ${POS} -1 POST)
  set(A "${PRE}${PLUS3}\n${POST}")
endif()

file(WRITE "${API_H}" "${A}")

# -----------------------------------------------------------------------------
# eSENCChart derives from ExtendedPlus3 and implements QueryVectorObjectsV1.
# Android is intentionally left unchanged for this Windows development slice.
# -----------------------------------------------------------------------------
file(READ "${CHART_H}" H)
string(REPLACE
  "class  eSENCChart : public PlugInChartBaseExtendedPlus2"
  "class  eSENCChart : public PlugInChartBaseExtendedPlus3"
  H "${H}")

if(NOT H MATCHES "QueryVectorObjectsV1\\(")
  set(DECL [===[
      bool QueryVectorObjectsV1(const PI_VectorQueryV1 *query,
                                const PlugIn_ViewPort *viewport,
                                PI_VectorObjectSinkV1 sink,
                                void *user_data) override;

]===])
  string(FIND "${H}" "      ListOfPI_S57Obj *GetObjRuleListAtLatLon" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate GetObjRuleListAtLatLon declaration in ${CHART_H}")
  endif()
  string(SUBSTRING "${H}" 0 ${POS} PRE)
  string(SUBSTRING "${H}" ${POS} -1 POST)
  set(H "${PRE}${DECL}${POST}")
endif()
file(WRITE "${CHART_H}" "${H}")

file(READ "${CHART_CPP}" C)

foreach(INC "#include <cmath>" "#include <cstring>" "#include <vector>")
  if(NOT C MATCHES "${INC}")
    string(REPLACE "#include <unordered_map>" "#include <unordered_map>\n${INC}" C "${C}")
  endif()
endforeach()

if(NOT C MATCHES "eSENCChart::QueryVectorObjectsV1")
  set(IMPL [===[

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
  uint32_t emitted = 0;

  for (auto node = objects->GetFirst(); node && keep_going && emitted < 256;
       node = node->GetNext()) {
    PI_S57Obj *obj = node->GetData();
    if (!obj || !obj->FeatureName[0]) continue;

    uint32_t geometry_type = PI_VECTOR_GEOMETRY_UNKNOWN_V1;
    if (obj->Primitive_type == GEO_POINT)
      geometry_type = PI_VECTOR_GEOMETRY_POINT_V1;
    else if (obj->Primitive_type == GEO_LINE)
      geometry_type = PI_VECTOR_GEOMETRY_LINE_V1;
    else if (obj->Primitive_type == GEO_AREA)
      geometry_type = PI_VECTOR_GEOMETRY_AREA_V1;
    else
      continue;

    std::vector<PI_VectorPositionV1> points;
    std::vector<PI_VectorPartV1> parts;

    if (geometry_type == PI_VECTOR_GEOMETRY_POINT_V1) {
      if (std::isfinite(obj->m_lat) && std::isfinite(obj->m_lon))
        points.push_back({obj->m_lat, obj->m_lon});
    } else if (obj->geoPt && obj->npt >= 2 && obj->npt <= 16384) {
      const pt *source = static_cast<const pt *>(obj->geoPt);
      PI_VectorPartV1 part{};
      part.first_point = 0;
      for (int i = 0; i < obj->npt; ++i) {
        const double east = source[i].x * obj->x_rate + obj->x_origin;
        const double north = source[i].y * obj->y_rate + obj->y_origin;
        double lat = 0.0;
        double lon = 0.0;
        fromSM(east, north, obj->chart_ref_lat, obj->chart_ref_lon, &lat, &lon);
        if (!std::isfinite(lat) || !std::isfinite(lon)) continue;
        points.push_back({lat, lon});
        ++part.point_count;
      }
      if (part.point_count >= 2) parts.push_back(part);
    }

    // Some line/area objects are represented only by the provider's edge/VBO
    // structures. Do not emit incomplete geometry; the next slice will add the
    // edge-list fallback after this basic provider path is validated.
    if (points.empty() ||
        (geometry_type != PI_VECTOR_GEOMETRY_POINT_V1 && parts.empty()))
      continue;

    std::string feature(obj->FeatureName,
                        strnlen(obj->FeatureName, sizeof(obj->FeatureName)));
    if (feature.empty()) continue;

    wxString object_name;
    std::vector<std::string> attr_names;
    std::vector<std::string> attr_values;
    std::vector<PI_VectorAttributeV1> attrs;
    const int attr_count = std::max(0, std::min(obj->n_attr, 512));
    attr_names.reserve(attr_count);
    attr_values.reserve(attr_count);

    if (obj->att_array && obj->attVal) {
      for (int i = 0; i < attr_count; ++i) {
        char acronym[7] = {0};
        memcpy(acronym, obj->att_array + i * 6, 6);
        if (!acronym[0]) continue;
        wxString name = wxString::FromUTF8(acronym);
        wxString value = GetObjectAttributeValueAsString(obj, i, name);
        const wxCharBuffer value_utf8 = value.ToUTF8();
        attr_names.emplace_back(acronym);
        attr_values.emplace_back(value_utf8.data() ? value_utf8.data() : "");
        if (!strcmp(acronym, "OBJNAM") && object_name.IsEmpty())
          object_name = value;
        if (!strcmp(acronym, "NOBJNM") && object_name.IsEmpty())
          object_name = value;
      }
    }

    attrs.reserve(attr_names.size());
    for (size_t i = 0; i < attr_names.size(); ++i)
      attrs.push_back({attr_names[i].c_str(), attr_values[i].c_str()});

    const wxCharBuffer object_name_utf8 = object_name.ToUTF8();
    PI_VectorObjectV1 out{};
    out.struct_size = sizeof(out);
    out.geometry_type = geometry_type;
    out.feature_class_utf8 = feature.c_str();
    out.object_name_utf8 = object_name_utf8.data();
    out.points = points.data();
    out.point_count = static_cast<uint32_t>(points.size());
    out.parts = parts.empty() ? nullptr : parts.data();
    out.part_count = static_cast<uint32_t>(parts.size());
    out.attributes = attrs.empty() ? nullptr : attrs.data();
    out.attribute_count = static_cast<uint32_t>(attrs.size());

    ++emitted;
    keep_going = sink(&out, user_data);
  }

  // GetObjRuleListAtLatLon returns provider-created PI_S57Obj copies.
  objects->DeleteContents(true);
  delete objects;
  return true;
}

]===])

  string(FIND "${C}" "ListOfPI_S57Obj *eSENCChart::GetObjRuleListAtLatLon" POS)
  if(POS EQUAL -1)
    string(FIND "${C}" "ListOfPI_S57Obj *eSENCChart::GetObjRuleListAtLatLon(" POS)
  endif()
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate GetObjRuleListAtLatLon implementation in ${CHART_CPP}")
  endif()
  string(SUBSTRING "${C}" 0 ${POS} PRE)
  string(SUBSTRING "${C}" ${POS} -1 POST)
  set(C "${PRE}${IMPL}${POST}")
endif()

file(WRITE "${CHART_CPP}" "${C}")
message(STATUS "Installed o-charts Vector Query Provider v1")
message(STATUS "  eSENCChart -> PlugInChartBaseExtendedPlus3")
message(STATUS "  Point geometry: enabled")
message(STATUS "  direct geoPt line/area geometry: enabled")
message(STATUS "  edge/VBO fallback: intentionally deferred to next validation slice")
