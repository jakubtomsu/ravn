#+vet explicit-allocators shadowing unused
package ravn_imgui_impl_platform

import "core:strings"
import "base:runtime"
import "core:time"
import "../../platform"
import ".."

State :: struct {
    init_context:   runtime.Context,
    allocator:      runtime.Allocator,
    window:         platform.Window,
    clipboard_data: cstring,
    prev_tick:      time.Tick,
}

_get_state :: proc() -> ^State {
    if imgui.GetCurrentContext() == nil {
        return nil
    }
    io := imgui.GetIO()
    return cast(^State)io.BackendPlatformUserData
}

init :: proc(window: platform.Window, allocator := context.allocator) {
    assert(platform._state != nil)

    imgui.CHECKVERSION()
    io := imgui.GetIO()
    assert(io.BackendPlatformUserData == nil, "Already initialized a platform backend")

    state := new(State, allocator)
    state.allocator = allocator
    state.init_context = context
    state.window = window

    io.BackendPlatformUserData = state
    io.BackendPlatformName = "imgui_impl_ravn_platform"
    io.BackendFlags += {.HasMouseCursors, .HasSetMousePos}

    plio := imgui.GetPlatformIO()

    plio.PlatformGetClipboardTextFn = _get_clipboard_text
    plio.PlatformSetClipboardTextFn = _set_clipboard_text
    plio.PlatformSetImeDataFn = nil // TODO
    plio.PlatformOpenInShellFn = _open_in_shell
}

shutdown :: proc() {
    assert(platform._state != nil)

    state := _get_state()
    assert(state != nil, "Backend already shut down")

    io := imgui.GetIO()
    plio := imgui.GetPlatformIO()

    if state.clipboard_data != "" {
        delete(state.clipboard_data, state.allocator)
    }

    io.BackendPlatformName = nil
    io.BackendPlatformUserData = nil
    io.BackendFlags -= {.HasMouseCursors, .HasSetMousePos, .HasGamepad}
    imgui.PlatformIO_ClearPlatformHandlers(plio)

    free(state, state.allocator)
}

new_frame :: proc() {
    assert(platform._state != nil)

    state := _get_state()
    assert(state != nil, "Backend not initialized, did you call init()?")

    io := imgui.GetIO()

    io.DisplaySize = cast([2]f32)platform.get_window_rect(state.window).size
    io.DisplayFramebufferScale = platform.get_window_dpi_scale(state.window)

    curr_tick := time.tick_now()
    delta := f32(time.duration_seconds(time.tick_diff(state.prev_tick, curr_tick)))
    io.DeltaTime = state.prev_tick._nsec > 0 ? delta : 0
    state.prev_tick = curr_tick
}

process_event :: proc(event: platform.Event) {
    io := imgui.GetIO()

    #partial switch v in event {
    case platform.Event_Button:
        if v.button in platform.MOUSE_BUTTON_SET {
            button := _imgui_mouse_button_index_from_button(v.button) or_break
            imgui.IO_AddMouseSourceEvent(io, .Mouse)
            imgui.IO_AddMouseButtonEvent(io, button, down = v.pressed)
        } else {
            key := _imgui_key_from_button(v.button) or_break
            imgui.IO_AddKeyEvent(io, key, v.pressed)
        }

    case platform.Event_Mouse:
        imgui.IO_AddMouseSourceEvent(io, .Mouse)
        imgui.IO_AddMousePosEvent(io, f32(v.pos.x), f32(v.pos.y))

    case platform.Event_Scroll:
        imgui.IO_AddMouseSourceEvent(io, .Mouse)
        imgui.IO_AddMouseWheelEvent(io, v.delta.x, v.delta.y)
    }
}

_get_clipboard_text :: proc "c" (ctx: ^imgui.Context) -> cstring {
    io := imgui.GetIO()
    state := cast(^State)io.BackendPlatformUserData
    context = state.init_context

    if state.clipboard_data != "" {
        delete(state.clipboard_data, state.allocator)
    }

    state.clipboard_data = nil
    str, str_ok := platform.clipboard_get(context.temp_allocator)
    if str_ok {
        state.clipboard_data = strings.clone_to_cstring(str, state.allocator)
    }

    return state.clipboard_data
}

_set_clipboard_text :: proc "c" (ctx: ^imgui.Context, text: cstring) {
    io := imgui.GetIO()
    state := cast(^State)io.BackendPlatformUserData
    context = state.init_context

    platform.clipboard_set(string(text))
}

_open_in_shell :: proc "c" (ctx: ^imgui.Context, path: cstring) -> bool {
    io := imgui.GetIO()
    state := cast(^State)io.BackendPlatformUserData
    context = state.init_context

    // TODO

    return false
}

_imgui_mouse_button_index_from_button :: proc(button: platform.Button) -> (i32, bool) {
    #partial switch button {
    case .Mouse_Left:   return 0, true
    case .Mouse_Right:  return 1, true
    case .Mouse_Middle: return 2, true
    case .Mouse_Extra_1:return 3, true
    case .Mouse_Extra_2:return 4, true
    }
    return -1, false
}

