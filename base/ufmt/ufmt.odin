/*
Micro-fmt

Extremely stripped down `core:fmt` replacement.

Supports only the following qualifiers:
- %s: strings
- %f: floats with 3 decimal places
- %i: integers
- %x: integers, pointers or floats
- %%: literal percentage sign
- %v: any value, RTTI will be used for printing.

NOTE: curly braces don't need to be doubled ({{ and }}) like in `core:fmt`

By Jakub Tomšů
Read https://jakubtomsu.github.io/posts/odin_comp_speed/ for more info.
*/
#+no-instrumentation
package ufmt

import "base:runtime"

INDENT :: "  "

eprintf :: proc(format: string, args: ..any) -> int {
    str := tprintf(format = format, args = args)
    runtime.print_string(str)
    return len(str)
}

eprintfln :: proc(format: string, args: ..any) -> int {
    str := tprintf(format = format, args = args)
    runtime.print_string(str)
    runtime.print_byte('\n')
    return len(str)
}

ctprintf :: proc(format: string, args: ..any) -> cstring {
    return cstring(raw_data(tprintf(format, args)))
}


tprintf :: proc(format: string, args: ..any) -> string {
    curr := format

    buf := make([dynamic]byte, 0, len(format) + 256, context.temp_allocator)

    curr_arg := 0

    for len(curr) > 0 {
        r, r_size := runtime.string_decode_rune(curr)

        if r != '%' {
            append_elems(&buf, ..transmute([]byte)curr[:r_size])
            curr = curr[r_size:]
            continue
        }

        curr = curr[r_size:]

        if len(curr) == 0 {
            return "<INVALID FORMAT>"
        }


        qual, qual_size := runtime.string_decode_rune(curr)
        curr = curr[qual_size:]

        arg: any = nil
        if curr_arg < len(args) {
            arg = args[curr_arg]
        }

        consume_arg := true
        switch qual {
        case 's':
            switch val in arg {
            case string:  _append_string(&buf, val)
            case cstring: _append_string(&buf, string(val))
            case: return "<NOT STRING>"
            }

        case 'i':
            switch val in arg {
            case u8:    _append_int(&buf, int(val))
            case i8:    _append_int(&buf, int(val))
            case u16:   _append_int(&buf, int(val))
            case i16:   _append_int(&buf, int(val))
            case u32:   _append_int(&buf, int(val))
            case i32:   _append_int(&buf, int(val))
            case u64:   _append_int(&buf, int(val))
            case i64:   _append_int(&buf, int(val))
            case uint:  _append_int(&buf, int(val))
            case int:   _append_int(&buf, int(val))
            case: return "<NOT INT>"
            }

        case 'x':
            switch val in arg {
            case u8:    _append_hex(&buf,      cast(u64)val, size_of(val))
            case i8:    _append_hex(&buf,      cast(u64)val, size_of(val))
            case u16:   _append_hex(&buf,      cast(u64)val, size_of(val))
            case i16:   _append_hex(&buf,      cast(u64)val, size_of(val))
            case u32:   _append_hex(&buf,      cast(u64)val, size_of(val))
            case i32:   _append_hex(&buf,      cast(u64)val, size_of(val))
            case u64:   _append_hex(&buf,               val, size_of(val))
            case i64:   _append_hex(&buf,      cast(u64)val, size_of(val))
            case uint:  _append_hex(&buf,      cast(u64)val, size_of(val))
            case int:   _append_hex(&buf,      cast(u64)val, size_of(val))
            case f16:   _append_hex(&buf, u64(transmute(u16)val), size_of(val))
            case f32:   _append_hex(&buf, u64(transmute(u32)val), size_of(val))
            case f64:   _append_hex(&buf, transmute(u64)val, size_of(val))
            case rawptr: _append_hex(&buf, cast(u64)uintptr(val), size_of(val))
            case uintptr: _append_hex(&buf, cast(u64)val, size_of(val))
            case: return "<NOT INT>"
            }

        case 'f':
            switch val in arg {
            case f16: _append_float(&buf, f64(val))
            case f32: _append_float(&buf, f64(val))
            case f64: _append_float(&buf, f64(val))
            case: return "<NOT FLOAT>"
            }

        case 'r':
            switch val in arg {
            case rune: _append_rune(&buf, val)
            case byte: _append_rune(&buf, rune(val))
            case: return "<NOT RUNE>"
            }


        case 'v':
            _append_any(&buf, arg, pretty = false, depth = 0)

        case '#':
            _append_any(&buf, arg, pretty = true, depth = 0)


        case '%', ' ':
            append_elem(&buf, '%')
            consume_arg = false

        case:
            return "<UNKNOWN SPECIFIER>"
        }

        if consume_arg {
            if curr_arg >= len(args) {
                return "<NOT ENOUGH ARGS>"
            }
            curr_arg += 1
        }
    }
    
    append_elem(&buf, 0)

    return string(buf[:len(buf) - 1])
}

