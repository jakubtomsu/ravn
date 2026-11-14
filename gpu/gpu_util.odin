#+vet explicit-allocators shadowing style unused
package ravn_gpu

import "core:log"
import "core:fmt"
import "base:runtime"



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: RTTI Vertex Layout
//

// Make vertex layout from a struct type using RTTI.
// Every field must be 4-byte aligned.
// Example:
//  Vertex :: struct {
//      pos:   [3]f32,
//      uv:    [2]f32,
//      color: [4]u8 `gpu:"U8x4_Norm"`,
//  }
make_vertex_layout :: proc($T: typeid, mode: Vertex_Step_Mode, loc := #caller_location) -> (result: Vertex_Layout_Desc) {
    ti_base := runtime.type_info_base(type_info_of(T))

    result.mode = mode

    #partial switch _ in ti_base.variant {
    case ^runtime.Type_Info_Float,
         ^runtime.Type_Info_Integer,
         ^runtime.Type_Info_Array:
        format, ok := _vertex_format_from_type(ti_base, loc = loc)
        if !ok {
            return {}
        }
        result.slots[0] = format
        return result
    }

    st, is_struct := ti_base.variant.(^runtime.Type_Info_Struct)
    if !is_struct {
        log.errorf("'%v' is not a struct", typeid_of(T), location = loc)
        panic("type must be a struct", loc)
    }

    if int(st.field_count) > MAX_VERTEX_LAYOUT_SLOTS {
        log.errorf("'%v' has %i fields, max is %i", typeid_of(T), st.field_count, MAX_VERTEX_LAYOUT_SLOTS, location = loc)
        panic("too many vertex fields", loc)
    }

    slot_index := 0
    for field_index in 0 ..< st.field_count {
        name := st.names[field_index]
        offset := st.offsets[field_index]

        if offset % 4 != 0 {
            log.errorf("field '%v.%s' at offset %i is not 4-byte aligned", typeid_of(T), name, offset, location = loc)
            panic("field is not 4-byte aligned", loc)
        }

        slot_format: Vertex_Format

        ok: bool
        if tag_val, has_tag := _struct_tag_lookup(st.tags[field_index], "gpu"); has_tag {
            if tag_val == "-" {
                continue
            }
            slot_format, ok = _vertex_format_from_name(tag_val, loc)
            if !ok {
                log.errorf("field '%v.%s' maps to '%s', which is not a valid Vertex_Format", typeid_of(T), name, tag_val, location = loc)
                panic("no matching Vertex_Format", loc)
            }
        } else {
            field_ti := runtime.type_info_core(st.types[field_index])
            slot_format, ok = _vertex_format_from_type(field_ti, loc = loc)
            if !ok {
                panic("Invalid vertex format type")
            }
        }

        result.slots[slot_index] = slot_format
        slot_index += 1
    }

    return result
}

_vertex_format_from_type :: proc(ti: ^runtime.Type_Info, loc: runtime.Source_Code_Location) -> (Vertex_Format, bool) {
    elem_ti := ti
    num_components := 1
    if arr, is_arr := ti.variant.(^runtime.Type_Info_Array); is_arr {
        num_components = arr.count
        elem_ti = runtime.type_info_core(arr.elem)
    }

    prefix: string
    #partial switch v in elem_ti.variant {
    case ^runtime.Type_Info_Float:   prefix = "F"
    case ^runtime.Type_Info_Integer: prefix = v.signed ? "I" : "U"
    case:
        log.errorf("Array '%v' has unsupported type '%v'", ti.id, elem_ti, location = loc)
        return .Invalid, false
    }

    format_name := fmt.tprintf("%s%i", prefix, elem_ti.size * 8)
    if num_components > 1 {
        format_name = fmt.tprintf("%sx%i", format_name, num_components)
    }

    result, ok := _vertex_format_from_name(format_name, loc)
    if !ok {
        log.errorf("Type '%v' maps to '%s', which is not a valid Vertex_Format", ti.id, format_name, location = loc)
        return .Invalid, false
    }

    return result, true
}

_vertex_format_from_name :: proc(name: string, loc: runtime.Source_Code_Location) -> (Vertex_Format, bool) {
    enum_ti := runtime.type_info_base(type_info_of(Vertex_Format)).variant.(^runtime.Type_Info_Enum)
    for n, i in enum_ti.names {
        format := Vertex_Format(i64(enum_ti.values[i]))
        if n == name && format != .Invalid {
            return format, true
        }
    }
    return .Invalid, false
}

// Based on core:reflect.struct_tag_lookup
@(require_results)
_struct_tag_lookup :: proc(tag: string, key: string) -> (value: string, ok: bool) {
    for t := tag; t != ""; /**/ {
        i := 0
        for i < len(t) && t[i] == ' ' { // Skip whitespace
            i += 1
        }
        t = t[i:]
        if len(t) == 0 {
            break
        }

        i = 0
        loop: for i < len(t) {
            switch t[i] {
            case ':', '"':
                break loop
            case 0x00 ..< ' ', 0x7f ..= 0x9f: // break if control character is found
                break loop
            }
            i += 1
        }

        if i == 0 {
            break
        }
        if i+1 >= len(t) {
            break
        }

        if t[i] != ':' || t[i+1] != '"' {
            break
        }
        name := string(t[:i])
        t = t[i+1:]

        i = 1
        for i < len(t) && t[i] != '"' { // find closing quote
            if t[i] == '\\' {
                i += 1 // Skip escaped characters
            }
            i += 1
        }

        if i >= len(t) {
            break
        }

        val := string(t[:i+1])
        t = t[i+1:]

        if key == name {
            return val[1:i], true
        }
    }
    return
}
