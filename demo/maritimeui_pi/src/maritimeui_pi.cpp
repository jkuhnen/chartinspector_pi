#include "maritimeui_pi.h"
#include "app_style.h"

#include <wx/dcbuffer.h>
#include <wx/dcmemory.h>

extern "C" DECL_EXP opencpn_plugin *create_pi(void *ppimgr) {
  return new MaritimeUiPi(ppimgr);
}

extern "C" DECL_EXP void destroy_pi(opencpn_plugin *plugin) {
  delete plugin;
}

namespace {

class DemoCanvas : public wxPanel {
public:
  DemoCanvas(wxFrame *frame, PI_ColorScheme scheme)
      : wxPanel(frame, wxID_ANY), m_frame(frame), m_scheme(scheme) {
    SetBackgroundStyle(wxBG_STYLE_PAINT);
    Bind(wxEVT_PAINT, &DemoCanvas::OnPaint, this);
    Bind(wxEVT_LEFT_DOWN, &DemoCanvas::OnLeftDown, this);
    Bind(wxEVT_LEFT_UP, &DemoCanvas::OnLeftUp, this);
    Bind(wxEVT_MOTION, &DemoCanvas::OnMotion, this);
    Bind(wxEVT_LEAVE_WINDOW, &DemoCanvas::OnLeave, this);
    ApplyScheme(scheme);
  }

