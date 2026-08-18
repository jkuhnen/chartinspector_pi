#include "chartinspector_pi.h"

#ifdef _WIN32
#include <windows.h>
#endif

#include <algorithm>
#include <vector>

#include <GL/gl.h>
#include <wx/checklst.h>
#include <wx/fileconf.h>
#include <wx/spinctrl.h>
#include <wx/statline.h>
#include <wx/tokenzr.h>

extern "C" DECL_EXP opencpn_plugin *create_pi(void *ppimgr) {
  return new ChartInspectorPi(ppimgr);
}

extern "C" DECL_EXP void destroy_pi(opencpn_plugin *plugin) { delete plugin; }

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
  if (m_infoPanel) {
    m_infoPanel->Destroy();
    m_infoPanel = nullptr;
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
  dc.SetBackground(wxBrush(wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOW)));
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
  long radius = 5;
  m_config->Read("HitRadiusPixels", &radius, 5L);
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

void ChartInspectorPi::BuildInfoPanel(wxWindow *canvas) {
  if (m_infoPanel || !canvas) return;

  m_infoPanel = new wxPanel(canvas, wxID_ANY, wxDefaultPosition,
                            wxDefaultSize, wxBORDER_SIMPLE);
  m_infoPanel->SetBackgroundColour(
      wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOW));

  wxBoxSizer *root = new wxBoxSizer(wxVERTICAL);
  wxBoxSizer *header = new wxBoxSizer(wxHORIZONTAL);

  m_infoTitle = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  wxFont titleFont = m_infoTitle->GetFont();
  titleFont.SetWeight(wxFONTWEIGHT_BOLD);
  titleFont.SetPointSize(titleFont.GetPointSize() + 2);
  m_infoTitle->SetFont(titleFont);
  header->Add(m_infoTitle, 1, wxALIGN_CENTER_VERTICAL);

  wxButton *close = new wxButton(m_infoPanel, wxID_ANY, "x",
                                 wxDefaultPosition, wxSize(28, 26), wxBU_EXACTFIT);
  close->SetToolTip("Close object information");
  close->Bind(wxEVT_BUTTON, [this](wxCommandEvent &) { HideObjectPopup(); });
  header->Add(close, 0, wxLEFT, 8);
  root->Add(header, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 12);

  m_infoSubtitle = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  root->Add(m_infoSubtitle, 0, wxLEFT | wxRIGHT | wxTOP, 12);

  m_infoAcronym = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  wxFont codeFont = m_infoAcronym->GetFont();
  codeFont.SetPointSize(std::max(7, codeFont.GetPointSize() - 1));
  m_infoAcronym->SetFont(codeFont);
  m_infoAcronym->SetForegroundColour(
      wxSystemSettings::GetColour(wxSYS_COLOUR_GRAYTEXT));
  root->Add(m_infoAcronym, 0, wxLEFT | wxRIGHT | wxTOP, 12);

  root->Add(new wxStaticLine(m_infoPanel), 0,
            wxEXPAND | wxLEFT | wxRIGHT | wxTOP | wxBOTTOM, 12);

  m_infoBody = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  root->Add(m_infoBody, 0, wxEXPAND | wxLEFT | wxRIGHT, 12);

  m_infoTechnical = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  wxFont techFont = m_infoTechnical->GetFont();
  techFont.SetPointSize(std::max(7, techFont.GetPointSize() - 1));
  m_infoTechnical->SetFont(techFont);
  m_infoTechnical->SetForegroundColour(
      wxSystemSettings::GetColour(wxSYS_COLOUR_GRAYTEXT));
  root->Add(m_infoTechnical, 0, wxEXPAND | wxALL, 12);

  m_infoPanel->SetSizer(root);
  m_infoPanel->Hide();
}

void ChartInspectorPi::HideObjectPopup() {
  if (m_infoPanel) m_infoPanel->Hide();
}

