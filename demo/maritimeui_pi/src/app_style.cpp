#include "app_style.h"

#include <algorithm>
#include <wx/settings.h>

namespace maritime_ui {
namespace {

wxColour Blend(const wxColour &a, const wxColour &b, double amountB) {
  amountB = std::max(0.0, std::min(1.0, amountB));
  const double amountA = 1.0 - amountB;
  return wxColour(
      static_cast<unsigned char>(a.Red() * amountA + b.Red() * amountB),
      static_cast<unsigned char>(a.Green() * amountA + b.Green() * amountB),
      static_cast<unsigned char>(a.Blue() * amountA + b.Blue() * amountB));
}

wxColour Scale(const wxColour &c, double factor) {
  factor = std::max(0.0, std::min(1.0, factor));
  return wxColour(static_cast<unsigned char>(c.Red() * factor),
                  static_cast<unsigned char>(c.Green() * factor),
                  static_cast<unsigned char>(c.Blue() * factor));
}

}  // namespace

Palette AppStyle::PaletteFor(PI_ColorScheme scheme) {
  Palette p;
  p.windowBackground = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOW);
  p.textPrimary = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOWTEXT);
  p.textSecondary = wxSystemSettings::GetColour(wxSYS_COLOUR_GRAYTEXT);
  GetGlobalColor("DILG0", &p.windowBackground);
  GetGlobalColor("DILG4", &p.textPrimary);
  GetGlobalColor("DILG3", &p.textSecondary);

  const bool dusk = scheme == PI_GLOBAL_COLOR_SCHEME_DUSK;
  const bool night = scheme == PI_GLOBAL_COLOR_SCHEME_NIGHT;
  if (dusk || night) {
    p.panelBackground = Blend(p.windowBackground, p.textPrimary, night ? 0.04 : 0.06);
    p.panelBorder = Blend(p.windowBackground, p.textPrimary, night ? 0.17 : 0.22);
    p.textSecondary = Blend(p.windowBackground, p.textPrimary, night ? 0.58 : 0.66);
  } else {
    p.panelBackground = Blend(p.windowBackground, p.textPrimary, 0.03);
    p.panelBorder = Blend(p.windowBackground, p.textPrimary, 0.20);
    p.textSecondary = Blend(p.windowBackground, p.textPrimary, 0.58);
  }

  p.accent = wxColour(35, 125, 155);
  p.focus = wxColour(45, 155, 185);
  p.warning = wxColour(220, 175, 45);
  p.alarm = wxColour(205, 65, 55);
  p.normal = wxColour(60, 145, 95);

  if (dusk) {
    p.accent = Scale(p.accent, 0.78);
    p.focus = Scale(p.focus, 0.78);
    p.warning = Scale(p.warning, 0.78);
    p.alarm = Scale(p.alarm, 0.78);
    p.normal = Scale(p.normal, 0.78);
  } else if (night) {
    p.accent = Scale(p.accent, 0.55);
    p.focus = Scale(p.focus, 0.55);
    p.warning = Scale(p.warning, 0.55);
    p.alarm = Scale(p.alarm, 0.55);
    p.normal = Scale(p.normal, 0.55);
  }
  return p;
}

wxFont AppStyle::TitleFont(const wxFont &base) {
  wxFont f = base;
  f.SetStyle(wxFONTSTYLE_NORMAL);
  f.SetWeight(wxFONTWEIGHT_BOLD);
  f.SetPointSize(f.GetPointSize() + 3);
  return f;
}

wxFont AppStyle::PrimaryFont(const wxFont &base) {
  wxFont f = base;
  f.SetStyle(wxFONTSTYLE_NORMAL);
  f.SetWeight(wxFONTWEIGHT_BOLD);
  f.SetPointSize(f.GetPointSize() + 1);
  return f;
}

wxFont AppStyle::LabelFont(const wxFont &base) {
  wxFont f = base;
  f.SetStyle(wxFONTSTYLE_NORMAL);
  return f;
}

wxFont AppStyle::TechnicalFont(const wxFont &base) {
  wxFont f = base;
  f.SetStyle(wxFONTSTYLE_NORMAL);
  f.SetPointSize(std::max(7, f.GetPointSize() - 1));
  return f;
}

}  // namespace maritime_ui
