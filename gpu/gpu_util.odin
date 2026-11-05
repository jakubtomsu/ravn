#+vet explicit-allocators shadowing style unused
package ravn_gpu

import "core:log"
import "base:runtime"



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Arena
//
// Not a traditional resource behind an opaque handle, it's a lightweight "userspace" wrapper
// over buffer resources for easy bump allocation.
//

// GPU memory arena
Arena :: struct #all_or_none {
    usage:              Usage,
    kind:               Buffer_Kind,
    size:               i32,
    stride:             i32,

    buf:                Resource_Handle,
    submitted_offset:   u64,
    upload_buf:         []byte,
    upload_offset:      u64,
    upload_allocator:   runtime.Allocator,
}

@(require_results)
arena_create :: proc(
    $T:                 typeid,
    kind:               Buffer_Kind,
    #any_int size:      i32,
    usage:              Usage = .Default,
    loc                 := #caller_location,
    allocator           := context.allocator, // for upload buf
) -> (result: Arena, ok: bool) {
    return arena_create_raw(
        kind = kind,
        stride = i32(size_of(T)),
        size = i32(size_of(T)) * size,
        usage = usage,
        loc = loc,
        allocator = allocator,
    )
}

@(require_results)
arena_create_raw :: proc(
    kind:               Buffer_Kind,
    #any_int stride:    i32,
    #any_int size:      i32,
    usage:              Usage = .Default,
    loc                 := #caller_location,
    allocator           := context.allocator, // for upload buf
) -> (result: Arena, ok: bool) {
    assert(kind != .Invalid, loc = loc)
    assert(size > 0, loc = loc)
    assert(size % stride == 0, loc = loc)
    assert(stride >= 4, loc = loc)
    assert(stride % 4 == 0, loc = loc)
    assert(usage != .Staging, loc = loc)

    result = {
        usage = usage,
        kind = kind,
        size = size,
        stride = stride,

        buf = {},
        submitted_offset = 0,
        upload_buf = runtime.make_aligned([]byte, size, alignment = 4096, allocator = allocator),
        upload_offset = 0,
        upload_allocator = allocator,
    }

    switch usage {
    case .Default, .Dynamic:
        if !_arena_create_buffer(&result, data = nil, loc = loc) {
            return {}, false
        }

    case .Immutable:
        // Resource will be created on submit
    case .Staging:
        assert(false)
    }

    return result, true
}

arena_destroy :: proc(arena: ^Arena) {
    destroy_resource(arena.buf)
    delete(arena.upload_buf, allocator = arena.upload_allocator)
    arena^ = {}
}

arena_reset :: proc(arena: ^Arena) {
    arena.upload_offset = 0
    arena.submitted_offset = 0
}

@(require_results)
_arena_create_buffer :: proc(arena: ^Arena, data: []byte, loc := #caller_location) -> bool {
    if !create_buffer(
        handle = &arena.buf,
        kind = arena.kind,
        stride = arena.stride,
        size = arena.size,
        usage = arena.usage,
        data = data,
        name = "Arena",
        loc = loc,
    ) {
        log.error("Failed to create arena buffer", location = loc)
        return false
    }
    return true
}

// NOTE: no alignment for now
@(require_results)
arena_alloc_bytes :: proc(arena: ^Arena, num_bytes: int) -> ([]byte, bool) #optional_ok {
    assert(num_bytes > 0)
    assert(num_bytes % int(arena.stride) == 0)
    space := len(arena.upload_buf) - int(arena.upload_offset)
    if num_bytes > space {
        return nil, false
    }
    result := arena.upload_buf[arena.upload_offset:][:num_bytes]
    arena.upload_offset += u64(num_bytes)
    return result, true
}

arena_push_val :: proc(arena: ^Arena, val: ^$T) -> bool {
    assert(size_of(T) % arena.stride == 0)
    return arena_push_data(arena, base.ptr_bytes(val))
}

// Write the data to the CPU-side staging buffer
arena_push_data :: proc(arena: ^Arena, data: []byte) -> bool {
    buf := arena_alloc_bytes(arena, len(data)) or_return
    assert(len(buf) >= len(data))
    runtime.mem_copy_non_overlapping(
        raw_data(buf),
        raw_data(data),
        len(data),
    )
    return true
}

// Flush the CPU-side staging buffer to the GPU
arena_submit :: proc(arena: ^Arena, loc := #caller_location) -> bool {
    if arena.upload_offset == 0 {
        return true
    }
    switch arena.usage {
    case .Immutable:
        if arena.submitted_offset != 0 {
            log.error("Immutable arena cannot be submitted-to multiple times. Always clear in between.", location = loc)
            return false
        }

        if !_arena_create_buffer(arena, arena.upload_buf[:arena.upload_offset], loc = loc) {
            return false
        }

    case .Default, .Dynamic:
        assert(arena.buf != {})
        assert(arena.submitted_offset + arena.upload_offset <= u64(arena.size), "GPU Buffer full", loc = loc)
        update_buffer(
            arena.buf,
            offset = int(arena.submitted_offset),
            buffers = {
                arena.upload_buf[:arena.upload_offset],
            },
            loc = loc,
        )

    case .Staging:
        assert(false)
    }

    arena.submitted_offset += arena.upload_offset
    arena.upload_offset = 0

    return true
}

arena_allocator :: proc(arena: ^Arena) -> runtime.Allocator {
    return {
        procedure = _arena_allocator_proc,
        data = arena,
    }
}

_arena_allocator_proc :: proc(
    allocator_data: rawptr,
    mode:           runtime.Allocator_Mode,
    size:           int,
    alignment:      int,
    old_memory:     rawptr,
    old_size:       int,
    loc             := #caller_location,
) -> (result: []byte, err: runtime.Allocator_Error) {
    arena := cast(^Arena)allocator_data

    switch mode {
    case .Alloc_Non_Zeroed, .Alloc:
        ok: bool
        result, ok = arena_alloc_bytes(arena, num_bytes = size)
        if !ok {
            return nil, .Out_Of_Memory
        }
        if mode != .Alloc_Non_Zeroed {
            runtime.mem_zero(raw_data(result), len(result))
        }
        return result, nil

    case .Free_All:
        arena_reset(arena)

    case .Query_Features:
        set := (^runtime.Allocator_Mode_Set)(old_memory)
        if set != nil {
            set^ = {.Alloc, .Alloc_Non_Zeroed, .Free_All, .Query_Features}
        }
        return nil, nil

    case .Free, .Resize, .Resize_Non_Zeroed, .Query_Info:
        return nil, .Mode_Not_Implemented
    }

    return nil, .Invalid_Argument
}



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
    case runtime.Type_Info_Float,
         runtime.Type_Info_Integer,
         runtime.Type_Info_Array:
        format, ok := _vertex_format_from_type(ti_base, loc = loc)
        if !ok {
            return {}
        }
        result.slots[0] = format
        return result
    }

    st, is_struct := ti_base.variant.(runtime.Type_Info_Struct)
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
    if arr, is_arr := ti.variant.(runtime.Type_Info_Array); is_arr {
        num_components = arr.count
        elem_ti = runtime.type_info_core(arr.elem)
    }

    prefix: string
    #partial switch v in elem_ti.variant {
    case runtime.Type_Info_Float:   prefix = "F"
    case runtime.Type_Info_Integer: prefix = v.signed ? "I" : "U"
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
    enum_ti := runtime.type_info_base(type_info_of(Vertex_Format)).variant.(runtime.Type_Info_Enum)
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