_append_string :: proc(buf: ^[dynamic]byte, str: string, quoted := false) {
    if quoted {
        append_elem(buf, '"')
    }
    append_elem_string(buf, str)
    if quoted {
        append_elem(buf, '"')
    }
}

_append_rune :: proc(buf: ^[dynamic]byte, val: rune) {
    bytes, size := runtime.encode_rune(val)
    append_elem(buf, '\'')
    append_elems(buf, ..bytes[:size])
    append_elem(buf, '\'')
}

_append_int :: proc(buf: ^[dynamic]byte, value: int) {
    val := value
    if val < 0 {
        append_elem(buf, '-')
        val = -val
    }

    if val == 0 {
        append_elem(buf, '0')
    }

    temp: [32]u8
    temp_index := len(temp) - 1
    for val != 0 {
        rem := val % 10
        val /= 10
        temp[temp_index] = u8('0' + rem)
        temp_index -= 1
    }

    append_elems(buf, ..temp[temp_index + 1:])
}

_append_hex :: proc(buf: ^[dynamic]byte, value: u64, size: int) {
    append_elem_string(buf, "0x")

    shift := (size * 8) - 4

    for shift >= 0 {
        d := (value >> uint(shift)) & 0xf
        if d < 10 {
            append_elem(buf, u8('0' + d))
        } else {
            append_elem(buf, u8('a' + (d - 10)))
        }
        shift -= 4
    }
}

_append_float :: proc(buf: ^[dynamic]byte, value: f64) {
    val := value
    if val < 0 {
        append_elem(buf, '-')
        val = -val
    }

    if value != value {
        append_elem_string(buf, "NaN")
        return
    }

    if value > max(f64) || value < -max(f64) {
        append_elem_string(buf, "Inf")
        return
    }


    scaled := i64(val * 1000.0 + 0.5)
    ip := scaled / 1000
    fp := scaled % 1000

    _append_int(buf, int(ip))

    // Always 3 decimal places
    append_elem(buf, '.')
    append_elem(buf, byte('0' + int(fp / 100) % 10))
    append_elem(buf, byte('0' + int(fp / 10 ) % 10))
    append_elem(buf, byte('0' + int(fp / 1  ) % 10))
}

_is_type_simple :: proc(ti: ^runtime.Type_Info) -> bool {
    base := runtime.type_info_base(ti)
    #partial switch v in base.variant {
    case runtime.Type_Info_Integer,
        runtime.Type_Info_Float,
        runtime.Type_Info_Rune,
        runtime.Type_Info_Quaternion,
        runtime.Type_Info_Boolean:
        return true
    }

    return false
}

_extract_int :: proc(ptr: rawptr, size: int) -> u64 {
    switch size {
    case 1: return u64((cast(^u8)ptr)^)
    case 2: return u64((cast(^u16)ptr)^)
    case 4: return u64((cast(^u32)ptr)^)
    case 8: return (cast(^u64)ptr)^
    case 16: return u64((cast(^u128)ptr)^)
    }
    panic("Integer size not supported")
}

_append_indent :: proc(buf: ^[dynamic]byte, num: int) {
    for _ in 0..<num {
        // append_elem(buf, ' ')
        append_elem_string(buf, INDENT)
    }
}

_append_slice :: proc(buf: ^[dynamic]byte, data: rawptr, len: int, stride: int, elem_id: typeid, pretty: bool, depth: int) {
    multiline := pretty
    if len <= 4 && _is_type_simple(type_info_of(elem_id)) {
        multiline = false
    }

    if len == 0 {
        multiline = false
    }

    append_elem(buf, '{')
    if multiline {
        append_elem(buf, '\n')
    }

    for i in 0..<len {
        if multiline {
            _append_indent(buf, depth + 1)
        }

        _append_any(buf, any{rawptr(uintptr(data) + uintptr(stride * i)), elem_id}, pretty = multiline, depth = depth + 1)

        if i + 1 < len || multiline {
            append_elem_string(buf, ", ")
        }

        if multiline {
            append_elem(buf, '\n')
        }
    }

    if multiline {
        _append_indent(buf, depth)
    }
    append_elem(buf, '}')
}

