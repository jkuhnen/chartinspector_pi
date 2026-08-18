set(ROOT "${CMAKE_CURRENT_LIST_DIR}/..")
get_filename_component(ROOT "${ROOT}" ABSOLUTE)
set(HEADER "${ROOT}/src/chartinspector_pi.h")
set(CPP "${ROOT}/src/chartinspector_pi.cpp")
set(CMAKELISTS "${ROOT}/CMakeLists.txt")

foreach(FILE_PATH "${HEADER}" "${CPP}" "${CMAKELISTS}")
  if(NOT EXISTS "${FILE_PATH}")
    message(FATAL_ERROR "Chart Inspector source file not found: ${FILE_PATH}")
  endif()
endforeach()

function(replace_section INPUT_VAR START_MARKER END_MARKER REPLACEMENT OUTPUT_VAR)
  set(TEXT "${${INPUT_VAR}}")
  string(FIND "${TEXT}" "${START_MARKER}" START_POS)
  if(START_POS EQUAL -1)
    message(FATAL_ERROR "Could not find section start: ${START_MARKER}")
  endif()
  string(FIND "${TEXT}" "${END_MARKER}" END_POS)
  if(END_POS EQUAL -1 OR END_POS LESS START_POS)
    message(FATAL_ERROR "Could not find section end: ${END_MARKER}")
  endif()
  string(SUBSTRING "${TEXT}" 0 ${START_POS} PREFIX)
  string(SUBSTRING "${TEXT}" ${END_POS} -1 SUFFIX)
  set(${OUTPUT_VAR} "${PREFIX}${REPLACEMENT}${SUFFIX}" PARENT_SCOPE)
endfunction()

file(READ "${HEADER}" H)
if(NOT H MATCHES "HitTestV5Fn")
  string(REPLACE "#include <wx/wx.h>"
                 "#include <wx/wx.h>\n\n#include <vector>"
                 H "${H}")

  set(V3_TYPE [=[  using HitTestV3Fn = bool (*)(int canvasIndex, double lat, double lon,
                               double radiusPixels, const char *featureFilter,
                               char *feature, int featureSize, char *objectName,
                               int objectNameSize, char *attributes,
                               int attributesSize, int *primitiveType,
                               double *markerLat, double *markerLon);]=])
  set(V5_TYPES [=[  using HitTestV3Fn = bool (*)(int canvasIndex, double lat, double lon,
                               double radiusPixels, const char *featureFilter,
                               char *feature, int featureSize, char *objectName,
                               int objectNameSize, char *attributes,
                               int attributesSize, int *primitiveType,
                               double *markerLat, double *markerLon);
  using HitTestV5Fn = bool (*)(
      int canvasIndex, double lat, double lon, double radiusPixels,
      const char *featureFilter, char *feature, int featureSize,
      char *objectName, int objectNameSize, char *attributes,
      int attributesSize, int *primitiveType, double *markerLat,
      double *markerLon, double *geometryLatLon, int geometryCapacityPoints,
      int *geometryPointCount, int *partOffsets, int partCapacity,
      int *partCount);]=])
  string(REPLACE "${V3_TYPE}" "${V5_TYPES}" H "${H}")

  string(REPLACE
      "  int m_lastPrimitiveType = 1;  // 1 point, 2 line, 3 area\n  bool m_hasVectorObject = false;"
      "  int m_lastPrimitiveType = 1;  // 1 point, 2 line, 3 area\n  std::vector<double> m_lastGeometryLatLon;  // lat/lon pairs from V5\n  std::vector<int> m_lastGeometryParts;     // point-index part starts\n  bool m_hasVectorObject = false;"
      H "${H}")

  string(REPLACE
      "  HitTestV3Fn m_hitTestV3 = nullptr;\n  HitTestV3Fn m_hitTestV4 = nullptr;"
      "  HitTestV3Fn m_hitTestV3 = nullptr;\n  HitTestV3Fn m_hitTestV4 = nullptr;\n  HitTestV5Fn m_hitTestV5 = nullptr;"
      H "${H}")

  if(NOT H MATCHES "HitTestV5Fn")
    message(FATAL_ERROR "Failed to add V5 declarations to chartinspector_pi.h")
  endif()
  file(WRITE "${HEADER}" "${H}")
endif()