  void ApplyScheme(PI_ColorScheme scheme) {
    m_scheme = scheme;
    m_palette = maritime_ui::AppStyle::PaletteFor(scheme);
    SetBackgroundColour(m_palette.windowBackground);
    Refresh(false);
  }

private:
  static wxFont MakeFont(const wxFont &base, int delta, wxFontWeight weight) {
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

  void DrawRule(wxDC &dc, int y) {
    dc.SetPen(wxPen(m_palette.panelBorder, 1));
    dc.DrawLine(18, y, GetClientSize().GetWidth() - 18, y);
  }

  void DrawStatusDot(wxDC &dc, int x, int y, const wxColour &colour) {
    dc.SetPen(*wxTRANSPARENT_PEN);
    dc.SetBrush(wxBrush(colour));
    dc.DrawCircle(wxPoint(x, y), 4);
  }

  void DrawChevron(wxDC &dc, int x, int y, bool expanded) {
    dc.SetPen(wxPen(m_palette.textSecondary, 2));
    if (expanded) {
      dc.DrawLine(x - 4, y + 2, x, y - 2);
      dc.DrawLine(x, y - 2, x + 4, y + 2);
    } else {
      dc.DrawLine(x - 2, y - 4, x + 2, y);
      dc.DrawLine(x + 2, y, x - 2, y + 4);
    }
  }

  void OnPaint(wxPaintEvent &) {
    wxAutoBufferedPaintDC dc(this);
    dc.SetBackground(wxBrush(m_palette.windowBackground));
    dc.Clear();

    const wxSize size = GetClientSize();
    const wxFont base = GetFont();
    const wxFont tiny = MakeFont(base, -1, wxFONTWEIGHT_NORMAL);
    const wxFont label = MakeFont(base, 0, wxFONTWEIGHT_NORMAL);
    const wxFont value = MakeFont(base, 1, wxFONTWEIGHT_BOLD);
    const wxFont title = MakeFont(base, 4, wxFONTWEIGHT_BOLD);
    const wxFont hero = MakeFont(base, 7, wxFONTWEIGHT_BOLD);

    dc.SetPen(wxPen(m_palette.panelBorder, 1));
    dc.SetBrush(*wxTRANSPARENT_BRUSH);
    dc.DrawRectangle(0, 0, size.GetWidth(), size.GetHeight());

    // Custom title bar.
    dc.SetPen(*wxTRANSPARENT_PEN);
    dc.SetBrush(wxBrush(m_palette.panelBackground));
    dc.DrawRectangle(1, 1, size.GetWidth() - 2, 35);
    DrawText(dc, "OBJECT INSPECTOR", 14, 10, tiny, m_palette.textSecondary);
    m_closeRect = wxRect(size.GetWidth() - 36, 1, 35, 35);
    if (m_closeHover) {
      dc.SetBrush(wxBrush(m_palette.panelBorder));
      dc.DrawRectangle(m_closeRect);
    }
    dc.SetPen(wxPen(m_palette.textSecondary, 2));
    dc.DrawLine(size.GetWidth() - 24, 12, size.GetWidth() - 14, 22);
    dc.DrawLine(size.GetWidth() - 14, 12, size.GetWidth() - 24, 22);

    int y = 52;
    DrawText(dc, "NORTH CARDINAL BUOY", 18, y, title, m_palette.textPrimary);
    y += 30;
    DrawText(dc, "Middelgrund N", 18, y, value, m_palette.textPrimary);
    y += 25;
    DrawText(dc, "BOYCAR  ·  POINT", 18, y, tiny, m_palette.textSecondary);

    y += 34;
    DrawRule(dc, y);
    y += 18;

    // Navigation-first presentation.
    DrawText(dc, "NORTH CARDINAL", 48, y, value, m_palette.textPrimary);
    dc.SetPen(wxPen(m_palette.textPrimary, 2));
    dc.SetBrush(*wxTRANSPARENT_BRUSH);
    dc.DrawLine(24, y + 17, 32, y + 5);
    dc.DrawLine(32, y + 5, 40, y + 17);
    dc.DrawLine(24, y + 23, 32, y + 11);
    dc.DrawLine(32, y + 11, 40, y + 23);
    y += 27;
    DrawText(dc, "black / yellow", 48, y, label, m_palette.textSecondary);
    y += 31;
    DrawText(dc, "Q W 1s", 18, y, hero, m_palette.textPrimary);
    DrawText(dc, "5 NM", 238, y + 4, value, m_palette.textPrimary);
    y += 40;
    DrawText(dc, "LIGHT CHARACTER", 18, y, tiny, m_palette.textSecondary);
    DrawText(dc, "NOMINAL RANGE", 238, y, tiny, m_palette.textSecondary);

    y += 29;
    DrawRule(dc, y);
    y += 18;

    // Quiet status: normal data is deliberately not green.
    DrawText(dc, "CHART SOURCE", 18, y, tiny, m_palette.textSecondary);
    DrawText(dc, "DK ENC · current", 150, y - 1, label, m_palette.textPrimary);
    y += 30;

    DrawStatusDot(dc, 22, y + 7, m_palette.warning);
    DrawText(dc, "SCALE", 36, y, tiny, m_palette.textSecondary);
    DrawText(dc, "Not shown at current scale", 150, y - 1, label,
             m_palette.warning);
    y += 30;

    DrawStatusDot(dc, 22, y + 7, m_palette.alarm);
    DrawText(dc, "POSITION", 36, y, tiny, m_palette.textSecondary);
    DrawText(dc, "Invalid sample data", 150, y - 1, value, m_palette.alarm);

    y += 34;
    DrawRule(dc, y);
    y += 8;

    m_technicalRect = wxRect(10, y, size.GetWidth() - 20, 42);
    if (m_technicalHover) {
      dc.SetPen(*wxTRANSPARENT_PEN);
      dc.SetBrush(wxBrush(m_palette.panelBackground));
      dc.DrawRectangle(m_technicalRect);
    }
    DrawText(dc, "SOURCE / TECHNICAL", 18, y + 13, tiny,
             m_palette.textSecondary);
    DrawChevron(dc, size.GetWidth() - 24, y + 21, m_technicalExpanded);
    y += 47;

    if (m_technicalExpanded) {
      DrawText(dc, "Cell", 18, y, tiny, m_palette.textSecondary);
      DrawText(dc, "DK4KATGN", 150, y - 1, label, m_palette.textPrimary);
      y += 24;
      DrawText(dc, "Edition / update", 18, y, tiny, m_palette.textSecondary);
      DrawText(dc, "7A / 12", 150, y - 1, label, m_palette.textPrimary);
      y += 24;
      DrawText(dc, "SORDAT", 18, y, tiny, m_palette.textSecondary);
      DrawText(dc, "20260415", 150, y - 1, label, m_palette.textPrimary);
      y += 24;
      DrawText(dc, "SCAMIN", 18, y, tiny, m_palette.textSecondary);
      DrawText(dc, "45000", 150, y - 1, label, m_palette.textPrimary);
      y += 24;
      DrawText(dc, "S-57 class", 18, y, tiny, m_palette.textSecondary);
      DrawText(dc, "BOYCAR", 150, y - 1, label, m_palette.textPrimary);
    }
  }

  void OnLeftDown(wxMouseEvent &event) {
    const wxPoint p = event.GetPosition();
    if (m_closeRect.Contains(p)) {
      m_frame->Hide();
      return;
    }
    if (m_technicalRect.Contains(p)) {
      m_technicalExpanded = !m_technicalExpanded;
      const int h = m_technicalExpanded ? 585 : 465;
      m_frame->SetClientSize(wxSize(370, h));
      Refresh(false);
      return;
    }
    if (p.y <= 35) {
      m_dragging = true;
      m_dragStartMouse = wxGetMousePosition();
      m_dragStartFrame = m_frame->GetPosition();
      CaptureMouse();
    }
  }

  void OnLeftUp(wxMouseEvent &) {
    if (m_dragging) {
      m_dragging = false;
      if (HasCapture()) ReleaseMouse();
    }
  }

  void OnMotion(wxMouseEvent &event) {
    const wxPoint p = event.GetPosition();
    const bool closeHover = m_closeRect.Contains(p);
    const bool technicalHover = m_technicalRect.Contains(p);
    if (closeHover != m_closeHover || technicalHover != m_technicalHover) {
      m_closeHover = closeHover;
      m_technicalHover = technicalHover;
      Refresh(false);
    }
    if (m_dragging && event.Dragging() && event.LeftIsDown()) {
      const wxPoint delta = wxGetMousePosition() - m_dragStartMouse;
      m_frame->Move(m_dragStartFrame + delta);
    }
  }

  void OnLeave(wxMouseEvent &) {
    if (m_closeHover || m_technicalHover) {
      m_closeHover = false;
      m_technicalHover = false;
      Refresh(false);
    }
  }

  wxFrame *m_frame = nullptr;
  PI_ColorScheme m_scheme = PI_GLOBAL_COLOR_SCHEME_DAY;
  maritime_ui::Palette m_palette;
  wxRect m_closeRect;
  wxRect m_technicalRect;
  bool m_closeHover = false;
  bool m_technicalHover = false;
  bool m_technicalExpanded = false;
  bool m_dragging = false;
  wxPoint m_dragStartMouse;
  wxPoint m_dragStartFrame;
};

}  // namespace

MaritimeUiPi::MaritimeUiPi(void *ppimgr) : opencpn_plugin_118(ppimgr) {}

int MaritimeUiPi::Init() {
  BuildToolbarBitmap();
  m_pluginBitmap = m_toolbarBitmap;
  m_toolbarId = InsertPlugInTool(
      "Maritime UI Demo", &m_pluginBitmap, &m_pluginBitmap, wxITEM_NORMAL,
      "Maritime UI Demo", "Open maritime HMI design demonstrator", nullptr,
      -1, 0, this);
  return WANTS_TOOLBAR_CALLBACK | INSTALLS_TOOLBAR_TOOL;
}

bool MaritimeUiPi::DeInit() {
  if (m_toolbarId >= 0) RemovePlugInTool(m_toolbarId);
  m_toolbarId = -1;
  if (m_window) {
    m_window->Destroy();
    m_window = nullptr;
    m_canvas = nullptr;
  }
  return true;
}

int MaritimeUiPi::GetAPIVersionMajor() { return 1; }
int MaritimeUiPi::GetAPIVersionMinor() { return 18; }
int MaritimeUiPi::GetPlugInVersionMajor() { return 0; }
int MaritimeUiPi::GetPlugInVersionMinor() { return 2; }
int MaritimeUiPi::GetToolbarToolCount() { return 1; }

wxBitmap *MaritimeUiPi::GetPlugInBitmap() { return &m_pluginBitmap; }
wxString MaritimeUiPi::GetCommonName() { return "Maritime UI Demo"; }
wxString MaritimeUiPi::GetShortDescription() {
  return "Navigation-oriented maritime HMI design demonstrator.";
}
wxString MaritimeUiPi::GetLongDescription() {
  return "V2 demonstrator for a compact custom-drawn maritime interaction "
         "layer following OpenCPN DAY, DUSK and NIGHT colour schemes.";
}

void MaritimeUiPi::BuildToolbarBitmap() {
  const maritime_ui::Palette p = maritime_ui::AppStyle::PaletteFor(m_colorScheme);
  wxBitmap bitmap(24, 24);
  wxMemoryDC dc(bitmap);
  dc.SetBackground(wxBrush(p.windowBackground));
  dc.Clear();
  dc.SetBrush(*wxTRANSPARENT_BRUSH);
  dc.SetPen(wxPen(p.focus, 2));
  dc.DrawCircle(wxPoint(12, 12), 8);
  dc.DrawLine(12, 3, 12, 7);
  dc.DrawLine(12, 17, 12, 21);
  dc.DrawLine(3, 12, 7, 12);
  dc.DrawLine(17, 12, 21, 12);
  dc.SetPen(wxPen(p.accent, 3));
  dc.DrawCircle(wxPoint(12, 12), 2);
  dc.SelectObject(wxNullBitmap);
  m_toolbarBitmap = bitmap;
}

void MaritimeUiPi::EnsureWindow() {
  if (m_window) return;

  wxWindow *parent = GetOCPNCanvasWindow();
  m_window = new wxFrame(parent, wxID_ANY, wxEmptyString, wxDefaultPosition,
                         wxSize(370, 465),
                         wxFRAME_TOOL_WINDOW | wxSTAY_ON_TOP | wxBORDER_NONE);
  m_canvas = new DemoCanvas(m_window, m_colorScheme);
  wxBoxSizer *sizer = new wxBoxSizer(wxVERTICAL);
  sizer->Add(m_canvas, 1, wxEXPAND);
  m_window->SetSizer(sizer);
  m_window->SetClientSize(wxSize(370, 465));
  m_window->SetMinClientSize(wxSize(370, 465));
  ApplyTheme();
}

void MaritimeUiPi::ApplyTheme() {
  if (!m_canvas) return;
  DemoCanvas *canvas = dynamic_cast<DemoCanvas *>(m_canvas);
  if (canvas) canvas->ApplyScheme(m_colorScheme);
}

void MaritimeUiPi::ToggleWindow() {
  EnsureWindow();
  if (!m_window) return;
  if (m_window->IsShown()) {
    m_window->Hide();
  } else {
    ApplyTheme();
    m_window->Show();
    m_window->Raise();
  }
}

void MaritimeUiPi::OnToolbarToolCallback(int id) {
  if (id == m_toolbarId) ToggleWindow();
}

void MaritimeUiPi::SetColorScheme(PI_ColorScheme cs) {
  m_colorScheme = cs;
  BuildToolbarBitmap();
  m_pluginBitmap = m_toolbarBitmap;
  if (m_toolbarId >= 0)
    SetToolbarToolBitmaps(m_toolbarId, &m_toolbarBitmap, &m_toolbarBitmap);
  ApplyTheme();
}
