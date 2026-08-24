#include "ui/app_style.h"

#include <algorithm>

#include <wx/settings.h>

namespace ci_ui {
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

AppPalette AppStyle::PaletteFor(PI_ColorScheme scheme) {
  AppPalette p;
  p.windowBackground = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOW);
  p.textPrimary = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOWTEXT);
  p.textSecondary = wxSystemSettings::GetColour(wxSYS_COLOUR_GRAYTEXT);

  // Follow the active OpenCPN colour table first. This keeps the plugin tied
  // to the bridge display's DAY / DUSK / NIGHT state rather than inventing a
  // separate desktop light/dark theme.
  GetGlobalColor("DILG0", &p.windowBackground);
  GetGlobalColor("DILG4", &p.textPrimary);
  GetGlobalColor("DILG3", &p.textSecondary);

  const bool dusk = scheme == PI_GLOBAL_COLOR_SCHEME_DUSK;
  const bool night = scheme == PI_GLOBAL_COLOR_SCHEME_NIGHT;
  const bool dark = dusk || night;

  // Keep information cards low-contrast. They provide grouping, not a second
  // visual layer competing with the chart itself.
  if (dark) {
    p.cardBackground = Blend(p.windowBackground, p.textPrimary, night ? 0.035 : 0.055);
    p.cardBorder = Blend(p.windowBackground, p.textPrimary, night ? 0.16 : 0.20);
    p.textSecondary = Blend(p.windowBackground, p.textPrimary, night ? 0.58 : 0.66);
  } else {
    p.cardBackground = Blend(p.windowBackground, p.textPrimary, 0.025);
    p.cardBorder = Blend(p.windowBackground, p.textPrimary, 0.18);
    p.textSecondary = Blend(p.windowBackground, p.textPrimary, 0.58);
  }

  // A cool blue/cyan focus family is used solely for interaction. It avoids
  // stealing the maritime safety semantics normally carried by red,
  // amber/yellow and green. Signal-light colour chips remain literal S-57
  // content and are therefore intentionally handled elsewhere.
  p.accent = wxColour(35, 125, 155);
  p.focus = wxColour(45, 155, 185);
  p.focusHalo = wxColour(25, 80, 105);
  if (dusk) {
    p.accent = Scale(p.accent, 0.78);
    p.focus = Scale(p.focus, 0.78);
    p.focusHalo = Scale(p.focusHalo, 0.78);
  } else if (night) {
    p.accent = Scale(p.accent, 0.55);
    p.focus = Scale(p.focus, 0.55);
    p.focusHalo = Scale(p.focusHalo, 0.55);
  }

  return p;
}

wxFont AppStyle::TitleFont(const wxFont &base) {
  wxFont f = base;
  f.SetStyle(wxFONTSTYLE_NORMAL);
  f.SetWeight(wxFONTWEIGHT_BOLD);
  f.SetPointSize(f.GetPointSize() + 2);
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
  f.SetWeight(wxFONTWEIGHT_NORMAL);
  return f;
}

wxFont AppStyle::TechnicalFont(const wxFont &base) {
  wxFont f = base;
  f.SetStyle(wxFONTSTYLE_NORMAL);
  f.SetPointSize(std::max(7, f.GetPointSize() - 1));
  return f;
}

}  // namespace ci_ui
