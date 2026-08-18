#include "chartinspector_pi.h"

#ifdef _WIN32
#include <windows.h>
#endif

#include <GL/gl.h>
#include <wx/fileconf.h>
#include <wx/popupwin.h>
#include <wx/spinctrl.h>
#include <wx/tokenzr.h>

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
    m_hitTestV2 = reinterpret_cast<HitTestV2Fn>(
        GetProcAddress(host, "OCPNChartInspectorHitTestV2"));
    m_hitTest = reinterpret_cast<HitTestFn>(
        GetProcAddress(host, "OCPNChartInspectorHitTest"));
  }
#endif

  wxString *sharedData = GetpSharedDataLocation();
  if (sharedData) m_s57Catalog.Load(*sharedData);

  m_config = GetOCPNConfigObject();
  LoadConfig();
  BuildToolbarBitmap();

  m_toolbarId = InsertPlugInTool(
      "Chart Inspector", &m_pluginBitmap, &m_pluginBitmap, wxITEM_CHECK,
      "Chart Inspector", "Enable or disable chart object inspection", nullptr,
      -1, 0, this);
  if (m_toolbarId >= 0) SetToolbarItemState(m_toolbarId, m_enabled);

  return WANTS_MOUSE_EVENTS | WANTS_CURSOR_LATLON | WANTS_OVERLAY_CALLBACK |
         WANTS_OPENGL_OVERLAY_CALLBACK | WANTS_TOOLBAR_CALLBACK |
         INSTALLS_TOOLBAR_TOOL | WANTS_PREFERENCES | WANTS_CONFIG;
}

bool ChartInspectorPi::DeInit() {
  SaveConfig();
  if (m_toolbarId >= 0) {
    RemovePlugInTool(m_toolbarId);
    m_toolbarId = -1;
  }
  if (m_hoverPopup) {
    m_hoverPopup->Destroy();
    m_hoverPopup = nullptr;
    m_hoverText = nullptr;
  }
  return true;
}

int ChartInspectorPi::GetAPIVersionMajor() { return 1; }
int ChartInspectorPi::GetAPIVersionMinor() { return 18; }
int ChartInspectorPi::GetPlugInVersionMajor() { return 0; }
int ChartInspectorPi::GetPlugInVersionMinor() { return 2; }
int ChartInspectorPi::GetToolbarToolCount() { return 1; }

wxBitmap *ChartInspectorPi::GetPlugInBitmap() { return &m_pluginBitmap; }
wxString ChartInspectorPi::GetCommonName() { return "Chart Inspector"; }
wxString ChartInspectorPi::GetShortDescription() {
  return "Interactive inspection of vector chart objects.";
}
wxString ChartInspectorPi::GetLongDescription() {
  return "Chart Inspector highlights configured vector chart features near the "
         "cursor and shows readable S-57 object information on click.";
}

void ChartInspectorPi::BuildToolbarBitmap() {
  m_pluginBitmap = wxBitmap(24, 24);
  wxMemoryDC dc(m_pluginBitmap);
  dc.SetBackground(wxBrush(wxColour(245, 245, 245)));
  dc.Clear();
  dc.SetBrush(*wxTRANSPARENT_BRUSH);
  dc.SetPen(wxPen(wxColour(0, 120, 150), 2));
  dc.DrawCircle(wxPoint(10, 10), 6);
  dc.DrawLine(14, 14, 21, 21);
  dc.SelectObject(wxNullBitmap);
}

void ChartInspectorPi::LoadConfig() {
  if (!m_config) return;
  m_config->SetPath("/PlugIns/ChartInspector");
  m_config->Read("Enabled", &m_enabled, true);
  m_config->Read("ShowTechnicalData", &m_showTechnicalData, false);
  long radius = 7;
  m_config->Read("HitRadiusPixels", &radius, 7L);
  if (radius < 2) radius = 2;
  if (radius > 20) radius = 20;
  m_hitRadiusPixels = static_cast<int>(radius);
  m_config->Read("FeatureFilter", &m_featureFilter,
                 "BOY*,BCN*,LIGHTS,WRECKS,UWTROC,OBSTRN");
}

void ChartInspectorPi::SaveConfig() {
  if (!m_config) return;
  m_config->SetPath("/PlugIns/ChartInspector");
  m_config->Write("Enabled", m_enabled);
  m_config->Write("ShowTechnicalData", m_showTechnicalData);
  m_config->Write("HitRadiusPixels", static_cast<long>(m_hitRadiusPixels));
  m_config->Write("FeatureFilter", m_featureFilter);
  m_config->Flush();
}

void ChartInspectorPi::SetCursorLatLon(double lat, double lon) {
  m_cursorLat = lat;
  m_cursorLon = lon;
  m_hasCursorPosition = true;
}

void ChartInspectorPi::ClearHover() {
  m_hasVectorObject = false;
  m_lastFeature.clear();
  m_lastObjectName.clear();
  m_lastAttributes.clear();
}

