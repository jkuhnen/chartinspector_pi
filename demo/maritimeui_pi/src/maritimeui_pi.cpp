#include "maritimeui_pi.h"
#include "app_style.h"

#include <algorithm>
#include <wx/dcmemory.h>
#include <wx/scrolwin.h>
#include <wx/statline.h>

extern "C" DECL_EXP opencpn_plugin *create_pi(void *ppimgr) {
  return new MaritimeUiPi(ppimgr);
}

extern "C" DECL_EXP void destroy_pi(opencpn_plugin *plugin) {
  delete plugin;
}

namespace {

enum SemanticState {
  kNeutral = 0,
  kNormal = 1,
  kWarning = 2,
  kAlarm = 3
};

wxColour SemanticColour(const maritime_ui::Palette &p, int state) {
  switch (state) {
    case kNormal: return p.normal;
    case kWarning: return p.warning;
    case kAlarm: return p.alarm;
    default: return p.textSecondary;
  }
}

void ApplyWindowColours(wxWindow *window, const maritime_ui::Palette &p) {
  if (!window) return;

  wxColour background = p.windowBackground;
  wxColour foreground = p.textPrimary;

  const wxString name = window->GetName();
  if (name == "card" || name == "status-row") background = p.panelBackground;
  if (name == "secondary") foreground = p.textSecondary;
  if (name == "status-normal") foreground = p.normal;
  if (name == "status-warning") foreground = p.warning;
  if (name == "status-alarm") foreground = p.alarm;

  window->SetBackgroundColour(background);
  window->SetForegroundColour(foreground);

  const wxWindowList &children = window->GetChildren();
  for (wxWindowList::const_iterator it = children.begin(); it != children.end(); ++it)
    ApplyWindowColours(*it, p);
}

}  // namespace

MaritimeUiPi::MaritimeUiPi(void *ppimgr) : opencpn_plugin_118(ppimgr) {}

int MaritimeUiPi::Init() {
  BuildToolbarBitmap();
  m_pluginBitmap = m_toolbarBitmap;
  m_toolbarId = InsertPlugInTool(
      "Maritime UI Demo", &m_pluginBitmap, &m_pluginBitmap, wxITEM_NORMAL,
      "Maritime UI Demo", "Open maritime HMI design demonstrator", nullptr,
      -1, 0, this);
  return WANTS_TOOLBAR_CALLBACK | INSTALLS_TOOLBAR_TOOL;
}

bool MaritimeUiPi::DeInit() {
  if (m_toolbarId >= 0) RemovePlugInTool(m_toolbarId);
  m_toolbarId = -1;
  if (m_window) {
    m_window->Destroy();
    m_window = nullptr;
  }
  return true;
}

int MaritimeUiPi::GetAPIVersionMajor() { return 1; }
int MaritimeUiPi::GetAPIVersionMinor() { return 18; }
int MaritimeUiPi::GetPlugInVersionMajor() { return 0; }
int MaritimeUiPi::GetPlugInVersionMinor() { return 1; }
int MaritimeUiPi::GetToolbarToolCount() { return 1; }

wxBitmap *MaritimeUiPi::GetPlugInBitmap() { return &m_pluginBitmap; }
wxString MaritimeUiPi::GetCommonName() { return "Maritime UI Demo"; }
wxString MaritimeUiPi::GetShortDescription() {
  return "Navigation-oriented maritime HMI design demonstrator.";
}
wxString MaritimeUiPi::GetLongDescription() {
  return "Demonstrates a consistent OpenCPN maritime user interface using "
         "DAY, DUSK and NIGHT schemes, restrained interaction colours, "
         "reserved safety colours and navigation-first information hierarchy.";
}

void MaritimeUiPi::BuildToolbarBitmap() {
  const maritime_ui::Palette p = maritime_ui::AppStyle::PaletteFor(m_colorScheme);
  wxBitmap bitmap(24, 24);
  wxMemoryDC dc(bitmap);
  dc.SetBackground(wxBrush(p.windowBackground));
  dc.Clear();
  dc.SetBrush(*wxTRANSPARENT_BRUSH);
  dc.SetPen(wxPen(p.focus, 2));
  dc.DrawCircle(wxPoint(12, 12), 8);
  dc.DrawLine(12, 3, 12, 7);
  dc.DrawLine(12, 17, 12, 21);
  dc.DrawLine(3, 12, 7, 12);
  dc.DrawLine(17, 12, 21, 12);
  dc.SetPen(wxPen(p.accent, 3));
  dc.DrawCircle(wxPoint(12, 12), 2);
  dc.SelectObject(wxNullBitmap);
  m_toolbarBitmap = bitmap;
}

