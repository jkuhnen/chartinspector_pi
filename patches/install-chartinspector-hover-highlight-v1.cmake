set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()
file(READ "${CPP}" C)
string(FIND "${C}" "CHARTINSPECTOR_VECTOR_HOVER_V1" DONE)
if(NOT DONE EQUAL -1)
  message(STATUS "Chart Inspector vector hover highlight v1 already installed")
  return()
endif()

set(NS_ANCHOR "namespace {\n")
set(NS_CODE [===[
namespace {
// CHARTINSPECTOR_VECTOR_HOVER_V1
struct CI_VectorQueryV1 {
  uint32_t struct_size; double lat; double lon; double search_radius_pixels;
  uint32_t flags; uint32_t geometry_mask; uint32_t max_objects;
  uint32_t max_points_per_object; const char *exclude_feature_classes_utf8;
};
struct CI_VectorPositionV1 { double lat; double lon; };
struct CI_VectorPartV1 { uint32_t first_point; uint32_t point_count; };
struct CI_VectorAttributeV1 { const char *name_utf8; const char *value_utf8; };
struct CI_VectorObjectV1 {
  uint32_t struct_size; uint32_t geometry_type; const char *feature_class_utf8;
  const char *object_name_utf8; const CI_VectorPositionV1 *points;
  uint32_t point_count; const CI_VectorPartV1 *parts; uint32_t part_count;
  const CI_VectorAttributeV1 *attributes; uint32_t attribute_count;
};
using CI_VectorSinkV1 = bool (*)(const CI_VectorObjectV1 *, void *);
using CI_QueryVectorV1 = bool (*)(int, const CI_VectorQueryV1 *, CI_VectorSinkV1, void *);
constexpr uint32_t CI_SKIP_ATTRIBUTES = 1u;
constexpr uint32_t CI_GEOMETRY_ALL = 7u;

struct CI_HoverPosition { double lat = 0.0; double lon = 0.0; };
struct CI_HoverPart { unsigned int firstPoint = 0; unsigned int pointCount = 0; };
struct CI_HoverCandidate {
  uint32_t geometry = 0;
  wxString feature;
  std::vector<CI_HoverPosition> points;
  std::vector<CI_HoverPart> parts;
  int score = -100000;
};

int CI_FeatureScore(const wxString &f, uint32_t geometry) {
  if (f.StartsWith("BOY") || f.StartsWith("BCN") || f == "LIGHTS" ||
      f == "WRECKS" || f == "UWTROC" || f == "OBSTRN") return 400;
  if (geometry == 1) return 300;
  if (geometry == 2) return 200;
  return 100;
}

bool CI_CollectHover(const CI_VectorObjectV1 *o, void *user) {
  if (!o || !user || !o->points || !o->point_count) return true;
  auto *best = static_cast<CI_HoverCandidate *>(user);
  const wxString feature = wxString::FromUTF8(o->feature_class_utf8 ? o->feature_class_utf8 : "").Upper();
  const int score = CI_FeatureScore(feature, o->geometry_type);
  if (score <= best->score) return true;
  CI_HoverCandidate next;
  next.geometry = o->geometry_type; next.feature = feature; next.score = score;
  for (uint32_t i = 0; i < o->point_count; ++i)
    next.points.push_back({o->points[i].lat, o->points[i].lon});
  for (uint32_t i = 0; i < o->part_count; ++i)
    next.parts.push_back({o->parts[i].first_point, o->parts[i].point_count});
  *best = next;
  return true;
}
]===])
string(REPLACE "${NS_ANCHOR}" "${NS_CODE}" C "${C}")

set(CLEAR_ANCHOR "void ChartInspectorPi::ClearHover() {\n")
set(CLEAR_CODE [===[
void ChartInspectorPi::ClearHoverGeometry() {
  m_hoverPoints.clear(); m_hoverParts.clear(); m_hoverFeature.clear();
  m_hoverGeometryType = 0; m_hasHoverGeometry = false;
}

void ChartInspectorPi::ClearHover() {
  ClearHoverGeometry();
]===])
string(REPLACE "${CLEAR_ANCHOR}" "${CLEAR_CODE}" C "${C}")

set(MOUSE_OLD [===[
bool ChartInspectorPi::MouseEventHook(wxMouseEvent &event) {
  m_mousePosition = event.GetPosition();
  m_hasMousePosition = true;
  UpdateHoverObject();
]===])
set(MOUSE_NEW [===[
void ChartInspectorPi::UpdateHoverGeometry(bool force) {
#ifdef _WIN32
  if (!m_enabled || !m_hasCursorPosition || !m_hasMousePosition) { ClearHoverGeometry(); return; }
  const long long now = wxGetUTCTimeMillis().GetValue();
  const int dx = m_mousePosition.x - m_lastHoverQueryPosition.x;
  const int dy = m_mousePosition.y - m_lastHoverQueryPosition.y;
  if (!force && now - m_lastHoverQueryMs < 75) return;
  if (!force && m_lastHoverQueryMs && dx * dx + dy * dy < 9) return;
  HMODULE host = GetModuleHandleW(nullptr);
  auto queryFn = host ? reinterpret_cast<CI_QueryVectorV1>(GetProcAddress(host, "QueryVectorChartObjectsV1")) : nullptr;
  if (!queryFn) { ClearHoverGeometry(); return; }
  CI_VectorQueryV1 q{};
  q.struct_size = sizeof(q); q.lat = m_cursorLat; q.lon = m_cursorLon;
  q.search_radius_pixels = static_cast<double>(std::max(8, m_hitRadiusPixels));
  q.flags = CI_SKIP_ATTRIBUTES; q.geometry_mask = CI_GEOMETRY_ALL;
  q.max_objects = 8; q.max_points_per_object = 50;
  q.exclude_feature_classes_utf8 = "LNDARE,COALNE,DEPARE,DEPCNT,M_NPUB,M_COVR,M_NSYS,MAGVAR,SEAARE";
  CI_HoverCandidate best;
  queryFn(0, &q, CI_CollectHover, &best);
  m_lastHoverQueryMs = now; m_lastHoverQueryPosition = m_mousePosition;
  if (best.points.empty()) { ClearHoverGeometry(); return; }
  m_hoverPoints.clear();
  m_hoverParts.clear();
  for (const auto &p : best.points) m_hoverPoints.push_back({p.lat, p.lon});
  for (const auto &part : best.parts) m_hoverParts.push_back({part.firstPoint, part.pointCount});
  m_hoverGeometryType = static_cast<int>(best.geometry); m_hoverFeature = best.feature;
  m_hasHoverGeometry = true;
#else
  (void)force;
#endif
}

bool ChartInspectorPi::MouseEventHook(wxMouseEvent &event) {
  m_mousePosition = event.GetPosition();
  m_hasMousePosition = true;
  UpdateHoverGeometry(event.LeftDown());
  if (event.LeftDown()) UpdateHoverObject();
]===])
string(FIND "${C}" "${MOUSE_OLD}" MP)
if(MP EQUAL -1)
  message(FATAL_ERROR "MouseEventHook anchor not found")
endif()
string(REPLACE "${MOUSE_OLD}" "${MOUSE_NEW}" C "${C}")

set(RENDER_OLD [===[
bool ChartInspectorPi::RenderOverlay(wxDC &dc, PlugIn_ViewPort *vp) {
  if (!vp || !m_enabled || !m_hasVectorObject) return false;
  wxPoint p;
  GetCanvasPixLL(vp, &p, m_lastObjectLat, m_lastObjectLon);
  dc.SetBrush(*wxTRANSPARENT_BRUSH);
  dc.SetPen(wxPen(wxColour(0, 255, 255), 3));
  dc.DrawCircle(p, m_lastPrimitiveType == 1 ? 12 : 9);
  return true;
}
]===])
set(RENDER_NEW [===[
bool ChartInspectorPi::RenderOverlay(wxDC &dc, PlugIn_ViewPort *vp) {
  if (!vp || !m_enabled) return false;
  if (m_hasHoverGeometry) {
    dc.SetBrush(*wxTRANSPARENT_BRUSH);
    auto draw = [&](int width, const wxColour &colour) {
      dc.SetPen(wxPen(colour, width));
      if (m_hoverGeometryType == 1 && !m_hoverPoints.empty()) {
        wxPoint p; GetCanvasPixLL(vp, &p, m_hoverPoints[0].lat, m_hoverPoints[0].lon);
        dc.DrawCircle(p, width > 5 ? 15 : 12);
      } else {
        for (const auto &part : m_hoverParts) {
          if (part.pointCount < 2 || part.firstPoint >= m_hoverPoints.size()) continue;
          std::vector<wxPoint> pix;
          const unsigned int end = std::min<unsigned int>(part.firstPoint + part.pointCount, static_cast<unsigned int>(m_hoverPoints.size()));
          for (unsigned int i = part.firstPoint; i < end; ++i) {
            wxPoint p; GetCanvasPixLL(vp, &p, m_hoverPoints[i].lat, m_hoverPoints[i].lon); pix.push_back(p);
          }
          if (pix.size() >= 2) dc.DrawLines(static_cast<int>(pix.size()), pix.data());
        }
      }
    };
    draw(9, wxColour(0, 120, 160)); draw(3, wxColour(0, 255, 255));
    return true;
  }
  if (!m_hasVectorObject) return false;
  wxPoint p; GetCanvasPixLL(vp, &p, m_lastObjectLat, m_lastObjectLon);
  dc.SetBrush(*wxTRANSPARENT_BRUSH); dc.SetPen(wxPen(wxColour(0, 255, 255), 3)); dc.DrawCircle(p, 12);
  return true;
}
]===])
string(FIND "${C}" "${RENDER_OLD}" RP)
if(RP EQUAL -1)
  message(FATAL_ERROR "RenderOverlay anchor not found")
endif()
string(REPLACE "${RENDER_OLD}" "${RENDER_NEW}" C "${C}")

set(GL_POINT [===[
  wxPoint p;
  GetCanvasPixLL(vp, &p, m_lastObjectLat, m_lastObjectLon);
  const float r = m_lastPrimitiveType == 1 ? 12.0f : 9.0f;
  glColor4f(0.0f, 1.0f, 1.0f, 0.9f);
  glLineWidth(3.0f);
  glBegin(GL_LINE_LOOP);
  for (int i = 0; i < 32; ++i) {
    const float a = static_cast<float>(i) * 6.28318530718f / 32.0f;
    glVertex2f(static_cast<float>(p.x) + r * cosf(a),
               static_cast<float>(p.y) + r * sinf(a));
  }
  glEnd();
]===])
set(GL_GEOM [===[
  auto drawHoverGL = [&](float width, float alpha) {
    glLineWidth(width); glColor4f(0.0f, 1.0f, 1.0f, alpha);
    if (m_hasHoverGeometry && m_hoverGeometryType == 1 && !m_hoverPoints.empty()) {
      wxPoint p; GetCanvasPixLL(vp, &p, m_hoverPoints[0].lat, m_hoverPoints[0].lon);
      const float r = width > 5.0f ? 15.0f : 12.0f; glBegin(GL_LINE_LOOP);
      for (int i = 0; i < 32; ++i) { const float a = i * 6.28318530718f / 32.0f; glVertex2f(p.x + r*cosf(a), p.y + r*sinf(a)); }
      glEnd();
    } else if (m_hasHoverGeometry) {
      for (const auto &part : m_hoverParts) {
        if (part.pointCount < 2 || part.firstPoint >= m_hoverPoints.size()) continue;
        const unsigned int end = std::min<unsigned int>(part.firstPoint + part.pointCount, static_cast<unsigned int>(m_hoverPoints.size()));
        glBegin(GL_LINE_STRIP);
        for (unsigned int i = part.firstPoint; i < end; ++i) { wxPoint p; GetCanvasPixLL(vp, &p, m_hoverPoints[i].lat, m_hoverPoints[i].lon); glVertex2f((float)p.x, (float)p.y); }
        glEnd();
      }
    }
  };
  if (m_hasHoverGeometry) { drawHoverGL(9.0f, 0.32f); drawHoverGL(3.0f, 0.95f); }
  else {
    wxPoint p; GetCanvasPixLL(vp, &p, m_lastObjectLat, m_lastObjectLon);
    glColor4f(0.0f, 1.0f, 1.0f, 0.9f); glLineWidth(3.0f); glBegin(GL_LINE_LOOP);
    for (int i = 0; i < 32; ++i) { const float a = i * 6.28318530718f / 32.0f; glVertex2f(p.x + 12.0f*cosf(a), p.y + 12.0f*sinf(a)); }
    glEnd();
  }
]===])
string(FIND "${C}" "${GL_POINT}" GP)
if(GP EQUAL -1)
  message(FATAL_ERROR "GL highlight anchor not found")
endif()
string(REPLACE "${GL_POINT}" "${GL_GEOM}" C "${C}")
string(REPLACE "if (!m_enabled || !m_hasVectorObject) return true;" "if (!m_enabled || (!m_hasVectorObject && !m_hasHoverGeometry)) return true;" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector vector hover highlight v1")
message(STATUS "  hover query throttled to 75 ms and 3 px movement")
message(STATUS "  max 8 objects / 50 points, attributes skipped")
message(STATUS "  background/meta chart classes excluded")
message(STATUS "  point halo and line/area two-pass cyan glow enabled")
