#include "chartinspector_pi.h"

#ifdef _WIN32
#include <windows.h>
#endif

#include <algorithm>
#include <cmath>
#include <vector>

#include <GL/gl.h>
#include <wx/checklst.h>
#include <wx/dcbuffer.h>
#include <wx/dcclient.h>
#include <wx/fileconf.h>
#include <wx/spinctrl.h>
#include <wx/statline.h>
#include <wx/timer.h>
#include <wx/tokenzr.h>

namespace {
wxString FilterRawAttributes(const wxString &raw,
                             const std::vector<wxString> &excluded) {
  wxString result;
  wxStringTokenizer lines(raw, "\n", wxTOKEN_STRTOK);
  while (lines.HasMoreTokens()) {
    wxString line = lines.GetNextToken();
    const int equals = line.Find('=');
    if (equals == wxNOT_FOUND) continue;
    wxString acronym = line.Left(equals).Upper();
    acronym.Trim(true);
    acronym.Trim(false);
    bool skip = false;
    for (const auto &item : excluded) {
      if (acronym == item) {
        skip = true;
        break;
      }
    }
    if (skip) continue;
    if (!result.IsEmpty()) result += "\n";
    result += line;
  }
  return result;
}

void AppendInfoLine(wxString *target, const wxString &label,
                    const wxString &value) {
  if (!target || value.IsEmpty()) return;
  if (!target->IsEmpty()) *target += "\n";
  *target += label + ": " + value;
}

wxString MetresAndFeet(const wxString &raw) {
  double metres = 0.0;
  if (!raw.ToDouble(&metres)) return raw;
  const long feet = static_cast<long>(std::lround(metres * 3.280839895));
  return wxString::Format("%g m / %ld ft", metres, feet);
}
}  // namespace

extern "C" DECL_EXP opencpn_plugin *create_pi(void *ppimgr) {
  return new ChartInspectorPi(ppimgr);
}

extern "C" DECL_EXP void destroy_pi(opencpn_plugin *plugin) { delete plugin; }

ChartInspectorPi::ChartInspectorPi(void *ppimgr) : opencpn_plugin_118(ppimgr) {}

int ChartInspectorPi::Init() {
#ifdef _WIN32
  HMODULE host = GetModuleHandleW(nullptr);
  if (host) {
    m_hitTestV4 = reinterpret_cast<HitTestV3Fn>(
        GetProcAddress(host, "OCPNChartInspectorHitTestV4"));
    m_hitTestV3 = reinterpret_cast<HitTestV3Fn>(
        GetProcAddress(host, "OCPNChartInspectorHitTestV3"));
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
  BuildToolbarBitmaps();
  m_pluginBitmap = m_enabled ? m_toolbarEnabledBitmap : m_toolbarDisabledBitmap;
  m_toolbarId = InsertPlugInTool(
      "Chart Inspector", &m_pluginBitmap, &m_pluginBitmap, wxITEM_CHECK,
      "Chart Inspector", "Enable or disable chart object inspection", nullptr,
      -1, 0, this);
  UpdateToolbarVisual();

  return WANTS_MOUSE_EVENTS | WANTS_CURSOR_LATLON | WANTS_OVERLAY_CALLBACK |
         WANTS_OPENGL_OVERLAY_CALLBACK | WANTS_TOOLBAR_CALLBACK |
         INSTALLS_TOOLBAR_TOOL | WANTS_PREFERENCES | WANTS_CONFIG;
}

bool ChartInspectorPi::DeInit() {
  SaveConfig();
  StopLightPreview();
  if (m_toolbarId >= 0) RemovePlugInTool(m_toolbarId);
  m_toolbarId = -1;
  if (m_infoPanel) m_infoPanel->Destroy();
  m_infoPanel = nullptr;
  return true;
}

int ChartInspectorPi::GetAPIVersionMajor() { return 1; }
int ChartInspectorPi::GetAPIVersionMinor() { return 18; }
int ChartInspectorPi::GetPlugInVersionMajor() { return 0; }
int ChartInspectorPi::GetPlugInVersionMinor() { return 8; }
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

void ChartInspectorPi::BuildToolbarBitmaps() {
  auto build = [](const wxColour &colour, bool active) {
    wxBitmap bitmap(24, 24);
    wxMemoryDC dc(bitmap);
    dc.SetBackground(wxBrush(wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOW)));
    dc.Clear();
    dc.SetPen(wxPen(colour, active ? 3 : 2));
    dc.SetBrush(active ? wxBrush(colour) : *wxTRANSPARENT_BRUSH);
    dc.DrawCircle(wxPoint(9, 9), 5);
    dc.SetBrush(*wxTRANSPARENT_BRUSH);
    dc.DrawLine(13, 13, 21, 21);
    dc.SelectObject(wxNullBitmap);
    return bitmap;
  };
  m_toolbarEnabledBitmap = build(wxColour(0, 210, 235), true);
  m_toolbarDisabledBitmap = build(wxColour(115, 115, 115), false);
}

