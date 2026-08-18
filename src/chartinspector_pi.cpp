#include "chartinspector_pi.h"

#ifdef _WIN32
#include <windows.h>
#endif
#include <GL/gl.h>

extern "C" DECL_EXP opencpn_plugin *create_pi(void *ppimgr) {
  return new ChartInspectorPi(ppimgr);
}

extern "C" DECL_EXP void destroy_pi(opencpn_plugin *plugin) {
  delete plugin;
}

ChartInspectorPi::ChartInspectorPi(void *ppimgr) : opencpn_plugin_118(ppimgr) {}

int ChartInspectorPi::Init() {
#ifdef _WIN32
  HMODULE host = GetModuleHandleW(nullptr);
  if (host) {
    m_hitTest = reinterpret_cast<HitTestFn>(
        GetProcAddress(host, "OCPNChartInspectorHitTest"));
  }
#endif

  return WANTS_MOUSE_EVENTS | WANTS_CURSOR_LATLON | WANTS_OVERLAY_CALLBACK |
         WANTS_OPENGL_OVERLAY_CALLBACK | WANTS_VECTOR_CHART_OBJECT_INFO;
}

bool ChartInspectorPi::DeInit() { return true; }

int ChartInspectorPi::GetAPIVersionMajor() { return 1; }
int ChartInspectorPi::GetAPIVersionMinor() { return 18; }
int ChartInspectorPi::GetPlugInVersionMajor() { return 0; }
int ChartInspectorPi::GetPlugInVersionMinor() { return 1; }

wxBitmap *ChartInspectorPi::GetPlugInBitmap() { return &m_pluginBitmap; }
wxString ChartInspectorPi::GetCommonName() { return "Chart Inspector"; }
wxString ChartInspectorPi::GetShortDescription() {
  return "Interactive inspection of vector chart objects.";
}
wxString ChartInspectorPi::GetLongDescription() {
  return "Chart Inspector adds direct interaction with vector chart features, "
         "including hover highlighting, object selection and quick access to "
         "feature metadata.";
}

void ChartInspectorPi::SetCursorLatLon(double lat, double lon) {
  m_cursorLat = lat;
  m_cursorLon = lon;
  m_hasCursorPosition = true;
}

void ChartInspectorPi::UpdateHoverObject() {
  if (!m_hitTest || !m_hasCursorPosition) return;

  char feature[32] = {0};
  char objectName[128] = {0};
  double objectLat = 0.0;
  double objectLon = 0.0;

  const bool found = m_hitTest(0, m_cursorLat, m_cursorLon, 18.0, feature,
                               static_cast<int>(sizeof(feature)), objectName,
                               static_cast<int>(sizeof(objectName)), &objectLat,
                               &objectLon);

  m_hasVectorObject = found;
  if (found) {
    m_lastFeature = wxString::FromUTF8(feature);
    m_lastObjectName = wxString::FromUTF8(objectName);
    m_lastObjectLat = objectLat;
    m_lastObjectLon = objectLon;
  } else {
    m_lastFeature.clear();
    m_lastObjectName.clear();
  }

  wxWindow *canvas = GetOCPNCanvasWindow();
  if (canvas) {
    if (found) {
      wxString tooltip = m_lastFeature;
      if (!m_lastObjectName.IsEmpty()) tooltip += " | " + m_lastObjectName;
      canvas->SetToolTip(tooltip);
    } else {
      canvas->UnsetToolTip();
    }
  }
}

bool ChartInspectorPi::MouseEventHook(wxMouseEvent &event) {
  m_mousePosition = event.GetPosition();
  m_hasMousePosition = true;

  UpdateHoverObject();

  wxWindow *canvas = GetOCPNCanvasWindow();
  if (canvas) RequestRefresh(canvas);
  return false;
}

void ChartInspectorPi::SendVectorChartObjectInfo(
    wxString &chart, wxString &feature, wxString &objname, double lat,
    double lon, double scale, int nativescale) {
  // Keep legacy callback support for compatibility with unmodified OpenCPN.
  m_lastChart = chart;
  m_lastFeature = feature;
  m_lastObjectName = objname;
  m_lastObjectLat = lat;
  m_lastObjectLon = lon;
  m_lastObjectScale = scale;
  m_lastObjectNativeScale = nativescale;
  m_hasVectorObject = true;
}

