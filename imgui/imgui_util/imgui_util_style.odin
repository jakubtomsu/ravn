package ravn_imgui_util

import ".."

Palette_Color :: enum u8 {
    Bg,
    Panel,
    Outline,
    Accent,
    AccentHover,
    Text,
}

RAVN_DARK_PALETTE :: [Palette_Color][4]f32{
    .Bg          = {0.00, 0.00, 0.07, 1.00},
    .Panel       = {0.13, 0.14, 0.16, 1.00},
    .Outline     = {0.28, 0.29, 0.33, 1.00},
    .Accent      = {0.30, 0.65, 0.30, 1.00},
    .AccentHover = {0.30, 0.70, 0.35, 1.00},
    .Text        = {0.94, 0.95, 0.86, 1.00},
}

DARK_PALETTE :: [Palette_Color][4]f32{
    .Bg          = {0.06, 0.06, 0.07, 1.00},
    .Panel       = {0.13, 0.14, 0.16, 1.00},
    .Outline     = {0.28, 0.29, 0.33, 1.00},
    .Accent      = {0.22, 0.55, 0.86, 1.00},
    .AccentHover = {0.33, 0.65, 0.96, 1.00},
    .Text        = {0.94, 0.95, 0.96, 1.00},
}

set_palette_style :: proc(palette := RAVN_DARK_PALETTE, style: ^imgui.Style = nil) {
    style := style
    style = style == nil ? imgui.GetStyle() : style
    
    imgui.StyleColorsDark(style)
    
    style.WindowPadding *= 2
    style.FramePadding *= 1.1
    
    style.WindowRounding = 0
    style.ChildRounding = 0
    style.PopupRounding = 0
    style.FrameRounding = 0
    style.ScrollbarRounding = 0
    style.GrabRounding = 0
    style.ImageRounding = 0
    style.TabRounding = 0
    style.TreeLinesRounding = 0
    style.MenuItemRounding = 0
    style.SelectableRounding = 0
    style.DragDropTargetRounding = 0
    
    style.Colors[imgui.Col.Text]                      = palette[.Text]
    style.Colors[imgui.Col.TextDisabled]              = palette[.Outline]
    style.Colors[imgui.Col.WindowBg]                  = _alpha(palette[.Bg], 0.95)
    style.Colors[imgui.Col.ChildBg]                   = {0.00, 0.00, 0.00, 0.00}
    style.Colors[imgui.Col.PopupBg]                   = _alpha(palette[.Panel], 0.95)
    style.Colors[imgui.Col.Border]                    = _alpha(palette[.Outline], 0.50)
    style.Colors[imgui.Col.BorderShadow]              = {0.00, 0.00, 0.00, 0.00}
    style.Colors[imgui.Col.FrameBg]                   = palette[.Panel]
    style.Colors[imgui.Col.FrameBgHovered]            = _alpha(palette[.AccentHover], 0.40)
    style.Colors[imgui.Col.FrameBgActive]             = _alpha(palette[.Accent], 0.67)
    style.Colors[imgui.Col.TitleBg]                   = palette[.Bg]
    style.Colors[imgui.Col.TitleBgActive]             = palette[.Panel]
    style.Colors[imgui.Col.TitleBgCollapsed]          = _alpha(palette[.Bg], 0.51)
    style.Colors[imgui.Col.MenuBarBg]                 = palette[.Panel]
    style.Colors[imgui.Col.ScrollbarBg]               = _alpha(palette[.Bg], 0.53)
    style.Colors[imgui.Col.ScrollbarGrab]             = palette[.Outline]
    style.Colors[imgui.Col.ScrollbarGrabHovered]      = palette[.Accent]
    style.Colors[imgui.Col.ScrollbarGrabActive]       = palette[.AccentHover]
    style.Colors[imgui.Col.CheckMark]                 = palette[.AccentHover]
    style.Colors[imgui.Col.CheckboxSelectedBg]        = _alpha(palette[.Accent], 0.40) 
    style.Colors[imgui.Col.SliderGrab]                = palette[.Accent]
    style.Colors[imgui.Col.SliderGrabActive]          = palette[.AccentHover]
    style.Colors[imgui.Col.Button]                    = _alpha(palette[.Accent], 0.60)
    style.Colors[imgui.Col.ButtonHovered]             = palette[.AccentHover]
    style.Colors[imgui.Col.ButtonActive]              = palette[.Accent]
    style.Colors[imgui.Col.Header]                    = _alpha(palette[.Accent], 0.40)
    style.Colors[imgui.Col.HeaderHovered]             = _alpha(palette[.AccentHover], 0.80)
    style.Colors[imgui.Col.HeaderActive]              = palette[.Accent]
    style.Colors[imgui.Col.Separator]                 = palette[.Outline]
    style.Colors[imgui.Col.SeparatorHovered]          = palette[.AccentHover]
    style.Colors[imgui.Col.SeparatorActive]           = palette[.Accent]
    style.Colors[imgui.Col.ResizeGrip]                = _alpha(palette[.Accent], 0.20)
    style.Colors[imgui.Col.ResizeGripHovered]         = _alpha(palette[.AccentHover], 0.67)
    style.Colors[imgui.Col.ResizeGripActive]          = _alpha(palette[.Accent], 0.95)
    style.Colors[imgui.Col.InputTextCursor]           = palette[.Text]
    style.Colors[imgui.Col.TabHovered]                = _alpha(palette[.AccentHover], 0.80)
    style.Colors[imgui.Col.Tab]                       = palette[.Panel]
    style.Colors[imgui.Col.TabSelected]               = palette[.Accent]
    style.Colors[imgui.Col.TabSelectedOverline]       = palette[.AccentHover]
    style.Colors[imgui.Col.TabDimmed]                 = palette[.Bg]
    style.Colors[imgui.Col.TabDimmedSelected]         = palette[.Panel]
    style.Colors[imgui.Col.TabDimmedSelectedOverline] = palette[.Outline]
    style.Colors[imgui.Col.DockingPreview]            = _alpha(palette[.Accent], 0.70)
    style.Colors[imgui.Col.DockingEmptyBg]            = palette[.Bg]
    style.Colors[imgui.Col.PlotLines]                 = palette[.Outline]
    style.Colors[imgui.Col.PlotLinesHovered]          = palette[.AccentHover]
    style.Colors[imgui.Col.PlotHistogram]             = palette[.Accent]
    style.Colors[imgui.Col.PlotHistogramHovered]      = palette[.AccentHover]
    style.Colors[imgui.Col.TableHeaderBg]             = palette[.Panel]
    style.Colors[imgui.Col.TableBorderStrong]         = palette[.Outline]
    style.Colors[imgui.Col.TableBorderLight]          = _alpha(palette[.Outline], 0.50)
    style.Colors[imgui.Col.TableRowBg]                = {0.00, 0.00, 0.00, 0.00}
    style.Colors[imgui.Col.TableRowBgAlt]             = _alpha(palette[.Text], 0.04)
    style.Colors[imgui.Col.TextLink]                  = palette[.AccentHover]
    style.Colors[imgui.Col.TextSelectedBg]            = _alpha(palette[.Accent], 0.35)
    style.Colors[imgui.Col.TreeLines]                 = palette[.Outline]
    style.Colors[imgui.Col.DragDropTarget]            = palette[.AccentHover]
    style.Colors[imgui.Col.DragDropTargetBg]          = {0.00, 0.00, 0.00, 0.00}
    style.Colors[imgui.Col.UnsavedMarker]             = palette[.Text]
    style.Colors[imgui.Col.NavCursor]                 = palette[.Accent]
    style.Colors[imgui.Col.NavWindowingHighlight]     = _alpha(palette[.Text], 0.70)
    style.Colors[imgui.Col.NavWindowingDimBg]         = _alpha(palette[.Bg], 0.80)
    style.Colors[imgui.Col.ModalWindowDimBg]          = _alpha(palette[.Bg], 0.60)
    
    return
    
    _alpha :: proc(v: [4]f32, a: f32) -> [4]f32 {
        return {**v.xyz, a}
    }
}