#ifndef CHARTINSPECTOR_OBJECT_INSPECTOR_PANEL_H
#define CHARTINSPECTOR_OBJECT_INSPECTOR_PANEL_H

#include <functional>
#include <vector>

#include <wx/colour.h>
#include <wx/panel.h>
#include <wx/string.h>

#include "ocpn_plugin.h"

namespace ci_ui {

struct InspectorProperty {
  wxString label;
  wxString value;
  std::vector<wxColour> colours;
};

struct ObjectInspectorData {
  wxString title;
  wxString objectName;
  wxString featureClass;
  wxString geometry;

  int cardinalCategory = 0;  // CATCAM: 1=N, 2=E, 3=S, 4=W
  wxString cardinalLabel;
  wxString cardinalColours;

  wxString primaryValue;
  wxString primaryLabel;

  wxString lightSummary;
  wxString lightRange;
  std::vector<wxColour> lightColours;

  std::vector<InspectorProperty> properties;

  bool scaleHidden = false;
  wxString technical;
};

class ObjectInspectorPanel : public wxPanel {
public:
  explicit ObjectInspectorPanel(wxWindow *parent);

  void SetScheme(PI_ColorScheme scheme);
  void SetData(const ObjectInspectorData &data);
  void SetCloseHandler(const std::function<void()> &handler);

private:
  void RecalculateSize();
  void OnPaint(wxPaintEvent &event);
  void OnLeftDown(wxMouseEvent &event);
  void OnLeftUp(wxMouseEvent &event);
  void OnMotion(wxMouseEvent &event);
  void OnLeave(wxMouseEvent &event);

  ObjectInspectorData m_data;
  PI_ColorScheme m_scheme = PI_GLOBAL_COLOR_SCHEME_DAY;
  std::function<void()> m_closeHandler;

  wxRect m_closeRect;
  wxRect m_technicalRect;
  bool m_closeHover = false;
  bool m_technicalHover = false;
  bool m_technicalExpanded = false;
  bool m_dragging = false;
  wxPoint m_dragStartMouse;
  wxPoint m_dragStartPanel;
};

}  // namespace ci_ui

#endif  // CHARTINSPECTOR_OBJECT_INSPECTOR_PANEL_H
