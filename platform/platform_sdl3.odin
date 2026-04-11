#+build !js
package raven_platform

import "base:runtime"
import "../base"
import "vendor:sdl3"

_ :: runtime
_ :: base
_ :: sdl3

BACKEND_SDL3 :: "SDL3"

when BACKEND == BACKEND_SDL3 {

    _State :: struct { _: u8 }

    _File_Handle :: struct {
    }

    _Async_File :: struct { _: u8 }

    _File_Watcher :: struct { _: u8 }

    _Directory_Iter :: struct { _: u8 }

    _Barrier :: struct { _: u8 }

    _Thread :: struct {
        thread: ^sdl3.Thread,
    }

    _Window :: struct {
        window: ^sdl3.Window,
    }

    _Module :: struct { _: u8 }

    _init :: proc() {
        if !sdl3.Init({.VIDEO, .EVENTS, .GAMEPAD}) {
            panic("Failed to initialize SDL3")
        }
    }

    _shutdown :: proc() {
        sdl3.Quit()
    }



    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Common
    //

    @(require_results)
    _get_commandline_args :: proc(allocator := context.allocator) -> []string {
    }

    @(require_results)
    _run_shell_command :: proc(command: string) -> int {
    }

    _exit_process :: proc(code: int) -> ! {
        runtime.trap()
    }

    _register_default_exception_handler :: proc() {}

    @(require_results)
    _memory_protect :: proc(ptr: rawptr, num_bytes: int, protect: Memory_Protection) -> bool {

    }

    @(require_results)
    _clipboard_set :: proc(data: []byte, format: Clipboard_Format = .Text) -> bool {
        switch format {
        case .Text:
            sdl3.SetClipboardText(
                clone_to_cstring(data)
            )
        case:
            unimplemented()
        }
        return false
    }

    @(require_results)
    _clipboard_get :: proc(format: Clipboard_Format = .Text, allocator := context.temp_allocator) -> ([]byte, bool) {
        switch format {
        case .Text:
            if !sdl3.HasClipboardText() {
                return {}, false
            }
            text := string(cstring(sdl3.GetClipboardText()))
            return transmute([]byte)text, true
        case:
            unimplemented()
        }
        return {}, false
    }

    @(require_results)
    _get_gamepad_state :: proc(#any_int index: int) -> (result: Gamepad_State, ok: bool) {
        sdl3.GetGamepadFromPlayerIndex
    }

    @(require_results)
    _set_gamepad_feedback :: proc(#any_int index: int, output: Gamepad_Feedback) -> bool {

    }


    @(require_results)
    _get_user_data_dir :: proc(allocator := context.allocator) -> string {
        return clone_to_cstring(sdl3.GetUserFolder(.SAVEDGAMES))
    }

    _set_mouse_relative :: proc(window: Window, relative: bool) {
        sdl3.SetWindowRelativeMouseMode(window.window, relative)
        sdl3.SetWindowMouseGrab(window.window, relative)
    }

    _set_mouse_visible :: proc(visible: bool) {
    }

    _set_dpi_aware :: proc() {

    }

    @(require_results)
    _get_main_monitor_rect :: proc() -> Rect {
    }

    @(require_results)
    _set_current_directory :: proc(path: string) -> bool {
    }

    @(require_results)
    _get_executable_path :: proc(allocator := context.temp_allocator) -> string {

    }

    @(require_results)
    _load_module :: proc(path: string) -> (result: Module, ok: bool) {
    }

    _unload_module :: proc(module: Module) {

    }

    @(require_results)
    _get_module_symbol_address :: proc(module: Module, cstr: cstring) -> (result: rawptr) {

    }

    _sleep_ms :: proc(#any_int ms: int) {
    }

    @(require_results)
    _get_time_ns :: proc() -> u64 {
        return sdl3.GetTicksNS()
    }


    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Thread
    //

    @(require_results)
    _create_thread :: proc(procedure: Thread_Proc, name: string) -> (result: Thread) {
        result.thread = sdl3.CreateThread(_thread_proc, clone_to_cstring(name), procedure)

        return

        _thread_proc :: proc "c" (data: rawptr) -> i32 {
            proc_ptr = transmute(Thread_Proc)data
            proc_ptr()
        }
    }

    _join_thread :: proc(thread: Thread) {
        sdl3.WaitThread(thread.thread, nil)
    }

    @(require_results)
    _get_current_thread :: proc() -> Thread {
    }

    @(require_results)
    _get_current_thread_id :: proc() -> u64 {

    }



    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Window
    //

    @(require_results)
    _create_window :: proc(name: string, style: Window_Style = .Regular, full_rect: Rect = {}) -> Window {
        flags: sdl3.WindowFlags

        if style == .Borderless {
            flags += {.BORDERLESS}
        }

        name_ptr := strings.clone_to_cstring(name, context.temp_allocator)

        x := full_rect.min.x
        y := full_rect.min.y
        w := full_rect.size.x
        h := full_rect.size.y

        wnd := sdl3.CreateWindow(name_ptr, w, h, flags)
        if wnd == nil {
            return {}
        }

        return Window{native = {handle = wnd}}
    }

    _destroy_window :: proc(window: Window) {
        sdl3.DestroyWindow(window.window)
    }

    @(require_results)
    _get_window_dpi_scale :: proc(window: Window) -> f32 {
        return sdl3.GetWindowDisplayScale(window.window)
    }

    _set_window_title :: proc(window: Window, name: string) {
        sdl3.SetWindowTitle(window.window, clone_to_cstring(name))
    }

    _set_window_style :: proc(window: Window, style: Window_Style) {

    }

    _set_window_pos :: proc(window: Window, pos: [2]i32) {
        sdl3.SetWindowPosition(window.window, pos.x, pos.y)
    }

    _set_window_size :: proc(window: Window, size: [2]i32) {
        sdl3.SetWindowSize(window.window, pos.x, pos.y)
    }

    @(require_results)
    _get_window_frame_rect :: proc(window: Window) -> Rect {
    }

    @(require_results)
    _get_window_full_rect :: proc(window: Window) -> Rect {

    }

    _set_mouse_pos_window_relative :: proc(window: Window, pos: [2]i32) {
        sdl3.WarpMouseInWindow(window.window, f32(pos.x), f32(pos.y))
    }

    @(require_results)
    _is_window_minimized :: proc(window: Window) -> bool {

    }

    @(require_results)
    _is_window_focused :: proc(window: Window) -> bool {

    }

    @(require_results)
    _get_native_window_ptr :: proc(window: Window) -> rawptr {

    }

    @(require_results)
    _poll_window_events :: proc(window: Window) -> (ok: bool) {

    }



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Barrier
    //

    @(require_results)
    _barrier_create :: proc(num_threads: int) -> (result: Barrier) {

    }

    _barrier_delete :: proc(barrier: ^Barrier) {

    }

    _barrier_sync :: proc(barrier: ^Barrier) {

    }



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: File IO
    //

    @(require_results)
    _open_file :: proc(path: string) -> (File_Handle, bool) {

    }

    _close_file :: proc(handle: File_Handle) {

    }

    @(require_results)
    _get_last_write_time :: proc(handle: File_Handle) -> (u64, bool) {

    }

    @(require_results)
    _delete_file :: proc(path: string) -> bool {

    }

    @(require_results)
    _read_file_by_path :: proc(path: string, allocator := context.allocator) -> (data: []byte, ok: bool) {

    }

    @(require_results)
    _write_file_by_path :: proc(path: string, data: []u8) -> bool {

    }

    @(require_results)
    _file_exists :: proc(path: string) -> bool {

    }

    @(require_results)
    _clone_file :: proc(path: string, new_path: string, fail_if_exists := true) -> bool {

    }

    @(require_results)
    _read_file_by_path_async :: proc(file: ^Async_File, path: string, allocator := context.allocator) -> bool {

    }

    @(require_results)
    _async_file_wait :: proc(file: ^Async_File) -> (buffer: []byte, ok: bool) {

    }

    @(require_results)
    _create_directory :: proc(path: string) -> bool {

    }

    @(require_results)
    _is_file :: proc(path: string) -> bool {

    }

    @(require_results)
    _is_directory :: proc(path: string) -> bool {

    }

    @(require_results)
    _iter_directory :: proc(iter: ^Directory_Iter, pattern: string, allocator := context.temp_allocator) -> (result: string, ok: bool) {

    }

    @(require_results)
    _init_file_watcher :: proc(watcher: ^File_Watcher, path: string, recursive := false) -> bool {

    }

    @(require_results)
    _poll_file_watcher :: proc(watcher: ^File_Watcher) -> []string {

    }

    _destroy_file_watcher :: proc(watcher: ^File_Watcher) {

    }

    @(require_results)
    _file_dialog :: proc(mode: File_Dialog_Mode, default_path: string, patterns: []File_Pattern, title := "") -> (string, bool) {
    }

    _sdl_mouse_button :: proc(b: u8) -> Mouse_Button {
        switch b {
        case sdl3.BUTTON_LEFT:   return .Left
        case sdl3.BUTTON_MIDDLE: return .Middle
        case sdl3.BUTTON_RIGHT:  return .Right
        case sdl3.BUTTON_X1:     return .Extra_1
        case sdl3.BUTTON_X2:     return .Extra_2
        }
        return .Left
    }

}