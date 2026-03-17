package raven_base

import "base:runtime"
import "ufmt"



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


// MARK: Module

// NOTE: This structure is passed between DLLs when hot-reloading.
Module_Desc :: struct {
    state_size: i64,
    init:       Module_Init_Proc,
    shutdown:   Module_Shutdown_Proc,
    update:     Module_Update_Proc,
}

// Called after internal init is done to let the app initialize.
Module_Init_Proc ::       #type proc()
// Called after request_shutdown() but before the engine cleans up.
Module_Shutdown_Proc ::   #type proc()
// Called every frame.
// Usually, hot_ptr is nil. But after a hotreload, hot_ptr is the last returned data_ptr.
// This way you can
Module_Update_Proc ::     #type proc(hot_ptr: rawptr) -> (data_ptr: rawptr)