bool ChartInspectorPi::RenderOverlay(wxDC &dc, PlugIn_ViewPort *vp) {
  if (!vp) return false;

  dc.SetBrush(*wxTRANSPARENT_BRUSH);
  dc.SetPen(wxPen(wxColour(255, 0, 255), 3));
  dc.DrawRectangle(18, 18, 24, 24);
  dc.DrawText("CI", wxPoint(48, 20));

  if (m_hasMousePosition) {
    const int x = m_mousePosition.x;
    const int y = m_mousePosition.y;
    dc.SetPen(wxPen(wxColour(255, 0, 255), 2));
    dc.DrawLine(x - 14, y, x + 14, y);
    dc.DrawLine(x, y - 14, x, y + 14);
  }

  if (m_hasVectorObject) {
    wxPoint p;
    GetCanvasPixLL(vp, &p, m_lastObjectLat, m_lastObjectLon);
    dc.SetPen(wxPen(wxColour(0, 255, 255), 3));
    dc.DrawCircle(p, 14);
    dc.SetTextForeground(wxColour(0, 255, 255));
    wxString label = m_lastFeature;
    if (!m_lastObjectName.IsEmpty()) label += " | " + m_lastObjectName;
    dc.DrawText(label, wxPoint(p.x + 18, p.y + 10));
  }

  return true;
}

bool ChartInspectorPi::RenderGLOverlayMultiCanvas(wxGLContext *pcontext,
                                                   PlugIn_ViewPort *vp,
                                                   int canvasIndex,
                                                   int priority) {
  (void)pcontext;
  (void)canvasIndex;
  if (!vp) return false;
  if (priority != -1 && priority != OVERLAY_LEGACY) return false;

  glPushAttrib(GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT | GL_LINE_BIT |
               GL_TRANSFORM_BIT | GL_VIEWPORT_BIT | GL_CURRENT_BIT);
  glDisable(GL_TEXTURE_2D);
  glDisable(GL_DEPTH_TEST);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  glMatrixMode(GL_PROJECTION);
  glPushMatrix();
  glLoadIdentity();
  glOrtho(0.0, static_cast<double>(vp->pix_width),
          static_cast<double>(vp->pix_height), 0.0, -1.0, 1.0);

  glMatrixMode(GL_MODELVIEW);
  glPushMatrix();
  glLoadIdentity();

  glColor4f(1.0f, 0.0f, 1.0f, 1.0f);
  glLineWidth(3.0f);
  glBegin(GL_LINE_LOOP);
  glVertex2f(18.0f, 18.0f);
  glVertex2f(42.0f, 18.0f);
  glVertex2f(42.0f, 42.0f);
  glVertex2f(18.0f, 42.0f);
  glEnd();

  if (m_hasMousePosition) {
    const float x = static_cast<float>(m_mousePosition.x);
    const float y = static_cast<float>(m_mousePosition.y);
    glLineWidth(2.0f);
    glBegin(GL_LINES);
    glVertex2f(x - 14.0f, y);
    glVertex2f(x + 14.0f, y);
    glVertex2f(x, y - 14.0f);
    glVertex2f(x, y + 14.0f);
    glEnd();
  }

  if (m_hasVectorObject) {
    wxPoint p;
    GetCanvasPixLL(vp, &p, m_lastObjectLat, m_lastObjectLon);
    const float cx = static_cast<float>(p.x);
    const float cy = static_cast<float>(p.y);
    const float r = 14.0f;
    glColor4f(0.0f, 1.0f, 1.0f, 1.0f);
    glLineWidth(3.0f);
    glBegin(GL_LINE_LOOP);
    for (int i = 0; i < 32; ++i) {
      const float a = static_cast<float>(i) * 6.28318530718f / 32.0f;
      glVertex2f(cx + r * cosf(a), cy + r * sinf(a));
    }
    glEnd();
  }

  glPopMatrix();
  glMatrixMode(GL_PROJECTION);
  glPopMatrix();
  glMatrixMode(GL_MODELVIEW);
  glPopAttrib();
  return true;
}
