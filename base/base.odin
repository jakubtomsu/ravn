package ravn_base

import "core:fmt"
import "base:runtime"

RELEASE :: #config(RELEASE, false)

Handle_Gen :: u8
Handle_Index :: u16

Handle :: struct {
    index:  Handle_Index,
    gen:    Handle_Gen,
    _:      u8,
}

make_logger :: proc() -> runtime.Logger {
    return {
        procedure = _logger_proc,
        data = nil,
        options = {.Terminal_Color},
    }
}

@(rodata)
_logger_prefix := [?]string{
     0..<10 = "DBG:  ",
    10..<20 = "INFO: ",
    20..<30 = "WARN: ",
    30..<40 = "ERR:  ",
    40..<50 = "FATAL: ",
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

    // NOTE: this should remain a single print call
    fmt.printfln("%s%s%s%s(%i:%i) %s: %s",
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
