#ifndef CHARTINSPECTOR_PI_H
#define CHARTINSPECTOR_PI_H

#include <vector>
#include <wx/wx.h>
#include "ocpn_plugin.h"
#include "s57_catalog.h"

class wxFileConfig;
class wxPanel;
class wxStaticText;
class wxTimer;

namespace ci_ui { class ObjectInspectorPanel; }

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
  using HitTestFn = bool (*)(int,double,double,double,char*,int,char*,int,double*,double*);
  using HitTestV2Fn = bool (*)(int,double,double,double,char*,int,char*,int,char*,int,double*,double*);
  using HitTestV3Fn = bool (*)(int,double,double,double,const char*,char*,int,char*,int,char*,int,int*,double*,double*);

  struct HoverPosition { double lat = 0.0; double lon = 0.0; };
  struct HoverPart { unsigned int firstPoint = 0; unsigned int pointCount = 0; };

  void BuildToolbarBitmaps();
  void UpdateToolbarVisual();
  void ApplyInfoTheme();
  void LoadConfig();
  void SaveConfig();
  void ClearHover();
  void ClearHoverGeometry();
  bool IsFeatureEnabled(const wxString &feature) const;
  void UpdateHoverObject();
  void UpdateHoverGeometry(bool force = false);
  void ApplyHoverWindowTheme();
  void UpdateHoverInfoPanel(const wxString &feature, const wxString &objectName,
                            const wxString &attributes, int geometryType,
                            const wxString &associatedLightAttributes = wxEmptyString);
  void HideHoverInfoPanel();
  void QueryAssociatedLight();
  void BuildInfoPanel(wxWindow *canvas);
  void BuildVisualSummary();
  void UpdateLightIndicator();
  void StopLightPreview();
  void ShowObjectPopup();
  void HideObjectPopup();
  void PresentModernInspector(ci_ui::ObjectInspectorPanel *panel,
                              const wxString &feature, const wxString &objectName,
                              const wxString &attributes, int geometryType,
                              const wxString &associatedLightAttributes,
                              bool scaleHidden);
  wxColour SignalColour(const wxString &value) const;
  wxString BuildLightSummary(const wxString &attributes) const;

  bool DeInitLegacy();
  int GetPlugInVersionMinorLegacy();
  void SetColorSchemeLegacy(PI_ColorScheme cs);
  bool MouseEventHookLegacy(wxMouseEvent &event);
  void UpdateHoverGeometryLegacy(bool force = false);
  void UpdateHoverInfoPanelLegacy(const wxString &feature,
                                  const wxString &objectName,
                                  const wxString &attributes, int geometryType,
                                  const wxString &associatedLightAttributes = wxEmptyString);
  void HideHoverInfoPanelLegacy();
  void BuildInfoPanelLegacy(wxWindow *canvas);
  void ShowObjectPopupLegacy();

  wxBitmap m_pluginBitmap, m_toolbarEnabledBitmap, m_toolbarDisabledBitmap;
  wxPoint m_mousePosition, m_lastHoverQueryPosition;
  double m_cursorLat = 0.0, m_cursorLon = 0.0;
  bool m_hasMousePosition = false, m_hasCursorPosition = false;
  long long m_lastHoverQueryMs = 0;

  wxString m_lastFeature, m_lastObjectName, m_lastAttributes, m_associatedLightAttributes;
  double m_lastObjectLat = 0.0, m_lastObjectLon = 0.0;
  int m_lastPrimitiveType = 1;
  bool m_hasVectorObject = false, m_hasAssociatedLight = false;

  std::vector<HoverPosition> m_hoverPoints;
  std::vector<HoverPart> m_hoverParts;
  int m_hoverGeometryType = 0;
  wxString m_hoverFeature;
  bool m_hasHoverGeometry = false, m_hoverScaleHidden = false;

  wxFrame *m_hoverInfoWindow = nullptr;
  ci_ui::ObjectInspectorPanel *m_hoverModernPanel = nullptr;
  wxStaticText *m_hoverInfoTitle = nullptr, *m_hoverInfoMeta = nullptr;
  wxPanel *m_hoverInfoDetails = nullptr;
  wxFlexGridSizer *m_hoverInfoGrid = nullptr;
  wxStaticText *m_hoverInfoBody = nullptr;
  wxString m_hoverInfoKey;

  wxPanel *m_infoPanel = nullptr;
  wxStaticText *m_infoTitle = nullptr, *m_infoSubtitle = nullptr, *m_infoAcronym = nullptr;
  wxPanel *m_infoVisual = nullptr;
  wxStaticText *m_infoBody = nullptr, *m_infoTechnical = nullptr;
  wxPanel *m_lightIndicator = nullptr;
  wxTimer *m_lightTimer = nullptr;
  wxColour m_lightColour;
  int m_lightCharacteristic = 0;
  double m_lightPeriodSeconds = 0.0;
  int m_lightGroupCount = 1;
  bool m_lightHasLongFlash = false, m_lightIsFixed = false, m_lightOn = true;

  wxFileConfig *m_config = nullptr;
  int m_toolbarId = -1;
  bool m_enabled = true, m_showTechnicalData = false, m_includeScaleHidden = false;
  int m_hitRadiusPixels = 5;
  wxString m_featureFilter = "BOY*,BCN*,LIGHTS,TOPMAR,DAYMAR,WRECKS,UWTROC,OBSTRN,LNDMRK,BUISGL,SILTNK,BRIDGE,CRANES,FLODOC,GATCON,DAMCON,HRBFAC,BERTHS,MORFAC,OFSPLF,PILPNT,CBLSUB,PIPARE,PIPSOL,TUNNEL,RTPBCN,RADSTA,RSCSTA,FORSTC,CAUSWY,DYKCON";
  PI_ColorScheme m_colorScheme = PI_GLOBAL_COLOR_SCHEME_DAY;
  S57Catalog m_s57Catalog;
  HitTestFn m_hitTest = nullptr;
  HitTestV2Fn m_hitTestV2 = nullptr;
  HitTestV3Fn m_hitTestV3 = nullptr, m_hitTestV4 = nullptr;
};

#endif