void ChartInspectorPi::UpdateToolbarVisual() {
  if (m_toolbarId < 0) return;
  wxBitmap *bitmap = m_enabled ? &m_toolbarEnabledBitmap : &m_toolbarDisabledBitmap;
  SetToolbarToolBitmaps(m_toolbarId, bitmap, bitmap);
  SetToolbarItemState(m_toolbarId, m_enabled);
}

void ChartInspectorPi::ApplyInfoTheme() {
  if (!m_infoPanel) return;
  wxColour background = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOW);
  wxColour foreground = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOWTEXT);
  wxColour secondary = wxSystemSettings::GetColour(wxSYS_COLOUR_GRAYTEXT);
  GetGlobalColor("DILG0", &background);
  GetGlobalColor("DILG4", &foreground);
  GetGlobalColor("DILG3", &secondary);
  m_infoPanel->SetBackgroundColour(background);
  m_infoPanel->SetForegroundColour(foreground);
  if (m_infoVisual) {
    m_infoVisual->SetBackgroundColour(background);
    m_infoVisual->SetForegroundColour(foreground);
  }
  if (m_infoTitle) m_infoTitle->SetForegroundColour(foreground);
  if (m_infoSubtitle) m_infoSubtitle->SetForegroundColour(foreground);
  if (m_infoAcronym) m_infoAcronym->SetForegroundColour(secondary);
  if (m_infoBody) m_infoBody->SetForegroundColour(foreground);
  if (m_infoTechnical) m_infoTechnical->SetForegroundColour(secondary);
  if (m_infoVisual) {
    const wxWindowList &children = m_infoVisual->GetChildren();
    for (wxWindowList::const_iterator it = children.begin(); it != children.end();
         ++it) {
      wxWindow *child = *it;
      if (!child || child == m_lightIndicator) continue;
      if (dynamic_cast<wxStaticText *>(child)) {
        child->SetBackgroundColour(background);
        child->SetForegroundColour(foreground);
      }
    }
  }
  if (m_lightIndicator) m_lightIndicator->SetBackgroundColour(background);
  m_infoPanel->Refresh();
}