void ChartInspectorPi::ShowObjectPopup() {
  if (!m_enabled || !m_hasVectorObject || m_lastFeature.IsEmpty()) return;

  wxWindow *canvas = GetOCPNCanvasWindow();
  if (!canvas) return;
  BuildInfoPanel(canvas);

  m_infoTitle->SetLabel(m_s57Catalog.ObjectName(m_lastFeature));
  m_infoSubtitle->SetLabel(m_lastObjectName);
  m_infoSubtitle->Show(!m_lastObjectName.IsEmpty());
  m_infoAcronym->SetLabel("S-57 object: " + m_lastFeature);

  wxString technical;
  const wxString readable =
      m_s57Catalog.FormatAttributes(m_lastAttributes, &technical);
  m_infoBody->SetLabel(readable.IsEmpty() ? "No readable attributes available."
                                          : readable);
  m_infoBody->Wrap(360);

  if (m_showTechnicalData) {
    wxString raw = "Technical S-57 data\n" + m_lastFeature;
    if (!technical.IsEmpty()) raw += "\n" + technical;
    m_infoTechnical->SetLabel(raw);
    m_infoTechnical->Wrap(360);
    m_infoTechnical->Show();
  } else {
    m_infoTechnical->Hide();
  }

  m_infoPanel->Layout();
  m_infoPanel->Fit();

  wxSize size = m_infoPanel->GetSize();
  if (size.GetWidth() < 300) size.SetWidth(300);
  if (size.GetWidth() > 420) size.SetWidth(420);
  m_infoPanel->SetSize(size);
  m_infoPanel->Layout();

  const wxSize canvasSize = canvas->GetClientSize();
  const int x = std::max(12, canvasSize.GetWidth() - size.GetWidth() - 14);
  m_infoPanel->Move(x, 14);
  m_infoPanel->Show();
  m_infoPanel->Raise();
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
  HideObjectPopup();

  wxDialog dialog(parent, wxID_ANY, "Chart Inspector Preferences",
                  wxDefaultPosition, wxSize(650, 650),
                  wxDEFAULT_DIALOG_STYLE | wxRESIZE_BORDER);
  wxBoxSizer *root = new wxBoxSizer(wxVERTICAL);

  wxCheckBox *enabled =
      new wxCheckBox(&dialog, wxID_ANY, "Enable Chart Inspector");
  enabled->SetValue(m_enabled);
  root->Add(enabled, 0, wxALL, 10);

  wxStaticBoxSizer *interaction =
      new wxStaticBoxSizer(wxVERTICAL, &dialog, "Interaction");
  wxBoxSizer *radiusRow = new wxBoxSizer(wxHORIZONTAL);
  radiusRow->Add(new wxStaticText(&dialog, wxID_ANY, "Hit radius:"), 0,
                 wxALIGN_CENTER_VERTICAL | wxRIGHT, 8);
  wxSpinCtrl *radius = new wxSpinCtrl(&dialog, wxID_ANY);
  radius->SetRange(2, 20);
  radius->SetValue(m_hitRadiusPixels);
  radiusRow->Add(radius, 0);
  radiusRow->Add(new wxStaticText(&dialog, wxID_ANY, "pixels"), 0,
                 wxALIGN_CENTER_VERTICAL | wxLEFT, 6);
  interaction->Add(radiusRow, 0, wxALL, 8);
  interaction->Add(
      new wxStaticText(&dialog, wxID_ANY,
                       "Hover highlights a nearby enabled object. Click the highlighted object to open its information card."),
      0, wxLEFT | wxRIGHT | wxBOTTOM, 8);
  root->Add(interaction, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, 10);

  wxStaticBoxSizer *objects =
      new wxStaticBoxSizer(wxVERTICAL, &dialog, "Object classes");
  objects->Add(new wxStaticText(
                   &dialog, wxID_ANY,
                   "Choose which S-57 chart object classes Chart Inspector should react to."),
               0, wxALL, 8);

  wxCheckListBox *classes = new wxCheckListBox(
      &dialog, wxID_ANY, wxDefaultPosition, wxSize(580, 330));
  std::vector<wxString> classAcronyms;
  for (const auto &info : m_s57Catalog.ObjectClasses()) {
    const unsigned int index = classes->Append(
        info.acronym + "  -  " + info.name);
    classes->Check(index, IsFeatureEnabled(info.acronym));
    classAcronyms.push_back(info.acronym);
  }
  objects->Add(classes, 1, wxEXPAND | wxLEFT | wxRIGHT, 8);

  wxBoxSizer *classButtons = new wxBoxSizer(wxHORIZONTAL);
  wxButton *defaults = new wxButton(&dialog, wxID_ANY, "Navigation defaults");
  wxButton *all = new wxButton(&dialog, wxID_ANY, "Select all");
  wxButton *none = new wxButton(&dialog, wxID_ANY, "Clear all");
  classButtons->Add(defaults, 0, wxRIGHT, 6);
  classButtons->Add(all, 0, wxRIGHT, 6);
  classButtons->Add(none, 0);
  objects->Add(classButtons, 0, wxALL, 8);

  defaults->Bind(wxEVT_BUTTON, [classes, &classAcronyms](wxCommandEvent &) {
    for (unsigned int i = 0; i < classes->GetCount(); ++i) {
      const wxString a = classAcronyms[i];
      const bool nav = a.StartsWith("BOY") || a.StartsWith("BCN") ||
                       a == "LIGHTS" || a == "WRECKS" || a == "UWTROC" ||
                       a == "OBSTRN";
      classes->Check(i, nav);
    }
  });
  all->Bind(wxEVT_BUTTON, [classes](wxCommandEvent &) {
    for (unsigned int i = 0; i < classes->GetCount(); ++i) classes->Check(i, true);
  });
  none->Bind(wxEVT_BUTTON, [classes](wxCommandEvent &) {
    for (unsigned int i = 0; i < classes->GetCount(); ++i) classes->Check(i, false);
  });

  root->Add(objects, 1, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, 10);

  wxCheckBox *technical = new wxCheckBox(
      &dialog, wxID_ANY,
      "Show technical S-57 acronyms and raw values at the bottom of the card");
  technical->SetValue(m_showTechnicalData);
  root->Add(technical, 0, wxLEFT | wxRIGHT | wxBOTTOM, 10);

  root->Add(dialog.CreateSeparatedButtonSizer(wxOK | wxCANCEL), 0,
            wxEXPAND | wxALL, 10);
  dialog.SetSizer(root);
  dialog.Layout();
  dialog.CentreOnParent();

  if (dialog.ShowModal() == wxID_OK) {
    m_enabled = enabled->GetValue();
    m_hitRadiusPixels = radius->GetValue();
    m_showTechnicalData = technical->GetValue();

    wxString filter;
    for (unsigned int i = 0; i < classes->GetCount(); ++i) {
      if (!classes->IsChecked(i)) continue;
      if (!filter.IsEmpty()) filter += ",";
      filter += classAcronyms[i];
    }
    m_featureFilter = filter;

    if (m_toolbarId >= 0) SetToolbarItemState(m_toolbarId, m_enabled);
    if (!m_enabled) ClearHover();
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
