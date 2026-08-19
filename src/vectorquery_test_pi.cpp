#include "ocpn_plugin.h"

#ifdef _WIN32
#include <windows.h>
#endif

#include <wx/log.h>
#include <wx/wx.h>

#include <cstdint>
#include <cstring>

namespace {

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
typedef bool (*QueryVectorChartObjectsV1Fn)(
    int canvas_index, const PI_VectorQueryV1 *query,
    PI_VectorObjectSinkV1 sink, void *user_data);

const char *GeometryName(uint32_t type) {
  switch (type) {
    case PI_VECTOR_GEOMETRY_POINT_V1:
      return "Point";
    case PI_VECTOR_GEOMETRY_LINE_V1:
      return "Line";
    case PI_VECTOR_GEOMETRY_AREA_V1:
      return "Area";
    default:
      return "Unknown";
  }
}

struct QueryResultCounter {
  int count = 0;
};

bool LogObject(const PI_VectorObjectV1 *object, void *user_data) {
  if (!object || !user_data) return false;
  auto *counter = static_cast<QueryResultCounter *>(user_data);
  ++counter->count;

  const char *feature = object->feature_class_utf8
                            ? object->feature_class_utf8
                            : "";
  const char *name = object->object_name_utf8 ? object->object_name_utf8 : "";

  wxLogMessage(
      "VECTORQUERY_TEST object=%d feature=%s type=%s points=%u parts=%u attrs=%u name=%s",
      counter->count, wxString::FromUTF8(feature),
      wxString::FromUTF8(GeometryName(object->geometry_type)),
      static_cast<unsigned>(object->point_count),
      static_cast<unsigned>(object->part_count),
      static_cast<unsigned>(object->attribute_count), wxString::FromUTF8(name));

  if (object->point_count > 0 && object->points) {
    const PI_VectorPositionV1 &p = object->points[0];
    wxLogMessage("VECTORQUERY_TEST first_point lat=%.8f lon=%.8f", p.lat,
                 p.lon);
  }

  if (object->attribute_count > 0 && object->attributes) {
    for (uint32_t i = 0; i < object->attribute_count; ++i) {
      const PI_VectorAttributeV1 &attr = object->attributes[i];
      const char *attr_name = attr.name_utf8 ? attr.name_utf8 : "";
      const char *attr_value = attr.value_utf8 ? attr.value_utf8 : "";
      wxLogMessage("VECTORQUERY_TEST attr object=%d %s=%s", counter->count,
                   wxString::FromUTF8(attr_name),
                   wxString::FromUTF8(attr_value));
    }
  }

  return true;
}

}  // namespace

class VectorQueryTestPi : public opencpn_plugin_118 {
public:
  explicit VectorQueryTestPi(void *ppimgr) : opencpn_plugin_118(ppimgr) {}

  int Init() override {
#ifdef _WIN32
    HMODULE host = GetModuleHandleW(nullptr);
    if (host) {
      m_query = reinterpret_cast<QueryVectorChartObjectsV1Fn>(
          GetProcAddress(host, "QueryVectorChartObjectsV1"));
    }
#endif
    wxLogMessage("VECTORQUERY_TEST init api=%s",
                 m_query ? "available" : "missing");
    return WANTS_MOUSE_EVENTS | WANTS_CURSOR_LATLON;
  }

  bool DeInit() override {
    wxLogMessage("VECTORQUERY_TEST deinit");
    return true;
  }

  int GetAPIVersionMajor() override { return 1; }
  int GetAPIVersionMinor() override { return 18; }
  int GetPlugInVersionMajor() override { return 0; }
  int GetPlugInVersionMinor() override { return 1; }
  int GetToolbarToolCount() override { return 0; }

  wxBitmap *GetPlugInBitmap() override { return &m_bitmap; }
  wxString GetCommonName() override { return "Vector Query API Test"; }
  wxString GetShortDescription() override {
    return "Diagnostic consumer for QueryVectorChartObjectsV1";
  }
  wxString GetLongDescription() override {
    return "Logs vector chart candidates and attributes on left click.";
  }

  void SetCursorLatLon(double lat, double lon) override {
    m_lat = lat;
    m_lon = lon;
    m_have_position = true;
  }

  bool MouseEventHook(wxMouseEvent &event) override {
    if (!event.LeftDown() || !m_query || !m_have_position) return false;

    PI_VectorQueryV1 query{};
    query.struct_size = sizeof(query);
    query.lat = m_lat;
    query.lon = m_lon;
    query.search_radius_pixels = 12.0;

    QueryResultCounter counter;
    const bool ok = m_query(0, &query, LogObject, &counter);
    wxLogMessage(
        "VECTORQUERY_TEST query lat=%.8f lon=%.8f ok=%d candidates=%d",
        m_lat, m_lon, ok ? 1 : 0, counter.count);
    return false;
  }

private:
  wxBitmap m_bitmap;
  QueryVectorChartObjectsV1Fn m_query = nullptr;
  double m_lat = 0.0;
  double m_lon = 0.0;
  bool m_have_position = false;
};

#ifdef _WIN32
#define VECTORQUERY_TEST_EXPORT __declspec(dllexport)
#else
#define VECTORQUERY_TEST_EXPORT DECL_EXP
#endif

extern "C" VECTORQUERY_TEST_EXPORT opencpn_plugin *create_pi(void *ppimgr) {
  return new VectorQueryTestPi(ppimgr);
}

extern "C" VECTORQUERY_TEST_EXPORT void destroy_pi(opencpn_plugin *plugin) {
  delete plugin;
}