wxPanel *MaritimeUiPi::CreateCard(wxWindow *parent, const wxString &eyebrow,
                                  const wxString &title,
                                  const wxString &body) {
  wxPanel *card = new wxPanel(parent, wxID_ANY, wxDefaultPosition,
                              wxDefaultSize, wxBORDER_SIMPLE);
  card->SetName("card");
  wxBoxSizer *sizer = new wxBoxSizer(wxVERTICAL);

  wxStaticText *eyebrowText = new wxStaticText(card, wxID_ANY, eyebrow.Upper());
  eyebrowText->SetName("secondary");
  eyebrowText->SetFont(maritime_ui::AppStyle::TechnicalFont(eyebrowText->GetFont()));
  sizer->Add(eyebrowText, 0, wxLEFT | wxRIGHT | wxTOP,
             maritime_ui::AppStyle::kMd);

  wxStaticText *titleText = new wxStaticText(card, wxID_ANY, title);
  titleText->SetFont(maritime_ui::AppStyle::PrimaryFont(titleText->GetFont()));
  sizer->Add(titleText, 0, wxLEFT | wxRIGHT | wxTOP,
             maritime_ui::AppStyle::kSm);

  wxStaticText *bodyText = new wxStaticText(card, wxID_ANY, body);
  bodyText->SetFont(maritime_ui::AppStyle::LabelFont(bodyText->GetFont()));
  bodyText->Wrap(430);
  sizer->Add(bodyText, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP | wxBOTTOM,
             maritime_ui::AppStyle::kMd);

  card->SetSizer(sizer);
  return card;
}

wxPanel *MaritimeUiPi::CreateStatusRow(wxWindow *parent,
                                       const wxString &label,
                                       const wxString &value,
                                       int semantic) {
  wxPanel *row = new wxPanel(parent, wxID_ANY, wxDefaultPosition,
                             wxDefaultSize, wxBORDER_NONE);
  row->SetName("status-row");
  wxBoxSizer *sizer = new wxBoxSizer(wxHORIZONTAL);

  wxStaticText *name = new wxStaticText(row, wxID_ANY, label);
  name->SetMinSize(wxSize(150, -1));
  name->SetName("secondary");
  sizer->Add(name, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT,
             maritime_ui::AppStyle::kMd);

  wxStaticText *state = new wxStaticText(row, wxID_ANY, value);
  state->SetFont(maritime_ui::AppStyle::PrimaryFont(state->GetFont()));
  if (semantic == kNormal) state->SetName("status-normal");
  else if (semantic == kWarning) state->SetName("status-warning");
  else if (semantic == kAlarm) state->SetName("status-alarm");
  sizer->Add(state, 1, wxALIGN_CENTER_VERTICAL);

  row->SetSizer(sizer);
  return row;
}