bool ChartInspectorPi::IsFeatureEnabled(const wxString &feature) const {
  const wxString candidate = feature.Upper();
  wxStringTokenizer tokens(m_featureFilter, ",; \t\r\n", wxTOKEN_STRTOK);
  while (tokens.HasMoreTokens()) {
    wxString token = tokens.GetNextToken().Upper();
    token.Trim(true);
    token.Trim(false);
    if (token.IsEmpty()) continue;
    if (token.EndsWith("*")) {
      token.RemoveLast();
      if (!token.IsEmpty() && candidate.StartsWith(token)) return true;
    } else if (candidate == token) {
      return true;
    }
  }
  return false;
}

void ChartInspectorPi::HideObjectPopup() {
  if (m_hoverPopup) m_hoverPopup->Show(false);
}

void ChartInspectorPi::ShowObjectPopup() {
  if (!m_enabled || !m_hasVectorObject || m_lastFeature.IsEmpty()) return;

  wxWindow *canvas = GetOCPNCanvasWindow();
  if (!canvas) return;

  if (!m_hoverPopup) {
    m_hoverPopup = new wxPopupWindow(canvas, wxBORDER_SIMPLE);
    wxPanel *panel = new wxPanel(m_hoverPopup, wxID_ANY);
    wxBoxSizer *sizer = new wxBoxSizer(wxVERTICAL);
    m_hoverText = new wxStaticText(panel, wxID_ANY, wxEmptyString);
    sizer->Add(m_hoverText, 0, wxALL, 8);
    panel->SetSizer(sizer);
    wxBoxSizer *popupSizer = new wxBoxSizer(wxVERTICAL);
    popupSizer->Add(panel, 1, wxEXPAND);
    m_hoverPopup->SetSizer(popupSizer);
  }

  wxString text = m_s57Catalog.ObjectName(m_lastFeature);
  if (!m_lastObjectName.IsEmpty()) text += "\n" + m_lastObjectName;

  wxString technical;
  const wxString readable =
      m_s57Catalog.FormatAttributes(m_lastAttributes, &technical);
  if (!readable.IsEmpty()) text += "\n\n" + readable;

  if (m_showTechnicalData) {
    text += "\n\nTechnical data\n" + m_lastFeature;
    if (!technical.IsEmpty()) text += "\n" + technical;
  }

  m_hoverText->SetLabel(text);
  m_hoverText->Wrap(390);
  m_hoverPopup->Fit();

  wxPoint pos = canvas->ClientToScreen(m_mousePosition + wxPoint(18, 18));
  m_hoverPopup->Move(pos);
  m_hoverPopup->Show(true);
  m_hoverPopup->Raise();
}

void ChartInspectorPi::UpdateHoverObject() {
  if (!m_enabled || (!m_hitTestV2 && !m_hitTest) || !m_hasCursorPosition) {
    ClearHover();
    return;
  }

  char feature[32] = {0};
  char objectName[128] = {0};
  char attributes[2048] = {0};
  double objectLat = 0.0;
  double objectLon = 0.0;

  bool found = false;
  if (m_hitTestV2) {
    found = m_hitTestV2(
        0, m_cursorLat, m_cursorLon, static_cast<double>(m_hitRadiusPixels),
        feature, static_cast<int>(sizeof(feature)), objectName,
        static_cast<int>(sizeof(objectName)), attributes,
        static_cast<int>(sizeof(attributes)), &objectLat, &objectLon);
  } else if (m_hitTest) {
    found = m_hitTest(
        0, m_cursorLat, m_cursorLon, static_cast<double>(m_hitRadiusPixels),
        feature, static_cast<int>(sizeof(feature)), objectName,
        static_cast<int>(sizeof(objectName)), &objectLat, &objectLon);
  }

  const wxString featureName = wxString::FromUTF8(feature).Upper();
  if (found && !IsFeatureEnabled(featureName)) found = false;

  if (found) {
    m_hasVectorObject = true;
    m_lastFeature = featureName;
    m_lastObjectName = wxString::FromUTF8(objectName);
    m_lastAttributes = wxString::FromUTF8(attributes);
    m_lastObjectLat = objectLat;
    m_lastObjectLon = objectLon;
  } else {
    ClearHover();
  }
}

bool ChartInspectorPi::MouseEventHook(wxMouseEvent &event) {
  m_mousePosition = event.GetPosition();
  m_hasMousePosition = true;

  UpdateHoverObject();

  if (event.LeftDown()) {
    if (m_hasVectorObject)
      ShowObjectPopup();
    else
      HideObjectPopup();
  }

  wxWindow *canvas = GetOCPNCanvasWindow();
  if (canvas) RequestRefresh(canvas);
  return false;
}

void ChartInspectorPi::OnToolbarToolCallback(int id) {
  if (id != m_toolbarId) return;
  m_enabled = !m_enabled;
  SetToolbarItemState(m_toolbarId, m_enabled);
  if (!m_enabled) {
    ClearHover();
    HideObjectPopup();
  }
  SaveConfig();
  wxWindow *canvas = GetOCPNCanvasWindow();
  if (canvas) RequestRefresh(canvas);
}

