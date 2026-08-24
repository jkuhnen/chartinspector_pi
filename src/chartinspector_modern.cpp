#include "chartinspector_pi.h"
#include "ui/object_inspector_panel.h"

// Compile the proven core unchanged and rename presentation entry points only.
#define DeInit DeInitLegacy
#define GetPlugInVersionMinor GetPlugInVersionMinorLegacy
#define SetColorScheme SetColorSchemeLegacy
#define MouseEventHook MouseEventHookLegacy
#define UpdateHoverGeometry UpdateHoverGeometryLegacy
#define UpdateHoverInfoPanel UpdateHoverInfoPanelLegacy
#define HideHoverInfoPanel HideHoverInfoPanelLegacy
#define BuildInfoPanel BuildInfoPanelLegacy
#define ShowObjectPopup ShowObjectPopupLegacy
#include "chartinspector_pi.cpp"
#undef ShowObjectPopup
#undef BuildInfoPanel
#undef HideHoverInfoPanel
#undef UpdateHoverInfoPanel
#undef UpdateHoverGeometry
#undef MouseEventHook
#undef SetColorScheme
#undef GetPlugInVersionMinor
#undef DeInit

int ChartInspectorPi::GetPlugInVersionMinor() { return 4; }

bool ChartInspectorPi::DeInit() {
  if (m_hoverModernPanel) {
    m_hoverModernPanel->Destroy();
    m_hoverModernPanel = nullptr;
  }
  return DeInitLegacy();
}

void ChartInspectorPi::SetColorScheme(PI_ColorScheme cs) {
  m_colorScheme = cs;
  BuildToolbarBitmaps();
  UpdateToolbarVisual();
  if (m_hoverModernPanel) m_hoverModernPanel->SetScheme(cs);
  if (auto *panel = dynamic_cast<ci_ui::ObjectInspectorPanel *>(m_infoPanel))
    panel->SetScheme(cs);
}

void ChartInspectorPi::PresentModernInspector(
    ci_ui::ObjectInspectorPanel *panel, const wxString &feature,
    const wxString &objectName, const wxString &attributes, int geometryType,
    const wxString &associatedLightAttributes, bool scaleHidden) {
  if (!panel || feature.IsEmpty()) return;

  ci_ui::ObjectInspectorData data;
  data.title = CI_CleanDecodedCodes(m_s57Catalog.ObjectName(feature));
  if (data.title.IsEmpty()) data.title = feature;
  data.objectName = objectName;
  data.featureClass = feature;
  data.geometry = geometryType == 3 ? "Area" : geometryType == 2 ? "Line" : "Point";
  data.scaleHidden = scaleHidden;

  const wxString catcamRaw = m_s57Catalog.RawAttributeValue(attributes, "CATCAM");
  long catcam = 0;
  if (feature == "BOYCAR" && catcamRaw.ToLong(&catcam) && catcam >= 1 && catcam <= 4) {
    data.cardinalCategory = static_cast<int>(catcam);
    switch (catcam) {
      case 1: data.cardinalLabel = "North cardinal"; break;
      case 2: data.cardinalLabel = "East cardinal"; break;
      case 3: data.cardinalLabel = "South cardinal"; break;
      case 4: data.cardinalLabel = "West cardinal"; break;
    }
    data.cardinalColours = CI_DecodeColours(
        m_s57Catalog.RawAttributeValue(attributes, "COLOUR"));
    data.cardinalColours.Replace(", ", " / ");
    data.cardinalColours.MakeLower();
  }

  const CI_NavigationInfo info = CI_BuildNavigationInfo(
      m_s57Catalog, feature, objectName, attributes, geometryType,
      m_showTechnicalData);

  if (!info.primary.IsEmpty()) {
    const int colon = info.primary.Find(':');
    if (colon == wxNOT_FOUND) {
      data.primaryValue = info.primary;
      data.primaryLabel = "Navigation value";
    } else {
      data.primaryLabel = info.primary.Left(colon);
      data.primaryValue = info.primary.Mid(colon + 1);
      data.primaryLabel.Trim(true); data.primaryLabel.Trim(false);
      data.primaryValue.Trim(true); data.primaryValue.Trim(false);
    }
  }

  const wxString colourRaw = m_s57Catalog.RawAttributeValue(attributes, "COLOUR");
  wxStringTokenizer lines(info.details, "\n", wxTOKEN_STRTOK);
  while (lines.HasMoreTokens()) {
    wxString line = lines.GetNextToken();
    line.Trim(true); line.Trim(false);
    if (line.IsEmpty()) continue;
    const int colon = line.Find(':');
    if (colon == wxNOT_FOUND) continue;

    ci_ui::InspectorProperty prop;
    prop.label = line.Left(colon);
    prop.value = line.Mid(colon + 1);
    prop.label.Trim(true); prop.label.Trim(false);
    prop.value.Trim(true); prop.value.Trim(false);
    if (prop.label == "Name") continue;
    if (data.cardinalCategory &&
        (prop.label == "Category of cardinal" || prop.label == "Color"))
      continue;

    if (prop.label == "Color") {
      wxStringTokenizer colours(colourRaw, ",", wxTOKEN_STRTOK);
      while (colours.HasMoreTokens()) {
        wxString token = colours.GetNextToken();
        token.Trim(true); token.Trim(false);
        if (!token.IsEmpty()) prop.colours.push_back(SignalColour(token));
      }
    }
    data.properties.push_back(prop);
  }

  wxString lightAttributes = associatedLightAttributes;
  if (feature == "LIGHTS") lightAttributes = attributes;
  if (!lightAttributes.IsEmpty()) {
    data.lightSummary = CI_LightSummary(m_s57Catalog, lightAttributes);
    const wxString range = m_s57Catalog.RawAttributeValue(lightAttributes, "VALNMR");
    double nm = 0.0;
    if (CI_ParseNumber(range, &nm)) data.lightRange = wxString::Format("%g NM", nm);
  }

  data.technical = "S-57 class: " + feature + "\nGeometry: " + data.geometry;
  if (m_showTechnicalData && !info.technical.IsEmpty()) {
    wxString extra = info.technical;
    wxStringTokenizer technicalLines(extra, "\n", wxTOKEN_STRTOK);
    int skip = 2;
    while (technicalLines.HasMoreTokens()) {
      wxString t = technicalLines.GetNextToken();
      if (skip > 0) { --skip; continue; }
      if (!t.IsEmpty()) data.technical += "\n" + t;
    }
  }

  panel->SetScheme(m_colorScheme);
  panel->SetData(data);
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
  HideHoverInfoPanel();
  BuildInfoPanel(canvas);
  auto *panel = dynamic_cast<ci_ui::ObjectInspectorPanel *>(m_infoPanel);
  if (!panel) return;

  PresentModernInspector(panel, m_lastFeature, m_lastObjectName, m_lastAttributes,
                         m_lastPrimitiveType, m_associatedLightAttributes, false);
  const wxSize size = panel->GetSize();
  const wxSize canvasSize = canvas->GetClientSize();
  panel->Move(std::max(12, canvasSize.GetWidth() - size.GetWidth() - 14), 14);
  panel->Show();
  panel->Raise();
}

