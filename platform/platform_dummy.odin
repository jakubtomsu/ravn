// Dummy backend for testing.
// Everything *must compile* on all targets, but won't run (by design)
// This can be a starting point when writing a new backend from scratch.
package ravn_platform

import "base:runtime"

when BACKEND == BACKEND_DUMMY {

    _State :: struct { _: u8 }

    _File_Handle :: struct { _: u8 }
    _Directory_Iter :: struct { _: u8 }
    _Thread :: struct { _: u8 }
    _Window :: struct { _: u8 }
    _Module :: struct { _: u8 }

    dummy :: proc "contextless" () -> ! {
        panic_contextless("Error: trying to call platform procedures with the dummy backend")
    }


    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Common
    //

    _init :: proc() { dummy() }
    _shutdown :: proc() { dummy() }

    _register_default_exception_handler :: proc() {}

    @(require_results) _clipboard_set :: proc(data: string) -> bool { dummy() }
    @(require_results) _clipboard_get :: proc(allocator := context.temp_allocator) -> (string, bool) { dummy() }
    @(require_results) _get_gamepad_state :: proc(#any_int index: int) -> (result: Gamepad_State, ok: bool) { dummy() }
    @(require_results) _set_gamepad_feedback :: proc(#any_int index: int, output: Gamepad_Feedback) -> bool { dummy() }

    @(require_results) _get_user_data_dir :: proc(allocator := context.allocator) -> string { dummy() }
    _set_mouse_relative :: proc(window: Window, relative: bool) { dummy() }
    _set_mouse_visible :: proc(visible: bool) { dummy() }
    @(require_results) _get_main_monitor_rect :: proc() -> Rect { dummy() }
    @(require_results) _get_executable_path :: proc(allocator := context.temp_allocator) -> string { dummy() }

    _refresh_cpu_core_info :: proc() {}
    _pin_thread_to_cpu_core :: proc(thread: Thread, core_index: int) -> bool { return false }
    @(require_results) _file_dialog :: proc(mode: File_Dialog_Mode, default_path: string, patterns: []File_Pattern, title := "") -> (string, bool) { dummy() }


    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Window
    //

    @(require_results) _create_window :: proc(name: string, style: Window_Style = .Regular, full_rect: Rect = {}, high_dpi: bool) -> Window { dummy() }
    _destroy_window :: proc(window: Window) { dummy() }
    @(require_results) _get_window_dpi_scale :: proc(window: Window) -> f32 { dummy() }
    _set_window_title :: proc(window: Window, name: string) { dummy() }
    _set_window_style :: proc(window: Window, style: Window_Style) { dummy() }
    _set_window_pos :: proc(window: Window, pos: [2]i32) { dummy() }
    _set_window_size :: proc(window: Window, size: [2]i32) { dummy() }
    @(require_results) _get_window_rect :: proc(window: Window) -> Rect { dummy() }
    _set_mouse_pos_window_relative :: proc(window: Window, pos: [2]i32) { dummy() }
    @(require_results) _is_window_minimized :: proc(window: Window) -> bool { dummy() }
    @(require_results) _is_window_focused :: proc(window: Window) -> bool { dummy() }
    @(require_results) _get_native_window_ptr :: proc(window: Window) -> rawptr { dummy() }
    @(require_results) _poll_window_events :: proc(window: Window) -> (ok: bool) { dummy() }
}
