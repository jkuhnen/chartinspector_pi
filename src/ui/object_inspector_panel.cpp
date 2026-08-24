#include "object_inspector_panel.h"
#include "app_style.h"

#include <wx/dcbuffer.h>
#include <wx/settings.h>
#include <wx/tokenzr.h>

namespace ci_ui {
namespace {

wxFont MakeFont(const wxFont &base, int delta, wxFontWeight weight) {
  wxFont f = base;
  f.SetStyle(wxFONTSTYLE_NORMAL);
  f.SetWeight(weight);
  f.SetPointSize(wxMax(7, f.GetPointSize() + delta));
  return f;
}

void DrawText(wxDC &dc, const wxString &text, int x, int y,
              const wxFont &font, const wxColour &colour) {
  dc.SetFont(font);
  dc.SetTextForeground(colour);
  dc.DrawText(text, x, y);
}

void DrawRule(wxDC &dc, int y, int width, const wxColour &colour) {
  dc.SetPen(wxPen(colour, 1));
  dc.DrawLine(18, y, width - 18, y);
}

void DrawCardinal(wxDC &dc, int x, int y, int catcam,
                  const wxColour &colour) {
  dc.SetPen(wxPen(colour, 2));
  dc.SetBrush(*wxTRANSPARENT_BRUSH);
  auto up = [&](int yy) {
    dc.DrawLine(x - 8, yy + 10, x, yy);
    dc.DrawLine(x, yy, x + 8, yy + 10);
  };
  auto down = [&](int yy) {
    dc.DrawLine(x - 8, yy, x, yy + 10);
    dc.DrawLine(x, yy + 10, x + 8, yy);
  };
  if (catcam == 1) { up(y); up(y + 7); }
  else if (catcam == 2) { up(y); down(y + 8); }
  else if (catcam == 3) { down(y); down(y + 7); }
  else if (catcam == 4) { down(y); up(y + 8); }
}

wxString Ellipsize(wxDC &dc, const wxString &text, int maxWidth) {
  if (text.IsEmpty()) return text;
  wxCoord w = 0, h = 0;
  dc.GetTextExtent(text, &w, &h);
  if (w <= maxWidth) return text;
  wxString out = text;
  const wxString dots = "...";
  while (!out.IsEmpty()) {
    out.RemoveLast();
    dc.GetTextExtent(out + dots, &w, &h);
    if (w <= maxWidth) return out + dots;
  }
  return dots;
}

}  // namespace

ObjectInspectorPanel::ObjectInspectorPanel(wxWindow *parent)
    : wxPanel(parent, wxID_ANY, wxDefaultPosition, wxSize(370, 390), wxBORDER_NONE) {
  SetBackgroundStyle(wxBG_STYLE_PAINT);
  Bind(wxEVT_PAINT, &ObjectInspectorPanel::OnPaint, this);
  Bind(wxEVT_LEFT_DOWN, &ObjectInspectorPanel::OnLeftDown, this);
  Bind(wxEVT_LEFT_UP, &ObjectInspectorPanel::OnLeftUp, this);
  Bind(wxEVT_MOTION, &ObjectInspectorPanel::OnMotion, this);
  Bind(wxEVT_LEAVE_WINDOW, &ObjectInspectorPanel::OnLeave, this);
}

void ObjectInspectorPanel::SetScheme(PI_ColorScheme scheme) {
  m_scheme = scheme;
  Refresh(false);
}

void ObjectInspectorPanel::SetData(const ObjectInspectorData &data) {
  m_data = data;
  RecalculateSize();
  Refresh(false);
}

void ObjectInspectorPanel::SetCloseHandler(const std::function<void()> &handler) {
  m_closeHandler = handler;
}

void ObjectInspectorPanel::RecalculateSize() {
  int h = 142;
  if (!m_data.cardinalLabel.IsEmpty()) h += 62;
  if (!m_data.lightSummary.IsEmpty()) h += 68;
  if (!m_data.primaryValue.IsEmpty()) h += 58;
  h += static_cast<int>(m_data.properties.size()) * 25;
  if (m_data.scaleHidden) h += 28;
  h += 58;
  if (m_technicalExpanded && !m_data.technical.IsEmpty()) {
    int lines = 1;
    for (size_t i = 0; i < m_data.technical.length(); ++i)
      if (m_data.technical[i] == '\n') ++lines;
    h += lines * 22 + 8;
  }
  h = wxMax(245, wxMin(650, h));
  SetSize(wxSize(370, h));
  SetMinSize(wxSize(370, h));
}

void ObjectInspectorPanel::OnPaint(wxPaintEvent &) {
  wxAutoBufferedPaintDC dc(this);
  const AppPalette p = AppStyle::PaletteFor(m_scheme);
  dc.SetBackground(wxBrush(p.cardBackground));
  dc.Clear();

  const int w = GetClientSize().GetWidth();
  const wxFont base = GetFont();
  const wxFont tiny = MakeFont(base, -1, wxFONTWEIGHT_NORMAL);
  const wxFont label = MakeFont(base, 0, wxFONTWEIGHT_NORMAL);
  const wxFont value = MakeFont(base, 1, wxFONTWEIGHT_BOLD);
  const wxFont title = MakeFont(base, 3, wxFONTWEIGHT_BOLD);
  const wxFont hero = MakeFont(base, 6, wxFONTWEIGHT_BOLD);

  dc.SetPen(wxPen(p.cardBorder, 1));
  dc.SetBrush(*wxTRANSPARENT_BRUSH);
  dc.DrawRectangle(0, 0, w, GetClientSize().GetHeight());

  dc.SetPen(*wxTRANSPARENT_PEN);
  dc.SetBrush(wxBrush(p.windowBackground));
  dc.DrawRectangle(1, 1, w - 2, 35);
  DrawText(dc, "Object inspector", 14, 10, tiny, p.textSecondary);
  m_closeRect = wxRect(w - 36, 1, 35, 35);
  if (m_closeHover) {
    dc.SetBrush(wxBrush(p.cardBorder));
    dc.DrawRectangle(m_closeRect);
  }
  dc.SetPen(wxPen(p.textSecondary, 2));
  dc.DrawLine(w - 24, 12, w - 14, 22);
  dc.DrawLine(w - 14, 12, w - 24, 22);

  int y = 55;
  dc.SetFont(title);
  DrawText(dc, Ellipsize(dc, m_data.title, w - 36), 18, y, title, p.textPrimary);
  y += 28;
  if (!m_data.objectName.IsEmpty()) {
    dc.SetFont(value);
    DrawText(dc, Ellipsize(dc, m_data.objectName, w - 36), 18, y, value,
             p.textPrimary);
    y += 23;
  }
  wxString meta = m_data.featureClass;
  if (!m_data.geometry.IsEmpty()) meta += " | " + m_data.geometry;
  DrawText(dc, meta, 18, y, tiny, p.textSecondary);
  y += 27;
  DrawRule(dc, y, w, p.cardBorder);
  y += 17;

  if (!m_data.cardinalLabel.IsEmpty()) {
    DrawCardinal(dc, 32, y + 1, m_data.cardinalCategory, p.textPrimary);
    DrawText(dc, m_data.cardinalLabel, 50, y, value, p.textPrimary);
    y += 24;
    if (!m_data.cardinalColours.IsEmpty())
      DrawText(dc, m_data.cardinalColours, 50, y, label, p.textSecondary);
    y += 30;
  }

  if (!m_data.lightSummary.IsEmpty()) {
    DrawText(dc, m_data.lightSummary, 18, y, hero, p.textPrimary);
    if (!m_data.lightRange.IsEmpty())
      DrawText(dc, m_data.lightRange, 238, y + 4, value, p.textPrimary);
    y += 36;
    DrawText(dc, "Light characteristic", 18, y, tiny, p.textSecondary);
    if (!m_data.lightRange.IsEmpty())
      DrawText(dc, "Nominal range", 238, y, tiny, p.textSecondary);
    y += 26;
  }

  if (!m_data.primaryValue.IsEmpty()) {
    DrawText(dc, m_data.primaryValue, 18, y, hero, p.textPrimary);
    y += 33;
    DrawText(dc, m_data.primaryLabel, 18, y, tiny, p.textSecondary);
    y += 25;
  }

  const int valueColumn = 150;
  const int valueWidth = w - valueColumn - 20;
  for (const auto &prop : m_data.properties) {
    if (prop.value.IsEmpty()) continue;
    dc.SetFont(tiny);
    DrawText(dc, Ellipsize(dc, prop.label, 122), 18, y, tiny, p.textSecondary);
    int valueX = valueColumn;
    for (const wxColour &c : prop.colours) {
      dc.SetPen(wxPen(p.cardBorder, 1));
      dc.SetBrush(wxBrush(c));
      dc.DrawRectangle(valueX, y - 1, 14, 14);
      valueX += 19;
    }
    dc.SetFont(label);
    DrawText(dc, Ellipsize(dc, prop.value, valueWidth - (valueX - valueColumn)),
             valueX, y - 1, label, p.textPrimary);
    y += 25;
  }

  if (m_data.scaleHidden) {
    dc.SetPen(*wxTRANSPARENT_PEN);
    dc.SetBrush(wxBrush(p.accent));
    dc.DrawCircle(wxPoint(22, y + 7), 3);
    DrawText(dc, "Scale", 36, y, tiny, p.textSecondary);
    DrawText(dc, "Not shown at current scale", valueColumn, y - 1, label,
             p.textSecondary);
    y += 28;
  }

  DrawRule(dc, y, w, p.cardBorder);
  y += 7;
  m_technicalRect = wxRect(10, y, w - 20, 42);
  if (m_technicalHover) {
    dc.SetPen(*wxTRANSPARENT_PEN);
    dc.SetBrush(wxBrush(p.windowBackground));
    dc.DrawRectangle(m_technicalRect);
  }
  DrawText(dc, "Source / technical", 18, y + 13, tiny, p.textSecondary);
  dc.SetPen(wxPen(p.textSecondary, 2));
  const int cx = w - 24, cy = y + 21;
  if (m_technicalExpanded) {
    dc.DrawLine(cx - 4, cy + 2, cx, cy - 2);
    dc.DrawLine(cx, cy - 2, cx + 4, cy + 2);
  } else {
    dc.DrawLine(cx - 2, cy - 4, cx + 2, cy);
    dc.DrawLine(cx + 2, cy, cx - 2, cy + 4);
  }
  y += 47;

  if (m_technicalExpanded && !m_data.technical.IsEmpty()) {
    wxStringTokenizer lines(m_data.technical, "\n", wxTOKEN_STRTOK);
    while (lines.HasMoreTokens()) {
      dc.SetFont(tiny);
      const wxString line = Ellipsize(dc, lines.GetNextToken(), w - 36);
      DrawText(dc, line, 18, y, tiny, p.textSecondary);
      y += 22;
    }
  }
}

void ObjectInspectorPanel::OnLeftDown(wxMouseEvent &event) {
  const wxPoint pt = event.GetPosition();
  if (m_closeRect.Contains(pt)) {
    if (m_closeHandler) m_closeHandler();
    return;
  }
  if (m_technicalRect.Contains(pt)) {
    m_technicalExpanded = !m_technicalExpanded;
    RecalculateSize();
    Refresh(false);
    return;
  }
  if (pt.y <= 35) {
    m_dragging = true;
    m_dragStartMouse = wxGetMousePosition();
    m_dragStartPanel = GetPosition();
    CaptureMouse();
  }
}

void ObjectInspectorPanel::OnLeftUp(wxMouseEvent &) {
  if (!m_dragging) return;
  m_dragging = false;
  if (HasCapture()) ReleaseMouse();
}

void ObjectInspectorPanel::OnMotion(wxMouseEvent &event) {
  const wxPoint pt = event.GetPosition();
  const bool ch = m_closeRect.Contains(pt);
  const bool th = m_technicalRect.Contains(pt);
  if (ch != m_closeHover || th != m_technicalHover) {
    m_closeHover = ch;
    m_technicalHover = th;
    Refresh(false);
  }
  if (m_dragging && event.Dragging() && event.LeftIsDown()) {
    Move(m_dragStartPanel + (wxGetMousePosition() - m_dragStartMouse));
  }
}

void ObjectInspectorPanel::OnLeave(wxMouseEvent &) {
  if (m_closeHover || m_technicalHover) {
    m_closeHover = false;
    m_technicalHover = false;
    Refresh(false);
  }
}

}  // namespace ci_ui
