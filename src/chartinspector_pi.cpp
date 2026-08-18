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

bool ChartInspectorPi::MouseEventHook(wxMouseEvent &event) {
  m_mousePosition = event.GetPosition();
  m_hasMousePosition = true;

  wxWindow *canvas = GetOCPNCanvasWindow();
  if (canvas) RequestRefresh(canvas);

  return false;
}

bool ChartInspectorPi::RenderOverlay(wxDC &dc, PlugIn_ViewPort *vp) {
  if (!vp) return false;

  // Fixed diagnostic marker proves that the non-OpenGL overlay callback runs.
  dc.SetBrush(*wxTRANSPARENT_BRUSH);
  dc.SetPen(wxPen(wxColour(255, 0, 255), 3));
  dc.DrawRectangle(18, 18, 24, 24);
  dc.DrawText("CI", wxPoint(48, 20));

  if (!m_hasMousePosition || !m_hasCursorPosition) return true;

  const int x = m_mousePosition.x;
  const int y = m_mousePosition.y;

  dc.SetPen(wxPen(wxColour(255, 0, 255), 2));
  dc.DrawCircle(x, y, 8);
  dc.DrawLine(x - 14, y, x + 14, y);
  dc.DrawLine(x, y - 14, x, y + 14);

  const wxString label = wxString::Format("%.5f, %.5f", m_cursorLat, m_cursorLon);
  dc.SetTextForeground(wxColour(255, 0, 255));
  dc.DrawText(label, wxPoint(x + 16, y + 12));

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

  // Fixed top-left diagnostic box.
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

  glPopMatrix();
  glMatrixMode(GL_PROJECTION);
  glPopMatrix();
  glMatrixMode(GL_MODELVIEW);
  glPopAttrib();

  return true;
}
