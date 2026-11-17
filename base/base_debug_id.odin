#+vet unused shadowing style explicit-allocators
package ravn_base

import "base:runtime"
import "core:fmt"

DEBUG_ID_ENABLED :: #config(DEBUG_ID_ENABLED, ODIN_DEBUG)

when DEBUG_ID_ENABLED {
    Debug_ID :: struct {
        name:   string,
        loc:    runtime.Source_Code_Location,
    }
} else {
    Debug_ID :: struct{}
}

// NOTE: A debug ID clones the name string with the *defualt allocator*. It intentionally bypasses
// the context allocator because many debug IDs are expected to last for the duration of the whole
// program, and not expected to ever be freed. This is fine, especially since it's intended for
// debug code only. Leaking the memory means we can never worry about use after free and corrupt
// IDs. It also means we do not have to needlessly satisfy the tracking allocator.
create_debug_id :: proc(name: string, loc: runtime.Source_Code_Location) -> Debug_ID {
    when DEBUG_ID_ENABLED {
        name := name
        if len(name) <= 0 {
            name = "<no debug name>"
        }
        name_clone := make([]byte, len(name), allocator = runtime.default_context().allocator, loc = loc)
        copy(name_clone, name)
        return {
            name = string(name_clone),
            loc = loc,
        }
    } else {
        return {}
    }
}

destroy_debug_id :: proc(id: ^Debug_ID) {
    when DEBUG_ID_ENABLED {
        delete_string(id.name, allocator = runtime.default_context().allocator)
        id^ = {}
    }
}

format_debug_id :: proc(id: Debug_ID, allocator := context.temp_allocator) -> string {
    when DEBUG_ID_ENABLED {
        if id != {} {
            return fmt.aprintf("<%s(%i:%i)%s: %s>", id.loc.file_path, id.loc.line, id.loc.column, id.loc.procedure, id.name, allocator = allocator)
        }
    }
    return "<no debug ID>"
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
            msg := fmt.tprintf("%s %s %s", expr, format_debug_id(id, context.temp_allocator), message)
            p("runtime assertion", msg, loc)
        }
        internal(id, message, expr, loc)
    }
}

panic_id :: proc(id: Debug_ID, message: string, loc := #caller_location) -> ! {
    panic(fmt.tprintf("%s %s", message, format_debug_id(id, context.temp_allocator)))
}