void MaritimeUiPi::EnsureWindow() {
  if (m_window) return;

  wxWindow *parent = GetOCPNCanvasWindow();
  m_window = new wxFrame(parent, wxID_ANY, "Maritime UI Demo",
                         wxDefaultPosition, wxSize(520, 720),
                         wxCAPTION | wxCLOSE_BOX | wxRESIZE_BORDER |
                             wxFRAME_TOOL_WINDOW | wxSTAY_ON_TOP);

  wxScrolledWindow *scroll = new wxScrolledWindow(m_window, wxID_ANY);
  scroll->SetScrollRate(0, 12);
  wxBoxSizer *root = new wxBoxSizer(wxVERTICAL);

  wxStaticText *context = new wxStaticText(scroll, wxID_ANY,
                                            "CHART OBJECT  /  SELECTED");
  context->SetName("secondary");
  context->SetFont(maritime_ui::AppStyle::TechnicalFont(context->GetFont()));
  root->Add(context, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP,
            maritime_ui::AppStyle::kLg);

  wxStaticText *title = new wxStaticText(scroll, wxID_ANY,
                                          "North cardinal buoy");
  title->SetFont(maritime_ui::AppStyle::TitleFont(title->GetFont()));
  root->Add(title, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP,
            maritime_ui::AppStyle::kSm);

  wxStaticText *meta = new wxStaticText(
      scroll, wxID_ANY, "BOYCAR  ·  POINT  ·  DK ENC");
  meta->SetName("secondary");
  meta->SetFont(maritime_ui::AppStyle::TechnicalFont(meta->GetFont()));
  root->Add(meta, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP,
            maritime_ui::AppStyle::kXs);

  wxPanel *primary = CreateCard(
      scroll, "Navigation", "North cardinal mark",
      "Name: Middelgrund N\nColour: black / yellow\nTopmark: two cones, points upward\nLight: Q W 1 s  ·  Nominal range 5 NM");
  root->Add(primary, 0, wxEXPAND | wxALL, maritime_ui::AppStyle::kLg);

  wxStaticText *statusHeading = new wxStaticText(scroll, wxID_ANY,
                                                  "INTEGRITY / STATUS");
  statusHeading->SetName("secondary");
  statusHeading->SetFont(
      maritime_ui::AppStyle::TechnicalFont(statusHeading->GetFont()));
  root->Add(statusHeading, 0, wxEXPAND | wxLEFT | wxRIGHT,
            maritime_ui::AppStyle::kLg);

  wxPanel *statusCard = new wxPanel(scroll, wxID_ANY, wxDefaultPosition,
                                    wxDefaultSize, wxBORDER_SIMPLE);
  statusCard->SetName("card");
  wxBoxSizer *statusSizer = new wxBoxSizer(wxVERTICAL);
  statusSizer->Add(CreateStatusRow(statusCard, "Chart source", "VALID", kNormal),
                   0, wxEXPAND | wxALL, maritime_ui::AppStyle::kMd);
  statusSizer->Add(CreateStatusRow(statusCard, "Scale visibility",
                                   "OUTSIDE SCAMIN", kWarning),
                   0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM,
                   maritime_ui::AppStyle::kMd);
  statusSizer->Add(CreateStatusRow(statusCard, "Position data", "INVALID", kAlarm),
                   0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM,
                   maritime_ui::AppStyle::kMd);
  statusCard->SetSizer(statusSizer);
  root->Add(statusCard, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP,
            maritime_ui::AppStyle::kLg);

  wxStaticText *legend = new wxStaticText(
      scroll, wxID_ANY,
      "Red, amber/yellow and green are shown here only because these rows "
      "represent real safety/status semantics. Selection and focus use blue/cyan.");
  legend->SetName("secondary");
  legend->SetFont(maritime_ui::AppStyle::TechnicalFont(legend->GetFont()));
  legend->Wrap(450);
  root->Add(legend, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP,
            maritime_ui::AppStyle::kSm);

  wxPanel *source = CreateCard(
      scroll, "Source / technical", "ENC provenance",
      "Cell: DK4KATGN\nEdition: 7  ·  Update: 12\nSORDAT: 20260415\nSCAMIN: 45000\nS-57 object class: BOYCAR");
  root->Add(source, 0, wxEXPAND | wxALL, maritime_ui::AppStyle::kLg);

  wxStaticText *note = new wxStaticText(
      scroll, wxID_ANY,
      "Design demonstrator — inspired by IMO MSC.191(79), MSC.1/Circ.1609, "
      "IEC 62288 and IHO S-52 principles. Not type approved and not an ECDIS.");
  note->SetName("secondary");
  note->SetFont(maritime_ui::AppStyle::TechnicalFont(note->GetFont()));
  note->Wrap(450);
  root->Add(note, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM,
            maritime_ui::AppStyle::kLg);

  scroll->SetSizer(root);
  m_window->SetMinSize(wxSize(430, 480));

  m_window->Bind(wxEVT_CLOSE_WINDOW, [this](wxCloseEvent &event) {
    if (m_window) m_window->Hide();
    event.Veto();
  });

  ApplyTheme();
}

void MaritimeUiPi::ApplyTheme() {
  if (!m_window) return;
  const maritime_ui::Palette p = maritime_ui::AppStyle::PaletteFor(m_colorScheme);
  ApplyWindowColours(m_window, p);
  m_window->Refresh(false);
}

void MaritimeUiPi::ToggleWindow() {
  EnsureWindow();
  if (!m_window) return;
  if (m_window->IsShown()) {
    m_window->Hide();
  } else {
    ApplyTheme();
    m_window->Show();
    m_window->Raise();
  }
}

void MaritimeUiPi::OnToolbarToolCallback(int id) {
  if (id == m_toolbarId) ToggleWindow();
}

void MaritimeUiPi::SetColorScheme(PI_ColorScheme cs) {
  m_colorScheme = cs;
  BuildToolbarBitmap();
  m_pluginBitmap = m_toolbarBitmap;
  if (m_toolbarId >= 0)
    SetToolbarToolBitmaps(m_toolbarId, &m_toolbarBitmap, &m_toolbarBitmap);
  ApplyTheme();
}