_imgui_key_from_button :: proc(button: platform.Button) -> (imgui.Key, bool) {
    #partial switch button {
    case .Num0:            return ._0, true
    case .Num1:            return ._1, true
    case .Num2:            return ._2, true
    case .Num3:            return ._3, true
    case .Num4:            return ._4, true
    case .Num5:            return ._5, true
    case .Num6:            return ._6, true
    case .Num7:            return ._7, true
    case .Num8:            return ._8, true
    case .Num9:            return ._9, true
    case .A:               return .A, true
    case .B:               return .B, true
    case .C:               return .C, true
    case .D:               return .D, true
    case .E:               return .E, true
    case .F:               return .F, true
    case .G:               return .G, true
    case .H:               return .H, true
    case .I:               return .I, true
    case .J:               return .J, true
    case .K:               return .K, true
    case .L:               return .L, true
    case .M:               return .M, true
    case .N:               return .N, true
    case .O:               return .O, true
    case .P:               return .P, true
    case .Q:               return .Q, true
    case .R:               return .R, true
    case .S:               return .S, true
    case .T:               return .T, true
    case .U:               return .U, true
    case .V:               return .V, true
    case .W:               return .W, true
    case .X:               return .X, true
    case .Y:               return .Y, true
    case .Z:               return .Z, true
    case .Space:           return .Space, true
    case .Apostrophe:      return .Apostrophe, true
    case .Comma:           return .Comma, true
    case .Minus:           return .Minus, true
    case .Period:          return .Period, true
    case .Slash:           return .Slash, true
    case .Semicolon:       return .Semicolon, true
    case .Equal:           return .Equal, true
    case .Left_Bracket:    return .LeftBracket, true
    case .Backslash:       return .Backslash, true
    case .Right_Bracket:   return .RightBracket, true
    case .Backtick:        return .GraveAccent, true
    case .Escape:          return .Escape, true
    case .Enter:           return .Enter, true
    case .Tab:             return .Tab, true
    case .Backspace:       return .Backspace, true
    case .Insert:          return .Insert, true
    case .Delete:          return .Delete, true
    case .Right:           return .RightArrow, true
    case .Left:            return .LeftArrow, true
    case .Down:            return .DownArrow, true
    case .Up:              return .UpArrow, true
    case .Page_Up:         return .PageUp, true
    case .Page_Down:       return .PageDown, true
    case .Home:            return .Home, true
    case .End:             return .End, true
    case .Capslock:        return .CapsLock, true
    case .Scroll_Lock:     return .ScrollLock, true
    case .Num_Lock:        return .NumLock, true
    case .Print_Screen:    return .PrintScreen, true
    case .Pause:           return .Pause, true
    case .F1:              return .F1, true
    case .F2:              return .F2, true
    case .F3:              return .F3, true
    case .F4:              return .F4, true
    case .F5:              return .F5, true
    case .F6:              return .F6, true
    case .F7:              return .F7, true
    case .F8:              return .F8, true
    case .F9:              return .F9, true
    case .F10:             return .F10, true
    case .F11:             return .F11, true
    case .F12:             return .F12, true
    case .F13:             return .F13, true
    case .F14:             return .F14, true
    case .F15:             return .F15, true
    case .F16:             return .F16, true
    case .F17:             return .F17, true
    case .F18:             return .F18, true
    case .F19:             return .F19, true
    case .F20:             return .F20, true
    case .F21:             return .F21, true
    case .F22:             return .F22, true
    case .F23:             return .F23, true
    case .F24:             return .F24, true
    case .Keypad_0:        return .Keypad0, true
    case .Keypad_1:        return .Keypad1, true
    case .Keypad_2:        return .Keypad2, true
    case .Keypad_3:        return .Keypad3, true
    case .Keypad_4:        return .Keypad4, true
    case .Keypad_5:        return .Keypad5, true
    case .Keypad_6:        return .Keypad6, true
    case .Keypad_7:        return .Keypad7, true
    case .Keypad_8:        return .Keypad8, true
    case .Keypad_9:        return .Keypad9, true
    case .Keypad_Decimal:  return .KeypadDecimal, true
    case .Keypad_Divide:   return .KeypadDivide, true
    case .Keypad_Multiply: return .KeypadMultiply, true
    case .Keypad_Subtract: return .KeypadSubtract, true
    case .Keypad_Add:      return .KeypadAdd, true
    case .Keypad_Enter:    return .KeypadEnter, true
    case .Keypad_Equal:    return .KeypadEqual, true
    case .Left_Shift:      return .LeftShift, true
    case .Left_Control:    return .LeftCtrl, true
    case .Left_Alt:        return .LeftAlt, true
    case .Left_Super:      return .LeftSuper, true
    case .Right_Shift:     return .RightShift, true
    case .Right_Control:   return .RightCtrl, true
    case .Right_Alt:       return .RightAlt, true
    case .Right_Super:     return .RightSuper, true
    case .Menu:            return .Menu, true
    }
    return .None, false
}