/*
NOTE: frame loop is done by the odin.js repeatedly calling `step`:

    @(private="file", export)
    step :: proc(dt: f32) -> bool {
        frame(dt)
        return true
    }

*/
#+build js
#+vet explicit-allocators shadowing unused
package raven_platform

import "../base"
import "core:sys/wasm/js"

#assert(BACKEND == BACKEND_JS)

_CANVAS_ID :: "#raven-canvas"

_State :: struct {
    _: u8,
}

_File_Handle :: struct { _: u8 }
_Async_File :: struct { _: u8 }
_File_Watcher :: struct { _: u8 }
_Directory_Iter :: struct { _: u8 }
_Barrier :: struct { _: u8 }
_Thread :: struct { _: u8 }
_Window :: struct { _: u8 }
_Module :: struct { _: u8 }



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Common
//

_init :: proc() {
    for proc_ptr, kind in _js_event_callbacks {
        if proc_ptr == nil {
            continue
        }
        if !js.add_window_event_listener(kind, user_data = nil, callback = proc_ptr) {
            base.log_err("Failed to add '%v' event listener when initializing", kind)
        }
    }

    _init_js(_CANVAS_ID)
}

_shutdown :: proc() {
    for proc_ptr, kind in _js_event_callbacks {
        if proc_ptr == nil {
            continue
        }
        if !js.remove_window_event_listener(kind, user_data = nil, callback = proc_ptr) {
            base.log_err("Failed to remove '%v' event listener when shutting down", kind)
        }
    }
}



@(require_results)
_get_commandline_args :: proc(allocator := context.allocator) -> []string {
    return nil
}

@(require_results)
_run_shell_command :: proc(command: string) -> int {
    return 0
}

_exit_process :: proc(code: int) -> ! {
    // HACK
    js.trap()
}

_register_default_exception_handler :: proc() {

}

@(require_results)
_memory_protect :: proc(ptr: rawptr, num_bytes: int, protect: Memory_Protection) -> bool {
    return true
}

@(require_results)
_clipboard_set :: proc(data: []byte, format: Clipboard_Format = .Text) -> bool {
    _js_unsupported()
    return true
}

@(require_results)
_clipboard_get :: proc(format: Clipboard_Format = .Text, allocator := context.temp_allocator) -> ([]byte, bool) {
    _js_unsupported()
    return nil, false
}

@(require_results)
_get_gamepad_state :: proc(#any_int index: int) -> (result: Gamepad_State, ok: bool) {
    state: js.Gamepad_State
    if !js.get_gamepad_state(index, &state) {
        return {}, false
    }

    // https://w3c.github.io/gamepad/#remapping

    if state.buttons[12].pressed do result.buttons += {.DPad_Up}
    if state.buttons[13].pressed do result.buttons += {.DPad_Down}
    if state.buttons[14].pressed do result.buttons += {.DPad_Left}
    if state.buttons[15].pressed do result.buttons += {.DPad_Right}
    if state.buttons[9].pressed do result.buttons += {.Start}
    if state.buttons[8].pressed do result.buttons += {.Back}
    if state.buttons[10].pressed do result.buttons += {.Left_Thumb}
    if state.buttons[11].pressed do result.buttons += {.Right_Thumb}
    if state.buttons[4].pressed do result.buttons += {.Left_Shoulder}
    if state.buttons[4].pressed do result.buttons += {.Right_Shoulder}
    if state.buttons[0].pressed do result.buttons += {.A}
    if state.buttons[1].pressed do result.buttons += {.B}
    if state.buttons[2].pressed do result.buttons += {.X}
    if state.buttons[3].pressed do result.buttons += {.Y}

    result.axes = {
        .Left_Trigger = f32(state.buttons[6].value),
        .Right_Trigger = f32(state.buttons[7].value),
        .Left_Thumb_X = f32(state.axes[0]),
        .Left_Thumb_Y = -f32(state.axes[1]),
        .Right_Thumb_X = f32(state.axes[2]),
        .Right_Thumb_Y = -f32(state.axes[3]),
    }

    return {}, false
}

@(require_results)
_set_gamepad_feedback :: proc(#any_int index: int, output: Gamepad_Feedback) -> bool {
    return false
}


@(require_results)
_get_user_data_dir :: proc(allocator := context.allocator) -> string {
    _js_unsupported()
    return ""
}

_set_mouse_relative :: proc(window: Window, relative: bool) {
}

_set_mouse_visible :: proc(visible: bool) {
}

_set_dpi_aware :: proc() {
}

@(require_results)
_get_main_monitor_rect :: proc() -> Rect {
    return _get_window_frame_rect({})
}

@(require_results)
_set_current_directory :: proc(path: string) -> bool {
    _js_unsupported()
    return false
}