void ChartInspectorPi::HideHoverInfoPanel() {
  m_hoverInfoKey.clear();
  if (m_hoverModernPanel) m_hoverModernPanel->Hide();
}

void ChartInspectorPi::UpdateHoverInfoPanel(
    const wxString &feature, const wxString &objectName,
    const wxString &attributes, int geometryType,
    const wxString &associatedLightAttributes) {
  if (!m_enabled || feature.IsEmpty()) {
    HideHoverInfoPanel();
    return;
  }
  if (m_infoPanel && m_infoPanel->IsShown()) {
    HideHoverInfoPanel();
    return;
  }

  wxWindow *canvas = GetOCPNCanvasWindow();
  if (!canvas) return;
  if (!m_hoverModernPanel) {
    m_hoverModernPanel = new ci_ui::ObjectInspectorPanel(canvas);
    m_hoverModernPanel->SetCloseHandler([this]() { HideHoverInfoPanel(); });
    m_hoverModernPanel->Move(24, 70);
  }

  PresentModernInspector(m_hoverModernPanel, feature, objectName, attributes,
                         geometryType, associatedLightAttributes,
                         m_hoverScaleHidden);
  m_hoverModernPanel->Show();
  m_hoverModernPanel->Raise();
}

void ChartInspectorPi::UpdateHoverGeometry(bool force) {
#ifdef _WIN32
  if (!m_enabled || !m_hasCursorPosition || !m_hasMousePosition) {
    ClearHoverGeometry();
    return;
  }
  const long long now = wxGetUTCTimeMillis().GetValue();
  const int dx = m_mousePosition.x - m_lastHoverQueryPosition.x;
  const int dy = m_mousePosition.y - m_lastHoverQueryPosition.y;
  if (!force && now - m_lastHoverQueryMs < 75) return;
  if (!force && m_lastHoverQueryMs && dx * dx + dy * dy < 9) return;

  HMODULE host = GetModuleHandleW(nullptr);
  auto queryFn = host ? reinterpret_cast<CI_QueryVectorV1>(
      GetProcAddress(host, "QueryVectorChartObjectsV1")) : nullptr;
  if (!queryFn) { ClearHoverGeometry(); return; }

  CI_VectorQueryV1 q{};
  q.struct_size = sizeof(q);
  q.lat = m_cursorLat;
  q.lon = m_cursorLon;
  q.search_radius_pixels = static_cast<double>(std::max(8, m_hitRadiusPixels));
  q.flags = CI_SKIP_ATTRIBUTES;
  q.geometry_mask = CI_GEOMETRY_ALL;
  q.max_objects = 8;
  q.max_points_per_object = 512;
  q.exclude_feature_classes_utf8 =
      "LNDARE,COALNE,DEPARE,DEPCNT,M_NPUB,M_COVR,M_NSYS,MAGVAR,SEAARE";

  CI_HoverCandidate best;
  best.cursorLat = m_cursorLat;
  best.cursorLon = m_cursorLon;
  best.includeFilter = m_featureFilter;
  m_hoverScaleHidden = false;
  queryFn(0, &q, CI_CollectHover, &best);

  if (m_includeScaleHidden && best.points.empty()) {
    CI_HoverCandidate hidden;
    hidden.cursorLat = m_cursorLat;
    hidden.cursorLon = m_cursorLon;
    hidden.includeFilter = m_featureFilter;
    q.flags = CI_SKIP_ATTRIBUTES | CI_INCLUDE_NON_RENDERED |
              CI_PREFER_DETAILED_CHART;
    queryFn(0, &q, CI_CollectHiddenNavigationHover, &hidden);
    if (!hidden.points.empty()) {
      best = hidden;
      m_hoverScaleHidden = true;
    }
  }

  if (!best.points.empty()) {
    const wxString key = best.feature + "|" +
        wxString::Format("%u|%.8f|%.8f", best.geometry,
                         best.points[0].lat, best.points[0].lon);
    if (key != m_hoverInfoKey) {
      CI_HoverCandidate details;
      details.cursorLat = m_cursorLat;
      details.cursorLon = m_cursorLon;
      details.includeFilter = m_featureFilter;
      q.flags &= ~CI_SKIP_ATTRIBUTES;
      q.max_points_per_object = 16384;
      queryFn(0, &q, CI_CollectHover, &details);
      if (!details.points.empty()) {
        best = details;
        wxString lightAttributes;
        if (details.geometry == 1 &&
            (details.feature.StartsWith("BOY") || details.feature.StartsWith("BCN"))) {
          CI_HoverCandidate light;
          light.cursorLat = details.points[0].lat;
          light.cursorLon = details.points[0].lon;
          light.includeFilter = "LIGHTS";
          auto lq = q;
          lq.lat = light.cursorLat;
          lq.lon = light.cursorLon;
          lq.search_radius_pixels = std::max(8.0, static_cast<double>(m_hitRadiusPixels));
          lq.flags &= ~CI_SKIP_ATTRIBUTES;
          lq.geometry_mask = 1u;
          lq.max_objects = 8;
          lq.max_points_per_object = 16;
          queryFn(0, &lq, CI_CollectHover, &light);
          if (light.feature == "LIGHTS") lightAttributes = light.attributes;
        }
        UpdateHoverInfoPanel(details.feature, details.objectName, details.attributes,
                             static_cast<int>(details.geometry), lightAttributes);
        m_hoverInfoKey = key;
      }
    }
  }

  m_lastHoverQueryMs = now;
  m_lastHoverQueryPosition = m_mousePosition;
  if (best.points.empty()) { ClearHoverGeometry(); return; }
  m_hoverPoints.clear();
  m_hoverParts.clear();
  for (const auto &p : best.points) m_hoverPoints.push_back({p.lat, p.lon});
  for (const auto &part : best.parts)
    m_hoverParts.push_back({part.firstPoint, part.pointCount});
  m_hoverGeometryType = static_cast<int>(best.geometry);
  m_hoverFeature = best.feature;
  m_hasHoverGeometry = true;
#else
  (void)force;
#endif
}

bool ChartInspectorPi::MouseEventHook(wxMouseEvent &event) {
  m_mousePosition = event.GetPosition();
  m_hasMousePosition = true;
  UpdateHoverGeometry(event.LeftDown());
  if (event.LeftDown()) UpdateHoverObject();
  if (event.LeftDown()) {
    if (m_hasVectorObject) ShowObjectPopup();
    else HideObjectPopup();
  }
  wxWindow *canvas = GetOCPNCanvasWindow();
  if (canvas) RequestRefresh(canvas);
  return false;
}