void ChartInspectorPi::LoadConfig() {
  if (!m_config) return;
  m_config->SetPath("/PlugIns/ChartInspector");
  m_config->Read("Enabled", &m_enabled, true);
  m_config->Read("ShowTechnicalData", &m_showTechnicalData, false);
  long radius = 5;
  m_config->Read("HitRadiusPixels", &radius, 5L);
  m_hitRadiusPixels = static_cast<int>(std::max(2L, std::min(20L, radius)));
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

void ChartInspectorPi::SetColorScheme(PI_ColorScheme cs) {
  m_colorScheme = cs;
  ApplyInfoTheme();
  if (m_infoPanel && m_infoPanel->IsShown()) {
    BuildVisualSummary();
    ApplyInfoTheme();
    m_infoPanel->Layout();
    m_infoPanel->Refresh();
  }
}

void ChartInspectorPi::ClearHover() {
  m_hasVectorObject = false;
  m_lastFeature.clear();
  m_lastObjectName.clear();
  m_lastAttributes.clear();
  m_associatedLightAttributes.clear();
  m_hasAssociatedLight = false;
  m_lastPrimitiveType = 1;
}

bool ChartInspectorPi::IsFeatureEnabled(const wxString &feature) const {
  const wxString candidate = feature.Upper();
  wxStringTokenizer tokens(m_featureFilter, ",; \t\r\n", wxTOKEN_STRTOK);
  while (tokens.HasMoreTokens()) {
    wxString token = tokens.GetNextToken().Upper();
    token.Trim(true);
    token.Trim(false);
    if (token.EndsWith("*")) {
      token.RemoveLast();
      if (!token.IsEmpty() && candidate.StartsWith(token)) return true;
    } else if (candidate == token) {
      return true;
    }
  }
  return false;
}

wxColour ChartInspectorPi::SignalColour(const wxString &value) const {
  long code = 0;
  value.BeforeFirst(',').ToLong(&code);
  wxColour c(210, 210, 210);
  switch (code) {
    case 1: c = wxColour(245, 245, 235); break;
    case 2: c = wxColour(25, 25, 25); break;
    case 3: c = wxColour(235, 55, 55); break;
    case 4: c = wxColour(45, 190, 85); break;
    case 5: c = wxColour(55, 120, 235); break;
    case 6: c = wxColour(245, 210, 40); break;
    case 7: c = wxColour(130, 130, 130); break;
    case 8: c = wxColour(145, 95, 55); break;
    case 9: c = wxColour(255, 175, 35); break;
    case 10: c = wxColour(145, 80, 190); break;
    case 11: c = wxColour(245, 125, 35); break;
    case 12: c = wxColour(220, 55, 180); break;
    case 13: c = wxColour(245, 135, 170); break;
    default: break;
  }
  double factor = 1.0;
  if (m_colorScheme == PI_GLOBAL_COLOR_SCHEME_DUSK) factor = 0.78;
  if (m_colorScheme == PI_GLOBAL_COLOR_SCHEME_NIGHT) factor = 0.58;
  return wxColour(static_cast<unsigned char>(c.Red() * factor),
                  static_cast<unsigned char>(c.Green() * factor),
                  static_cast<unsigned char>(c.Blue() * factor));
}

wxString ChartInspectorPi::BuildLightSummary(const wxString &attributes) const {
  const wxString chr = m_s57Catalog.RawAttributeValue(attributes, "LITCHR");
  const wxString grp = m_s57Catalog.RawAttributeValue(attributes, "SIGGRP");
  const wxString col = m_s57Catalog.RawAttributeValue(attributes, "COLOUR");
  const wxString per = m_s57Catalog.RawAttributeValue(attributes, "SIGPER");
  long c = 0;
  chr.ToLong(&c);
  wxString abbr;
  switch (c) {
    case 1: abbr = "F"; break;
    case 2: abbr = "Fl"; break;
    case 3: abbr = "LFl"; break;
    case 4: abbr = "Q"; break;
    case 5: abbr = "VQ"; break;
    case 6: abbr = "UQ"; break;
    case 7: abbr = "Iso"; break;
    case 8: abbr = "Oc"; break;
    case 9: abbr = "IQ"; break;
    case 10: abbr = "IVQ"; break;
    case 11: abbr = "IUQ"; break;
    case 12: abbr = "Mo"; break;
    case 13: abbr = "F.Fl"; break;
    case 14: abbr = "Fl.LFl"; break;
    case 28: abbr = "Al"; break;
    case 29: abbr = "F.Al.Fl"; break;
    default: abbr = m_s57Catalog.DecodeValue("LITCHR", chr); break;
  }
  if (!grp.IsEmpty() && grp != "()" && grp != "(1)") abbr += grp;
  long colourCode = 0;
  col.BeforeFirst(',').ToLong(&colourCode);
  wxString colourAbbr;
  switch (colourCode) {
    case 1: colourAbbr = "W"; break;
    case 3: colourAbbr = "R"; break;
    case 4: colourAbbr = "G"; break;
    case 5: colourAbbr = "Bu"; break;
    case 6: colourAbbr = "Y"; break;
    default: colourAbbr = m_s57Catalog.DecodeValue("COLOUR", col); break;
  }
  wxString result = abbr;
  if (!colourAbbr.IsEmpty()) result += " " + colourAbbr;
  if (!per.IsEmpty()) result += " " + per + "s";
  return result.IsEmpty() ? "Light" : result;
}

void ChartInspectorPi::StopLightPreview() {
  if (m_lightTimer) {
    m_lightTimer->Stop();
    delete m_lightTimer;
    m_lightTimer = nullptr;
  }
  m_lightIndicator = nullptr;
}

void ChartInspectorPi::UpdateLightIndicator() {
  if (!m_lightIndicator) return;
  bool on = true;
  if (!m_lightIsFixed && m_lightPeriodSeconds > 0.05) {
    const long long periodMs =
        static_cast<long long>(m_lightPeriodSeconds * 1000.0);
    const long long phaseMs = wxGetUTCTimeMillis().GetValue() % periodMs;
    const double phase = static_cast<double>(phaseMs) / periodMs;
    if (m_lightCharacteristic == 7) {
      on = phase < 0.5;  // Iso: equal light and dark intervals.
    } else if (m_lightCharacteristic == 8) {
      on = phase < 0.75;  // Oc: light longer than eclipse, schematic preview.
    } else if (m_lightCharacteristic == 4 || m_lightCharacteristic == 5 ||
               m_lightCharacteristic == 6) {
      if (m_lightGroupCount <= 1) {
        on = phase < 0.25;
      } else {
        const double activeWindow = m_lightHasLongFlash ? 0.72 : 0.62;
        if (m_lightHasLongFlash && phase > 0.74 && phase < 0.90) {
          on = true;
        } else if (phase < activeWindow) {
          const double local =
              std::fmod(phase * m_lightGroupCount / activeWindow, 1.0);
          on = local < 0.24;
        } else {
          on = false;
        }
      }
    } else {
      const int flashes = std::max(1, m_lightGroupCount);
      const double activeWindow = 0.62;
      if (phase < activeWindow) {
        const double local = std::fmod(phase * flashes / activeWindow, 1.0);
        on = local < 0.22;
      } else {
        on = false;
      }
    }
  }
  m_lightOn = on;
  m_lightIndicator->Refresh(false);
}

void ChartInspectorPi::BuildVisualSummary() {
  if (!m_infoVisual) return;
  StopLightPreview();
  wxSizer *sizer = m_infoVisual->GetSizer();
  if (!sizer) {
    sizer = new wxBoxSizer(wxVERTICAL);
    m_infoVisual->SetSizer(sizer);
  }
  sizer->Clear(true);

  if (m_lastFeature != "LIGHTS") {
    const wxString colourRaw =
        m_s57Catalog.RawAttributeValue(m_lastAttributes, "COLOUR");
    if (!colourRaw.IsEmpty()) {
      wxBoxSizer *row = new wxBoxSizer(wxHORIZONTAL);
      wxStaticText *label = new wxStaticText(m_infoVisual, wxID_ANY, "Colour");
      wxFont f = label->GetFont();
      f.SetWeight(wxFONTWEIGHT_BOLD);
      label->SetFont(f);
      row->Add(label, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 10);
      wxStringTokenizer values(colourRaw, ",", wxTOKEN_STRTOK);
      while (values.HasMoreTokens()) {
        wxString token = values.GetNextToken();
        token.Trim(true);
        token.Trim(false);
        wxPanel *chip = new wxPanel(m_infoVisual, wxID_ANY, wxDefaultPosition,
                                    wxSize(18, 18), wxBORDER_SIMPLE);
        chip->SetMinSize(wxSize(18, 18));
        chip->SetBackgroundColour(SignalColour(token));
        row->Add(chip, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 5);
      }
      row->Add(new wxStaticText(
                   m_infoVisual, wxID_ANY,
                   m_s57Catalog.DecodeValue("COLOUR", colourRaw)),
               0, wxALIGN_CENTER_VERTICAL);
      sizer->Add(row, 0, wxBOTTOM, 10);
    }
  }

  wxString lightAttributes;
  if (m_lastFeature == "LIGHTS")
    lightAttributes = m_lastAttributes;
  else if (m_hasAssociatedLight)
    lightAttributes = m_associatedLightAttributes;

  if (!lightAttributes.IsEmpty()) {
    const wxString lightColourRaw =
        m_s57Catalog.RawAttributeValue(lightAttributes, "COLOUR");
    wxBoxSizer *lightRow = new wxBoxSizer(wxHORIZONTAL);
    m_lightColour = SignalColour(lightColourRaw);
    m_lightIndicator = new wxPanel(m_infoVisual, wxID_ANY, wxDefaultPosition,
                                   wxSize(30, 30), wxBORDER_NONE);
    m_lightIndicator->SetMinSize(wxSize(30, 30));
    m_lightIndicator->SetBackgroundStyle(wxBG_STYLE_PAINT);
    m_lightIndicator->Bind(wxEVT_PAINT, [this](wxPaintEvent &) {
      if (!m_lightIndicator) return;
      wxAutoBufferedPaintDC dc(m_lightIndicator);
      wxColour background = m_infoVisual->GetBackgroundColour();
      wxColour border = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOWTEXT);
      GetGlobalColor("DILG4", &border);
      wxColour offColour(68, 68, 68);
      if (m_colorScheme == PI_GLOBAL_COLOR_SCHEME_DUSK)
        offColour = wxColour(58, 58, 58);
      else if (m_colorScheme == PI_GLOBAL_COLOR_SCHEME_NIGHT)
        offColour = wxColour(44, 44, 44);
      dc.SetBackground(wxBrush(background));
      dc.Clear();
      dc.SetPen(wxPen(border, 2));
      dc.SetBrush(wxBrush(m_lightOn ? m_lightColour : offColour));
      dc.DrawRectangle(5, 5, 20, 20);
    });
    lightRow->Add(m_lightIndicator, 0, wxALIGN_TOP | wxRIGHT, 10);

    wxBoxSizer *lightText = new wxBoxSizer(wxVERTICAL);
    wxStaticText *character = new wxStaticText(
        m_infoVisual, wxID_ANY,
        (m_lastFeature == "LIGHTS" ? wxString() : "Light  ") +
            BuildLightSummary(lightAttributes));
    wxFont cf = character->GetFont();
    cf.SetWeight(wxFONTWEIGHT_BOLD);
    cf.SetPointSize(cf.GetPointSize() + 2);
    character->SetFont(cf);
    lightText->Add(character, 0);

    wxString lightDetails;
    const wxString height =
        m_s57Catalog.RawAttributeValue(lightAttributes, "HEIGHT");
    const wxString range =
        m_s57Catalog.RawAttributeValue(lightAttributes, "VALNMR");
    const wxString visibility =
        m_s57Catalog.RawAttributeValue(lightAttributes, "LITVIS");
    const wxString sector1 =
        m_s57Catalog.RawAttributeValue(lightAttributes, "SECTR1");
    const wxString sector2 =
        m_s57Catalog.RawAttributeValue(lightAttributes, "SECTR2");
    AppendInfoLine(&lightDetails, "Light height", MetresAndFeet(height));
    if (!range.IsEmpty()) AppendInfoLine(&lightDetails, "Nominal range", range + " NM");
    if (!visibility.IsEmpty())
      AppendInfoLine(&lightDetails, "Visibility",
                     m_s57Catalog.DecodeValue("LITVIS", visibility));
    if (!sector1.IsEmpty() || !sector2.IsEmpty()) {
      wxString sector;
      if (!sector1.IsEmpty()) sector += sector1 + wxString::FromUTF8("°");
      if (!sector1.IsEmpty() && !sector2.IsEmpty()) sector += " - ";
      if (!sector2.IsEmpty()) sector += sector2 + wxString::FromUTF8("°");
      AppendInfoLine(&lightDetails, "Sector", sector);
    }
    if (!lightDetails.IsEmpty()) {
      wxStaticText *details =
          new wxStaticText(m_infoVisual, wxID_ANY, lightDetails);
      lightText->Add(details, 0, wxTOP, 4);
    }

    const wxString groupRaw =
        m_s57Catalog.RawAttributeValue(lightAttributes, "SIGGRP");
    const bool complexPattern =
        (!groupRaw.IsEmpty() && groupRaw != "()" && groupRaw != "(1)") ||
        m_s57Catalog.RawAttributeValue(lightAttributes, "SIGSEQ").length() > 0;
    wxStaticText *note = new wxStaticText(
        m_infoVisual, wxID_ANY,
        complexPattern
            ? "Schematic animated preview; encoded light characteristic is authoritative"
            : "Animated preview of the encoded light characteristic");
    wxFont nf = note->GetFont();
    nf.SetPointSize(std::max(7, nf.GetPointSize() - 1));
    note->SetFont(nf);
    lightText->Add(note, 0, wxTOP, 4);
    lightRow->Add(lightText, 1, wxEXPAND);
    sizer->Add(lightRow, 0, wxEXPAND | wxBOTTOM, 10);

    long chr = 0;
    m_s57Catalog.RawAttributeValue(lightAttributes, "LITCHR").ToLong(&chr);
    m_lightCharacteristic = static_cast<int>(chr);
    m_lightIsFixed = chr == 1;
    m_lightPeriodSeconds = 0.0;
    const bool hasEncodedPeriod =
        m_s57Catalog.RawAttributeValue(lightAttributes, "SIGPER")
            .ToDouble(&m_lightPeriodSeconds);

    m_lightGroupCount = 1;
    wxString group = groupRaw;
    m_lightHasLongFlash = group.Upper().Find("LFL") != wxNOT_FOUND;
    wxString countPart = group;
    const int plus = countPart.Find('+');
    if (plus != wxNOT_FOUND) countPart = countPart.Left(plus);
    countPart.Replace("(", "");
    countPart.Replace(")", "");
    long groupCount = 1;
    if (countPart.ToLong(&groupCount) && groupCount > 0)
      m_lightGroupCount = static_cast<int>(groupCount);

    if (!hasEncodedPeriod || m_lightPeriodSeconds <= 0.05) {
      if (m_lightGroupCount <= 1) {
        if (chr == 4)
          m_lightPeriodSeconds = 1.0;
        else if (chr == 5)
          m_lightPeriodSeconds = 0.5;
        else if (chr == 6)
          m_lightPeriodSeconds = 0.25;
      } else {
        m_lightPeriodSeconds = 0.0;
      }
    }

    m_lightOn = m_lightIsFixed;
    UpdateLightIndicator();
    if (!m_lightIsFixed && m_lightPeriodSeconds > 0.05) {
      m_lightTimer = new wxTimer();
      m_lightTimer->SetOwner(m_infoPanel);
      m_infoPanel->Bind(wxEVT_TIMER,
                        [this](wxTimerEvent &) { UpdateLightIndicator(); },
                        m_lightTimer->GetId());
      m_lightTimer->Start(50);
    }
  }

  m_infoVisual->Show(sizer->GetItemCount() > 0);
  m_infoVisual->Layout();
  ApplyInfoTheme();
}

