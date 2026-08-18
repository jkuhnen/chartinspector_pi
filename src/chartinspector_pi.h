#ifndef CHARTINSPECTOR_PI_H
#define CHARTINSPECTOR_PI_H

#include <wx/wx.h>

#include "ocpn_plugin.h"
#include "s57_catalog.h"

class wxFileConfig;
class wxPanel;
class wxStaticText;
class wxTimer;

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
  int GetToolbarToolCount() override;

  wxBitmap *GetPlugInBitmap() override;
  wxString GetCommonName() override;
  wxString GetShortDescription() override;
  wxString GetLongDescription() override;

  void SetCursorLatLon(double lat, double lon) override;
  void SetColorScheme(PI_ColorScheme cs) override;
  bool MouseEventHook(wxMouseEvent &event) override;
  void OnToolbarToolCallback(int id) override;
  void ShowPreferencesDialog(wxWindow *parent) override;
  void SendVectorChartObjectInfo(wxString &chart, wxString &feature,
                                 wxString &objname, double lat, double lon,
                                 double scale, int nativescale) override;
  bool RenderOverlay(wxDC &dc, PlugIn_ViewPort *vp) override;
  bool RenderGLOverlayMultiCanvas(wxGLContext *pcontext, PlugIn_ViewPort *vp,
                                  int canvasIndex, int priority = -1) override;

private:
  using HitTestFn = bool (*)(int canvasIndex, double lat, double lon,
                             double radiusPixels, char *feature,
                             int featureSize, char *objectName,
                             int objectNameSize, double *objectLat,
                             double *objectLon);
  using HitTestV2Fn = bool (*)(int canvasIndex, double lat, double lon,
                               double radiusPixels, char *feature,
                               int featureSize, char *objectName,
                               int objectNameSize, char *attributes,
                               int attributesSize, double *objectLat,
                               double *objectLon);
  using HitTestV3Fn = bool (*)(int canvasIndex, double lat, double lon,
                               double radiusPixels, const char *featureFilter,
                               char *feature, int featureSize, char *objectName,
                               int objectNameSize, char *attributes,
                               int attributesSize, int *primitiveType,
                               double *markerLat, double *markerLon);

  void BuildToolbarBitmaps();
  void UpdateToolbarVisual();
  void ApplyInfoTheme();
  void LoadConfig();
  void SaveConfig();
  void ClearHover();
  bool IsFeatureEnabled(const wxString &feature) const;
  void UpdateHoverObject();
  void QueryAssociatedLight();
  void BuildInfoPanel(wxWindow *canvas);
  void BuildVisualSummary();
  void UpdateLightIndicator();
  void StopLightPreview();
  void ShowObjectPopup();
  void HideObjectPopup();
  wxColour SignalColour(const wxString &value) const;
  wxString BuildLightSummary(const wxString &attributes) const;

  wxBitmap m_pluginBitmap;
  wxBitmap m_toolbarEnabledBitmap;
  wxBitmap m_toolbarDisabledBitmap;
  wxPoint m_mousePosition;
  double m_cursorLat = 0.0;
  double m_cursorLon = 0.0;
  bool m_hasMousePosition = false;
  bool m_hasCursorPosition = false;

  wxString m_lastFeature;
  wxString m_lastObjectName;
  wxString m_lastAttributes;
  wxString m_associatedLightAttributes;
  double m_lastObjectLat = 0.0;
  double m_lastObjectLon = 0.0;
  int m_lastPrimitiveType = 1;  // 1 point, 2 line, 3 area
  bool m_hasVectorObject = false;
  bool m_hasAssociatedLight = false;

  wxPanel *m_infoPanel = nullptr;
  wxStaticText *m_infoTitle = nullptr;
  wxStaticText *m_infoSubtitle = nullptr;
  wxStaticText *m_infoAcronym = nullptr;
  wxPanel *m_infoVisual = nullptr;
  wxStaticText *m_infoBody = nullptr;
  wxStaticText *m_infoTechnical = nullptr;
  wxPanel *m_lightIndicator = nullptr;
  wxTimer *m_lightTimer = nullptr;
  wxColour m_lightColour;
  int m_lightCharacteristic = 0;
  double m_lightPeriodSeconds = 0.0;
  int m_lightGroupCount = 1;
  bool m_lightHasLongFlash = false;
  bool m_lightIsFixed = false;
  bool m_lightOn = true;

  wxFileConfig *m_config = nullptr;
  int m_toolbarId = -1;
  bool m_enabled = true;
  bool m_showTechnicalData = false;
  int m_hitRadiusPixels = 5;
  wxString m_featureFilter = "BOY*,BCN*,LIGHTS,WRECKS,UWTROC,OBSTRN";
  PI_ColorScheme m_colorScheme = PI_GLOBAL_COLOR_SCHEME_DAY;

  S57Catalog m_s57Catalog;
  HitTestFn m_hitTest = nullptr;
  HitTestV2Fn m_hitTestV2 = nullptr;
  HitTestV3Fn m_hitTestV3 = nullptr;
  HitTestV3Fn m_hitTestV4 = nullptr;
};

#endif  // CHARTINSPECTOR_PI_H
