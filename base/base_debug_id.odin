package ravn_base

import "ufmt"
import "base:runtime"

Debug_ID :: struct {
    name_ptr:   [^]byte,
    file_ptr:   [^]byte,
    name_len:   i16,
    file_len:   i16,
    line:       i32,
}

create_debug_id :: proc(name: string, loc := #caller_location, allocator := context.allocator) -> Debug_ID {
    name := name
    if name == "" {
        name = "AnonID"
    }
    name_clone := make([]byte, len(name), allocator)
    copy(name_clone, name)
    return {
        name_ptr = raw_data(name_clone),
        name_len = i16(len(name_clone)),
        file_ptr = raw_data(loc.file_path),
        file_len = i16(len(loc.file_path)),
        line = loc.line,
    }
}

destroy_debug_id :: proc(id: ^Debug_ID, allocator := context.allocator) {
    delete(transmute(string)(id.name_ptr[:id.name_len]), allocator = allocator)
}

format_debug_id :: proc(id: Debug_ID, allocator := context.temp_allocator) -> string {
    return ufmt.aprintf("%s(%s:%i)", id.name_ptr[:id.name_len], id.file_ptr[:id.file_len], id.line, allocator = allocator)
}

get_debug_id_name :: #force_inline proc "contextless" (id: Debug_ID) -> string {
    return id.name_ptr == nil ? "nil" : transmute(string)(id.name_ptr[:id.name_len])
}

get_debug_id_file :: #force_inline proc "contextless" (id: Debug_ID) -> string {
    return id.file_ptr == nil ? "nil" : transmute(string)(id.file_ptr[:id.file_len])
}

@(disabled = ODIN_DISABLE_ASSERT)
assert_id :: proc(id: Debug_ID, condition: bool, message: string = "", expr := #caller_expression(condition), loc := #caller_location) {
    if !condition {
        @(cold)
        internal :: proc(id: Debug_ID, message: string, expr: string, loc: runtime.Source_Code_Location) {
            p := context.assertion_failure_proc
            if p == nil {
                p = runtime.default_assertion_failure_proc
            }
            msg := ufmt.tprintf("%s\n\tCondition: %s\n\tSource: %s %s:%i\n\t", message, expr, get_debug_id_name(id), get_debug_id_file(id), id.line)
            p("runtime assertion", msg, loc)
        }
        internal(id, message, expr, loc)
    }
}

panic_id :: proc(id: Debug_ID, message: string, loc := #caller_location) -> ! {
    panic(ufmt.tprintf("%s\n\tSource: %s %s:%i\n\t", message, get_debug_id_name(id), get_debug_id_file(id), id.line))
}
