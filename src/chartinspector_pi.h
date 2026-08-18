#ifndef CHARTINSPECTOR_PI_H
#define CHARTINSPECTOR_PI_H

#include <wx/wx.h>

#include "ocpn_plugin.h"

class ChartInspectorPi : public opencpn_plugin_118 {
public:
  explicit ChartInspectorPi(void *ppimgr);
  ~ChartInspectorPi() override = default;

  int Init() override;
  bool DeInit() override;

  int GetAPIVersionMajor() override;
  int GetAPIVersionMinor() override;
  int GetPlugInVersionMajor() override;
  int GetPlugInVersionMinor() override;

  wxBitmap *GetPlugInBitmap() override;
  wxString GetCommonName() override;
  wxString GetShortDescription() override;
  wxString GetLongDescription() override;

  void SetCursorLatLon(double lat, double lon) override;
  bool MouseEventHook(wxMouseEvent &event) override;
  bool RenderOverlay(wxDC &dc, PlugIn_ViewPort *vp) override;
  bool RenderGLOverlayMultiCanvas(wxGLContext *pcontext, PlugIn_ViewPort *vp,
                                  int canvasIndex, int priority = -1) override;

private:
  wxBitmap m_pluginBitmap;
  wxPoint m_mousePosition;
  double m_cursorLat = 0.0;
  double m_cursorLon = 0.0;
  bool m_hasMousePosition = false;
  bool m_hasCursorPosition = false;
};

#endif  // CHARTINSPECTOR_PI_H