file(READ "${CPP}" C)
if(NOT C MATCHES "OCPNChartInspectorHitTestV5")
  string(REPLACE
      "  if (host) {\n    m_hitTestV4 = reinterpret_cast<HitTestV3Fn>("
      "  if (host) {\n    m_hitTestV5 = reinterpret_cast<HitTestV5Fn>(\n        GetProcAddress(host, \"OCPNChartInspectorHitTestV5\"));\n    m_hitTestV4 = reinterpret_cast<HitTestV3Fn>("
      C "${C}")

  string(REPLACE
      "int ChartInspectorPi::GetPlugInVersionMinor() { return 8; }"
      "int ChartInspectorPi::GetPlugInVersionMinor() { return 3; }"
      C "${C}")

  string(REPLACE
      "  m_lastPrimitiveType = 1;\n}"
      "  m_lastPrimitiveType = 1;\n  m_lastGeometryLatLon.clear();\n  m_lastGeometryParts.clear();\n}"
      C "${C}")

  set(UPDATE_HOVER [=[void ChartInspectorPi::UpdateHoverObject() {
  if (!m_enabled ||
      (!m_hitTestV5 && !m_hitTestV4 && !m_hitTestV3 && !m_hitTestV2 &&
       !m_hitTest) ||
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

  m_lastGeometryLatLon.clear();
  m_lastGeometryParts.clear();

  if (m_hitTestV5) {
    const int kMaxGeometryPoints = 4096;
    const int kMaxGeometryParts = 128;
    std::vector<double> geometry(kMaxGeometryPoints * 2, 0.0);
    std::vector<int> parts(kMaxGeometryParts, 0);
    int geometryPointCount = 0;
    int partCount = 0;
    found = m_hitTestV5(
        0, m_cursorLat, m_cursorLon, static_cast<double>(m_hitRadiusPixels),
        filter.data(), feature, static_cast<int>(sizeof(feature)), objectName,
        static_cast<int>(sizeof(objectName)), attributes,
        static_cast<int>(sizeof(attributes)), &primitiveType, &markerLat,
        &markerLon, geometry.data(), kMaxGeometryPoints,
        &geometryPointCount, parts.data(), kMaxGeometryParts, &partCount);

    if (found && geometryPointCount > 0) {
      geometryPointCount = std::min(geometryPointCount, kMaxGeometryPoints);
      m_lastGeometryLatLon.assign(
          geometry.begin(), geometry.begin() + geometryPointCount * 2);
      partCount = std::min(partCount, kMaxGeometryParts);
      if (partCount > 0)
        m_lastGeometryParts.assign(parts.begin(), parts.begin() + partCount);
      if (m_lastGeometryParts.empty()) m_lastGeometryParts.push_back(0);
    }
  } else if (m_hitTestV4 || m_hitTestV3) {
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

]=])
  replace_section(C "void ChartInspectorPi::UpdateHoverObject() {"
                  "bool ChartInspectorPi::MouseEventHook"
                  "${UPDATE_HOVER}" C)

  set(RENDER_DC [=[bool ChartInspectorPi::RenderOverlay(wxDC &dc, PlugIn_ViewPort *vp) {
  if (!vp || !m_enabled || !m_hasVectorObject) return false;

  dc.SetBrush(*wxTRANSPARENT_BRUSH);
  dc.SetPen(wxPen(wxColour(0, 255, 255), 4));

  const int pointCount = static_cast<int>(m_lastGeometryLatLon.size() / 2);
  if (m_lastPrimitiveType > 1 && pointCount >= 2 &&
      !m_lastGeometryParts.empty()) {
    for (size_t partIndex = 0; partIndex < m_lastGeometryParts.size();
         ++partIndex) {
      const int start = m_lastGeometryParts[partIndex];
      const int end = partIndex + 1 < m_lastGeometryParts.size()
                          ? m_lastGeometryParts[partIndex + 1]
                          : pointCount;
      if (start < 0 || end > pointCount || end - start < 2) continue;

      wxPoint first;
      wxPoint previous;
      GetCanvasPixLL(vp, &first, m_lastGeometryLatLon[start * 2],
                     m_lastGeometryLatLon[start * 2 + 1]);
      previous = first;
      for (int i = start + 1; i < end; ++i) {
        wxPoint current;
        GetCanvasPixLL(vp, &current, m_lastGeometryLatLon[i * 2],
                       m_lastGeometryLatLon[i * 2 + 1]);
        dc.DrawLine(previous, current);
        previous = current;
      }
      if (m_lastPrimitiveType == 3 && end - start > 2)
        dc.DrawLine(previous, first);
    }
    return true;
  }

  wxPoint p;
  GetCanvasPixLL(vp, &p, m_lastObjectLat, m_lastObjectLon);
  dc.SetPen(wxPen(wxColour(0, 255, 255), 3));
  dc.DrawCircle(p, 12);
  return true;
}

]=])
  replace_section(C "bool ChartInspectorPi::RenderOverlay(wxDC &dc, PlugIn_ViewPort *vp) {"
                  "bool ChartInspectorPi::RenderGLOverlayMultiCanvas"
                  "${RENDER_DC}" C)

  set(RENDER_GL [=[bool ChartInspectorPi::RenderGLOverlayMultiCanvas(wxGLContext *pcontext,
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
  glColor4f(0.0f, 1.0f, 1.0f, 0.9f);

  const int pointCount = static_cast<int>(m_lastGeometryLatLon.size() / 2);
  if (m_lastPrimitiveType > 1 && pointCount >= 2 &&
      !m_lastGeometryParts.empty()) {
    glLineWidth(4.0f);
    for (size_t partIndex = 0; partIndex < m_lastGeometryParts.size();
         ++partIndex) {
      const int start = m_lastGeometryParts[partIndex];
      const int end = partIndex + 1 < m_lastGeometryParts.size()
                          ? m_lastGeometryParts[partIndex + 1]
                          : pointCount;
      if (start < 0 || end > pointCount || end - start < 2) continue;
      glBegin(m_lastPrimitiveType == 3 ? GL_LINE_LOOP : GL_LINE_STRIP);
      for (int i = start; i < end; ++i) {
        wxPoint p;
        GetCanvasPixLL(vp, &p, m_lastGeometryLatLon[i * 2],
                       m_lastGeometryLatLon[i * 2 + 1]);
        glVertex2f(static_cast<float>(p.x), static_cast<float>(p.y));
      }
      glEnd();
    }
  } else {
    wxPoint p;
    GetCanvasPixLL(vp, &p, m_lastObjectLat, m_lastObjectLon);
    const float r = 12.0f;
    glLineWidth(3.0f);
    glBegin(GL_LINE_LOOP);
    for (int i = 0; i < 32; ++i) {
      const float a = static_cast<float>(i) * 6.28318530718f / 32.0f;
      glVertex2f(static_cast<float>(p.x) + r * cosf(a),
                 static_cast<float>(p.y) + r * sinf(a));
    }
    glEnd();
  }

  glPopMatrix();
  glMatrixMode(GL_PROJECTION);
  glPopMatrix();
  glMatrixMode(GL_MODELVIEW);
  glPopAttrib();
  return true;
}
]=])
  replace_section(C "bool ChartInspectorPi::RenderGLOverlayMultiCanvas"
                  "\n}"
                  "${RENDER_GL}" C_TMP)

  # The generic end marker above would find the first closing brace inside the
  # function.  Since RenderGLOverlayMultiCanvas is the final function in this
  # file, replace from its start to EOF instead.
  string(FIND "${C}" "bool ChartInspectorPi::RenderGLOverlayMultiCanvas" GL_START)
  if(GL_START EQUAL -1)
    message(FATAL_ERROR "Could not locate RenderGLOverlayMultiCanvas")
  endif()
  string(SUBSTRING "${C}" 0 ${GL_START} GL_PREFIX)
  set(C "${GL_PREFIX}${RENDER_GL}")

  if(NOT C MATCHES "OCPNChartInspectorHitTestV5")
    message(FATAL_ERROR "Failed to patch chartinspector_pi.cpp for V5")
  endif()
  file(WRITE "${CPP}" "${C}")
endif()

file(READ "${CMAKELISTS}" CL)
string(REPLACE "project(chartinspector VERSION 0.2.8.0 LANGUAGES CXX)"
               "project(chartinspector VERSION 0.3.0.0 LANGUAGES CXX)"
               CL "${CL}")
file(WRITE "${CMAKELISTS}" "${CL}")

message(STATUS "Installed Chart Inspector plugin-side V5 geometry selection.")
