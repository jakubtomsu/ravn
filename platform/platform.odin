#+vet explicit-allocators shadowing unused
package ravn_platform

BACKEND :: #config(PLATFORM_BACKEND, DEFAULT_BACKEND)

BACKEND_DUMMY :: "Dummy"
BACKEND_WINDOWS :: "Windows"
BACKEND_JS :: "JS"

when ODIN_OS == .Windows {
    DEFAULT_BACKEND :: BACKEND_WINDOWS
} else when ODIN_OS == .JS {
    DEFAULT_BACKEND :: BACKEND_JS
} else when ODIN_OS == .Linux {
    DEFAULT_BACKEND :: BACKEND_SDL3
} else when ODIN_OS == .Darwin {
    DEFAULT_BACKEND :: BACKEND_SDL3
} else {
    #panic("Platform not supported")
    DEFAULT_BACKEND :: BACKEND_DUMMY
}

SEPARATOR :: "\\" when ODIN_OS == .Windows else "/"

EVENT_QUEUE_SIZE :: 256
MAX_CORE_INFO :: 256
MAX_GAMEPADS :: 4

_state: ^State

State :: struct {
    using native:       _State,

    mouse_pos:          [2]i32,
    mouse_relative:     bool,
    mouse_visible:      bool,

    event_queue:        _Event_Queue,
    event_counter:      i32,
}

Rect :: struct {
    min:    [2]i32, // top left
    size:   [2]i32, // positive Y is down
}

Window :: struct {
    using native: _Window,
}

Window_Style :: enum u8 {
    Regular = 0,
    Borderless,
}

Event :: union {
    Event_Exit,
    Event_Key,
    Event_Mouse,
    Event_Mouse_Button,
    Event_Scroll,
    Event_Window_Size,
}

Event_Exit :: struct {}

Event_Key :: struct {
    key:        Key,
    pressed:    bool,
}

Event_Mouse :: struct {
    pos:    [2]i32,
    move:   [2]i32,
}

Event_Mouse_Button :: struct {
    button:     Mouse_Button,
    pressed:    bool,
}

Event_Scroll :: struct {
    delta:  [2]f32,
}

Event_Window_Size :: struct {
    size:   [2]i32,
}

File_Dialog_Mode :: enum u8 {
    Open,
    Save,
}

File_Pattern :: struct {
    desc:    string,
    filters: []string,
}

Gamepad_State :: struct {
    buttons:    bit_set[Gamepad_Button], // set if down
    axes:       [Gamepad_Axis]f32,
}

Gamepad_Axis :: enum u8 {
    Left_Trigger,
    Right_Trigger,
    Left_Thumb_X,
    Left_Thumb_Y,
    Right_Thumb_X,
    Right_Thumb_Y,
}

Gamepad_Button :: enum u8 {
    DPad_Up,
    DPad_Down,
    DPad_Left,
    DPad_Right,
    Start,
    Back,
    Left_Thumb,
    Right_Thumb,
    Left_Shoulder,
    Right_Shoulder,
    A,
    B,
    X,
    Y,
}

Gamepad_Feedback :: struct {
    left_motor_speed:   f32,
    right_motor_speed:  f32,
}

Mouse_Button :: enum u8 {
    Left,
    Middle,
    Right,
    Extra_1,
    Extra_2,
}

