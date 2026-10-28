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
            lpstrFile         = &file_buf[0],
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
            windows.CF_UNICODETEXT,
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

        memory_handle := windows.GetClipboardData(windows.CF_UNICODETEXT)

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

            button: Button = .Invalid

            if int(scancode) < len(_win32_scancode_table) {
                button = _win32_scancode_table[scancode]

                if is_extended {
                    #partial switch button {
                    case .Enter: button = .Keypad_Enter
                    case .Left_Alt: button = .Right_Alt
                    case .Left_Control: button = .Right_Control
                    case .Slash: button = .Keypad_Divide
                    case .Capslock: button = .Capslock
                    }
                } else {
                    #partial switch button  {
                    case .Home: button = .Keypad_7
                    case .Up: button = .Keypad_8
                    case .Page_Up: button = .Keypad_9
                    case .Left: button = .Keypad_4
                    case .Right: button = .Keypad_6
                    case .End: button = .Keypad_1
                    case .Down: button = .Keypad_2
                    case .Page_Down: button = .Keypad_3
                    case .Insert: button = .Keypad_0
                    case .Delete: button = .Keypad_Decimal
                    case .Print_Screen: button = .Keypad_Multiply
                    }
                }
            }

            if button == .Invalid {
                switch wparam {
                case windows.VK_LEFT: button = .Left
                case windows.VK_RIGHT: button = .Right
                case windows.VK_UP: button = .Up
                case windows.VK_DOWN: button = .Down
                }
            }

            if button == .Invalid {
                break
            }

            // Check for Alt+F4
            if msg == windows.WM_KEYDOWN || msg == windows.WM_SYSKEYDOWN {
                if bool(windows.HIWORD(lparam) & windows.KF_ALTDOWN) && button == .F4 {
                    _event_queue_push(Event_Exit{})
                    break
                }
            }

            _event_queue_push(Event_Button{
                button = button,
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

            for button in MOUSE_BUTTONS {
                mask: uintptr
                #partial switch button {
                case .Mouse_Left:     mask = windows.MK_LBUTTON
                case .Mouse_Middle:   mask = windows.MK_MBUTTON
                case .Mouse_Right:    mask = windows.MK_RBUTTON
                case .Mouse_Extra_1:  mask = windows.MK_XBUTTON1
                case .Mouse_Extra_2:  mask = windows.MK_XBUTTON2
                }

                curr_down := (wparam & mask) != 0
                prev_down := (_state.last_mouse_wparam & mask) != 0

                if curr_down && !prev_down {
                    _event_queue_push(Event_Button{
                        button = button,
                        pressed = true,
                    })
                } else if prev_down && !curr_down {
                    _event_queue_push(Event_Button{
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

            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_1_DOWN) != 0 { _event_queue_push(Event_Button{ button = .Mouse_Left, pressed = true }) }
            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_1_UP)   != 0 { _event_queue_push(Event_Button{ button = .Mouse_Left, pressed = false }) }
            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_2_DOWN) != 0 { _event_queue_push(Event_Button{ button = .Mouse_Right, pressed = true }) }
            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_2_UP)   != 0 { _event_queue_push(Event_Button{ button = .Mouse_Right, pressed = false }) }
            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_3_DOWN) != 0 { _event_queue_push(Event_Button{ button = .Mouse_Middle, pressed = true }) }
            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_3_UP)   != 0 { _event_queue_push(Event_Button{ button = .Mouse_Middle, pressed = false }) }
            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_4_DOWN) != 0 { _event_queue_push(Event_Button{ button = .Mouse_Extra_1, pressed = true }) }
            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_4_UP)   != 0 { _event_queue_push(Event_Button{ button = .Mouse_Extra_1, pressed = false }) }
            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_5_DOWN) != 0 { _event_queue_push(Event_Button{ button = .Mouse_Extra_2, pressed = true }) }
            if (mouse.usButtonFlags & windows.RI_MOUSE_BUTTON_5_UP)   != 0 { _event_queue_push(Event_Button{ button = .Mouse_Extra_2, pressed = false }) }

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
            if len(str) > 1 && str[len(str)-1] == '\n' {
                str = str[:len(str)-1]
            }
            base.log_err("%s : %s", text, str, loc = loc)
        }
    }


    // from sdl/scancodes_windows.h
    @(rodata)
    _win32_scancode_table := [?]Button{
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

} // when BACKEND == .Windows