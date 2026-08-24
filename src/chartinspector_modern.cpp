#include "chartinspector_pi.h"
#include "ui/object_inspector_panel.h"

// Keep the proven query/hit-test/overlay implementation byte-for-byte intact.
// Only the four interaction-layer entry points are renamed while the core is
// compiled into this translation unit; modern replacements follow below.
#define SetColorScheme SetColorSchemeLegacy
#define MouseEventHook MouseEventHookLegacy
#define BuildInfoPanel BuildInfoPanelLegacy
#define ShowObjectPopup ShowObjectPopupLegacy
#include "chartinspector_pi.cpp"
#undef ShowObjectPopup
#undef BuildInfoPanel
#undef MouseEventHook
#undef SetColorScheme

void ChartInspectorPi::SetColorScheme(PI_ColorScheme cs) {
  m_colorScheme = cs;
  BuildToolbarBitmaps();
  UpdateToolbarVisual();
  ApplyHoverWindowTheme();

  if (auto *panel = dynamic_cast<ci_ui::ObjectInspectorPanel *>(m_infoPanel)) {
    panel->SetScheme(m_colorScheme);
    panel->Refresh(false);
  }
}

void ChartInspectorPi::BuildInfoPanel(wxWindow *canvas) {
  if (m_infoPanel || !canvas) return;

  auto *panel = new ci_ui::ObjectInspectorPanel(canvas);
  panel->SetScheme(m_colorScheme);
  panel->SetCloseHandler([this]() { HideObjectPopup(); });
  m_infoPanel = panel;
  m_infoPanel->Hide();
}

