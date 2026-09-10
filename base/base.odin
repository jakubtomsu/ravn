package ravn_base

import "base:runtime"
import "ufmt"

RELEASE :: #config(RELEASE, false)

eprintf :: ufmt.eprintf
eprintfln :: ufmt.eprintfln
tprintf :: ufmt.tprintf

Handle_Gen :: u8
Handle_Index :: u16

Handle :: struct {
    index:  Handle_Index,
    gen:    Handle_Gen,
    _:      u8,
}


// MARK: Log

Log_Level :: runtime.Logger_Level

log_err :: proc(format: string, args: ..any, loc := #caller_location) {
    log(.Error, format = format, args = args, loc = loc)
}

log_warn :: proc(format: string, args: ..any, loc := #caller_location) {
    log(.Warning, format = format, args = args, loc = loc)
}

log_info :: proc(format: string, args: ..any, loc := #caller_location) {
    log(.Info, format = format, args = args, loc = loc)
}

log_debug :: proc(format: string, args: ..any, loc := #caller_location) {
    log(.Debug, format = format, args = args, loc = loc)
}

log_dump :: proc(arg: any, expr := #caller_expression(arg), loc := #caller_location) {
    if type_info_of(arg.id).size <= 16 {
        log(.Debug, format = "%s = %v", args = {expr, arg}, loc = loc)
    } else {
        log(.Debug, format = "%s = %#", args = {expr, arg}, loc = loc)
    }
}

log :: proc(level: Log_Level, format: string, args: ..any, loc := #caller_location) {
    logger := context.logger
    if level < logger.lowest_level {
        return
    }
    if logger.procedure == nil {
        return
    }
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    str := ufmt.tprintf(format = format, args = args)
    context.logger.procedure(logger.data, level, str, logger.options, location = loc)
}

make_logger :: proc() -> runtime.Logger {
    return {
        procedure = _logger_proc,
        data = nil,
        options = {.Terminal_Color},
    }
}

_logger_proc :: proc(
    logger_data:    rawptr,
    level:          runtime.Logger_Level,
    text:           string,
    options:        bit_set[runtime.Logger_Option],
    loc             := #caller_location,
) {
    ESC :: "\e"
    CSI :: ESC + "["
    SGR :: "m"
    RESET :: "0"

    FG_BLACK                :: "30"
    FG_RED                  :: "31"
    FG_GREEN                :: "32"
    FG_YELLOW               :: "33"
    FG_BLUE                 :: "34"
    FG_MAGENTA              :: "35"
    FG_CYAN                 :: "36"
    FG_WHITE                :: "37"

    begin_col: string
    end_col: string

    if .Terminal_Color in options {
        end_col = CSI + RESET + SGR
        switch level {
        case .Debug:    begin_col = CSI + FG_BLACK + SGR
        case .Info:     begin_col = CSI + FG_CYAN + SGR
        case .Warning:  begin_col = CSI + FG_YELLOW + SGR
        case .Error:    begin_col = CSI + FG_RED + SGR
        case .Fatal:    begin_col = CSI + FG_RED + SGR
        }
    }

    // NOTE: it's important for this to remain a single call to eprintfln.
    // This way multithreaded logging should behave nicer.
    ufmt.eprintfln("%s%s%s%s(%i:%i) %s: %s",
        begin_col,
        _logger_prefix[level],
        end_col,
        loc.file_path,
        loc.line,
        loc.column,
        loc.procedure,
        text,
    )
}

@(rodata)
_logger_prefix := [?]string{
     0..<10 = "DBG:  ",
    10..<20 = "INFO: ",
    20..<30 = "WARN: ",
    30..<40 = "ERR:  ",
    40..<50 = "FATAL: ",
}

@(require_results)
ptr_bytes :: proc(ptr: ^$T, len := 1) -> []byte {
    return transmute([]byte)runtime.Raw_Slice{ptr, len * size_of(T)}
}

@(require_results)
slice_bytes :: proc(s: []$T) -> []byte where T != byte {
    return ([^]byte)(raw_data(s))[:len(s) * size_of(T)]
}

@(require_results)
clone_to_cstring :: proc(s: string, allocator := context.allocator, loc := #caller_location) -> (res: cstring, err: runtime.Allocator_Error) #optional_allocator_error {
    c := make([]byte, len(s)+1, allocator, loc) or_return
    copy(c, s)
    c[len(s)] = 0
    return cstring(&c[0]), nil
}

@(require_results)
reinterpret_slice :: proc "contextless" ($T: typeid, data: []$E, loc := #caller_location) -> []T {
    bytes := to_bytes(data)
    n := len(bytes) / size_of(T)
    assert_contextless(n * size_of(T) == len(bytes), loc = loc)
    return (cast([^]T)raw_data(bytes))[:n]
}

@(require_results)
reinterpret_bytes :: proc "contextless" ($T: typeid, bytes: []byte, loc := #caller_location) -> []T {
    n := len(bytes) / size_of(T)
    assert_contextless(n * size_of(T) == len(bytes), loc = loc)
    return ([^]T)(raw_data(bytes))[:n]
}

@(require_results)
to_bytes :: proc "contextless" (data: []$T) -> []byte {
    return (cast([^]byte)raw_data(data))[:size_of(T) * len(data)]
}

// Quickly checks if x is not NaN or Inf
@(require_results)
is_finite_f32 :: #force_inline proc(x: f32) -> bool {
    return ((transmute(u32)x) & 0x7F800000) != 0x7F800000
}

@(require_results)
is_finite_vec :: #force_inline proc(v: [$N]f32) -> bool {
    res := true
    for x in v {
        res &= is_finite_f32(x)
    }
    return res
}

@(require_results)
hash_fnv64a :: proc "contextless" (data: []byte, seed: u64) -> u64 {
    h: u64 = seed
    for b in data {
        h = (h ~ u64(b)) * 0x100000001b3
    }
    return h
}

// https://nullprogram.com/blog/2018/07/31/

@(require_results)
hash_murmurhash32_mix32 :: proc "contextless" (x: u32) -> u32 {
    x := x
    x ~= x >> 16
    x *= 0x85ebca6b
    x ~= x >> 13
    x *= 0xc2b2ae35
    x ~= x >> 16
    return x
}

@(require_results)
hash_splittable64 :: proc "contextless" (x: u64) -> u64 {
    x := x
    x ~= x >> 30
    x *= 0xbf58476d1ce4e5b9
    x ~= x >> 27
    x *= 0x94d049bb133111eb
    x ~= x >> 31
    return x
}

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

destroy_debug_id :: proc(id: ^Debug_ID) {
    delete(transmute(string)(id.name_ptr[:id.name_len]))
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