void ChartInspectorPi::BuildInfoPanel(wxWindow *canvas) {
  if (m_infoPanel || !canvas) return;
  m_infoPanel = new wxPanel(canvas, wxID_ANY, wxDefaultPosition, wxDefaultSize,
                            wxBORDER_SIMPLE);
  wxBoxSizer *root = new wxBoxSizer(wxVERTICAL);
  wxBoxSizer *header = new wxBoxSizer(wxHORIZONTAL);
  m_infoTitle = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  wxFont titleFont = m_infoTitle->GetFont();
  titleFont.SetWeight(wxFONTWEIGHT_BOLD);
  titleFont.SetPointSize(titleFont.GetPointSize() + 2);
  m_infoTitle->SetFont(titleFont);
  header->Add(m_infoTitle, 1, wxALIGN_CENTER_VERTICAL);
  wxButton *close = new wxButton(m_infoPanel, wxID_ANY, "x", wxDefaultPosition,
                                 wxSize(28, 26), wxBU_EXACTFIT);
  close->Bind(wxEVT_BUTTON, [this](wxCommandEvent &) { HideObjectPopup(); });
  header->Add(close, 0, wxLEFT, 8);
  root->Add(header, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 12);
  m_infoSubtitle = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  root->Add(m_infoSubtitle, 0, wxLEFT | wxRIGHT | wxTOP, 8);
  m_infoAcronym = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  root->Add(m_infoAcronym, 0, wxLEFT | wxRIGHT | wxTOP, 8);
  root->Add(new wxStaticLine(m_infoPanel), 0,
            wxEXPAND | wxLEFT | wxRIGHT | wxTOP | wxBOTTOM, 12);
  m_infoVisual = new wxPanel(m_infoPanel, wxID_ANY);
  m_infoVisual->SetSizer(new wxBoxSizer(wxVERTICAL));
  root->Add(m_infoVisual, 0, wxEXPAND | wxLEFT | wxRIGHT, 12);
  m_infoBody = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  root->Add(m_infoBody, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 12);
  m_infoTechnical = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  wxFont techFont = m_infoTechnical->GetFont();
  techFont.SetPointSize(std::max(7, techFont.GetPointSize() - 1));
  m_infoTechnical->SetFont(techFont);
  root->Add(m_infoTechnical, 0, wxEXPAND | wxALL, 12);
  m_infoPanel->SetSizer(root);
  ApplyInfoTheme();
  m_infoPanel->Hide();
}