void ChartInspectorPi::ShowObjectPopup() {
  if (!m_enabled || !m_hasVectorObject || m_lastFeature.IsEmpty()) return;

  wxWindow *canvas = GetOCPNCanvasWindow();
  if (!canvas) return;
  BuildInfoPanel(canvas);

  auto *panel = dynamic_cast<ci_ui::ObjectInspectorPanel *>(m_infoPanel);
  if (!panel) return;

  ci_ui::ObjectInspectorData data;
  data.title = CI_CleanDecodedCodes(m_s57Catalog.ObjectName(m_lastFeature));
  if (data.title.IsEmpty()) data.title = m_lastFeature;
  data.objectName = m_lastObjectName;
  data.featureClass = m_lastFeature;
  data.geometry = m_lastPrimitiveType == 3 ? "Area" :
                  m_lastPrimitiveType == 2 ? "Line" : "Point";

  // Cardinal topmarks are UI pictograms derived directly from the ENC CATCAM
  // value. They are intentionally not presented as replacement S-52 symbols.
  const wxString catcamRaw =
      m_s57Catalog.RawAttributeValue(m_lastAttributes, "CATCAM");
  long catcam = 0;
  if (m_lastFeature == "BOYCAR" && catcamRaw.ToLong(&catcam) &&
      catcam >= 1 && catcam <= 4) {
    data.cardinalCategory = static_cast<int>(catcam);
    switch (catcam) {
      case 1: data.cardinalLabel = "North cardinal"; break;
      case 2: data.cardinalLabel = "East cardinal"; break;
      case 3: data.cardinalLabel = "South cardinal"; break;
      case 4: data.cardinalLabel = "West cardinal"; break;
    }
    data.cardinalColours = CI_DecodeColours(
        m_s57Catalog.RawAttributeValue(m_lastAttributes, "COLOUR"));
    data.cardinalColours.Replace(", ", " / ");
    data.cardinalColours.MakeLower();
  }

  const CI_NavigationInfo info = CI_BuildNavigationInfo(
      m_s57Catalog, m_lastFeature, m_lastObjectName, m_lastAttributes,
      m_lastPrimitiveType, m_showTechnicalData);

  if (!info.primary.IsEmpty()) {
    const int colon = info.primary.Find(':');
    if (colon == wxNOT_FOUND) {
      data.primaryValue = info.primary;
      data.primaryLabel = "Navigation value";
    } else {
      data.primaryLabel = info.primary.Left(colon);
      data.primaryValue = info.primary.Mid(colon + 1);
      data.primaryLabel.Trim(true);
      data.primaryLabel.Trim(false);
      data.primaryValue.Trim(true);
      data.primaryValue.Trim(false);
    }
  }

  const wxString colourRaw =
      m_s57Catalog.RawAttributeValue(m_lastAttributes, "COLOUR");
  wxStringTokenizer detailLines(info.details, "\n", wxTOKEN_STRTOK);
  while (detailLines.HasMoreTokens()) {
    wxString line = detailLines.GetNextToken();
    line.Trim(true);
    line.Trim(false);
    if (line.IsEmpty()) continue;

    const int colon = line.Find(':');
    if (colon == wxNOT_FOUND) continue;

    ci_ui::InspectorProperty property;
    property.label = line.Left(colon);
    property.value = line.Mid(colon + 1);
    property.label.Trim(true);
    property.label.Trim(false);
    property.value.Trim(true);
    property.value.Trim(false);

    if (property.label == "Name") continue;
    if (data.cardinalCategory &&
        (property.label == "Category of cardinal" ||
         property.label == "Color"))
      continue;

    if (property.label == "Color") {
      wxStringTokenizer colours(colourRaw, ",", wxTOKEN_STRTOK);
      while (colours.HasMoreTokens()) {
        wxString token = colours.GetNextToken();
        token.Trim(true);
        token.Trim(false);
        if (!token.IsEmpty()) property.colours.push_back(SignalColour(token));
      }
    }

    data.properties.push_back(property);
  }

  wxString lightAttributes;
  if (m_lastFeature == "LIGHTS")
    lightAttributes = m_lastAttributes;
  else if (m_hasAssociatedLight)
    lightAttributes = m_associatedLightAttributes;

  if (!lightAttributes.IsEmpty()) {
    data.lightSummary = CI_LightSummary(m_s57Catalog, lightAttributes);

    const wxString range =
        m_s57Catalog.RawAttributeValue(lightAttributes, "VALNMR");
    double nm = 0.0;
    if (CI_ParseNumber(range, &nm))
      data.lightRange = wxString::Format("%g NM", nm);

    const wxString colour =
        m_s57Catalog.RawAttributeValue(lightAttributes, "COLOUR");
    wxStringTokenizer colours(colour, ",", wxTOKEN_STRTOK);
    while (colours.HasMoreTokens()) {
      wxString token = colours.GetNextToken();
      token.Trim(true);
      token.Trim(false);
      if (!token.IsEmpty()) data.lightColours.push_back(SignalColour(token));
    }
  }

  // Class and geometry remain available in the disclosure even when the
  // preference for verbose raw S-57 metadata is disabled.
  data.technical = "S-57 class: " + m_lastFeature +
                   "\nGeometry: " + data.geometry;
  if (m_showTechnicalData && !info.technical.IsEmpty()) {
    wxString extra = info.technical;
    if (extra.StartsWith("S-57 class:")) {
      const int secondLine = extra.Find('\n');
      if (secondLine != wxNOT_FOUND) {
        extra = extra.Mid(secondLine + 1);
        const int thirdLine = extra.Find('\n');
        if (thirdLine != wxNOT_FOUND)
          extra = extra.Mid(thirdLine + 1);
        else
          extra.clear();
      }
    }
    if (!extra.IsEmpty()) data.technical += "\n" + extra;

    if (m_hasAssociatedLight) {
      wxString lightTechnical;
      m_s57Catalog.FormatAttributes(m_associatedLightAttributes,
                                    &lightTechnical);
      if (!lightTechnical.IsEmpty())
        data.technical += "\nAssociated LIGHTS\n" + lightTechnical;
    }
  }

  panel->SetScheme(m_colorScheme);
  panel->SetData(data);

  const wxSize size = panel->GetSize();
  const wxSize canvasSize = canvas->GetClientSize();
  panel->Move(std::max(12, canvasSize.GetWidth() - size.GetWidth() - 14), 14);
  panel->Show();
  panel->Raise();
}

bool ChartInspectorPi::MouseEventHook(wxMouseEvent &event) {
  m_mousePosition = event.GetPosition();
  m_hasMousePosition = true;
  UpdateHoverGeometry(event.LeftDown());

  if (event.LeftDown()) UpdateHoverObject();
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
