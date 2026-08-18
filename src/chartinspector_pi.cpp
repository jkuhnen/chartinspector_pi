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
  // Intentionally passive for the initial scaffold. Mouse events are enabled
  // now so hit-testing and hover interaction can be developed incrementally.
  (void)event;
  return false;
}

bool ChartInspectorPi::RenderOverlay(wxDC &dc, PlugIn_ViewPort *vp) {
  // Overlay rendering will be used for non-destructive hover highlighting.
  (void)dc;
  (void)vp;
  return false;
}