void ChartInspectorPi::HideObjectPopup() {
  StopLightPreview();
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
  const wxString geometry = m_lastPrimitiveType == 3 ? "Area" :
                            m_lastPrimitiveType == 2 ? "Line" : "Point";
  m_infoAcronym->SetLabel("S-57: " + m_lastFeature + "  -  " + geometry);
  BuildVisualSummary();

  wxString bodyAttributes = m_lastAttributes;
  if (m_lastFeature == "LIGHTS") {
    bodyAttributes = FilterRawAttributes(
        bodyAttributes,
        {"COLOUR", "LITCHR", "SIGGRP", "SIGPER", "SIGSEQ", "HEIGHT",
         "VALNMR", "LITVIS", "SECTR1", "SECTR2"});
  }
  wxString technical;
  const wxString readable =
      m_s57Catalog.FormatAttributes(bodyAttributes, &technical);
  m_infoBody->SetLabel(readable);
  m_infoBody->Wrap(360);
  m_infoBody->Show(!readable.IsEmpty());

  if (m_showTechnicalData) {
    wxString raw = "Technical S-57 data\n" + m_lastFeature;
    wxString allTechnical;
    m_s57Catalog.FormatAttributes(m_lastAttributes, &allTechnical);
    if (!allTechnical.IsEmpty()) raw += "\n" + allTechnical;
    if (m_hasAssociatedLight) {
      wxString lightTechnical;
      m_s57Catalog.FormatAttributes(m_associatedLightAttributes,
                                    &lightTechnical);
      raw += "\n\nAssociated LIGHTS";
      if (!lightTechnical.IsEmpty()) raw += "\n" + lightTechnical;
    }
    m_infoTechnical->SetLabel(raw);
    m_infoTechnical->Wrap(360);
    m_infoTechnical->Show();
  } else {
    m_infoTechnical->Hide();
  }

  ApplyInfoTheme();
  m_infoPanel->Layout();
  m_infoPanel->Fit();
  wxSize size = m_infoPanel->GetSize();
  size.SetWidth(std::max(340, std::min(460, size.GetWidth())));
  m_infoPanel->SetSize(size);
  m_infoPanel->Layout();
  const wxSize canvasSize = canvas->GetClientSize();
  m_infoPanel->Move(std::max(12, canvasSize.GetWidth() - size.GetWidth() - 14),
                    14);
  m_infoPanel->Show();
  m_infoPanel->Raise();
}

