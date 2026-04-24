// Dummy backend for testing.
// Everything *must compile* on all targets, but won't run (by design)
// This can be a starting point when writing a new backend from scratch.
package raven_platform

when BACKEND == BACKEND_DUMMY {

    _State :: struct { _: u8 }

    _File_Handle :: struct { _: u8 }
    _File_Watcher :: struct { _: u8 }
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

    @(require_results) _get_commandline_args :: proc(allocator := context.allocator) -> []string { dummy() }
    @(require_results) _run_shell_command :: proc(command: string) -> int { dummy() }
    _exit_process :: proc(code: int) -> ! { dummy() }
    _register_default_exception_handler :: proc() {}

    @(require_results) _memory_protect :: proc(ptr: rawptr, num_bytes: int, protect: Memory_Protection) -> bool { dummy() }
    @(require_results) _clipboard_set :: proc(data: string) -> bool { dummy() }
    @(require_results) _clipboard_get :: proc(allocator := context.temp_allocator) -> (string, bool) { dummy() }
    @(require_results) _get_gamepad_state :: proc(#any_int index: int) -> (result: Gamepad_State, ok: bool) { dummy() }
    @(require_results) _set_gamepad_feedback :: proc(#any_int index: int, output: Gamepad_Feedback) -> bool { dummy() }

    @(require_results) _get_user_data_dir :: proc(allocator := context.allocator) -> string { dummy() }
    _set_mouse_relative :: proc(window: Window, relative: bool) { dummy() }
    _set_mouse_visible :: proc(visible: bool) { dummy() }
    _set_dpi_aware :: proc() { dummy() }
    @(require_results) _get_main_monitor_rect :: proc() -> Rect { dummy() }
    @(require_results) _set_current_directory :: proc(path: string) -> bool { dummy() }
    @(require_results) _get_executable_path :: proc(allocator := context.temp_allocator) -> string { dummy() }
    @(require_results) _load_module :: proc(path: string) -> (result: Module, ok: bool) { dummy() }
    _unload_module :: proc(module: Module) { dummy() }
    @(require_results) _get_module_symbol_address :: proc(module: Module, cstr: cstring) -> (result: rawptr) { dummy() }
    _sleep_ms :: proc(#any_int ms: int) { dummy() }
    @(require_results) _get_time_ns :: proc() -> u64 { dummy() }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Thread
    //

    @(require_results) _create_thread :: proc(procedure: Thread_Proc, name: string) -> Thread { dummy() }
    _join_thread :: proc(thread: Thread) { dummy() }
    _set_thread_name :: proc(thread: Thread, name: string) { dummy() }
    @(require_results) _get_current_thread :: proc() -> Thread { dummy() }
    @(require_results) _get_current_thread_id :: proc() -> u64 { dummy() }


    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Window
    //

    @(require_results) _create_window :: proc(name: string, style: Window_Style = .Regular, full_rect: Rect = {}) -> Window { dummy() }
    _destroy_window :: proc(window: Window) { dummy() }
    @(require_results) _get_window_dpi_scale :: proc(window: Window) -> f32 { dummy() }
    _set_window_title :: proc(window: Window, name: string) { dummy() }
    _set_window_style :: proc(window: Window, style: Window_Style) { dummy() }
    _set_window_pos :: proc(window: Window, pos: [2]i32) { dummy() }
    _set_window_size :: proc(window: Window, size: [2]i32) { dummy() }
    @(require_results) _get_window_frame_rect :: proc(window: Window) -> Rect { dummy() }
    @(require_results) _get_window_full_rect :: proc(window: Window) -> Rect { dummy() }
    _set_mouse_pos_window_relative :: proc(window: Window, pos: [2]i32) { dummy() }
    @(require_results) _is_window_minimized :: proc(window: Window) -> bool { dummy() }
    @(require_results) _is_window_focused :: proc(window: Window) -> bool { dummy() }
    @(require_results) _get_native_window_ptr :: proc(window: Window) -> rawptr { dummy() }
    @(require_results) _poll_window_events :: proc(window: Window) -> (ok: bool) { dummy() }


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: File IO
    //

    @(require_results) _open_file :: proc(path: string) -> (File_Handle, bool) { dummy() }
    _close_file :: proc(handle: File_Handle) { dummy() }
    @(require_results) _get_last_write_time :: proc(handle: File_Handle) -> (u64, bool) { dummy() }
    @(require_results) _delete_file :: proc(path: string) -> bool { dummy() }
    @(require_results) _read_file_by_path :: proc(path: string, allocator := context.allocator) -> (data: []byte, ok: bool) { dummy() }
    @(require_results) _write_file_by_path :: proc(path: string, data: []u8) -> bool { dummy() }
    @(require_results) _file_exists :: proc(path: string) -> bool { dummy() }
    @(require_results) _clone_file :: proc(path: string, new_path: string, fail_if_exists := true) -> bool { dummy() }
    @(require_results) _create_directory :: proc(path: string) -> bool { dummy() }
    @(require_results) _is_file :: proc(path: string) -> bool { dummy() }
    @(require_results) _is_directory :: proc(path: string) -> bool { dummy() }
    @(require_results) _iter_directory :: proc(iter: ^Directory_Iter, pattern: string, allocator := context.temp_allocator) -> (result: string, ok: bool) { dummy() }
    @(require_results) _init_file_watcher :: proc(watcher: ^File_Watcher, path: string, recursive := false) -> bool { dummy() }
    @(require_results) _poll_file_watcher :: proc(watcher: ^File_Watcher) -> []string { dummy() }
    _destroy_file_watcher :: proc(watcher: ^File_Watcher) { dummy() }
    @(require_results) _file_dialog :: proc(mode: File_Dialog_Mode, default_path: string, patterns: []File_Pattern, title := "") -> (string, bool) { dummy() }
}
