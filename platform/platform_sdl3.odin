// Fallback backend using SDL.
// Missing features use core libraries.
#+build !js
#+vet explicit-allocators shadowing style unused
package ravn_platform

import "core:strings"
import "core:time"
import "base:runtime"
import "vendor:sdl3"
import "core:path/filepath"
import "../base"
import "../base/ufmt"
import "core:os"
import "core:dynlib"

_ :: runtime
_ :: base
_ :: sdl3
_ :: filepath
_ :: ufmt
_ :: strings
_ :: time
_ :: os
_ :: dynlib

BACKEND_SDL3 :: "SDL3"

when BACKEND == BACKEND_SDL3 {

    _State :: struct { _: u8 }

    _Directory_Iter :: struct {
        index: i32,
        count: i32,
        matches: [^]cstring, // allocated by sdl.GlobDirectory
    }

    _Window :: struct {
        window: ^sdl3.Window,
    }

    _init :: proc() {
        if !sdl3.Init({.VIDEO, .EVENTS, .GAMEPAD}) {
            panic("Failed to initialize SDL3")
        }
        base.log_info("Initialized SDL3")

        // sdl3.SetHint(sdl3.HINT_MOUSE_FOCUS_CLICKTHROUGH, "1")
    }

    _shutdown :: proc() {
        sdl3.Quit()
    }



    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Common
    //

    _register_default_exception_handler :: proc() {

    }

    @(require_results)
    _clipboard_set :: proc(data: string) -> bool {
        return sdl3.SetClipboardText(
            strings.clone_to_cstring(data, context.temp_allocator),
        )
    }

    @(require_results)
    _clipboard_get :: proc(allocator := context.temp_allocator) -> (string, bool) {
        if !sdl3.HasClipboardText() {
            return {}, false
        }
        text := string(cstring(sdl3.GetClipboardText()))
        return text, true
    }

    @(require_results)
    _get_gamepad_state :: proc(#any_int index: int) -> (result: Gamepad_State, ok: bool) {
        gamepad := sdl3.GetGamepadFromPlayerIndex(i32(index))
        if gamepad == nil {
            return {}, false
        }

        result.axes = {
            .Left_Trigger   = f32(sdl3.GetGamepadAxis(gamepad, .LEFT_TRIGGER))  / f32(max(i16)),
            .Right_Trigger  = f32(sdl3.GetGamepadAxis(gamepad, .RIGHT_TRIGGER)) / f32(max(i16)),
            .Left_Thumb_X   = f32(sdl3.GetGamepadAxis(gamepad, .LEFTX))         / f32(max(i16)),
            .Left_Thumb_Y   = f32(sdl3.GetGamepadAxis(gamepad, .LEFTY))         / f32(max(i16)),
            .Right_Thumb_X  = f32(sdl3.GetGamepadAxis(gamepad, .RIGHTX))        / f32(max(i16)),
            .Right_Thumb_Y  = f32(sdl3.GetGamepadAxis(gamepad, .RIGHTY))        / f32(max(i16)),
        }

        if sdl3.GetGamepadButton(gamepad, .DPAD_UP) do result.buttons += {.DPad_Up}
        if sdl3.GetGamepadButton(gamepad, .DPAD_DOWN) do result.buttons += {.DPad_Down}
        if sdl3.GetGamepadButton(gamepad, .DPAD_LEFT) do result.buttons += {.DPad_Left}
        if sdl3.GetGamepadButton(gamepad, .DPAD_RIGHT) do result.buttons += {.DPad_Right}
        if sdl3.GetGamepadButton(gamepad, .START) do result.buttons += {.Start}
        if sdl3.GetGamepadButton(gamepad, .BACK) do result.buttons += {.Back}
        if sdl3.GetGamepadButton(gamepad, .LEFT_STICK) do result.buttons += {.Left_Thumb}
        if sdl3.GetGamepadButton(gamepad, .RIGHT_STICK) do result.buttons += {.Right_Thumb}
        if sdl3.GetGamepadButton(gamepad, .LEFT_SHOULDER) do result.buttons += {.Left_Shoulder}
        if sdl3.GetGamepadButton(gamepad, .RIGHT_SHOULDER) do result.buttons += {.Right_Shoulder}
        if sdl3.GetGamepadButton(gamepad, .SOUTH) do result.buttons += {.A}
        if sdl3.GetGamepadButton(gamepad, .EAST) do result.buttons += {.B}
        if sdl3.GetGamepadButton(gamepad, .WEST) do result.buttons += {.X}
        if sdl3.GetGamepadButton(gamepad, .NORTH) do result.buttons += {.Y}

        return result, true
    }

    @(require_results)
    _set_gamepad_feedback :: proc(#any_int index: int, output: Gamepad_Feedback) -> bool {
        return false
    }


    @(require_results)
    _get_user_data_dir :: proc(allocator := context.allocator) -> string {
        return string(sdl3.GetUserFolder(.SAVEDGAMES))
    }

    _set_mouse_relative :: proc(window: Window, relative: bool) {
        _ = sdl3.SetWindowRelativeMouseMode(window.window, relative)
        _ = sdl3.SetWindowMouseGrab(window.window, relative)
    }

    _set_mouse_visible :: proc(visible: bool) {
        if visible {
            _ = sdl3.ShowCursor()
        } else {
            _ = sdl3.HideCursor()
        }
    }

    @(require_results)
    _get_main_monitor_rect :: proc() -> Rect {
        r: sdl3.Rect
        if !sdl3.GetDisplayBounds(sdl3.GetPrimaryDisplay(), &r) {
            return {}
        }
        return {
            min = {
                r.x,
                r.y,
            },
            size = {
                r.w,
                r.h,
            },
        }
    }



    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Window
    //

    @(require_results)
    _create_window :: proc(name: string, style: Window_Style, rect: Rect, high_dpi: bool) -> Window {
        flags: sdl3.WindowFlags = {
            .INPUT_FOCUS,
        }

        if style == .Borderless {
            flags += {.BORDERLESS}
        }

        if high_dpi {
            flags += {.HIGH_PIXEL_DENSITY}
        }

        name_ptr := strings.clone_to_cstring(name, context.temp_allocator)

        wnd := sdl3.CreateWindow(name_ptr, rect.size.x, rect.size.y, flags)
        if wnd == nil {
            return {}
        }

        sdl3.SetWindowPosition(wnd, rect.min.x, rect.min.y)
        sdl3.ShowWindow(wnd)

        return Window{native = {window = wnd}}
    }

    _destroy_window :: proc(window: Window) {
        sdl3.DestroyWindow(window.window)
    }

    @(require_results)
    _get_window_dpi_scale :: proc(window: Window) -> f32 {
        return sdl3.GetWindowDisplayScale(window.window)
    }

    _set_window_title :: proc(window: Window, name: string) {
        sdl3.SetWindowTitle(window.window, strings.clone_to_cstring(name, context.temp_allocator))
    }

    _set_window_style :: proc(window: Window, style: Window_Style) {
        switch style {
        case .Regular:
            sdl3.SetWindowBordered(window.window, true)

        case .Borderless:
            sdl3.SetWindowBordered(window.window, false)
        }
    }

    _set_window_pos :: proc(window: Window, pos: [2]i32) {
        sdl3.SetWindowPosition(window.window, pos.x, pos.y)
    }

    _set_window_size :: proc(window: Window, size: [2]i32) {
        sdl3.SetWindowSize(window.window, size.x, size.y)
    }

    @(require_results)
    _get_window_rect :: proc(window: Window) -> (result: Rect) {
        sdl3.GetWindowSizeInPixels(window.window, &result.size.x, &result.size.y) // HACK
        sdl3.GetWindowPosition(window.window, &result.min.x, &result.min.y)
        return result
    }

    _set_mouse_pos_window_relative :: proc(window: Window, pos: [2]i32) {
        sdl3.WarpMouseInWindow(window.window, f32(pos.x), f32(pos.y))
    }

    @(require_results)
    _is_window_minimized :: proc(window: Window) -> bool {
        return .MINIMIZED in sdl3.GetWindowFlags(window.window)
    }

    @(require_results)
    _is_window_focused :: proc(window: Window) -> bool {
        return .INPUT_FOCUS in sdl3.GetWindowFlags(window.window)
    }

    @(require_results)
    _get_native_window_ptr :: proc(window: Window) -> rawptr {
        when ODIN_OS == .Windows {
            return sdl3.GetPointerProperty(sdl3.GetWindowProperties(window.window), sdl3.PROP_WINDOW_WIN32_HWND_POINTER, nil)
        } else when ODIN_OS == .Linux {
            return window.window
        } else {
            return nil
        }
    }

    @(require_results)
    _poll_window_events :: proc(window: Window) -> (ok: bool) {
        for {
            event: sdl3.Event
            if !sdl3.PollEvent(&event) {
                return false
            }

            #partial switch event.type {
            case .WINDOW_CLOSE_REQUESTED:
                _event_queue_push(Event_Exit{})
                return true

            case .KEY_DOWN, .KEY_UP:
                _event_queue_push(Event_Button{
                    button = _sdl_scancode_to_button(event.key.scancode),
                    pressed = event.key.down,
                })
                return true

            case .MOUSE_MOTION:
                _event_queue_push(Event_Mouse{
                    move = {
                        i32(event.motion.xrel),
                        i32(event.motion.yrel),
                    },
                    pos = {
                        i32(event.motion.x),
                        i32(event.motion.y),
                    },
                })
                return true

            case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
                _event_queue_push(Event_Button{
                    button = _sdl_mouse_to_button(event.button.button),
                    pressed = event.button.down,
                })
                return true

            case .MOUSE_WHEEL:
                _event_queue_push(Event_Scroll{
                    delta = {
                        event.wheel.x,
                        event.wheel.y,
                    },
                })
                return true

            case .WINDOW_RESIZED:
                _event_queue_push(Event_Window_Size{
                    size = {
                        event.window.data1,
                        event.window.data2,
                    },
                })
                return true

            }
        }
        return false
    }

    _sdl_mouse_to_button :: proc(button: u8) -> Button {
        switch button {
        case sdl3.BUTTON_LEFT:  return .Mouse_Left
        case sdl3.BUTTON_MIDDLE:return .Mouse_Middle
        case sdl3.BUTTON_RIGHT: return .Mouse_Right
        case sdl3.BUTTON_X1:    return .Mouse_Extra_1
        case sdl3.BUTTON_X2:    return .Mouse_Extra_2
        }
        return .Invalid
    }

    _sdl_scancode_to_button :: proc(scancode: sdl3.Scancode) -> Button {
        // NOTE: few of our keys don't map cleanly.
        #partial switch scancode {
        case .UNKNOWN: return .Invalid
        case ._0: return .Num0
        case ._1: return .Num1
        case ._2: return .Num2
        case ._3: return .Num3
        case ._4: return .Num4
        case ._5: return .Num5
        case ._6: return .Num6
        case ._7: return .Num7
        case ._8: return .Num8
        case ._9: return .Num9
        case .A: return .A
        case .B: return .B
        case .C: return .C
        case .D: return .D
        case .E: return .E
        case .F: return .F
        case .G: return .G
        case .H: return .H
        case .I: return .I
        case .J: return .J
        case .K: return .K
        case .L: return .L
        case .M: return .M
        case .N: return .N
        case .O: return .O
        case .P: return .P
        case .Q: return .Q
        case .R: return .R
        case .S: return .S
        case .T: return .T
        case .U: return .U
        case .V: return .V
        case .W: return .W
        case .X: return .X
        case .Y: return .Y
        case .Z: return .Z
        case .SPACE: return .Space
        case .APOSTROPHE: return .Apostrophe
        case .COMMA: return .Comma
        case .MINUS: return .Minus
        case .PERIOD: return .Period
        case .SLASH: return .Slash
        case .SEMICOLON: return .Semicolon
        case .EQUALS: return .Equal
        case .LEFTBRACKET: return .Left_Bracket
        case .BACKSLASH: return .Backslash
        case .RIGHTBRACKET: return .Right_Bracket
        case .GRAVE: return .Backtick
        case .ESCAPE: return .Escape
        case .RETURN: return .Enter
        case .TAB: return .Tab
        case .BACKSPACE: return .Backspace
        case .INSERT: return .Insert
        case .DELETE: return .Delete
        case .RIGHT: return .Right
        case .LEFT: return .Left
        case .DOWN: return .Down
        case .UP: return .Up
        case .PAGEUP: return .Page_Up
        case .PAGEDOWN: return .Page_Down
        case .HOME: return .Home
        case .END: return .End
        case .CAPSLOCK: return .Capslock
        case .SCROLLLOCK: return .Scroll_Lock
        case .PRINTSCREEN: return .Print_Screen
        case .PAUSE: return .Pause
        case .F1: return .F1
        case .F2: return .F2
        case .F3: return .F3
        case .F4: return .F4
        case .F5: return .F5
        case .F6: return .F6
        case .F7: return .F7
        case .F8: return .F8
        case .F9: return .F9
        case .F10: return .F10
        case .F11: return .F11
        case .F12: return .F12
        case .F13: return .F13
        case .F14: return .F14
        case .F15: return .F15
        case .F16: return .F16
        case .F17: return .F17
        case .F18: return .F18
        case .F19: return .F19
        case .F20: return .F20
        case .F21: return .F21
        case .F22: return .F22
        case .F23: return .F23
        case .F24: return .F24
        case .KP_0: return .Keypad_0
        case .KP_1: return .Keypad_1
        case .KP_2: return .Keypad_2
        case .KP_3: return .Keypad_3
        case .KP_4: return .Keypad_4
        case .KP_5: return .Keypad_5
        case .KP_6: return .Keypad_6
        case .KP_7: return .Keypad_7
        case .KP_8: return .Keypad_8
        case .KP_9: return .Keypad_9
        case .KP_DECIMAL: return .Keypad_Decimal
        case .KP_DIVIDE: return .Keypad_Divide
        case .KP_MULTIPLY: return .Keypad_Multiply
        case .KP_MINUS: return .Keypad_Subtract
        case .KP_PLUS: return .Keypad_Add
        case .KP_ENTER: return .Keypad_Enter
        case .KP_EQUALS: return .Keypad_Equal
        case .LSHIFT: return .Left_Shift
        case .LCTRL: return .Left_Control
        case .LALT: return .Left_Alt
        case .LGUI: return .Left_Super
        case .RSHIFT: return .Right_Shift
        case .RCTRL: return .Right_Control
        case .RALT: return .Right_Alt
        case .RGUI: return .Right_Super
        case .MENU: return .Menu
        }
        return .Invalid
    }

    @(require_results)
    _file_dialog :: proc(mode: File_Dialog_Mode, default_path: string, patterns: []File_Pattern, title := "") -> (string, bool) {
        return "", false
    }

}