void ChartInspectorPi::ShowPreferencesDialog(wxWindow *parent) {
  wxDialog dialog(parent, wxID_ANY, "Chart Inspector Preferences",
                  wxDefaultPosition, wxDefaultSize,
                  wxDEFAULT_DIALOG_STYLE | wxRESIZE_BORDER);
  wxBoxSizer *root = new wxBoxSizer(wxVERTICAL);

  wxCheckBox *enabled = new wxCheckBox(&dialog, wxID_ANY, "Enable Chart Inspector");
  enabled->SetValue(m_enabled);
  root->Add(enabled, 0, wxALL, 10);

  wxStaticBoxSizer *interaction =
      new wxStaticBoxSizer(wxVERTICAL, &dialog, "Interaction");
  wxBoxSizer *radiusRow = new wxBoxSizer(wxHORIZONTAL);
  radiusRow->Add(new wxStaticText(&dialog, wxID_ANY, "Hit radius (pixels):"),
                 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 8);
  wxSpinCtrl *radius = new wxSpinCtrl(&dialog, wxID_ANY);
  radius->SetRange(2, 20);
  radius->SetValue(m_hitRadiusPixels);
  radiusRow->Add(radius, 0);
  interaction->Add(radiusRow, 0, wxALL, 8);
  interaction->Add(
      new wxStaticText(&dialog, wxID_ANY,
                       "Hover only highlights nearby objects. Click the highlighted object to show information."),
      0, wxLEFT | wxRIGHT | wxBOTTOM, 8);
  root->Add(interaction, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, 10);

  wxStaticBoxSizer *objects =
      new wxStaticBoxSizer(wxVERTICAL, &dialog, "Enabled S-57 object classes");
  objects->Add(new wxStaticText(
                   &dialog, wxID_ANY,
                   "Comma-separated acronyms. Use * as a prefix wildcard, for example BOY* or BCN*."),
               0, wxALL, 8);
  wxTextCtrl *filter = new wxTextCtrl(&dialog, wxID_ANY, m_featureFilter,
                                      wxDefaultPosition, wxSize(520, -1));
  objects->Add(filter, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, 8);
  objects->Add(new wxStaticText(
                   &dialog, wxID_ANY,
                   "Default: BOY*, BCN*, LIGHTS, WRECKS, UWTROC, OBSTRN"),
               0, wxLEFT | wxRIGHT | wxBOTTOM, 8);
  root->Add(objects, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, 10);

  wxCheckBox *technical =
      new wxCheckBox(&dialog, wxID_ANY,
                     "Append technical S-57 acronyms and raw values");
  technical->SetValue(m_showTechnicalData);
  root->Add(technical, 0, wxLEFT | wxRIGHT | wxBOTTOM, 10);

  root->Add(dialog.CreateSeparatedButtonSizer(wxOK | wxCANCEL), 0,
            wxEXPAND | wxALL, 10);
  dialog.SetSizerAndFit(root);

  if (dialog.ShowModal() == wxID_OK) {
    m_enabled = enabled->GetValue();
    m_hitRadiusPixels = radius->GetValue();
    m_featureFilter = filter->GetValue();
    m_showTechnicalData = technical->GetValue();
    if (m_toolbarId >= 0) SetToolbarItemState(m_toolbarId, m_enabled);
    if (!m_enabled) {
      ClearHover();
      HideObjectPopup();
    }
    SaveConfig();
    wxWindow *canvas = GetOCPNCanvasWindow();
    if (canvas) RequestRefresh(canvas);
  }
}

void ChartInspectorPi::SendVectorChartObjectInfo(
    wxString &chart, wxString &feature, wxString &objname, double lat,
    double lon, double scale, int nativescale) {
  (void)chart;
  (void)feature;
  (void)objname;
  (void)lat;
  (void)lon;
  (void)scale;
  (void)nativescale;
}

bool ChartInspectorPi::RenderOverlay(wxDC &dc, PlugIn_ViewPort *vp) {
  if (!vp || !m_enabled || !m_hasVectorObject) return false;
  wxPoint p;
  GetCanvasPixLL(vp, &p, m_lastObjectLat, m_lastObjectLon);
  dc.SetBrush(*wxTRANSPARENT_BRUSH);
  dc.SetPen(wxPen(wxColour(0, 255, 255), 3));
  dc.DrawCircle(p, 12);
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
  if (!m_enabled || !m_hasVectorObject) return true;

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

  wxPoint p;
  GetCanvasPixLL(vp, &p, m_lastObjectLat, m_lastObjectLon);
  const float cx = static_cast<float>(p.x);
  const float cy = static_cast<float>(p.y);
  const float r = 12.0f;
  glColor4f(0.0f, 1.0f, 1.0f, 0.9f);
  glLineWidth(3.0f);
  glBegin(GL_LINE_LOOP);
  for (int i = 0; i < 32; ++i) {
    const float a = static_cast<float>(i) * 6.28318530718f / 32.0f;
    glVertex2f(cx + r * cosf(a), cy + r * sinf(a));
  }
  glEnd();

  glPopMatrix();
  glMatrixMode(GL_PROJECTION);
  glPopMatrix();
  glMatrixMode(GL_MODELVIEW);
  glPopAttrib();
  return true;
}
