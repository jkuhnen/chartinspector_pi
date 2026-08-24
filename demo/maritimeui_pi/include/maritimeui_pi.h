#ifndef MARITIMEUI_PI_H
#define MARITIMEUI_PI_H

#include <wx/wx.h>
#include "ocpn_plugin.h"

class MaritimeUiPi : public opencpn_plugin_118 {
public:
  explicit MaritimeUiPi(void *ppimgr);
  ~MaritimeUiPi() override = default;

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

  void OnToolbarToolCallback(int id) override;
  void SetColorScheme(PI_ColorScheme cs) override;

private:
  void BuildToolbarBitmap();
  void EnsureWindow();
  void ApplyTheme();
  void ToggleWindow();

  int m_toolbarId = -1;
  wxBitmap m_pluginBitmap;
  wxBitmap m_toolbarBitmap;
  wxFrame *m_window = nullptr;
  PI_ColorScheme m_colorScheme = PI_GLOBAL_COLOR_SCHEME_DAY;
};

#endif