Key :: enum u8 {
    Invalid = 0,

    Num0, Num1, Num2, Num3, Num4, Num5, Num6, Num7, Num8, Num9,

    A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,

    Space,
    Apostrophe,    // '
    Comma,         // ,
    Minus,         // -
    Period,        // .
    Slash,         // /
    Semicolon,     // ;
    Equal,         // =
    Left_Bracket,  // [
    Backslash,     // \
    Right_Bracket, // ]
    Backtick,      // ` (Grave Accent)
    World_1,       // Non-Us #1
    World_2,       // Non-Us #2

    // Function Keys
    Escape,
    Enter,
    Tab,
    Backspace,
    Insert,
    Delete,
    Right,
    Left,
    Down,
    Up,
    Page_Up,
    Page_Down,
    Home,
    End,
    Capslock,
    Scroll_Lock,
    Num_Lock,
    Print_Screen,
    Pause,

    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12, F13, F14, F15, F16, F17, F18, F19, F20, F21, F22, F23, F24, F25,

    Keypad_0, Keypad_1, Keypad_2, Keypad_3, Keypad_4, Keypad_5, Keypad_6, Keypad_7, Keypad_8, Keypad_9,

    Keypad_Decimal,
    Keypad_Divide,
    Keypad_Multiply,
    Keypad_Subtract,
    Keypad_Add,
    Keypad_Enter,
    Keypad_Equal,
    Left_Shift,
    Left_Control,
    Left_Alt,
    Left_Super,
    Right_Shift,
    Right_Control,
    Right_Alt,
    Right_Super,
    Menu,
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: General
//

set_state_ptr :: proc(state: ^State) {
    _state = state
}

get_state_ptr :: proc() -> (state: ^State) {
    return _state
}

init :: proc(state: ^State) {
    if _state != nil {
        return
    }

    _state = state

    _init()

    _state.mouse_visible = true
}

shutdown :: proc() {
    if _state == nil {
        return
    }

    _shutdown()

    _state = nil
}


clipboard_set :: proc(data: string) -> bool {
    return _clipboard_set(data)
}

clipboard_get :: proc(allocator := context.temp_allocator) -> (string, bool) {
    return _clipboard_get(allocator)
}

@(require_results)
get_gamepad_state :: proc(#any_int index: int) -> (result: Gamepad_State, ok: bool) {
    return _get_gamepad_state(index)
}

set_gamepad_feedback :: proc(#any_int index: int, output: Gamepad_Feedback) -> bool {
    return _set_gamepad_feedback(index, output)
}

get_user_data_dir :: proc(allocator := context.allocator) -> string {
    return _get_user_data_dir(allocator)
}

set_mouse_relative :: proc(window: Window, relative: bool) {
    if relative == _state.mouse_relative {
        return
    }

    _state.mouse_relative = relative
    _set_mouse_relative(window, relative)
}

set_mouse_visible :: proc(visible: bool) {
    if _state.mouse_visible == visible {
        return
    }
    _state.mouse_visible = visible
    _set_mouse_visible(visible)
}

register_default_exception_handler :: proc() {
    _register_default_exception_handler()
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Window
//

@(require_results)
create_window :: proc(name: string, style: Window_Style = .Regular, rect: Rect = {}, high_dpi := false) -> Window {
    rect := rect

    if rect.size == 0 {
        monitor := get_main_monitor_rect()
        switch style {
        case .Borderless:
            rect = monitor

        case .Regular:
            rect = {
                min = monitor.min + monitor.size / 4,
                size = monitor.size / 2,
            }
        }
    }

    return _create_window(name, style, rect, high_dpi)
}

destroy_window :: proc(window: Window) {
    _destroy_window(window)
}

set_window_title :: proc(window: Window, name: string) {
    _set_window_title(window, name)
}

set_window_style :: proc(window: Window, style: Window_Style) {
    _set_window_style(window, style)
}

set_window_pos :: proc(window: Window, pos: [2]i32) {
    _set_window_pos(window, pos)
}

set_window_size :: proc(window: Window, size: [2]i32) {
    _set_window_size(window, size)
}

// Drawable area within the window, without decorators.
get_window_rect :: proc(window: Window) -> Rect {
    return _get_window_rect(window)
}

set_mouse_pos_window_relative :: proc(window: Window, pos: [2]i32) {
    _set_mouse_pos_window_relative(window, pos)
}

is_window_minimized :: proc(window: Window) -> bool {
    return _is_window_minimized(window)
}

is_window_focused :: proc(window: Window) -> bool {
    return _is_window_focused(window)
}

@(require_results)
get_window_dpi_scale :: proc(window: Window) -> f32 {
    return _get_window_dpi_scale(window)
}

// HWND on windows
@(require_results)
get_native_window_ptr :: proc(window: Window) -> rawptr {
    return _get_native_window_ptr(window)
}


@(require_results)
poll_window_events :: proc(window: Window) -> (event: Event, should_continue: bool) {
    event, should_continue = _event_queue_pop()
    if should_continue {
        return event, true
    }

    _event_queue_clear()

    if !_poll_window_events(window) {
        _state.event_counter = 0
        return nil, false
    }

    _state.event_counter += 1

    // maybe new events are queued up, just not returned
    event, should_continue = _event_queue_pop()
    if should_continue {
        return event, true
    }

    _state.event_counter = 0
    return nil, false
}

get_main_monitor_rect :: proc() -> Rect {
    return _get_main_monitor_rect()
}

file_dialog :: proc(mode: File_Dialog_Mode, default_path: string, patterns: []File_Pattern, title := "") -> (string, bool) {
    return _file_dialog(mode, default_path, patterns, title)
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Internal
//

_Event_Queue :: struct {
    events: [EVENT_QUEUE_SIZE]Event,
    len:    i32,
    offset: i32,
}


_event_queue_push :: proc(event: Event, loc := #caller_location) {
    assert(event != nil, loc = loc)
    if _state.event_queue.len < len(_state.event_queue.events) {
        _state.event_queue.events[(_state.event_queue.offset + _state.event_queue.len) % len(_state.event_queue.events)] = event
        _state.event_queue.len += 1
    }
}

@(require_results)
_event_queue_pop :: proc(loc := #caller_location) -> (result: Event, ok: bool) {
    if _state.event_queue.len <= 0 {
        return nil, false
    }
    result = _state.event_queue.events[(_state.event_queue.offset) % len(_state.event_queue.events)]
    _state.event_queue.offset += 1
    _state.event_queue.len -= 1
    assert(result != nil, loc = loc)
    return result, true
}

_event_queue_clear :: proc() {
    _state.event_queue.len = 0
    _state.event_queue.offset = 0
}
