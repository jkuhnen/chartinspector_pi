#include "chartinspector_pi.h"

extern "C" DECL_EXP opencpn_plugin *create_pi(void *ppimgr) {
  return new ChartInspectorPi(ppimgr);
}

extern "C" DECL_EXP void destroy_pi(opencpn_plugin *plugin) {
  delete plugin;
}

ChartInspectorPi::ChartInspectorPi(void *ppimgr) : opencpn_plugin_118(ppimgr) {}

int ChartInspectorPi::Init() {
  return WANTS_MOUSE_EVENTS | WANTS_CURSOR_LATLON | WANTS_OVERLAY_CALLBACK |
         WANTS_VECTOR_CHART_OBJECT_INFO;
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
  if (!vp || !m_hasMousePosition || !m_hasCursorPosition) return false;

  const int x = m_mousePosition.x;
  const int y = m_mousePosition.y;

  dc.SetBrush(*wxTRANSPARENT_BRUSH);
  dc.SetPen(wxPen(wxColour(255, 0, 255), 2));
  dc.DrawCircle(x, y, 8);
  dc.DrawLine(x - 14, y, x + 14, y);
  dc.DrawLine(x, y - 14, x, y + 14);

  const wxString label = wxString::Format("%.5f, %.5f", m_cursorLat, m_cursorLon);
  const wxPoint textPos(x + 16, y + 12);

  dc.SetTextForeground(wxColour(255, 0, 255));
  dc.DrawText(label, textPos);

  return true;
}
