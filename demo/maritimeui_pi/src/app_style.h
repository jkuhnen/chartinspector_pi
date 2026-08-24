#ifndef MARITIMEUI_APP_STYLE_H
#define MARITIMEUI_APP_STYLE_H

#include <wx/colour.h>
#include <wx/font.h>
#include "ocpn_plugin.h"

namespace maritime_ui {

struct Palette {
  wxColour windowBackground;
  wxColour panelBackground;
  wxColour panelBorder;
  wxColour textPrimary;
  wxColour textSecondary;
  wxColour accent;
  wxColour focus;
  wxColour warning;
  wxColour alarm;
  wxColour normal;
};

class AppStyle {
public:
  static Palette PaletteFor(PI_ColorScheme scheme);
  static wxFont TitleFont(const wxFont &base);
  static wxFont PrimaryFont(const wxFont &base);
  static wxFont LabelFont(const wxFont &base);
  static wxFont TechnicalFont(const wxFont &base);

  static const int kXs = 4;
  static const int kSm = 8;
  static const int kMd = 12;
  static const int kLg = 16;
};

}  // namespace maritime_ui

#endif