void ChartInspectorPi::QueryAssociatedLight() {
  m_associatedLightAttributes.clear();
  m_hasAssociatedLight = false;
  if (!(m_lastFeature.StartsWith("BOY") || m_lastFeature.StartsWith("BCN")))
    return;
  HitTestV3Fn query = m_hitTestV4 ? m_hitTestV4 : m_hitTestV3;
  if (!query) return;
  char feature[32] = {0};
  char objectName[128] = {0};
  char attributes[2048] = {0};
  int primitiveType = 1;
  double markerLat = 0.0;
  double markerLon = 0.0;
  const bool found = query(
      0, m_lastObjectLat, m_lastObjectLon,
      static_cast<double>(std::max(8, m_hitRadiusPixels)), "LIGHTS", feature,
      static_cast<int>(sizeof(feature)), objectName,
      static_cast<int>(sizeof(objectName)), attributes,
      static_cast<int>(sizeof(attributes)), &primitiveType, &markerLat,
      &markerLon);
  if (found && wxString::FromUTF8(feature).Upper() == "LIGHTS") {
    m_associatedLightAttributes = wxString::FromUTF8(attributes);
    m_hasAssociatedLight = !m_associatedLightAttributes.IsEmpty();
  }
}

void ChartInspectorPi::UpdateHoverObject() {
  if (!m_enabled ||
      (!m_hitTestV4 && !m_hitTestV3 && !m_hitTestV2 && !m_hitTest) ||
      !m_hasCursorPosition) {
    ClearHover();
    return;
  }
  char feature[32] = {0};
  char objectName[128] = {0};
  char attributes[2048] = {0};
  double markerLat = 0.0;
  double markerLon = 0.0;
  int primitiveType = 1;
  bool found = false;
  const wxCharBuffer filter = m_featureFilter.ToUTF8();
  if (m_hitTestV4 || m_hitTestV3) {
    HitTestV3Fn query = m_hitTestV4 ? m_hitTestV4 : m_hitTestV3;
    found = query(0, m_cursorLat, m_cursorLon,
                  static_cast<double>(m_hitRadiusPixels), filter.data(), feature,
                  static_cast<int>(sizeof(feature)), objectName,
                  static_cast<int>(sizeof(objectName)), attributes,
                  static_cast<int>(sizeof(attributes)), &primitiveType,
                  &markerLat, &markerLon);
  } else if (m_hitTestV2) {
    found = m_hitTestV2(0, m_cursorLat, m_cursorLon,
                        static_cast<double>(m_hitRadiusPixels), feature,
                        static_cast<int>(sizeof(feature)), objectName,
                        static_cast<int>(sizeof(objectName)), attributes,
                        static_cast<int>(sizeof(attributes)), &markerLat,
                        &markerLon);
  } else if (m_hitTest) {
    found = m_hitTest(0, m_cursorLat, m_cursorLon,
                      static_cast<double>(m_hitRadiusPixels), feature,
                      static_cast<int>(sizeof(feature)), objectName,
                      static_cast<int>(sizeof(objectName)), &markerLat,
                      &markerLon);
  }
  const wxString featureName = wxString::FromUTF8(feature).Upper();
  if (found && !IsFeatureEnabled(featureName)) found = false;
  if (!found) {
    ClearHover();
    return;
  }
  m_hasVectorObject = true;
  m_lastFeature = featureName;
  m_lastObjectName = wxString::FromUTF8(objectName);
  m_lastAttributes = wxString::FromUTF8(attributes);
  m_lastObjectLat = markerLat;
  m_lastObjectLon = markerLon;
  m_lastPrimitiveType = primitiveType;
  QueryAssociatedLight();
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
  UpdateToolbarVisual();
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

  wxBoxSizer *radiusRow = new wxBoxSizer(wxHORIZONTAL);
  radiusRow->Add(new wxStaticText(&dialog, wxID_ANY, "Hit radius:"), 0,
                 wxALIGN_CENTER_VERTICAL | wxRIGHT, 8);
  wxSpinCtrl *radius = new wxSpinCtrl(&dialog, wxID_ANY);
  radius->SetRange(2, 20);
  radius->SetValue(m_hitRadiusPixels);
  radiusRow->Add(radius, 0);
  radiusRow->Add(new wxStaticText(&dialog, wxID_ANY, "pixels"), 0,
                 wxALIGN_CENTER_VERTICAL | wxLEFT, 6);
  root->Add(radiusRow, 0, wxLEFT | wxRIGHT | wxBOTTOM, 10);

  wxCheckListBox *classes = new wxCheckListBox(
      &dialog, wxID_ANY, wxDefaultPosition, wxSize(580, 400));
  std::vector<wxString> classAcronyms;
  for (const auto &info : m_s57Catalog.ObjectClasses()) {
    const unsigned int index = classes->Append(info.acronym + "  -  " + info.name);
    classes->Check(index, IsFeatureEnabled(info.acronym));
    classAcronyms.push_back(info.acronym);
  }
  root->Add(classes, 1, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, 10);

  wxCheckBox *technical = new wxCheckBox(
      &dialog, wxID_ANY,
      "Show technical S-57 acronyms and raw values at the bottom of the card");
  technical->SetValue(m_showTechnicalData);
  root->Add(technical, 0, wxLEFT | wxRIGHT | wxBOTTOM, 10);
  root->Add(dialog.CreateSeparatedButtonSizer(wxOK | wxCANCEL), 0,
            wxEXPAND | wxALL, 10);
  dialog.SetSizer(root);
  DimeWindow(&dialog);
  dialog.CentreOnParent();

  if (dialog.ShowModal() == wxID_OK) {
    m_enabled = enabled->GetValue();
    m_hitRadiusPixels = radius->GetValue();
    m_showTechnicalData = technical->GetValue();
    wxString filterValue;
    for (unsigned int i = 0; i < classes->GetCount(); ++i) {
      if (!classes->IsChecked(i)) continue;
      if (!filterValue.IsEmpty()) filterValue += ",";
      filterValue += classAcronyms[i];
    }
    m_featureFilter = filterValue;
    UpdateToolbarVisual();
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
  dc.DrawCircle(p, m_lastPrimitiveType == 1 ? 12 : 9);
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
  const float r = m_lastPrimitiveType == 1 ? 12.0f : 9.0f;
  glColor4f(0.0f, 1.0f, 1.0f, 0.9f);
  glLineWidth(3.0f);
  glBegin(GL_LINE_LOOP);
  for (int i = 0; i < 32; ++i) {
    const float a = static_cast<float>(i) * 6.28318530718f / 32.0f;
    glVertex2f(static_cast<float>(p.x) + r * cosf(a),
               static_cast<float>(p.y) + r * sinf(a));
  }
  glEnd();
  glPopMatrix();
  glMatrixMode(GL_PROJECTION);
  glPopMatrix();
  glMatrixMode(GL_MODELVIEW);
  glPopAttrib();
  return true;
}
