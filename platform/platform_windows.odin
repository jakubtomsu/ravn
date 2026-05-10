#+build windows
#+vet explicit-allocators shadowing unused
package ravn_platform

// TODO: FIXME: on very low FPS input messages seem to get dropped

import "../base"
import "base:intrinsics"
import "base:runtime"
import "core:sys/windows"

_ :: base
_ :: intrinsics
_ :: runtime
_ :: windows

// https://ph3at.github.io/posts/Windows-Input/

when BACKEND == BACKEND_WINDOWS {

    foreign import kernel32 "system:Kernel32.lib"
    foreign import user32 "system:User32.lib"

    _State :: struct {
        last_mouse_wparam:      windows.WPARAM,
        message_hook_proc:      Win32_Message_Hook_Proc,
        message_hook_data:      rawptr,
        xinput_valid:           bit_set[0..<MAX_GAMEPADS],
        xinput_query_index:     i32,
        xinput_query_counter:   f32,
        perf_counter_freq:      windows.LARGE_INTEGER,
        perf_counter_start:     windows.LARGE_INTEGER,
    }

    _Window :: struct {
        hwnd:   windows.HWND,
    }

    _Module :: struct {
        hmod:   windows.HMODULE,
    }

    _Thread :: struct {
        handle: windows.HANDLE,
    }

    _File_Watcher :: struct {
        handle:             windows.HANDLE,
        buffer:             [1024]byte,
        bytes_returned:     u32,
        recursive:          bool,
        overlapped:         windows.OVERLAPPED,
    }

    _Directory_Iter :: struct {
        handle: windows.HANDLE,
        find:   windows.WIN32_FIND_DATAW,
    }

    _File_Handle :: struct {
        handle: windows.HANDLE,
    }

    Win32_Message_Hook_Proc :: #type proc "system" (
        hwnd:   windows.HWND,
        msg:    windows.UINT,
        wparam: windows.WPARAM,
        lparam: windows.LPARAM,
        data:   rawptr,
    )

    win32_set_message_hook_proc :: proc(message_hook: Win32_Message_Hook_Proc, data: rawptr = nil) {
        _state.message_hook_proc = message_hook
        _state.message_hook_data = data
    }

    _init :: proc() {
        windows.timeBeginPeriod(1)

        _state.xinput_valid = {0, 1, 2, 3}

        windows.QueryPerformanceFrequency(&_state.perf_counter_freq)
        windows.QueryPerformanceCounter(&_state.perf_counter_start)

        ATTACH_PARENT_PROCESS :: transmute(windows.DWORD)i32(-1)
        windows.AttachConsole(ATTACH_PARENT_PROCESS)
    }

    _shutdown :: proc() {
        windows.timeEndPeriod(1)

        windows.GetLastError()
    }

    _exit_process :: proc(code: int) -> ! {
        windows.ExitProcess(windows.DWORD(code))
    }

    _register_default_exception_handler :: proc() {
        windows.AddVectoredExceptionHandler(1, _win32_vectored_exception_handler)
    }

    _win32_vectored_exception_handler :: proc "system" (ptrs: ^windows.EXCEPTION_POINTERS) -> windows.LONG {
        // Filter non-errors
        if ptrs.ExceptionRecord.ExceptionCode < 0xC0000000 {
            return windows.EXCEPTION_CONTINUE_SEARCH
        }

        kind: string
        info: string

        // https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-exception_record
        switch ptrs.ExceptionRecord.ExceptionCode {
        case windows.EXCEPTION_ACCESS_VIOLATION:
            kind = "ACCESS_VIOLATION"
            info = "The thread tried to read from or write to a virtual address for which it does not have the appropriate access."
        case windows.EXCEPTION_ARRAY_BOUNDS_EXCEEDED:
            kind = "ARRAY_BOUNDS_EXCEEDED"
            info = "The thread tried to access an array element that is out of bounds and the underlying hardware supports bounds checking."
        case windows.EXCEPTION_FLT_DENORMAL_OPERAND:
            kind = "FLT_DENORMAL_OPERAND"
            info = "One of the operands in a floating-point operation is denormal. A denormal value is one that is too small to represent as a standard floating-point value."
        case windows.EXCEPTION_FLT_DIVIDE_BY_ZERO:
            kind = "FLT_DIVIDE_BY_ZERO"
            info = "The thread tried to divide a floating-point value by a floating-point divisor of zero."
        case windows.EXCEPTION_FLT_INEXACT_RESULT:
            kind = "FLT_INEXACT_RESULT"
            info = "The result of a floating-point operation cannot be represented exactly as a decimal fraction."
        case windows.EXCEPTION_FLT_INVALID_OPERATION:
            kind = "FLT_INVALID_OPERATION"
            info = "This exception represents any floating-point exception not included in this list."
        case windows.EXCEPTION_FLT_OVERFLOW:
            kind = "FLT_OVERFLOW"
            info = "The exponent of a floating-point operation is greater than the magnitude allowed by the corresponding type."
        case windows.EXCEPTION_FLT_STACK_CHECK:
            kind = "FLT_STACK_CHECK"
            info = "The stack overflowed or underflowed as the result of a floating-point operation."
        case windows.EXCEPTION_FLT_UNDERFLOW:
            kind = "FLT_UNDERFLOW"
            info = "The exponent of a floating-point operation is less than the magnitude allowed by the corresponding type."
        case windows.EXCEPTION_ILLEGAL_INSTRUCTION:
            kind = "ILLEGAL_INSTRUCTION"
            info = "The thread tried to execute an invalid instruction."
        case windows.EXCEPTION_IN_PAGE_ERROR:
            kind = "IN_PAGE_ERROR"
            info = "The thread tried to access a page that was not present, and the system was unable to load the page. For example, this exception might occur if a network connection is lost while running a program over the network."
        case windows.EXCEPTION_INT_DIVIDE_BY_ZERO:
            kind = "INT_DIVIDE_BY_ZERO"
            info = "The thread tried to divide an integer value by an integer divisor of zero."
        case windows.EXCEPTION_INT_OVERFLOW:
            kind = "INT_OVERFLOW"
            info = "The result of an integer operation caused a carry out of the most significant bit of the result."
        case windows.EXCEPTION_INVALID_DISPOSITION:
            kind = "INVALID_DISPOSITION"
            info = "An exception handler returned an invalid disposition to the exception dispatcher. Programmers using a high-level language such as C should never encounter this exception."
        case windows.EXCEPTION_NONCONTINUABLE_EXCEPTION:
            kind = "NONCONTINUABLE_EXCEPTION"
            info = "The thread tried to continue execution after a noncontinuable exception occurred."
        case windows.EXCEPTION_PRIV_INSTRUCTION:
            kind = "PRIV_INSTRUCTION"
            info = "The thread tried to execute an instruction whose operation is not allowed in the current machine mode."
        case windows.EXCEPTION_STACK_OVERFLOW:
            kind = "STACK_OVERFLOW"
            info = "The thread used up its stack."

        case:
            runtime.print_string("Unknown exception:\n")
            runtime.print_u64(u64(ptrs.ExceptionRecord.ExceptionCode))
            runtime.print_string("\n")
            return windows.EXCEPTION_CONTINUE_SEARCH
        }

        runtime.print_string(kind)
        runtime.print_string(" Exception at ")
        runtime.print_uintptr(uintptr(ptrs.ExceptionRecord.ExceptionAddress))
        runtime.print_string(":\n")
        runtime.print_string(info)

        return windows.EXCEPTION_CONTINUE_SEARCH
    }

    _get_user_data_dir :: proc(allocator := context.allocator) -> string {
        S_OK :: 0
        path: windows.LPWSTR
        folder_id := windows.FOLDERID_SavedGames
        if res := windows.SHGetKnownFolderPath(&folder_id, u32(windows.KNOWN_FOLDER_FLAG.CREATE), nil, &path); res == S_OK {
            if str, err := windows.wstring_to_utf8_alloc(cstring16(path), -1, allocator); err == nil {
                return str
            }
        }
        return ""
    }

    _set_mouse_relative :: proc(window: Window, relative: bool) {
        if relative {
            rect := get_window_rect(window)
            set_mouse_pos_window_relative(window, rect.size / 2)

            top_left: windows.POINT = {
                rect.min.x,
                rect.min.y,
            }

            bottom_right: windows.POINT = {
                rect.min.x + rect.size.x,
                rect.min.y + rect.size.y,
            }

            windows.ClientToScreen(window.hwnd, &top_left)
            windows.ClientToScreen(window.hwnd, &bottom_right)

            rect_screen: windows.RECT = {
                top_left.x,
                top_left.y,
                bottom_right.x,
                bottom_right.y,
            }

            windows.ClipCursor(&rect_screen)

            rid: windows.RAWINPUTDEVICE = {
                usUsagePage = 0x01,
                usUsage = 0x02,
                dwFlags = 0,
                hwndTarget = nil,
            }

            windows.RegisterRawInputDevices(&rid, 1, size_of(rid))

        } else {
            windows.ClipCursor(nil)

            rid: windows.RAWINPUTDEVICE = {
                usUsagePage = 0x01,
                usUsage = 0x02,
                dwFlags = windows.RIDEV_REMOVE,
                hwndTarget = nil,
            }

            windows.RegisterRawInputDevices(&rid, 1, size_of(rid))
        }
    }

    _set_mouse_visible :: proc(visible: bool) {
        if visible {
            for {
                if windows.ShowCursor(true) > 0 {
                    break
                }
            }
        } else {
            for {
                if windows.ShowCursor(false) < 0 {
                    break
                }
            }
        }
    }

    @(require_results)
    _memory_protect :: proc(ptr: rawptr, num_bytes: int, protect: Memory_Protection) -> bool {
        new_protect: windows.DWORD
        switch protect {
        case .No_Access:             new_protect = windows.PAGE_NOACCESS
        case .Read:                  new_protect = windows.PAGE_READONLY
        case .Read_Write:            new_protect = windows.PAGE_READWRITE
        case .Execute:               new_protect = windows.PAGE_EXECUTE
        case .Execute_Read:          new_protect = windows.PAGE_EXECUTE_READ
        case .Execute_Read_Write:    new_protect = windows.PAGE_EXECUTE_READWRITE
        case:
            return false
        }

        old_protect: windows.DWORD
        res := windows.VirtualProtect(
            lpAddress = ptr,
            dwSize = windows.SIZE_T(num_bytes),
            flNewProtect = new_protect,
            lpflOldProtect = &old_protect,
        )

        return bool(res)
    }

    @(require_results)
    _load_module :: proc(path: string) -> (result: Module, ok: bool) {
        windows.SetLastError(0)
        buf: [512]u16
        wstr := windows.utf8_to_wstring_buf(buf[:], path)
        result.hmod = windows.LoadLibraryW(wstr)
        if result.hmod == nil {
            _win32_log_last_error("LoadLibraryW")
            return {}, false
        }
        return result, true
    }

    _unload_module :: proc(module: Module) {
        windows.FreeLibrary(module.hmod)
    }

    @(require_results)
    _get_module_symbol_address :: proc(module: Module, cstr: cstring) -> (result: rawptr) {
        result = windows.GetProcAddress(module.hmod, cstr)
        return result
    }

    _sleep_ms :: proc(ms: int) {
        windows.Sleep(windows.DWORD(ms))
    }

    _get_time_ns :: proc() -> u64 {
        qpc: windows.LARGE_INTEGER
        windows.QueryPerformanceCounter(&qpc)
        counter := u64(qpc) - u64(_state.perf_counter_start)
        return u64(f64(counter) * 1e9 / f64(_state.perf_counter_freq))
    }

    _set_current_directory :: proc(path: string) -> bool {
        buf: [256]u16
        return bool(windows.SetCurrentDirectoryW(windows.utf8_to_wstring_buf(buf[:], path)))
    }

    _get_executable_path :: proc(allocator := context.temp_allocator) -> string {
        buf: [windows.MAX_PATH]u16
        length := windows.GetModuleFileNameW(nil, &buf[0], len(buf))
        if length == 0 {
            return ""
        }
        return windows.wstring_to_utf8_alloc(cstring16(&buf[0]), int(length), allocator) or_else ""
    }


    @(require_results)
    _get_commandline_args :: proc(allocator: runtime.Allocator) -> []string {
        // NOTE: this implementation is from 'core:os'
        arg_count: i32
        arg_list_ptr := windows.CommandLineToArgvW(windows.GetCommandLineW(), &arg_count)
        arg_list := make([]string, int(arg_count), allocator)
        for _, i in arg_list {
            wc_str := (^windows.wstring)(uintptr(arg_list_ptr) + size_of(windows.wstring)*uintptr(i))^
            olen := windows.WideCharToMultiByte(windows.CP_UTF8, 0, wc_str, -1,
                                            nil, 0, nil, nil)

            buf := make([]byte, int(olen), allocator)
            n := windows.WideCharToMultiByte(windows.CP_UTF8, 0, wc_str, -1, raw_data(buf), olen, nil, nil)
            if n > 0 {
                n -= 1
            }
            arg_list[i] = string(buf[:n])
        }

        return arg_list
    }

    @(require_results)
    _run_shell_command :: proc(args: string) -> int {
        si: windows.STARTUPINFOW
        pi: windows.PROCESS_INFORMATION

        si.cb = size_of(si)

        wargs := windows.utf8_to_utf16_alloc(args, context.temp_allocator)

        if !windows.CreateProcessW(
            lpApplicationName    = nil,
            lpCommandLine        = cstring16(&wargs[0]),
            lpProcessAttributes  = nil,
            lpThreadAttributes   = nil,
            bInheritHandles      = false,
            dwCreationFlags      = 0,
            lpEnvironment        = nil,
            lpCurrentDirectory   = nil,
            lpStartupInfo        = &si,
            lpProcessInformation = &pi)
        {
            return -1
        }

        windows.WaitForSingleObject(pi.hProcess, windows.INFINITE)

        exit_code: windows.DWORD
        windows.GetExitCodeProcess(pi.hProcess, &exit_code)

        windows.CloseHandle(pi.hThread)
        windows.CloseHandle(pi.hProcess)

        return int(exit_code)
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: thread
    //

    @(require_results)
    _create_thread :: proc(procedure: Thread_Proc, name: string) -> Thread {
        handle := windows.CreateThread(
            lpThreadAttributes    = nil,
            dwStackSize           = 0,
            lpStartAddress        = _thread_start_routine,
            lpParameter           = rawptr(procedure),
            dwCreationFlags       = 0,
            lpThreadId            = nil,
        )

        if handle == nil {
            base.log_err("Failed to create thread.")
            return {}
        }

        buf: [128]u16
        str := windows.utf8_to_wstring_buf(buf[:], name)
        windows.SetThreadDescription(handle, str)

        return Thread{handle = handle}

        _thread_start_routine :: proc "system" (param: rawptr) -> windows.DWORD {
            procedure := cast(Thread_Proc)param
            procedure()
            return 0
        }
    }

    _join_thread :: proc(thread: Thread) {
        if windows.WaitForSingleObject(thread.handle, windows.INFINITE) ==
        windows.WAIT_FAILED {
            base.log_err("Failed to wait for threads to finish.")
            return
        }
        if !windows.CloseHandle(thread.handle) {
            base.log_err("Failed to close thread handle")
            return
        }
    }

    @(require_results)
    _get_current_thread_id :: proc() -> u64 {
        return u64(windows.GetCurrentThreadId())
    }



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: file dialog
    //

    _file_dialog :: proc(
        mode: File_Dialog_Mode,
        default_path: string,
        patterns: []File_Pattern,
        title := "",
    ) -> (string, bool) {
        file_buf: [512]u16
        copy(file_buf[:], windows.utf8_to_utf16(default_path, context.temp_allocator))

        params := windows.OPENFILENAMEW {
            lStructSize       = size_of(windows.OPENFILENAMEW),
            lpstrFilter       = nil,
            lpstrCustomFilter = nil,
            nFilterIndex      = 0,
            lpstrFile         = cstring16(&file_buf[0]),
            nMaxFile          = len(file_buf),
            lpstrTitle        = windows.utf8_to_wstring(title, context.temp_allocator),
            Flags             = windows.OFN_PATHMUSTEXIST,
        }

        res: windows.BOOL

        switch mode {
        case .Open:
            res = windows.GetOpenFileNameW(&params)

        case .Save:
            res = windows.GetSaveFileNameW(&params)
        }

        if !res {
            return "", false
        }

        str, err := windows.wstring_to_utf8(cstring16(&file_buf[0]), -1, allocator = context.temp_allocator)
        if err != nil {
            return "", false
        }

        return str, true
    }



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: clipboard
    //

    _clipboard_set :: proc(data: string) -> bool {
        hwnd := windows.GetActiveWindow()
        if hwnd == nil {
            return false
        }

        if !windows.OpenClipboard(hwnd) {
            return false
        }

        defer windows.CloseClipboard()

        windows.EmptyClipboard()

        memory_handle := cast(windows.HGLOBAL)windows.GlobalAlloc(windows.GMEM_MOVEABLE, len(data) + 1)
        if memory_handle == nil {
            return false
        }

        memory := windows.GlobalLock(memory_handle)

        runtime.mem_copy(memory, raw_data(data), len(data))
        (cast([^]byte)memory)[len(data)] = 0 // null terminator

        windows.GlobalUnlock(memory_handle)

        windows.SetClipboardData(
            windows.CF_TEXT,
            cast(windows.HANDLE)memory_handle,
        )

        return true
    }

    _clipboard_get :: proc(allocator := context.temp_allocator) -> (string, bool) {
        windows.SetLastError(0)

        hwnd := windows.GetActiveWindow()
        if hwnd == nil {
            return {}, false
        }

        if !windows.OpenClipboard(hwnd) {
            return {}, false
        }

        defer windows.CloseClipboard()

        memory_handle := windows.GetClipboardData(windows.CF_TEXT)

        if memory_handle == nil {
            return {}, false
        }

        memory := windows.GlobalLock(cast(windows.HGLOBAL)memory_handle)

        if memory == nil {
            return {}, false
        }

        defer windows.GlobalUnlock(cast(windows.HGLOBAL)memory_handle)

        length := len(cstring(memory)) // dumb
        result, err := runtime.mem_alloc(length, allocator = allocator)
        if err != nil {
            return {}, false
        }

        runtime.mem_copy_non_overlapping(raw_data(result), memory, length)

        return transmute(string)result, true
    }



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: file IO
    //
    // https://cbloomrants.blogspot.com/2020/07/robust-win32-io.html
    //

    @(require_results)
    _open_file :: proc(path: string) -> (result: File_Handle, ok: bool) {
        windows.SetLastError(0)

        handle := windows.CreateFileW(
            lpFileName = windows.utf8_to_wstring(path, context.temp_allocator),
            dwDesiredAccess = windows.FILE_GENERIC_READ,
            dwShareMode = windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE,
            lpSecurityAttributes = nil,
            dwCreationDisposition = windows.OPEN_EXISTING,
            dwFlagsAndAttributes = windows.FILE_ATTRIBUTE_NORMAL | windows.FILE_FLAG_BACKUP_SEMANTICS,
            hTemplateFile = nil,
        )

        if handle == windows.INVALID_HANDLE_VALUE {
            // _win32_log_last_error("CreateFileW Failed")
            return {}, false
        }

        return {handle = handle}, true
    }

    _close_file :: proc(handle: File_Handle) {
        windows.CloseHandle(handle.handle)
    }

    _get_last_write_time :: proc(handle: File_Handle) -> (u64, bool) {
        windows.SetLastError(0)

        last_write: windows.FILETIME

        if !windows.GetFileTime(handle.handle, nil, nil, lpLastWriteTime = &last_write) {
            // _win32_log_last_error("GetFileTime Failed")
            return 0, false
        }

        return transmute(u64)last_write, true // note: uniform scale across OSes?
    }

    _delete_file :: proc(path: string) -> (result: bool) {
        windows.SetLastError(0)
        result = bool(windows.DeleteFileW(windows.utf8_to_wstring_alloc(path, context.temp_allocator)))
        // if !result {
        //     _win32_log_last_error("DeleteFileW")
        // }
        return result
    }

    @(require_results)
    _read_file_by_path :: proc(path: string, allocator := context.allocator) -> (data: []byte, ok: bool) {
        windows.SetLastError(0)

        handle := windows.CreateFileW(
            lpFileName = windows.utf8_to_wstring(path, context.temp_allocator),
            dwDesiredAccess = windows.FILE_GENERIC_READ,
            dwShareMode = windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE,
            lpSecurityAttributes = nil,
            dwCreationDisposition = windows.OPEN_EXISTING,
            dwFlagsAndAttributes = windows.FILE_ATTRIBUTE_NORMAL | windows.FILE_FLAG_BACKUP_SEMANTICS,
            hTemplateFile = nil,
        )

        if handle == windows.INVALID_HANDLE_VALUE {
            _win32_log_last_error("CreateFile Failed")
            return {}, false
        }

        defer windows.CloseHandle(handle)

        size: windows.LARGE_INTEGER
        if !windows.GetFileSizeEx(handle, &size) {
            _win32_log_last_error("GetSize Failed")
            return {}, false
        }

        buf, err := make([]byte, size, allocator)
        if err != nil {
            base.log_err("Failed to Allocate buffer")
            return {}, false
        }

        num_read: windows.DWORD
        if !windows.ReadFile(handle, raw_data(buf), windows.DWORD(len(buf)), &num_read, nil) {
            _win32_log_last_error("ReadFile failed")
            return {}, false
        }

        assert(int(num_read) <= len(buf))

        return buf[:num_read], true
    }

    _write_file_by_path :: proc(path: string, data: []u8) -> bool {
        windows.SetLastError(0)

        handle := windows.CreateFileW(
            lpFileName = windows.utf8_to_wstring(path, context.temp_allocator),
            dwDesiredAccess = windows.FILE_GENERIC_WRITE,
            dwShareMode = windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE,
            lpSecurityAttributes = nil,
            dwCreationDisposition = windows.CREATE_ALWAYS,
            dwFlagsAndAttributes = windows.FILE_ATTRIBUTE_NORMAL | windows.FILE_FLAG_BACKUP_SEMANTICS,
            hTemplateFile = nil,
        )

        if handle == windows.INVALID_HANDLE_VALUE {
            _win32_log_last_error("CreateFile Failed")
            return false
        }

        defer windows.CloseHandle(handle)

        num_written: windows.DWORD
        if !windows.WriteFile(handle, raw_data(data), windows.DWORD(len(data)), &num_written, nil) {
            _win32_log_last_error("WriteFile failed")
            return false
        }

        return true
    }

    _file_exists :: proc(path: string) -> bool {
        return cast(bool)windows.PathFileExistsW(windows.utf8_to_wstring(path, context.temp_allocator))
    }

    _clone_file :: proc(path: string, new_path: string, fail_if_exists := true) -> bool {
        windows.SetLastError(0)
        result := cast(bool)windows.CopyFileW(
            windows.utf8_to_wstring(path, context.temp_allocator),
            windows.utf8_to_wstring(new_path, context.temp_allocator),
            cast(windows.BOOL)fail_if_exists,
        )
        if !result {
            _win32_log_last_error("CopyFileW")
        }
        return result
    }

    _create_directory :: proc(path: string) -> bool {
        return true == windows.CreateDirectoryW(windows.utf8_to_wstring(path, context.temp_allocator), nil)
    }

    _is_file :: proc(path: string) -> bool {
        buf: [256]u16
        attribs := windows.GetFileAttributesW(
            windows.utf8_to_wstring_buf(buf[:], path),
        )

        return attribs != windows.INVALID_FILE_ATTRIBUTES &&
            ((attribs & windows.FILE_ATTRIBUTE_DIRECTORY) == 0)
    }

    _is_directory :: proc(path: string) -> bool {
        buf: [256]u16
        attribs := windows.GetFileAttributesW(
            windows.utf8_to_wstring_buf(buf[:], path),
        )

        return (attribs & windows.FILE_ATTRIBUTE_DIRECTORY) != 0
    }

    _iter_directory :: proc(iter: ^Directory_Iter, path: string, allocator := context.temp_allocator) -> (result: string, ok: bool) {
        buf: [256]u16

        if iter.handle == {} {
            iter.handle = windows.FindFirstFileW(
                fileName = windows.utf8_to_wstring_buf(buf[:], path),
                findFileData = &iter.find,
            )

            if iter.handle == windows.INVALID_HANDLE_VALUE {
                // base.log_err("invalid init:", path)
                // _win32_log_last_error("FindFirstFileW")
                return {}, false
            }

        } else {
            if !windows.FindNextFileW(iter.handle, &iter.find) {
                windows.FindClose(iter.handle)
                return {}, false
            }
        }

        res, err := windows.wstring_to_utf8_alloc(transmute(cstring16)&iter.find.cFileName[0], N = -1, allocator = allocator)
        if err != nil {
            base.log_err("%v", err)
            return "", false
        }

        return res, true
    }

    _init_file_watcher :: proc(watcher: ^File_Watcher, path: string, recursive := false) -> bool {
        buf: [256]u16

        watcher.recursive = recursive

        watcher.handle = windows.CreateFileW(
            lpFileName            = windows.utf8_to_wstring_buf(buf[:], path),
            dwDesiredAccess       = windows.FILE_LIST_DIRECTORY,
            dwShareMode           = windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE | windows.FILE_SHARE_DELETE,
            lpSecurityAttributes  = nil,
            dwCreationDisposition = windows.OPEN_EXISTING,
            dwFlagsAndAttributes  = windows.FILE_FLAG_BACKUP_SEMANTICS | windows.FILE_FLAG_OVERLAPPED,
            hTemplateFile         = nil,
        )

        if watcher.handle == windows.INVALID_HANDLE_VALUE {
            base.log_err("Failed to initialize file watcher with path '%s", path)
            _win32_log_last_error("CreateFileW")
            watcher.handle = {}
            return false
        }

        watcher.overlapped = {
            hEvent = windows.CreateEventW(
                nil,
                bManualReset = true,
                bInitialState = false,
                lpName = nil,
            ),
        }

        _win32_file_watcher_begin_read(watcher)

        // TODO: more error checking!
        return true
    }

    _poll_file_watcher :: proc(watcher: ^File_Watcher) -> []string {
        assert(watcher.handle != {})

        result := make([dynamic]string, 0, 0, context.temp_allocator)

        res := windows.WaitForSingleObject(watcher.overlapped.hEvent, 0)
        if res == windows.WAIT_OBJECT_0 {
            info := cast(^windows.FILE_NOTIFY_INFORMATION)&watcher.buffer[0]

            for {
                if info.action == windows.FILE_ACTION_MODIFIED || info.action == windows.FILE_ACTION_ADDED {
                    data := cast([^]u16)&info.file_name[0]
                    num_chars := info.file_name_length / 2 // file_name_length is in num bytes, excluding null terminator

                    str, _ := windows.wstring_to_utf8_alloc(cstring16(data), int(num_chars), context.temp_allocator)

                    append(&result, str)
                }

                if info.next_entry_offset == 0 {
                    break
                }

                info = cast(^windows.FILE_NOTIFY_INFORMATION)(cast(uintptr)info + cast(uintptr)info.next_entry_offset)
            }

            windows.ResetEvent(watcher.overlapped.hEvent)

            _win32_file_watcher_begin_read(watcher)
        }

        return result[:]
    }

    _destroy_file_watcher :: proc(watcher: ^File_Watcher) {
        if watcher.handle == {} {
            return
        }

        windows.CancelIo(watcher.handle)
        windows.CloseHandle(watcher.overlapped.hEvent)
        windows.CloseHandle(watcher.handle)

        intrinsics.mem_zero(watcher, size_of(File_Watcher))
    }

    _win32_file_watcher_begin_read :: proc(watcher: ^File_Watcher) {
        windows.ReadDirectoryChangesW(
            hDirectory          = watcher.handle,
            lpBuffer            = &watcher.buffer[0],
            nBufferLength       = size_of(watcher.buffer),
            bWatchSubtree       = windows.BOOL(watcher.recursive),
            dwNotifyFilter      =
                // windows.FILE_NOTIFY_CHANGE_FILE_NAME |
                // windows.FILE_NOTIFY_CHANGE_DIR_NAME |
                windows.FILE_NOTIFY_CHANGE_LAST_WRITE,
            lpBytesReturned     = &watcher.bytes_returned,
            lpOverlapped        = &watcher.overlapped,
            lpCompletionRoutine = nil,
        )
    }



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: window
    //

    _get_native_window_ptr :: proc(window: Window) -> rawptr {
        return window.hwnd
    }

    _create_window :: proc(name: string, style: Window_Style, rect: Rect, high_dpi: bool) -> Window {
        instance := windows.GetModuleHandleW(nil)

        if high_dpi {
            windows.SetProcessDpiAwarenessContext(windows.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
            // scaling := f32(GetDpiForSystem()) / 96
        }

        wndclass := windows.WNDCLASSW{
            style = 0,
            lpfnWndProc = _win32_window_proc,
            cbClsExtra = 0,
            cbWndExtra = 0,
            hInstance = cast(windows.HANDLE)instance,
            hIcon = nil,
            hCursor = nil,
            hbrBackground = nil,
            lpszMenuName = nil,
            lpszClassName = "ravn",
        }

        if windows.RegisterClassW(&wndclass) == 0 {
            base.log_err("Failed to register class")
        }

        name_buf: [256]u16
        wname := windows.utf8_to_wstring_buf(name_buf[:], name)

        hwnd := windows.CreateWindowExW(
            dwExStyle = 0,
            lpClassName = "ravn",
            lpWindowName = wname,
            dwStyle = _win32_window_style(style) | windows.WS_VISIBLE,
            X = rect.min.x,
            Y = rect.min.y,
            nWidth = rect.size.x,
            nHeight = rect.size.y,
            hWndParent = nil,
            hMenu = nil,
            hInstance = cast(windows.HANDLE)instance,
            lpParam = nil,
        )

        if hwnd == nil {
            base.log_err("Failed to create window")
            return {}
        }

        return {hwnd = hwnd}
    }

    @(require_results)
    _get_window_dpi_scale :: proc(window: Window) -> f32 {
        // https://learn.microsoft.com/en-us/windows/win32/learnwin32/dpi-and-device-independent-pixels
        return f32(windows.GetDpiForWindow(window.hwnd)) / 96.0
    }

    _destroy_window :: proc(window: Window) {
        windows.DestroyWindow(window.hwnd)
    }

    _get_main_monitor_rect :: proc() -> Rect {
        monitor := windows.MonitorFromPoint({0, 0}, .MONITOR_DEFAULTTOPRIMARY)
        monitor_info: windows.MONITORINFO = {
            cbSize = size_of(windows.MONITORINFO),
        }
        windows.GetMonitorInfoW(monitor, &monitor_info)

        return _win32_rect(monitor_info.rcMonitor)
    }

    _set_window_style :: proc(window: Window, style: Window_Style) {
        flags := windows.GetWindowLongW(window.hwnd, windows.GWL_STYLE)

        flags &= cast(i32)(~(windows.WS_POPUP | windows.WS_OVERLAPPEDWINDOW)) // remove all possible styles
        flags |= cast(i32)(_win32_window_style(style))

        windows.SetWindowLongW(window.hwnd, windows.GWL_STYLE, flags)

        monitor := windows.MonitorFromPoint({0, 0}, .MONITOR_DEFAULTTOPRIMARY)
        monitor_info: windows.MONITORINFO = {
            cbSize = size_of(windows.MONITORINFO),
        }
        windows.GetMonitorInfoW(monitor, &monitor_info)

        if !windows.SetWindowPos(
            window.hwnd,
            windows.HWND_TOP,
            X = 0,
            Y = 0,
            cx = 0,
            cy = 0,
            uFlags = windows.SWP_FRAMECHANGED | windows.SWP_SHOWWINDOW | windows.SWP_NOMOVE | windows.SWP_NOSIZE,
        ) {
            _win32_log_last_error("SetWindowPos")
        }
    }

    _set_window_title :: proc(window: Window, name: string) {
        name_buf: [256]u16
        wname := windows.utf8_to_wstring_buf(name_buf[:], name)

        windows.SetWindowTextW(window.hwnd, wname)
    }

    _set_window_pos :: proc(window: Window, pos: [2]i32) {
        if !windows.SetWindowPos(
            window.hwnd,
            windows.HWND_TOP,
            X = pos.x,
            Y = pos.y,
            cx = 0,
            cy = 0,
            uFlags = windows.SWP_FRAMECHANGED | windows.SWP_SHOWWINDOW | windows.SWP_NOSIZE,
        ) {
            _win32_log_last_error("SetWindowPos")
        }
    }

    _set_window_size :: proc(window: Window, size: [2]i32) {
        if !windows.SetWindowPos(
            window.hwnd,
            windows.HWND_TOP,
            X = 0,
            Y = 0,
            cx = size.x,
            cy = size.y,
            uFlags = windows.SWP_FRAMECHANGED | windows.SWP_SHOWWINDOW | windows.SWP_NOMOVE,
        ) {
            _win32_log_last_error("SetWindowPos")
        }
    }

    _win32_window_proc :: proc "system" (
        hwnd:   windows.HWND,
        msg:    windows.UINT,
        wparam: windows.WPARAM,
        lparam: windows.LPARAM,
    ) -> (result: windows.LRESULT) {
        context = runtime.default_context()

        result = -1

        switch msg {
        case
            windows.WM_CLOSE,
            windows.WM_DESTROY:
            event := Event_Exit{}
            _event_queue_push(event)

        case windows.WM_SETCURSOR:
            if windows.LOWORD(lparam) == windows.HTCLIENT {
                windows.SetCursor(windows.LoadCursorA(nil, windows.IDC_ARROW))
                result = 0
            }

        case
            windows.WM_KEYDOWN,
            windows.WM_SYSKEYDOWN,
            windows.WM_KEYUP,
            windows.WM_SYSKEYUP:

            pressed := !bool(windows.HIWORD(lparam) & windows.KF_UP)
            scancode := (lparam >> 16) & 0xFF
            is_extended := (lparam & (1 << 24)) != 0

            // key := _win32_scancode_to_key(scancode)

            key: Key = .Invalid

            if int(scancode) < len(_win32_scancode_table) {
                key = _win32_scancode_table[scancode]

                if is_extended {
                    #partial switch key {
                    case .Enter: key = .Keypad_Enter
                    case .Left_Alt: key = .Right_Alt
                    case .Left_Control: key = .Right_Control
                    case .Slash: key = .Keypad_Divide
                    case .Capslock: key = .Keypad_Add
                    }
                } else {
                    #partial switch key  {
                    case .Home: key = .Keypad_7
                    case .Up: key = .Keypad_8
                    case .Page_Up: key = .Keypad_9
                    case .Left: key = .Keypad_4
                    case .Right: key = .Keypad_6
                    case .End: key = .Keypad_1
                    case .Down: key = .Keypad_2
                    case .Page_Down: key = .Keypad_3
                    case .Insert: key = .Keypad_0
                    case .Delete: key = .Keypad_Decimal
                    case .Print_Screen: key = .Keypad_Multiply
                    }
                }
            }

            if key == .Invalid {
                switch wparam {
                case windows.VK_LEFT: key = .Left
                case windows.VK_RIGHT: key = .Right
                case windows.VK_UP: key = .Up
                case windows.VK_DOWN: key = .Down
                }
            }

            if key == .Invalid {
                break
            }

            // Check for Alt+F4
            if msg == windows.WM_KEYDOWN || msg == windows.WM_SYSKEYDOWN {
                if bool(windows.HIWORD(lparam) & windows.KF_ALTDOWN) && key == .F4 {
                    _event_queue_push(Event_Exit{})
                    break
                }
            }

            _event_queue_push(Event_Key{
                key = key,
                pressed = pressed,
            })

            result = 0

        case windows.WM_MOUSEMOVE:
            if !_state.mouse_relative {
                pos := [2]i32{
                    windows.GET_X_LPARAM(lparam),
                    windows.GET_Y_LPARAM(lparam),
                }

                move := pos - _state.mouse_pos

                if move != {} {
                    _event_queue_push(Event_Mouse{
                        pos = pos,
                        move = move,
                    })
                }

                _state.mouse_pos = pos

                result = 0
            }

            fallthrough

        case
            windows.WM_LBUTTONUP,
            windows.WM_RBUTTONUP,
            windows.WM_MBUTTONUP,
            windows.WM_XBUTTONUP,
            windows.WM_LBUTTONDOWN,
            windows.WM_LBUTTONDBLCLK,
            windows.WM_RBUTTONDOWN,
            windows.WM_RBUTTONDBLCLK,
            windows.WM_MBUTTONDOWN,
            windows.WM_MBUTTONDBLCLK,
            windows.WM_XBUTTONDOWN,
            windows.WM_XBUTTONDBLCLK:

            #unroll for button in Mouse_Button {
                mask: uintptr
                switch button {
                case .Left:     mask = windows.MK_LBUTTON
                case .Middle:   mask = windows.MK_MBUTTON
                case .Right:    mask = windows.MK_RBUTTON
                case .Extra_1:  mask = windows.MK_XBUTTON1
                case .Extra_2:  mask = windows.MK_XBUTTON2
                }

                curr_down := (wparam & mask) != 0
                prev_down := (_state.last_mouse_wparam & mask) != 0

                if curr_down && !prev_down {
                    _event_queue_push(Event_Mouse_Button{
                        button = button,
                        pressed = true,
                    })
                } else if prev_down && !curr_down {
                    _event_queue_push(Event_Mouse_Button{
                        button = button,
                        pressed = false,
                    })
                }
            }

            _state.last_mouse_wparam = wparam

            result = 0

        case
            windows.WM_MOUSEWHEEL,
            windows.WM_MOUSEHWHEEL:

            integer_amount := windows.GET_WHEEL_DELTA_WPARAM(wparam)

            amount := f32(integer_amount) / f32(windows.WHEEL_DELTA)

            if msg == windows.WM_MOUSEWHEEL {
                _event_queue_push(Event_Scroll{
                    delta = {
                        0,
                        amount,
                    },
                })
            } else {
                _event_queue_push(Event_Scroll{
                    delta = {
                        amount,
                        0,
                    },
                })
            }

            result = 0

        case windows.WM_INPUT:
            // if !_state.mouse_relative {
            //     break
            // }

            // raw: windows.RAWINPUT
            // size: u32 = size_of(raw)
            // windows.GetRawInputData(windows.HRAWINPUT(lparam), windows.RID_INPUT, &raw, &size, size_of(windows.RAWINPUTHEADER))

            // _win32_process_raw_input_message(&raw)
        }

        if result < 0 {
            result = windows.CallWindowProcW(windows.DefWindowProcW, hwnd, msg, wparam, lparam)
        }

        return result
    }

    _win32_process_raw_input_message :: proc(raw: ^windows.RAWINPUT) {
        switch raw.header.dwType {
        case windows.RIM_TYPEMOUSE:
            // result = 0

            mouse := raw.data.mouse

            if (mouse.usFlags & windows.MOUSE_MOVE_ABSOLUTE) != 0 {
                if (mouse.lLastX != 0 && mouse.lLastY != 0) {
                    unimplemented()
                }
            } else {
                move := [2]i32{
                    i32(mouse.lLastX),
                    i32(mouse.lLastY),
                }
                _state.mouse_pos += move

                // common case
                _event_queue_push(Event_Mouse{
                    pos = _state.mouse_pos,
                    move = move,
                })
            }

            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_1_DOWN) != 0 {
                _event_queue_push(Event_Mouse_Button{
                    button = .Left,
                    pressed = true,
                })
            }

            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_1_UP) != 0 {
                _event_queue_push(Event_Mouse_Button{
                    button = .Left,
                    pressed = false,
                })
            }

            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_2_DOWN) != 0 {
                _event_queue_push(Event_Mouse_Button{
                    button = .Right,
                    pressed = true,
                })
            }

            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_2_UP) != 0 {
                _event_queue_push(Event_Mouse_Button{
                    button = .Right,
                    pressed = false,
                })
            }

            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_3_DOWN) != 0 {
                _event_queue_push(Event_Mouse_Button{
                    button = .Middle,
                    pressed = true,
                })
            }

            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_3_UP) != 0 {
                _event_queue_push(Event_Mouse_Button{
                    button = .Middle,
                    pressed = false,
                })
            }

            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_4_DOWN) != 0 {
                _event_queue_push(Event_Mouse_Button{
                    button = .Extra_1,
                    pressed = true,
                })
            }

            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_4_UP) != 0 {
                _event_queue_push(Event_Mouse_Button{
                    button = .Extra_1,
                    pressed = false,
                })
            }

            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_5_DOWN) != 0 {
                _event_queue_push(Event_Mouse_Button{
                    button = .Extra_2,
                    pressed = true,
                })
            }

            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_5_UP) != 0 {
                _event_queue_push(Event_Mouse_Button{
                    button = .Extra_2,
                    pressed = false,
                })
            }

        case:
            assert(false)
        }
    }

    _get_window_rect :: proc(window: Window) -> Rect {
        rect: windows.RECT
        if !windows.GetClientRect(window.hwnd, &rect) {
            return {}
        }

        return {
            min = {
                rect.left,
                rect.top,
            },
            size = {
                rect.right - rect.left,
                rect.bottom - rect.top,
            },
        }
    }

    _set_mouse_pos_window_relative :: proc(window: Window, pos: [2]i32) {
        center := windows.POINT{
            pos.x,
            pos.y,
        }

        windows.ClientToScreen(window.hwnd, &center)
        windows.SetCursorPos(center.x, center.y)
    }

    _is_window_minimized :: proc(window: Window) -> bool {
        return bool(windows.IsIconic(window.hwnd))
    }

    _is_window_focused :: proc(window: Window) -> bool {
        return windows.GetForegroundWindow() == window.hwnd && !windows.IsIconic(window.hwnd)
    }

    _win32_RAWINPUT_ALIGN :: proc(x: uintptr) -> uintptr{
        return (x + size_of(uintptr) - 1) & ~uintptr(size_of(uintptr) - 1)
    }

    _win32_NEXTRAWINPUTBLOCK :: proc(ptr: ^windows.RAWINPUT) -> ^windows.RAWINPUT {
        return cast(^windows.RAWINPUT)_win32_RAWINPUT_ALIGN(uintptr(ptr) + uintptr(ptr.header.dwSize))
    }

    _win32_process_raw_input :: proc() {
        // https://learn.microsoft.com/en-us/windows/win32/inputdev/using-raw-input
        for {
            buf: [64]windows.RAWINPUT
            size := u32(size_of(buf))
            num := windows.GetRawInputBuffer(
                pRawInput = &buf[0],
                pcbSize = &size,
                cbSizeHeader = size_of(windows.RAWINPUTHEADER),
            )

            if num == 0{
                break
            }

            assert(num > 0)

            curr: ^windows.RAWINPUT = &buf[0]
            for _ in 0..<num {
                _win32_process_raw_input_message(curr)

                curr = _win32_NEXTRAWINPUTBLOCK(curr)
            }
        }
    }

    _poll_window_events :: proc(window: Window) -> (ok: bool) {
        MAX_EVENTS :: 16
        if _state.event_counter >= MAX_EVENTS {
            return false
        }

        if _state.event_counter == 0 && _state.mouse_relative {
            _win32_process_raw_input()
        }

        msg: windows.MSG
        res: windows.BOOL
        if is_window_focused(window) {
            res = windows.PeekMessageW(&msg, window.hwnd, 0, 0, windows.PM_REMOVE)
        } else {
            res = windows.PeekMessageW(&msg, window.hwnd, 0, windows.WM_INPUT-1, windows.PM_REMOVE)
            if !bool(res) {
                res = windows.PeekMessageW(&msg, window.hwnd, windows.WM_INPUT+1, max(u32), windows.PM_REMOVE)
            }
        }

        if !bool(res) {
            return false
        }

        if _state.message_hook_proc != nil {
            _state.message_hook_proc(window.hwnd, msg.message, msg.wParam, msg.lParam, _state.message_hook_data)
        }

        switch msg.message {
        case windows.WM_QUIT:
            _event_queue_push(Event_Exit{})
            return true
        }

        windows.TranslateMessage(&msg)
        windows.DispatchMessageW(&msg)

        return true
    }



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: gamepad
    //


    _get_gamepad_state :: proc(index: int) -> (result: Gamepad_State, ok: bool) {
        if index >= MAX_GAMEPADS {
            return {}, false
        }

        if index >= windows.XUSER_MAX_COUNT {
            return {}, false
        }

        // NOTE: checking for non-connected controllers apparently could be slow, so space out queries
        if index == int(_state.xinput_query_index) {
            if index in _state.xinput_valid {
                _state.xinput_query_index = (_state.xinput_query_index + 1) %% windows.XUSER_MAX_COUNT
            } else {
                FRAMES_PER_QUERY :: 100

                _state.xinput_query_counter += 1
                if _state.xinput_query_counter >= FRAMES_PER_QUERY {
                    _state.xinput_query_counter -= FRAMES_PER_QUERY
                    // continue and do query
                } else {
                    return {}, false
                }
            }
        }

        state: windows.XINPUT_STATE
        res := windows.XInputGetState(windows.XUSER(index), &state)

        if res != .SUCCESS {
            // note: either ERROR_DEVICE_NOT_CONNECTED or failed
            _state.xinput_valid -= {index}
            return {}, false
        }

        _state.xinput_valid += {index}

        if .DPAD_UP in state.Gamepad.wButtons do result.buttons += {.DPad_Up}
        if .DPAD_DOWN in state.Gamepad.wButtons do result.buttons += {.DPad_Down}
        if .DPAD_LEFT in state.Gamepad.wButtons do result.buttons += {.DPad_Left}
        if .DPAD_RIGHT in state.Gamepad.wButtons do result.buttons += {.DPad_Right}
        if .START in state.Gamepad.wButtons do result.buttons += {.Start}
        if .BACK in state.Gamepad.wButtons do result.buttons += {.Back}
        if .LEFT_THUMB in state.Gamepad.wButtons do result.buttons += {.Left_Thumb}
        if .RIGHT_THUMB in state.Gamepad.wButtons do result.buttons += {.Right_Thumb}
        if .LEFT_SHOULDER in state.Gamepad.wButtons do result.buttons += {.Left_Shoulder}
        if .RIGHT_SHOULDER in state.Gamepad.wButtons do result.buttons += {.Right_Shoulder}
        if .A in state.Gamepad.wButtons do result.buttons += {.A}
        if .B in state.Gamepad.wButtons do result.buttons += {.B}
        if .X in state.Gamepad.wButtons do result.buttons += {.X}
        if .Y in state.Gamepad.wButtons do result.buttons += {.Y}

        result.axes = {
            .Right_Trigger = f32(state.Gamepad.bRightTrigger) / f32(max(u8)),
            .Left_Trigger = f32(state.Gamepad.bLeftTrigger) / f32(max(u8)),
            .Right_Thumb_X = f32(state.Gamepad.sThumbRX) / f32(max(i16)),
            .Right_Thumb_Y = f32(state.Gamepad.sThumbRY) / f32(max(i16)),
            .Left_Thumb_X = f32(state.Gamepad.sThumbLX) / f32(max(i16)),
            .Left_Thumb_Y = f32(state.Gamepad.sThumbLY) / f32(max(i16)),
        }

        return result, true
    }

    _set_gamepad_feedback :: proc(index: int, output: Gamepad_Feedback) -> bool {
        if index >= MAX_GAMEPADS {
            return false
        }

        if index >= windows.XUSER_MAX_COUNT {
            return false
        }

        vibration: windows.XINPUT_VIBRATION = {
            wLeftMotorSpeed  = windows.WORD(output.left_motor_speed  * f32(max(windows.WORD))),
            wRightMotorSpeed = windows.WORD(output.right_motor_speed * f32(max(windows.WORD))),
        }

        res := windows.XInputSetState(windows.XUSER(index), &vibration)

        return res == .SUCCESS
    }



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: misc
    //

    _win32_rect :: proc(rect: windows.RECT) -> Rect {
        return {
            min = {
                rect.left,
                rect.top,
            },
            size = {
                rect.right - rect.left,
                rect.bottom - rect.top,
            },
        }
    }

    _win32_window_style :: proc(style: Window_Style) -> windows.DWORD {
        switch style {
        case:
            fallthrough

        case .Regular:
            return windows.WS_OVERLAPPEDWINDOW

        case .Borderless:
            return windows.WS_POPUP
        }
    }

    _win32_log_last_error :: proc(text: string, loc := #caller_location) {
        if context.logger != {} {
            error := windows.GetLastError()
            msg_buf: windows.wstring
            num_msg_chars := windows.FormatMessageW(
                flags = windows.FORMAT_MESSAGE_ALLOCATE_BUFFER |
                        windows.FORMAT_MESSAGE_FROM_SYSTEM |
                        windows.FORMAT_MESSAGE_IGNORE_INSERTS,
                lpSrc = nil,
                msgId = error,
                langId = 0,
                buf = cast(^u16)&msg_buf,
                nsize = 0,
                args = nil,
            )

            defer windows.LocalFree(rawptr(msg_buf))

            str, _ := windows.wstring_to_utf8_alloc(msg_buf, int(num_msg_chars), context.temp_allocator)
            if str[len(str)-1] == '\n' {
                str = str[:len(str)-1]
            }
            base.log_err("%s : %s", text, str, loc = loc)
        }
    }


    // from sdl/scancodes_windows.h
    @(rodata)
    _win32_scancode_table := [?]Key{
        .Invalid,
        .Escape,
        .Num1,
        .Num2,
        .Num3,
        .Num4,
        .Num5,
        .Num6,
        .Num7,
        .Num8,
        .Num9,
        .Num0,
        .Minus,
        .Equal,
        .Backspace,
        .Tab,
        .Q,
        .W,
        .E,
        .R,
        .T,
        .Y,
        .U,
        .I,
        .O,
        .P,
        .Left_Bracket,
        .Right_Bracket,
        .Enter,
        .Left_Control,
        .A,
        .S,
        .D,
        .F,
        .G,
        .H,
        .J,
        .K,
        .L,
        .Semicolon,
        .Apostrophe,
        .Backtick,
        .Left_Shift,
        .Backslash,
        .Z,
        .X,
        .C,
        .V,
        .B,
        .N,
        .M,
        .Comma,
        .Period,
        .Slash,
        .Right_Shift,
        .Print_Screen,
        .Left_Alt,
        .Space,
        .Capslock,
        .F1,
        .F2,
        .F3,
        .F4,
        .F5,
        .F6,
        .F7,
        .F8,
        .F9,
        .F10,
        .Invalid,
        .Scroll_Lock,
        .Home,
        .Up,
        .Page_Up,
        .Keypad_Subtract,
        .Left,
        .Keypad_5,
        .Right,
        .Keypad_Add,
        .End,
        .Down,
        .Page_Down,
        .Insert,
        .Delete,
        .Invalid,
        .Invalid,
        .Invalid,
        .F11,
        .F12,
        .Pause,
        .Invalid,
        .Invalid,
        .Invalid,
        .Invalid,
        .Invalid,
        .Invalid,
        .Invalid,
        .Invalid,
        .Invalid,
        .Invalid,
        .F13,
        .F14,
        .F15,
        .F16,
        .F17,
        .F18,
        .F19,
    }

    _win32_KAFFINITY :: windows.ULONG_PTR

    _win32_GROUP_AFFINITY :: struct {
        Mask:       _win32_KAFFINITY,
        Group:      windows.WORD,
        Reserved:   [3]windows.WORD,
    }

    _win32_CPU_SET_INFORMATION_TYPE :: enum u32 {
        CpuSetInformation,
    }

    _win32_SYSTEM_CPU_SET_INFORMATION :: struct {
        Size: windows.DWORD,
        Type: _win32_CPU_SET_INFORMATION_TYPE,
        using _: struct #raw_union {
            CpuSet: struct {
                Id:                       windows.DWORD,
                Group:                    windows.WORD,
                LogicalProcessorIndex:    windows.BYTE,
                CoreIndex:                windows.BYTE,
                LastLevelCacheIndex:      windows.BYTE,
                NumaNodeIndex:            windows.BYTE,
                EfficiencyClass:          windows.BYTE,
                using _: struct #raw_union {
                    AllFlags:   windows.BYTE,
                    using _: bit_field u8 {
                        Parked:                   windows.BYTE | 1,
                        Allocated:                windows.BYTE | 1,
                        AllocatedToTargetProcess: windows.BYTE | 1,
                        RealTime:                 windows.BYTE | 1,
                        ReservedFlags:            windows.BYTE | 4,
                    },
                },
                using _: struct #raw_union {
                    Reserved:           windows.DWORD,
                    SchedulingClass:    windows.BYTE,
                },
                AllocationTag:        windows.DWORD64,
            },
        },
    }


    @(default_calling_convention = "system")
    foreign user32 {
        GetDpiForSystem :: proc() -> windows.UINT ---
    }

    @(default_calling_convention = "system")
    foreign kernel32 {
        GetSystemCpuSetInformation :: proc(
            Information: ^_win32_SYSTEM_CPU_SET_INFORMATION,
            BufferLength: windows.ULONG,
            ReturnedLength: ^windows.ULONG,
            Process: windows.HANDLE,
            Flags: windows.ULONG,
        ) -> windows.BOOL ---

        GetProcessDefaultCpuSets :: proc(
            Process: windows.HANDLE,
            CpuSetIds: ^windows.ULONG,
            CpuSetIdCount: windows.ULONG,
            RequiredIdCount: ^windows.ULONG,
        ) -> windows.BOOL ---

        SetProcessDefaultCpuSets :: proc(
            Process: windows.HANDLE,
            CpuSetIds: ^windows.ULONG,
            CpuSetIdCount: windows.ULONG,
        ) -> windows.BOOL ---

        GetThreadSelectedCpuSets :: proc(
            Thread: windows.HANDLE,
            CpuSetIds: ^windows.ULONG,
            CpuSetIdCount: windows.ULONG,
            RequiredIdCount: ^windows.ULONG,
        ) -> windows.BOOL ---

        SetThreadSelectedCpuSets :: proc(
            Thread: windows.HANDLE,
            CpuSetIds: ^windows.ULONG,
            CpuSetIdCount: windows.ULONG,
        ) -> windows.BOOL ---

        GetProcessDefaultCpuSetMasks :: proc(
            Process: windows.HANDLE,
            CpuSetMasks: ^_win32_GROUP_AFFINITY,
            CpuSetMaskCount: windows.USHORT,
            RequiredMaskCount: ^windows.USHORT,
        ) -> windows.BOOL ---

        SetProcessDefaultCpuSetMasks :: proc(
            Process: windows.HANDLE,
            CpuSetMasks: ^_win32_GROUP_AFFINITY,
            CpuSetMaskCount: windows.USHORT,
        ) -> windows.BOOL ---

        GetThreadSelectedCpuSetMasks :: proc(
            Thread: windows.HANDLE,
            CpuSetMasks: ^_win32_GROUP_AFFINITY,
            CpuSetMaskCount: windows.USHORT,
            RequiredMaskCount: ^windows.USHORT,
        ) -> windows.BOOL ---

        SetThreadSelectedCpuSetMasks :: proc(
            Thread: windows.HANDLE,
            CpuSetMasks: ^_win32_GROUP_AFFINITY,
            CpuSetMaskCount: windows.USHORT,
        ) -> windows.BOOL ---
    }


    // Scans system and returns the list of physical cores
    _refresh_cpu_core_info :: proc() {
        base.log_info("refreshing cores")
        needed: windows.ULONG
        GetSystemCpuSetInformation(nil, 0, &needed, windows.INVALID_HANDLE_VALUE, 0)

        base.log_dump(needed)

        buffer := make([]byte, needed, context.temp_allocator)

        returned: windows.ULONG
        GetSystemCpuSetInformation(
            Information = (^_win32_SYSTEM_CPU_SET_INFORMATION)(&buffer[0]),
            BufferLength = windows.ULONG(len(buffer)),
            ReturnedLength = &returned,
            Process = windows.INVALID_HANDLE_VALUE,
            Flags = 0,
        )

        ptr := uintptr(&buffer[0])
        end := ptr + uintptr(returned)

        id_counters: [256]u8

        for ptr < end {
            info := (^ _win32_SYSTEM_CPU_SET_INFORMATION)(ptr)
            defer ptr += uintptr(info.Size)

            if info.Type == .CpuSetInformation {
                core_index := info.CpuSet.CoreIndex

                _state.core_info[_state.core_info_num] = {
                    id = info.CpuSet.Id,
                    efficiency = u8(info.CpuSet.EfficiencyClass),
                    logical_index = id_counters[core_index],
                }
                _state.core_info_num += 1

                id_counters[core_index] += 1
            }
        }
    }

    _pin_thread_to_cpu_core :: proc(thread: Thread, core_index: int) -> bool {
        id := _state.core_info[core_index].id
        handle := thread.handle
        if thread == {} {
            handle = windows.GetCurrentThread()
        }

        return bool(SetThreadSelectedCpuSets(handle, &id, 1))
    }

    /*
    _win32_message_name :: proc "contextless" (msg: windows.UINT) -> string {
        switch msg {
        case windows.WM_NULL: return "WM_NULL"
        case windows.WM_CREATE: return "WM_CREATE"
        case windows.WM_DESTROY: return "WM_DESTROY"
        case windows.WM_MOVE: return "WM_MOVE"
        case windows.WM_SIZE: return "WM_SIZE"
        case windows.WM_ACTIVATE: return "WM_ACTIVATE"
        case windows.WM_SETFOCUS: return "WM_SETFOCUS"
        case windows.WM_KILLFOCUS: return "WM_KILLFOCUS"
        case windows.WM_ENABLE: return "WM_ENABLE"
        case windows.WM_SETREDRAW: return "WM_SETREDRAW"
        case windows.WM_SETTEXT: return "WM_SETTEXT"
        case windows.WM_GETTEXT: return "WM_GETTEXT"
        case windows.WM_GETTEXTLENGTH: return "WM_GETTEXTLENGTH"
        case windows.WM_PAINT: return "WM_PAINT"
        case windows.WM_CLOSE: return "WM_CLOSE"
        case windows.WM_QUERYENDSESSION: return "WM_QUERYENDSESSION"
        case windows.WM_QUIT: return "WM_QUIT"
        case windows.WM_QUERYOPEN: return "WM_QUERYOPEN"
        case windows.WM_ERASEBKGND: return "WM_ERASEBKGND"
        case windows.WM_SYSCOLORCHANGE: return "WM_SYSCOLORCHANGE"
        case windows.WM_ENDSESSION: return "WM_ENDSESSION"
        case windows.WM_SHOWWINDOW: return "WM_SHOWWINDOW"
        case windows.WM_CTLCOLOR: return "WM_CTLCOLOR"
        case windows.WM_WININICHANGE: return "WM_WININICHANGE"
        case windows.WM_DEVMODECHANGE: return "WM_DEVMODECHANGE"
        case windows.WM_ACTIVATEAPP: return "WM_ACTIVATEAPP"
        case windows.WM_FONTCHANGE: return "WM_FONTCHANGE"
        case windows.WM_TIMECHANGE: return "WM_TIMECHANGE"
        case windows.WM_CANCELMODE: return "WM_CANCELMODE"
        case windows.WM_SETCURSOR: return "WM_SETCURSOR"
        case windows.WM_MOUSEACTIVATE: return "WM_MOUSEACTIVATE"
        case windows.WM_CHILDACTIVATE: return "WM_CHILDACTIVATE"
        case windows.WM_QUEUESYNC: return "WM_QUEUESYNC"
        case windows.WM_GETMINMAXINFO: return "WM_GETMINMAXINFO"
        case windows.WM_PAINTICON: return "WM_PAINTICON"
        case windows.WM_ICONERASEBKGND: return "WM_ICONERASEBKGND"
        case windows.WM_NEXTDLGCTL: return "WM_NEXTDLGCTL"
        case windows.WM_SPOOLERSTATUS: return "WM_SPOOLERSTATUS"
        case windows.WM_DRAWITEM: return "WM_DRAWITEM"
        case windows.WM_MEASUREITEM: return "WM_MEASUREITEM"
        case windows.WM_DELETEITEM: return "WM_DELETEITEM"
        case windows.WM_VKEYTOITEM: return "WM_VKEYTOITEM"
        case windows.WM_CHARTOITEM: return "WM_CHARTOITEM"
        case windows.WM_SETFONT: return "WM_SETFONT"
        case windows.WM_GETFONT: return "WM_GETFONT"
        case windows.WM_SETHOTKEY: return "WM_SETHOTKEY"
        case windows.WM_GETHOTKEY: return "WM_GETHOTKEY"
        case windows.WM_QUERYDRAGICON: return "WM_QUERYDRAGICON"
        case windows.WM_COMPAREITEM: return "WM_COMPAREITEM"
        case windows.WM_GETOBJECT: return "WM_GETOBJECT"
        case windows.WM_COMPACTING: return "WM_COMPACTING"
        case windows.WM_COMMNOTIFY: return "WM_COMMNOTIFY"
        case windows.WM_WINDOWPOSCHANGING: return "WM_WINDOWPOSCHANGING"
        case windows.WM_WINDOWPOSCHANGED: return "WM_WINDOWPOSCHANGED"
        case windows.WM_POWER: return "WM_POWER"
        case windows.WM_COPYGLOBALDATA: return "WM_COPYGLOBALDATA"
        case windows.WM_COPYDATA: return "WM_COPYDATA"
        case windows.WM_CANCELJOURNAL: return "WM_CANCELJOURNAL"
        case windows.WM_NOTIFY: return "WM_NOTIFY"
        case windows.WM_INPUTLANGCHANGEREQUEST: return "WM_INPUTLANGCHANGEREQUEST"
        case windows.WM_INPUTLANGCHANGE: return "WM_INPUTLANGCHANGE"
        case windows.WM_TCARD: return "WM_TCARD"
        case windows.WM_HELP: return "WM_HELP"
        case windows.WM_USERCHANGED: return "WM_USERCHANGED"
        case windows.WM_NOTIFYFORMAT: return "WM_NOTIFYFORMAT"
        case windows.WM_CONTEXTMENU: return "WM_CONTEXTMENU"
        case windows.WM_STYLECHANGING: return "WM_STYLECHANGING"
        case windows.WM_STYLECHANGED: return "WM_STYLECHANGED"
        case windows.WM_DISPLAYCHANGE: return "WM_DISPLAYCHANGE"
        case windows.WM_GETICON: return "WM_GETICON"
        case windows.WM_SETICON: return "WM_SETICON"
        case windows.WM_NCCREATE: return "WM_NCCREATE"
        case windows.WM_NCDESTROY: return "WM_NCDESTROY"
        case windows.WM_NCCALCSIZE: return "WM_NCCALCSIZE"
        case windows.WM_NCHITTEST: return "WM_NCHITTEST"
        case windows.WM_NCPAINT: return "WM_NCPAINT"
        case windows.WM_NCACTIVATE: return "WM_NCACTIVATE"
        case windows.WM_GETDLGCODE: return "WM_GETDLGCODE"
        case windows.WM_SYNCPAINT: return "WM_SYNCPAINT"
        case windows.WM_NCMOUSEMOVE: return "WM_NCMOUSEMOVE"
        case windows.WM_NCLBUTTONDOWN: return "WM_NCLBUTTONDOWN"
        case windows.WM_NCLBUTTONUP: return "WM_NCLBUTTONUP"
        case windows.WM_NCLBUTTONDBLCLK: return "WM_NCLBUTTONDBLCLK"
        case windows.WM_NCRBUTTONDOWN: return "WM_NCRBUTTONDOWN"
        case windows.WM_NCRBUTTONUP: return "WM_NCRBUTTONUP"
        case windows.WM_NCRBUTTONDBLCLK: return "WM_NCRBUTTONDBLCLK"
        case windows.WM_NCMBUTTONDOWN: return "WM_NCMBUTTONDOWN"
        case windows.WM_NCMBUTTONUP: return "WM_NCMBUTTONUP"
        case windows.WM_NCMBUTTONDBLCLK: return "WM_NCMBUTTONDBLCLK"
        case windows.WM_NCXBUTTONDOWN: return "WM_NCXBUTTONDOWN"
        case windows.WM_NCXBUTTONUP: return "WM_NCXBUTTONUP"
        case windows.WM_NCXBUTTONDBLCLK: return "WM_NCXBUTTONDBLCLK"
        case windows.EM_GETSEL: return "EM_GETSEL"
        case windows.EM_SETSEL: return "EM_SETSEL"
        case windows.EM_GETRECT: return "EM_GETRECT"
        case windows.EM_SETRECT: return "EM_SETRECT"
        case windows.EM_SETRECTNP: return "EM_SETRECTNP"
        case windows.EM_SCROLL: return "EM_SCROLL"
        case windows.EM_LINESCROLL: return "EM_LINESCROLL"
        case windows.EM_SCROLLCARET: return "EM_SCROLLCARET"
        case windows.EM_GETMODIFY: return "EM_GETMODIFY"
        case windows.EM_SETMODIFY: return "EM_SETMODIFY"
        case windows.EM_GETLINECOUNT: return "EM_GETLINECOUNT"
        case windows.EM_LINEINDEX: return "EM_LINEINDEX"
        case windows.EM_SETHANDLE: return "EM_SETHANDLE"
        case windows.EM_GETHANDLE: return "EM_GETHANDLE"
        case windows.EM_GETTHUMB: return "EM_GETTHUMB"
        case windows.EM_LINELENGTH: return "EM_LINELENGTH"
        case windows.EM_REPLACESEL: return "EM_REPLACESEL"
        case windows.EM_SETFONT: return "EM_SETFONT"
        case windows.EM_GETLINE: return "EM_GETLINE"
        case windows.EM_LIMITTEXT: return "EM_LIMITTEXT"
        case windows.EM_CANUNDO: return "EM_CANUNDO"
        case windows.EM_UNDO: return "EM_UNDO"
        case windows.EM_FMTLINES: return "EM_FMTLINES"
        case windows.EM_LINEFROMCHAR: return "EM_LINEFROMCHAR"
        case windows.EM_SETWORDBREAK: return "EM_SETWORDBREAK"
        case windows.EM_SETTABSTOPS: return "EM_SETTABSTOPS"
        case windows.EM_SETPASSWORDCHAR: return "EM_SETPASSWORDCHAR"
        case windows.EM_EMPTYUNDOBUFFER: return "EM_EMPTYUNDOBUFFER"
        case windows.EM_GETFIRSTVISIBLELINE: return "EM_GETFIRSTVISIBLELINE"
        case windows.EM_SETREADONLY: return "EM_SETREADONLY"
        case windows.EM_SETWORDBREAKPROC: return "EM_SETWORDBREAKPROC"
        case windows.EM_GETWORDBREAKPROC: return "EM_GETWORDBREAKPROC"
        case windows.EM_GETPASSWORDCHAR: return "EM_GETPASSWORDCHAR"
        case windows.EM_SETMARGINS: return "EM_SETMARGINS"
        case windows.EM_GETMARGINS: return "EM_GETMARGINS"
        case windows.EM_GETLIMITTEXT: return "EM_GETLIMITTEXT"
        case windows.EM_POSFROMCHAR: return "EM_POSFROMCHAR"
        case windows.EM_CHARFROMPOS: return "EM_CHARFROMPOS"
        case windows.EM_SETIMESTATUS: return "EM_SETIMESTATUS"
        case windows.EM_GETIMESTATUS: return "EM_GETIMESTATUS"
        case windows.SBM_SETPOS: return "SBM_SETPOS"
        case windows.SBM_GETPOS: return "SBM_GETPOS"
        case windows.SBM_SETRANGE: return "SBM_SETRANGE"
        case windows.SBM_GETRANGE: return "SBM_GETRANGE"
        case windows.SBM_ENABLE_ARROWS: return "SBM_ENABLE_ARROWS"
        case windows.SBM_SETRANGEREDRAW: return "SBM_SETRANGEREDRAW"
        case windows.SBM_SETSCROLLINFO: return "SBM_SETSCROLLINFO"
        case windows.SBM_GETSCROLLINFO: return "SBM_GETSCROLLINFO"
        case windows.SBM_GETSCROLLBARINFO: return "SBM_GETSCROLLBARINFO"
        case windows.BM_GETCHECK: return "BM_GETCHECK"
        case windows.BM_SETCHECK: return "BM_SETCHECK"
        case windows.BM_GETSTATE: return "BM_GETSTATE"
        case windows.BM_SETSTATE: return "BM_SETSTATE"
        case windows.BM_SETSTYLE: return "BM_SETSTYLE"
        case windows.BM_CLICK: return "BM_CLICK"
        case windows.BM_GETIMAGE: return "BM_GETIMAGE"
        case windows.BM_SETIMAGE: return "BM_SETIMAGE"
        case windows.BM_SETDONTCLICK: return "BM_SETDONTCLICK"
        case windows.WM_INPUT_DEVICE_CHANGE: return "WM_INPUT_DEVICE_CHANGE"
        case windows.WM_INPUT: return "WM_INPUT"
        case windows.WM_KEYDOWN: return "WM_KEYDOWN"
        case windows.WM_KEYUP: return "WM_KEYUP"
        case windows.WM_CHAR: return "WM_CHAR"
        case windows.WM_DEADCHAR: return "WM_DEADCHAR"
        case windows.WM_SYSKEYDOWN: return "WM_SYSKEYDOWN"
        case windows.WM_SYSKEYUP: return "WM_SYSKEYUP"
        case windows.WM_SYSCHAR: return "WM_SYSCHAR"
        case windows.WM_SYSDEADCHAR: return "WM_SYSDEADCHAR"
        case windows.WM_UNICHAR: return "WM_UNICHAR"
        case windows.UNICODE_NOCHAR: return "UNICODE_NOCHAR"
        case windows.WM_CONVERTREQUEST: return "WM_CONVERTREQUEST"
        case windows.WM_CONVERTRESULT: return "WM_CONVERTRESULT"
        case windows.WM_INTERIM: return "WM_INTERIM"
        case windows.WM_IME_STARTCOMPOSITION: return "WM_IME_STARTCOMPOSITION"
        case windows.WM_IME_ENDCOMPOSITION: return "WM_IME_ENDCOMPOSITION"
        case windows.WM_IME_COMPOSITION: return "WM_IME_COMPOSITION"
        case windows.WM_INITDIALOG: return "WM_INITDIALOG"
        case windows.WM_COMMAND: return "WM_COMMAND"
        case windows.WM_SYSCOMMAND: return "WM_SYSCOMMAND"
        case windows.WM_TIMER: return "WM_TIMER"
        case windows.WM_HSCROLL: return "WM_HSCROLL"
        case windows.WM_VSCROLL: return "WM_VSCROLL"
        case windows.WM_INITMENU: return "WM_INITMENU"
        case windows.WM_INITMENUPOPUP: return "WM_INITMENUPOPUP"
        case windows.WM_SYSTIMER: return "WM_SYSTIMER"
        case windows.WM_MENUSELECT: return "WM_MENUSELECT"
        case windows.WM_MENUCHAR: return "WM_MENUCHAR"
        case windows.WM_ENTERIDLE: return "WM_ENTERIDLE"
        case windows.WM_MENURBUTTONUP: return "WM_MENURBUTTONUP"
        case windows.WM_MENUDRAG: return "WM_MENUDRAG"
        case windows.WM_MENUGETOBJECT: return "WM_MENUGETOBJECT"
        case windows.WM_UNINITMENUPOPUP: return "WM_UNINITMENUPOPUP"
        case windows.WM_MENUCOMMAND: return "WM_MENUCOMMAND"
        case windows.WM_CHANGEUISTATE: return "WM_CHANGEUISTATE"
        case windows.WM_UPDATEUISTATE: return "WM_UPDATEUISTATE"
        case windows.WM_QUERYUISTATE: return "WM_QUERYUISTATE"
        case windows.WM_LBTRACKPOINT: return "WM_LBTRACKPOINT"
        case windows.WM_CTLCOLORMSGBOX: return "WM_CTLCOLORMSGBOX"
        case windows.WM_CTLCOLOREDIT: return "WM_CTLCOLOREDIT"
        case windows.WM_CTLCOLORLISTBOX: return "WM_CTLCOLORLISTBOX"
        case windows.WM_CTLCOLORBTN: return "WM_CTLCOLORBTN"
        case windows.WM_CTLCOLORDLG: return "WM_CTLCOLORDLG"
        case windows.WM_CTLCOLORSCROLLBAR: return "WM_CTLCOLORSCROLLBAR"
        case windows.WM_CTLCOLORSTATIC: return "WM_CTLCOLORSTATIC"
        case windows.CB_GETEDITSEL: return "CB_GETEDITSEL"
        case windows.CB_LIMITTEXT: return "CB_LIMITTEXT"
        case windows.CB_SETEDITSEL: return "CB_SETEDITSEL"
        case windows.CB_ADDSTRING: return "CB_ADDSTRING"
        case windows.CB_DELETESTRING: return "CB_DELETESTRING"
        case windows.CB_DIR: return "CB_DIR"
        case windows.CB_GETCOUNT: return "CB_GETCOUNT"
        case windows.CB_GETCURSEL: return "CB_GETCURSEL"
        case windows.CB_GETLBTEXT: return "CB_GETLBTEXT"
        case windows.CB_GETLBTEXTLEN: return "CB_GETLBTEXTLEN"
        case windows.CB_INSERTSTRING: return "CB_INSERTSTRING"
        case windows.CB_RESETCONTENT: return "CB_RESETCONTENT"
        case windows.CB_FINDSTRING: return "CB_FINDSTRING"
        case windows.CB_SELECTSTRING: return "CB_SELECTSTRING"
        case windows.CB_SETCURSEL: return "CB_SETCURSEL"
        case windows.CB_SHOWDROPDOWN: return "CB_SHOWDROPDOWN"
        case windows.CB_GETITEMDATA: return "CB_GETITEMDATA"
        case windows.CB_SETITEMDATA: return "CB_SETITEMDATA"
        case windows.CB_GETDROPPEDCONTROLRECT: return "CB_GETDROPPEDCONTROLRECT"
        case windows.CB_SETITEMHEIGHT: return "CB_SETITEMHEIGHT"
        case windows.CB_GETITEMHEIGHT: return "CB_GETITEMHEIGHT"
        case windows.CB_SETEXTENDEDUI: return "CB_SETEXTENDEDUI"
        case windows.CB_GETEXTENDEDUI: return "CB_GETEXTENDEDUI"
        case windows.CB_GETDROPPEDSTATE: return "CB_GETDROPPEDSTATE"
        case windows.CB_FINDSTRINGEXACT: return "CB_FINDSTRINGEXACT"
        case windows.CB_SETLOCALE: return "CB_SETLOCALE"
        case windows.CB_GETLOCALE: return "CB_GETLOCALE"
        case windows.CB_GETTOPINDEX: return "CB_GETTOPINDEX"
        case windows.CB_SETTOPINDEX: return "CB_SETTOPINDEX"
        case windows.CB_GETHORIZONTALEXTENT: return "CB_GETHORIZONTALEXTENT"
        case windows.CB_SETHORIZONTALEXTENT: return "CB_SETHORIZONTALEXTENT"
        case windows.CB_GETDROPPEDWIDTH: return "CB_GETDROPPEDWIDTH"
        case windows.CB_SETDROPPEDWIDTH: return "CB_SETDROPPEDWIDTH"
        case windows.CB_INITSTORAGE: return "CB_INITSTORAGE"
        case windows.CB_MULTIPLEADDSTRING: return "CB_MULTIPLEADDSTRING"
        case windows.CB_GETCOMBOBOXINFO: return "CB_GETCOMBOBOXINFO"
        case windows.CB_MSGMAX: return "CB_MSGMAX"
        case windows.WM_MOUSEMOVE: return "WM_MOUSEMOVE"
        case windows.WM_LBUTTONDOWN: return "WM_LBUTTONDOWN"
        case windows.WM_LBUTTONUP: return "WM_LBUTTONUP"
        case windows.WM_LBUTTONDBLCLK: return "WM_LBUTTONDBLCLK"
        case windows.WM_RBUTTONDOWN: return "WM_RBUTTONDOWN"
        case windows.WM_RBUTTONUP: return "WM_RBUTTONUP"
        case windows.WM_RBUTTONDBLCLK: return "WM_RBUTTONDBLCLK"
        case windows.WM_MBUTTONDOWN: return "WM_MBUTTONDOWN"
        case windows.WM_MBUTTONUP: return "WM_MBUTTONUP"
        case windows.WM_MBUTTONDBLCLK: return "WM_MBUTTONDBLCLK"
        case windows.WM_MOUSEWHEEL: return "WM_MOUSEWHEEL"
        case windows.WM_XBUTTONDOWN: return "WM_XBUTTONDOWN"
        case windows.WM_XBUTTONUP: return "WM_XBUTTONUP"
        case windows.WM_XBUTTONDBLCLK: return "WM_XBUTTONDBLCLK"
        case windows.WM_MOUSEHWHEEL: return "WM_MOUSEHWHEEL"
        case windows.WM_PARENTNOTIFY: return "WM_PARENTNOTIFY"
        case windows.WM_ENTERMENULOOP: return "WM_ENTERMENULOOP"
        case windows.WM_EXITMENULOOP: return "WM_EXITMENULOOP"
        case windows.WM_NEXTMENU: return "WM_NEXTMENU"
        case windows.WM_SIZING: return "WM_SIZING"
        case windows.WM_CAPTURECHANGED: return "WM_CAPTURECHANGED"
        case windows.WM_MOVING: return "WM_MOVING"
        case windows.WM_POWERBROADCAST: return "WM_POWERBROADCAST"
        case windows.WM_DEVICECHANGE: return "WM_DEVICECHANGE"
        case windows.WM_MDICREATE: return "WM_MDICREATE"
        case windows.WM_MDIDESTROY: return "WM_MDIDESTROY"
        case windows.WM_MDIACTIVATE: return "WM_MDIACTIVATE"
        case windows.WM_MDIRESTORE: return "WM_MDIRESTORE"
        case windows.WM_MDINEXT: return "WM_MDINEXT"
        case windows.WM_MDIMAXIMIZE: return "WM_MDIMAXIMIZE"
        case windows.WM_MDITILE: return "WM_MDITILE"
        case windows.WM_MDICASCADE: return "WM_MDICASCADE"
        case windows.WM_MDIICONARRANGE: return "WM_MDIICONARRANGE"
        case windows.WM_MDIGETACTIVE: return "WM_MDIGETACTIVE"
        case windows.WM_MDISETMENU: return "WM_MDISETMENU"
        case windows.WM_ENTERSIZEMOVE: return "WM_ENTERSIZEMOVE"
        case windows.WM_EXITSIZEMOVE: return "WM_EXITSIZEMOVE"
        case windows.WM_DROPFILES: return "WM_DROPFILES"
        case windows.WM_MDIREFRESHMENU: return "WM_MDIREFRESHMENU"
        case windows.WM_POINTERDEVICECHANGE: return "WM_POINTERDEVICECHANGE"
        case windows.WM_POINTERDEVICEINRANGE: return "WM_POINTERDEVICEINRANGE"
        case windows.WM_POINTERDEVICEOUTOFRANGE: return "WM_POINTERDEVICEOUTOFRANGE"
        case windows.WM_TOUCH: return "WM_TOUCH"
        case windows.WM_NCPOINTERUPDATE: return "WM_NCPOINTERUPDATE"
        case windows.WM_NCPOINTERDOWN: return "WM_NCPOINTERDOWN"
        case windows.WM_NCPOINTERUP: return "WM_NCPOINTERUP"
        case windows.WM_POINTERUPDATE: return "WM_POINTERUPDATE"
        case windows.WM_POINTERDOWN: return "WM_POINTERDOWN"
        case windows.WM_POINTERUP: return "WM_POINTERUP"
        case windows.WM_POINTERENTER: return "WM_POINTERENTER"
        case windows.WM_POINTERLEAVE: return "WM_POINTERLEAVE"
        case windows.WM_POINTERACTIVATE: return "WM_POINTERACTIVATE"
        case windows.WM_POINTERCAPTURECHANGED: return "WM_POINTERCAPTURECHANGED"
        case windows.WM_TOUCHHITTESTING: return "WM_TOUCHHITTESTING"
        case windows.WM_POINTERWHEEL: return "WM_POINTERWHEEL"
        case windows.WM_POINTERHWHEEL: return "WM_POINTERHWHEEL"
        case windows.DM_POINTERHITTEST: return "DM_POINTERHITTEST"
        case windows.WM_POINTERROUTEDTO: return "WM_POINTERROUTEDTO"
        case windows.WM_POINTERROUTEDAWAY: return "WM_POINTERROUTEDAWAY"
        case windows.WM_POINTERROUTEDRELEASED: return "WM_POINTERROUTEDRELEASED"
        case windows.WM_IME_REPORT: return "WM_IME_REPORT"
        case windows.WM_IME_SETCONTEXT: return "WM_IME_SETCONTEXT"
        case windows.WM_IME_NOTIFY: return "WM_IME_NOTIFY"
        case windows.WM_IME_CONTROL: return "WM_IME_CONTROL"
        case windows.WM_IME_COMPOSITIONFULL: return "WM_IME_COMPOSITIONFULL"
        case windows.WM_IME_SELECT: return "WM_IME_SELECT"
        case windows.WM_IME_CHAR: return "WM_IME_CHAR"
        case windows.WM_IME_REQUEST: return "WM_IME_REQUEST"
        case windows.WM_IMEKEYDOWN: return "WM_IMEKEYDOWN"
        case windows.WM_IMEKEYUP: return "WM_IMEKEYUP"
        case windows.WM_NCMOUSEHOVER: return "WM_NCMOUSEHOVER"
        case windows.WM_MOUSEHOVER: return "WM_MOUSEHOVER"
        case windows.WM_NCMOUSELEAVE: return "WM_NCMOUSELEAVE"
        case windows.WM_MOUSELEAVE: return "WM_MOUSELEAVE"
        case windows.WM_WTSSESSION_CHANGE: return "WM_WTSSESSION_CHANGE"
        case windows.WM_TABLET_FIRST: return "WM_TABLET_FIRST"
        case windows.WM_TABLET_LAST: return "WM_TABLET_LAST"
        case windows.WM_DPICHANGED: return "WM_DPICHANGED"
        case windows.WM_DPICHANGED_BEFOREPARENT: return "WM_DPICHANGED_BEFOREPARENT"
        case windows.WM_DPICHANGED_AFTERPARENT: return "WM_DPICHANGED_AFTERPARENT"
        case windows.WM_GETDPISCALEDSIZE: return "WM_GETDPISCALEDSIZE"
        case windows.WM_CUT: return "WM_CUT"
        case windows.WM_COPY: return "WM_COPY"
        case windows.WM_PASTE: return "WM_PASTE"
        case windows.WM_CLEAR: return "WM_CLEAR"
        case windows.WM_UNDO: return "WM_UNDO"
        case windows.WM_RENDERFORMAT: return "WM_RENDERFORMAT"
        case windows.WM_RENDERALLFORMATS: return "WM_RENDERALLFORMATS"
        case windows.WM_DESTROYCLIPBOARD: return "WM_DESTROYCLIPBOARD"
        case windows.WM_DRAWCLIPBOARD: return "WM_DRAWCLIPBOARD"
        case windows.WM_PAINTCLIPBOARD: return "WM_PAINTCLIPBOARD"
        case windows.WM_VSCROLLCLIPBOARD: return "WM_VSCROLLCLIPBOARD"
        case windows.WM_SIZECLIPBOARD: return "WM_SIZECLIPBOARD"
        case windows.WM_ASKCBFORMATNAME: return "WM_ASKCBFORMATNAME"
        case windows.WM_CHANGECBCHAIN: return "WM_CHANGECBCHAIN"
        case windows.WM_HSCROLLCLIPBOARD: return "WM_HSCROLLCLIPBOARD"
        case windows.WM_QUERYNEWPALETTE: return "WM_QUERYNEWPALETTE"
        case windows.WM_PALETTEISCHANGING: return "WM_PALETTEISCHANGING"
        case windows.WM_PALETTECHANGED: return "WM_PALETTECHANGED"
        case windows.WM_HOTKEY: return "WM_HOTKEY"
        case windows.WM_PRINT: return "WM_PRINT"
        case windows.WM_PRINTCLIENT: return "WM_PRINTCLIENT"
        case windows.WM_APPCOMMAND: return "WM_APPCOMMAND"
        case windows.WM_THEMECHANGED: return "WM_THEMECHANGED"
        case windows.WM_CLIPBOARDUPDATE: return "WM_CLIPBOARDUPDATE"
        case windows.WM_DWMCOMPOSITIONCHANGED: return "WM_DWMCOMPOSITIONCHANGED"
        case windows.WM_DWMNCRENDERINGCHANGED: return "WM_DWMNCRENDERINGCHANGED"
        case windows.WM_DWMCOLORIZATIONCOLORCHANGED: return "WM_DWMCOLORIZATIONCOLORCHANGED"
        case windows.WM_DWMWINDOWMAXIMIZEDCHANGE: return "WM_DWMWINDOWMAXIMIZEDCHANGE"
        case windows.WM_DWMSENDICONICTHUMBNAIL: return "WM_DWMSENDICONICTHUMBNAIL"
        case windows.WM_GETTITLEBARINFOEX: return "WM_GETTITLEBARINFOEX"
        case windows.WM_HANDHELDFIRST: return "WM_HANDHELDFIRST"
        case windows.WM_HANDHELDLAST: return "WM_HANDHELDLAST"
        case windows.WM_AFXFIRST: return "WM_AFXFIRST"
        case windows.WM_AFXLAST: return "WM_AFXLAST"
        case windows.WM_PENWINFIRST: return "WM_PENWINFIRST"
        case windows.WM_RCRESULT: return "WM_RCRESULT"
        case windows.WM_HOOKRCRESULT: return "WM_HOOKRCRESULT"
        case windows.WM_GLOBALRCCHANGE: return "WM_GLOBALRCCHANGE"
        case windows.WM_SKB: return "WM_SKB"
        case windows.WM_HEDITCTL: return "WM_HEDITCTL"
        case windows.WM_PENMISC: return "WM_PENMISC"
        case windows.WM_CTLINIT: return "WM_CTLINIT"
        case windows.WM_PENEVENT: return "WM_PENEVENT"
        case windows.WM_PENWINLAST: return "WM_PENWINLAST"
        }
        return "UNKNOWN!"
    }
    */

} // when BACKEND == .Windows