@(require_results)
_get_executable_path :: proc(allocator := context.temp_allocator) -> string {
    _js_unsupported()
    return ""
}

@(require_results)
_load_module :: proc(path: string) -> (result: Module, ok: bool) {
    _js_unsupported()
    return {}, false
}

_unload_module :: proc(module: Module) {
    _js_unsupported()
}

@(require_results)
_module_symbol_address :: proc(module: Module, cstr: cstring) -> (result: rawptr) {
    _js_unsupported()
    return nil
}

_sleep_ms :: proc(#any_int ms: int) {
    _js_unsupported()
}

@(require_results)
_get_time_ns :: proc() -> u64 {
    return u64(_tick_now() * 1e6)
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Thread
//

@(require_results)
_create_thread :: proc(procedure: Thread_Proc) -> Thread {
    _js_unsupported()
    return {}
}

_join_thread :: proc(thread: Thread) {
    _js_unsupported()
}

_set_thread_name :: proc(thread: Thread, name: string) {
    _js_unsupported()
}

@(require_results)
_get_current_thread :: proc() -> Thread {
    _js_unsupported()
    return {}
}

@(require_results)
_get_current_thread_id :: proc() -> u64 {
    _js_unsupported()
    return 0
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Window
//

@(require_results)
_create_window :: proc(name: string, style: Window_Style = .Regular, full_rect: Rect = {}) -> Window {
    _js_unsupported()
    return {}
}

_destroy_window :: proc(window: Window) {
    _js_unsupported()
}

@(require_results)
_get_window_dpi_scale :: proc(window: Window) -> f32 {
    // _js_unsupported()
    return 1.0
}

_set_window_style :: proc(window: Window, style: Window_Style) {
    _js_unsupported()
}

_set_window_title :: proc(window: Window, name: string) {

}


_set_window_pos :: proc(window: Window, pos: [2]i32) {
    _js_unsupported()
}

_set_window_size :: proc(window: Window, size: [2]i32) {
    _js_unsupported()
}

@(require_results)
_get_window_frame_rect :: proc(window: Window) -> Rect {
    rect := js.get_bounding_client_rect("body")
    dpi := js.device_pixel_ratio()
    return {
        min = 0,
        size = {
            i32(f64(rect.width) * dpi),
            i32(f64(rect.height) * dpi),
        },
    }
}

@(require_results)
_get_window_full_rect :: proc(window: Window) -> Rect {
    return _get_window_frame_rect(window)
}

_set_mouse_pos_window_relative :: proc(window: Window, pos: [2]i32) {
    _js_unsupported()
}

@(require_results)
_is_window_minimized :: proc(window: Window) -> bool {
    _js_unsupported()
    return false
}

@(require_results)
_is_window_focused :: proc(window: Window) -> bool {
    _js_unsupported()
    return true
}

@(require_results)
_get_native_window_ptr :: proc(window: Window) -> rawptr {
    return nil
}

@(require_results)
_poll_window_events :: proc(window: Window) -> (ok: bool) {
    return false
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Barrier
//

@(require_results)
_barrier_create :: proc(num_threads: int) -> (result: Barrier) {
    _js_unsupported()
    return {}
}

_barrier_delete :: proc(barrier: ^Barrier) {
    _js_unsupported()
}

_barrier_sync :: proc(barrier: ^Barrier) {
    _js_unsupported()
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: File IO
//

@(require_results)
_open_file :: proc(path: string) -> (File_Handle, bool) {
    _js_unsupported()
    return {}, false
}

_close_file :: proc(handle: File_Handle) {
}

@(require_results)
_get_last_write_time :: proc(handle: File_Handle) -> (u64, bool) {
    _js_unsupported()
    return 0, false
}

@(require_results)
_delete_file :: proc(path: string) -> bool {
    _js_unsupported()
    return false
}

@(require_results)
_read_file_by_path :: proc(path: string, allocator := context.allocator) -> (data: []byte, ok: bool) {
    _js_unsupported()
    return nil, false
}

@(require_results)
_write_file_by_path :: proc(path: string, data: []u8) -> bool {
    _js_unsupported()
    return false
}

@(require_results)
_file_exists :: proc(path: string) -> bool {
    _js_unsupported()
    return false
}

@(require_results)
_clone_file :: proc(path: string, new_path: string, fail_if_exists := true) -> bool {
    _js_unsupported()
    return false
}

@(require_results)
_read_file_by_path_async :: proc(file: ^Async_File, path: string, allocator := context.allocator) -> bool {
    _js_unsupported()
    return false
}

@(require_results)
_async_file_wait :: proc(file: ^Async_File) -> (buffer: []byte, ok: bool) {
    _js_unsupported()
    return {}, false
}

@(require_results)
_create_directory :: proc(path: string) -> bool {
    _js_unsupported()
    return false
}

@(require_results)
_is_file :: proc(path: string) -> bool {
    return false
}

@(require_results)
_is_directory :: proc(path: string) -> bool {
    return false
}

@(require_results)
_iter_directory :: proc(iter: ^Directory_Iter, pattern: string, allocator := context.temp_allocator) -> (result: string, ok: bool) {
    return "", false
}

@(require_results)
_init_file_watcher :: proc(watcher: ^File_Watcher, path: string, recursive := false) -> bool {
    return false
}

@(require_results)
_poll_file_watcher :: proc(watcher: ^File_Watcher) -> []string {
    return nil
}

_destroy_file_watcher :: proc(watcher: ^File_Watcher) {
}

@(require_results)
_file_dialog :: proc(mode: File_Dialog_Mode, default_path: string, patterns: []File_Pattern, title := "") -> (string, bool) {
    // TODO
    _js_unsupported()
    return {}, false
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Internal
//

_js_unsupported :: proc(loc := #caller_location) {
    // NOTE: this doesn't mean it won't be implemented at some point if possible.
    // base.log_warn("'%s' is not supported on JS target", loc.procedure, loc = loc)
}

_js_mouse_button :: proc(index: i16) -> Mouse_Button {
    // https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent/button
    switch index {
    case 0: return .Left // Main button, usually the left button or the un-initialized state
    case 1: return .Middle // Auxiliary button, usually the wheel button or the middle button (if present)
    case 2: return .Right // Secondary button, usually the right button
    case 3: return .Extra_1 // Fourth button, typically the Browser Back button
    case 4: return .Extra_2 // Fifth button, typically the Browser Forward button
    }
    assert(false)
    return .Left
}

_js_key_code :: proc(str: string) -> Key {
    // https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent
    // https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/code
    // TODO: first match prefix for faster lookups?
    switch str {
    case "ArrowLeft":   return .Left
    case "ArrowRight":  return .Right
    case "ArrowUp":     return .Up
    case "ArrowDown":   return .Down

    case "Digit0": return .Num0
    case "Digit1": return .Num1
    case "Digit2": return .Num2
    case "Digit3": return .Num3
    case "Digit4": return .Num4
    case "Digit5": return .Num5
    case "Digit6": return .Num6
    case "Digit7": return .Num7
    case "Digit8": return .Num8
    case "Digit9": return .Num9

    case "KeyA": return .A
    case "KeyB": return .B
    case "KeyC": return .C
    case "KeyD": return .D
    case "KeyE": return .E
    case "KeyF": return .F
    case "KeyG": return .G
    case "KeyH": return .H
    case "KeyI": return .I
    case "KeyJ": return .J
    case "KeyK": return .K
    case "KeyL": return .L
    case "KeyM": return .M
    case "KeyN": return .N
    case "KeyO": return .O
    case "KeyP": return .P
    case "KeyQ": return .Q
    case "KeyR": return .R
    case "KeyS": return .S
    case "KeyT": return .T
    case "KeyU": return .U
    case "KeyV": return .V
    case "KeyW": return .W
    case "KeyX": return .X
    case "KeyY": return .Y
    case "KeyZ": return .Z

    case "Space":           return .Space
    case "Quote":           return .Apostrophe
    case "Comma":           return .Comma
    case "Minus":           return .Minus
    case "Period":          return .Period
    case "Slash":           return .Slash
    case "Semicolon":       return .Semicolon
    case "Equal":           return .Equal
    case "BracketLeft":     return .Left_Bracket
    case "Backslash":       return .Backslash
    case "BracketRight":    return .Right_Bracket
    case "Backquote":       return .Backtick

    case "AltLeft":         return .Left_Alt
    case "ShiftLeft":       return .Left_Shift
    case "ShiftRight":      return .Right_Shift
    case "ControlLeft":     return .Left_Control
    case "ControlRight":    return .Right_Control
    case "Tab":             return .Tab
    case "Enter":           return .Enter
    case "Escape":          return .Escape
    case "Delete":          return .Delete
    }

    return .Invalid
}


_JS_Event_Callback :: #type proc(event: js.Event)

@(rodata)
_js_event_callbacks := [js.Event_Kind]_JS_Event_Callback {
    .Invalid = nil,
    .Load = nil,
    .Unload = nil,
    .Error = nil,

    .Resize = proc(e: js.Event) {
        _event_queue_push(Event_Window_Size{
            size = _get_window_frame_rect({}).size,
        })
    },

    .Visibility_Change = nil,
    .Fullscreen_Change = nil,
    .Fullscreen_Error = nil,
    .Click = nil,
    .Double_Click = nil,

    .Mouse_Move = proc(e: js.Event) {
        assert(e.kind == .Mouse_Move)

        // If the app wants the mouse locked, and it's not locked
        // because the browser decided so (e.g. user pressed Escape),
        // don't return mouse movement.
        if _state.mouse_relative {
            if !_get_pointer_lock(_CANVAS_ID) {
                return
            }
        }

        _event_queue_push(Event_Mouse{
            pos = {i32(e.mouse.client.x), i32(e.mouse.client.y)},
            move = {i32(e.mouse.movement.x), i32(e.mouse.movement.y)},
        })
    },

    .Mouse_Over = nil,
    .Mouse_Out = nil,

    .Mouse_Up = proc(e: js.Event) {
        assert(e.kind == .Mouse_Up)
        _event_queue_push(Event_Mouse_Button{
            button = _js_mouse_button(e.mouse.button),
            pressed = false,
        })
    },

    .Mouse_Down = proc(e: js.Event) {
        assert(e.kind == .Mouse_Down)
        _event_queue_push(Event_Mouse_Button{
            button = _js_mouse_button(e.mouse.button),
            pressed = true,
        })

        if _state.mouse_relative {
            _set_pointer_lock(_CANVAS_ID, true)
        } else {
            _set_pointer_lock(_CANVAS_ID, false)
        }
    },

    .Key_Up = proc(e: js.Event) {
        assert(e.kind == .Key_Up)
        key := _js_key_code(e.key.code)
        if key == .Invalid do return
        _event_queue_push(Event_Key{
            key = key,
            pressed = false,
        })
    },

    .Key_Down = proc(e: js.Event) {
        assert(e.kind == .Key_Down)
        key := _js_key_code(e.key.code)
        if key == .Invalid do return
        _event_queue_push(Event_Key{
            key = key,
            pressed = true,
        })
    },

    .Key_Press = nil, // obsolete

    .Scroll = proc(e: js.Event) {
        assert(e.kind == .Scroll)
        event: Event_Scroll
        event.delta = {f32(e.scroll.delta.x), f32(e.scroll.delta.y)}
        _event_queue_push(event)
    },

    .Wheel = proc(e: js.Event) {
        assert(e.kind == .Wheel)
        event: Event_Scroll
        // TODO: e.wheel.delta_mode
        event.delta = {f32(e.wheel.delta.x), f32(e.wheel.delta.y)}
        _event_queue_push(event)
    },

    .Focus = nil,
    .Focus_In = nil,
    .Focus_Out = nil,

    .Submit = nil,
    .Blur = nil,
    .Change = nil,
    .Hash_Change = nil,
    .Select = nil,

    .Animation_Start = nil,
    .Animation_End = nil,
    .Animation_Iteration = nil,
    .Animation_Cancel = nil,

    .Copy = nil,
    .Cut = nil,
    .Paste = nil,

    .Pointer_Cancel = nil,
    .Pointer_Down = nil,
    .Pointer_Enter = nil,
    .Pointer_Leave = nil,
    .Pointer_Move = nil,
    .Pointer_Over = nil,
    .Pointer_Up = nil,
    .Got_Pointer_Capture = nil,
    .Lost_Pointer_Capture = nil,
    .Pointer_Lock_Change = nil,
    .Pointer_Lock_Error = nil,

    .Selection_Change = nil,
    .Selection_Start = nil,

    .Touch_Cancel = nil,
    .Touch_End = nil,
    .Touch_Move = nil,
    .Touch_Start = nil,
    .Transition_Start = nil,
    .Transition_End = nil,
    .Transition_Run = nil,
    .Transition_Cancel = nil,
    .Context_Menu = nil,

    .Gamepad_Connected = nil,
    .Gamepad_Disconnected = nil,

    .Custom = nil,
}


foreign import "odin_env"

foreign odin_env {
    @(link_name="time_now")     _time_now :: proc "contextless" () -> i64 ---
    @(link_name="tick_now")     _tick_now :: proc "contextless" () -> f64 ---
}


@(export)
foreign import raven_platform "raven_platform"

@(default_calling_convention="c")
foreign raven_platform {
    @(link_name="init")
    _init_js :: proc "contextless" (canvas: string) ---

    // lock=true Only works when called from user gesture.
    @(link_name="set_pointer_lock")
    _set_pointer_lock :: proc "contextless" (canvas: string, lock: b32) ---

    // Check if the mouse is *actually* locked. It doesn't have to be after calling set_pointer_lock.
    @(link_name="get_pointer_lock")
    _get_pointer_lock :: proc "contextless" (canvas: string) -> b32 ---
}