_append_any :: proc(buf: ^[dynamic]byte, value: any, pretty := false, depth := 0) {
    assert(depth < 64)

    switch val in value {
    case rune:      _append_rune(buf, val); return
    case string:    _append_string(buf, val, quoted = depth > 0); return
    case cstring:   _append_string(buf, string(val), quoted = depth > 0); return
    case u8:        _append_int(buf, int(val)); return
    case i8:        _append_int(buf, int(val)); return
    case u16:       _append_int(buf, int(val)); return
    case i16:       _append_int(buf, int(val)); return
    case u32:       _append_int(buf, int(val)); return
    case i32:       _append_int(buf, int(val)); return
    case u64:       _append_int(buf, int(val)); return
    case i64:       _append_int(buf, int(val)); return
    case uint:      _append_int(buf, int(val)); return
    case int:       _append_int(buf, int(val)); return
    case f16:       _append_float(buf, f64(val)); return
    case f32:       _append_float(buf, f64(val)); return
    case f64:       _append_float(buf, f64(val)); return
    case rawptr:    _append_hex(buf, u64(uintptr(val)), size_of(rawptr)); return
    case uintptr:   _append_hex(buf, u64(val), size_of(uintptr)); return
    }


    ti := type_info_of(value.id)

    switch v in ti.variant {
    case runtime.Type_Info_Named:
        _append_any(buf, any({data = value.data, id = v.base.id}), pretty, depth)

    case runtime.Type_Info_Integer, runtime.Type_Info_Rune, runtime.Type_Info_Float, runtime.Type_Info_String:
        unreachable()

    case runtime.Type_Info_Pointer,
         runtime.Type_Info_Multi_Pointer,
         runtime.Type_Info_Procedure:
        _append_hex(buf, u64((cast(^uintptr)value.data)^), size_of(uintptr))

    case runtime.Type_Info_Boolean:
        val := _extract_int(value.data, ti.size)
        _append_string(buf, val == 0 ? "false" : "true")

    case runtime.Type_Info_Complex:
        val: [2]f64
        switch ti.size {
        case 4:
            raw := (transmute(^runtime.Raw_Complex32)value.data)^
            val = {f64(raw.real), f64(raw.imag)}
        case 8:
            raw := (transmute(^runtime.Raw_Complex64)value.data)^
            val = {f64(raw.real), f64(raw.imag)}
        case 16:
            val = (transmute(^[2]f64)value.data)^
        case:
            _append_string(buf, "<INVALID COMPLEX>")
        }
        _append_float(buf, val[0])
        _append_string(buf, " + ")
        _append_float(buf, val[1])
        _append_string(buf, "i")

    case runtime.Type_Info_Quaternion:
        val: [4]f64
        switch ti.size {
        case 8:
            raw := (transmute(^[4]f16)value.data)^
            val = {f64(raw.x), f64(raw.y), f64(raw.z), f64(raw.w)}
        case 16:
            raw := (transmute(^[4]f32)value.data)^
            val = {f64(raw.x), f64(raw.y), f64(raw.z), f64(raw.w)}
        case 32:
            val = (transmute(^[4]f64)value.data)^
        case:
            _append_string(buf, "<INVALID COMPLEX>")
        }
        _append_string(buf, "{")
        _append_float(buf, val[0])
        _append_string(buf, ", ")
        _append_float(buf, val[1])
        _append_string(buf, ", ")
        _append_float(buf, val[2])
        _append_string(buf, ", ")
        _append_float(buf, val[3])
        _append_string(buf, "}")


    case runtime.Type_Info_Struct:
        multiline := pretty

        // Short structs
        if multiline && v.field_count <= 4 {
            all_simple := true
            for type in v.types[:v.field_count] {
                if !_is_type_simple(type) {
                    all_simple = false
                    break
                }
            }
            if all_simple {
                multiline = false
            }
        }

        append_elem(buf, '{')
        if multiline {
            append_elem(buf, '\n')
        }
        for i in 0..<v.field_count {
            if multiline do _append_indent(buf, depth + 1)
            append_elem_string(buf, v.names[i])
            append_elem_string(buf, " = ")

            val := any{
                data = rawptr(uintptr(value.data) + v.offsets[i]),
                id = v.types[i].id,
            }

            _append_any(buf, val, multiline, depth + 1)

            if i + 1 < v.field_count || multiline {
                append_elem_string(buf, ", ")
            }

            if multiline {
                append_elem(buf, '\n')
            }
        }
        if multiline {
            _append_indent(buf, depth)
        }
        append_elem(buf, '}')

    case runtime.Type_Info_Bit_Field:
        append_elem_string(buf, "bit_field")

    case runtime.Type_Info_Enum:
        _ = v.base.variant.(runtime.Type_Info_Integer)
        val := _extract_int(value.data, v.base.size)
        for enum_val, i in v.values {
            if val == u64(enum_val) {
                if depth > 0 {
                    append_elem(buf, '.')
                }
                append_elem_string(buf, v.names[i])
                break
            }
        }

    case runtime.Type_Info_Bit_Set:
        val := _extract_int(value.data, v.elem.size)

        append_elem(buf, '{')

        for bit_index, i in v.lower..=v.upper {
            if ((1 << uint(bit_index)) & val) == 0 {
                continue
            }

            elem := runtime.type_info_base(v.elem)

            #partial switch ve in elem.variant {
            case runtime.Type_Info_Enum:
                append_elem(buf, '.')
                append_elem_string(buf, ve.names[i - int(v.lower)])

            case runtime.Type_Info_Integer:
                _append_int(buf, int(v.lower) + i)

            case: panic("Invalid bit set backing type")
            }

            if (val >> uint(bit_index + 1)) != 0 {
                append_elem_string(buf, ", ")
            }
        }

        append_elem(buf, '}')


    case runtime.Type_Info_Enumerated_Array:
        index_enum := runtime.type_info_base(v.index).variant.(runtime.Type_Info_Enum)

        multiline := pretty
        if v.count <= 4 && _is_type_simple(v.elem) {
            multiline = false
        }

        append_elem(buf, '{')
        if multiline {
            append_elem(buf, '\n')
        }

        for i in 0..<v.count {
            if multiline {
                _append_indent(buf, depth + 1)
            }

            append_elem(buf, '.')
            append_elem_string(buf, index_enum.names[i])
            append_elem_string(buf, " = ")

            _append_any(buf, any{rawptr(uintptr(value.data) + uintptr(v.elem_size * i)), v.elem.id}, pretty = multiline, depth = depth + 1)

            if i + 1 < v.count || multiline {
                append_elem_string(buf, ", ")
            }

            if multiline {
                append_elem(buf, '\n')
            }
        }

        if multiline {
            _append_indent(buf, depth)
        }
        append_elem(buf, '}')

    case runtime.Type_Info_Array:
        _append_slice(buf, value.data, v.count, v.elem_size, v.elem.id, pretty = pretty, depth = depth)

    case runtime.Type_Info_Simd_Vector:
        _append_slice(buf, value.data, v.count, v.elem_size, v.elem.id, pretty = pretty, depth = depth)

    case runtime.Type_Info_Slice:
        raw := (transmute(^runtime.Raw_Slice)value.data)^
        _append_slice(buf, raw.data, raw.len, v.elem_size, v.elem.id, pretty = pretty, depth = depth)

    case runtime.Type_Info_Dynamic_Array:
        raw := (transmute(^runtime.Raw_Dynamic_Array)value.data)^
        _append_slice(buf, raw.data, raw.len, v.elem_size, v.elem.id, pretty = pretty, depth = depth)

    case runtime.Type_Info_Fixed_Capacity_Dynamic_Array:
        length := (cast(^int)(uintptr(value.data) + v.len_offset))^
        _append_slice(buf, value.data, length, v.elem_size, v.elem.id, pretty = pretty, depth = depth)

    case runtime.Type_Info_Any:
        _append_any(buf, (cast(^any)value.data)^, pretty = pretty, depth = depth)

    case runtime.Type_Info_Type_Id:
        ti := type_info_of((cast(^typeid)value.data)^)
        #partial switch vt in ti.variant {
        case runtime.Type_Info_Named:
            append_elem_string(buf, vt.name)
        case:
            // TODO
            append_elem_string(buf, "typeid")
        }

    case runtime.Type_Info_Union: unimplemented()
    case runtime.Type_Info_Map: unimplemented()
    case runtime.Type_Info_Matrix:
        append_elem(buf, '{')
        if pretty {
            append_elem(buf, '\n')
        }

        // Printed in Row-Major layout to match text layout
        for row in 0..<v.row_count {
            if pretty {
                _append_indent(buf, depth + 1)
            }

            for col in 0..<v.column_count {
                if col > 0 {
                    append_elem_string(buf, ", ")
                }

                offset: int
                switch v.layout {
                case .Column_Major: offset = (row + col*v.elem_stride)*v.elem_size
                case .Row_Major:    offset = (col + row*v.elem_stride)*v.elem_size
                }

                data := uintptr(value.data) + uintptr(offset)
                _append_any(buf, any{rawptr(data), v.elem.id}, pretty = pretty, depth = depth + 1)
            }

            if pretty {
                append_elem_string(buf, ";\n")
            } else if row + 1 < v.row_count {
                append_elem_string(buf, "; ")
            }
        }

        if pretty {
            _append_indent(buf, depth)
        }
        append_elem(buf, '}')

    case runtime.Type_Info_Soa_Pointer:
        unimplemented()

    case runtime.Type_Info_Parameters:
        unreachable()
    }
}
