/* Lightweight entity container package

Entity is a union of structs (entity variants). The System
manages a separate free-list-based pool for each entity variant.

Entities can be iterated by types or by subtypes ("components").
*/
#+vet shadowing explicit-allocators unused style semicolon cast
package ravn_entities

import "base:intrinsics"
import "base:runtime"

UNION_LEN :: intrinsics.type_union_variant_count
UNION_HAS :: intrinsics.type_is_variant_of
UNION_INDEX :: intrinsics.type_variant_index_of

Handle_Index :: u16
Handle_Gen :: u8
Handle_Variant :: u8

// A handle uniquely identifies an entity.
Handle :: struct {
    index:      Handle_Index,
    gen:        Handle_Gen,
    variant:    Handle_Variant,
}

/* Base type of each entity, must be at offset 0.
Recommended usage is:

My_Entity :: struct {
    using base: entity_system.Base,
    // Other fields AFTER this
}
*/
Base :: struct {
    handle:     Handle, // Self
    _next_free: Handle_Index,
}

/*
Val_Union:
    - union of all possible item values
    - all fields must be a struct with 'Base' at offset 0

Sub_Union:
    - union of subtypes present in values
    - doesn't have to contain all subtypes, but only these will be query-able
*/
System :: struct($Val_Union: typeid, $Sub_Union: typeid)
    where
        intrinsics.type_is_union(Val_Union),
        intrinsics.type_is_union(Sub_Union),
        UNION_LEN(Val_Union) < 256
{
    buffers:    [UNION_LEN(Val_Union)]Buffer,
    sizes:      [UNION_LEN(Val_Union)]i64,
    offsets:    [UNION_LEN(Sub_Union)][UNION_LEN(Val_Union)]i64,
    allocator:  runtime.Allocator,
}

Buffer :: struct {
    data:       [^]byte,
    cap:        i32, // In number of values, not bytes!
    top:        i32,
    free:       i32,
}

init :: proc(
    sys:            ^$S/System($Val_Union, $Sub_Union),
    specific_cap:   []int = nil,
    default_cap     := 4096,
    allocator       := context.allocator,
) {
    sys.allocator = allocator

    val_ti := runtime.type_info_core(type_info_of(Val_Union))
    val_ti_union := val_ti.variant.(runtime.Type_Info_Union)

    sub_ti := runtime.type_info_core(type_info_of(Sub_Union))
    sub_ti_union := sub_ti.variant.(runtime.Type_Info_Union)

    for val_var_ti, val_var_index in val_ti_union.variants {
        sys.sizes[val_var_index] = i64(val_var_ti.size)
    }

    for i in 0..<UNION_LEN(Val_Union) {
        cap := i < len(specific_cap) ? specific_cap[i] : 0
        if cap == 0 {
            cap = default_cap
        }
        assert(cap >= 2)
        data := runtime.make_aligned([]byte, cap * int(sys.sizes[i]), alignment = 4096, allocator = allocator)
        sys.buffers[i] = {
            data = raw_data(data),
            cap = i32(cap),
            top = 0,
            free = 0,
        }
    }

    // TODO: search recursively
    for val_var_ti in val_ti_union.variants {
        sti := runtime.type_info_core(val_var_ti).variant.(runtime.Type_Info_Struct) or_continue

        has_base := false
        for fi in 0..<sti.field_count {
            if sti.offsets[fi] == 0 {
                if sti.types[fi].id == typeid_of(Base) {
                    has_base = true
                }
            }
        }

        if !has_base {
            // panic("All variants must have a Base member at offset 0")
        }
    }

    sys.offsets = -1
    for sub_var_ti, sub_var_index in sub_ti_union.variants {
        for val_var_ti, val_var_index in val_ti_union.variants {
            sti := runtime.type_info_core(val_var_ti).variant.(runtime.Type_Info_Struct) or_continue

            offs: i64 = -1
            for fi in 0..<sti.field_count {
                if sti.types[fi].id == sub_var_ti.id {
                    offs = i64(sti.offsets[fi])
                    break
                }
            }

            sys.offsets[sub_var_index][val_var_index] = offs
        }
    }
}

// Frees buffers and clears the entire system
shutdown :: proc(sys: ^$S/System($Val_Union, $Sub_Union)) {
    for buf in sys.buffers {
        free(buf.data, sys.allocator)
    }
    sys^ = {}
}

create :: proc {
    create_val,
    create_sub,
}

create_val :: proc(sys: ^$S/System($Val_Union, $Sub_Union), val: Val_Union) -> (result: Handle, ok: bool) #optional_ok {
    val := val
    variant_index := _extract_variant_index(&val)
    base, index := _create_empty(sys, variant_index) or_return

    result = {
        index = Handle_Index(index),
        gen = base.handle.gen,
        variant = Handle_Variant(variant_index),
    }

    intrinsics.mem_copy_non_overlapping(base, &val, sys.sizes[variant_index])
    base.handle = result
    base._next_free = 0

    return result, true
}

create_sub :: proc(sys: ^$S/System($Val_Union, $Sub_Union), val: $Val) -> (result: Handle, ok: bool) where UNION_HAS(Val_Union, Val) #optional_ok {
    VARIANT_INDEX :: UNION_INDEX(Val_Union, Val)
    base, index := _create_empty(sys, VARIANT_INDEX) or_return

    result = {
        index = Handle_Index(index),
        gen = base.handle.gen,
        variant = Handle_Variant(VARIANT_INDEX),
    }

    (cast(^Val)base)^ = val
    base.handle = result
    base._next_free = 0

    return result, true
}

_create_empty :: proc(sys: ^$S/System($Val_Union, $Sub_Union), variant_index: int) -> (result: ^Base, index: i32, ok: bool) {
    buf := &sys.buffers[variant_index]

    index = buf.free
    result = cast(^Base)(uintptr(buf.data) + uintptr(index) * uintptr(sys.sizes[variant_index]))

    if index > 0 && index < buf.cap {
        buf.free = i32(result._next_free)
    } else if buf.top >= (buf.cap - 1) {
        return nil, -1, false
    } else {
        buf.top += 1
        index = buf.top
        result = cast(^Base)(uintptr(buf.data) + uintptr(index) * uintptr(sys.sizes[variant_index]))
    }

    return result, index, true
}

destroy :: proc(sys: ^$S/System($Val_Union, $Sub_Union), handle: Handle) -> bool  {
    if handle.variant >= UNION_LEN(Val_Union) {
        return false
    }

    buf := &sys.buffers[handle.variant]

    if  handle.index <= 0 ||
        i32(handle.index) > buf.top
    {
        return false
    }

    base := cast(^Base)(uintptr(buf.data) + uintptr(handle.index) * uintptr(sys.sizes[handle.variant]))

    if handle != base.handle {
        return false
    }

    base.handle = {
        index = 0,
        gen = handle.gen + 1,
        variant = max(Handle_Variant),
    }
    base._next_free = Handle_Index(buf.free)
    buf.free = i32(handle.index)

    return true
}

@(require_results)
get :: proc(
    sys: ^$S/System($Val_Union, $Sub_Union),
    handle: Handle,
) -> (result: intrinsics.type_convert_variants_to_pointers(Val_Union), ok: bool) #optional_ok {
    R :: intrinsics.type_convert_variants_to_pointers(Val_Union)
    Raw_Pointer_Union :: struct {
        value:  rawptr,
        tag:    uintptr,
    }

    #assert(size_of(R) == size_of(Raw_Pointer_Union))
    #assert(intrinsics.type_union_tag_offset(R) == offset_of(Raw_Pointer_Union, tag))

    if handle.variant >= UNION_LEN(Val_Union) {
        return nil, false
    }

    buf := sys.buffers[handle.variant]

    if  handle.index <= 0 ||
        i32(handle.index) > buf.top
    {
        return nil, false
    }

    base := cast(^Base)(uintptr(buf.data) + uintptr(handle.index) * uintptr(sys.sizes[handle.variant]))

    if handle != base.handle {
        return nil, false
    }

    raw_result := transmute(^Raw_Pointer_Union)&result
    raw_result.value = base
    raw_result.tag = intrinsics.type_union_base_tag_value(R) + uintptr(handle.variant)

    return result, true
}

@(require_results)
get_sub :: proc(sys: ^$S/System($Val_Union, $Sub_Union), handle: Handle, $Sub: typeid) -> (result: ^Sub, ok: bool) {
    offset := sys.offsets[UNION_INDEX(Sub_Union, Sub)][handle.variant]

    if offset == -1 {
        return nil, false
    }

    ptr :=
        uintptr(sys.buffers[handle.variant].data) +
        uintptr(handle.index) * uintptr(sys.sizes[handle.variant]) +
        uintptr(offset)

    return transmute(^Sub)ptr, true
}

@(require_results)
get_buffer :: proc(sys: ^$S/System($Val_Union, $Sub_Union), $Val: typeid) -> []Val where UNION_HAS(Val_Union, Val) {
    buf := sys.buffers[UNION_INDEX(Val_Union, Val)]
    return (cast([^]Val)buf.data)[1:buf.top+1]
}



//
// MARK: Iteration
//
// Usage:
// for it := begin(&s, Val_Or_Sub_Type); val := next(&it) { ... }
//

begin :: proc {
    begin_val,
    begin_sub,
}

next :: proc {
    next_val,
    next_sub,
}

Iter_Val :: struct($Val: typeid) {
    ptr:    uintptr,
    step:   uintptr,
    end:    uintptr,
}

@(require_results)
begin_val :: proc(sys: ^$S/System($Val_Union, $Sub_Union), $Val: typeid) -> (result: Iter_Val(Val)) where UNION_HAS(Val_Union, Val) {
    buf := sys.buffers[UNION_INDEX(Val_Union, Val)]
    result = {
        ptr = uintptr(buf.data),
        step = size_of(Val),
        end = uintptr(buf.data) + uintptr(buf.top) * size_of(Val),
    }
    return result
}

next_val :: proc(it: ^Iter_Val($Val)) -> (value: ^Val, ok: bool) {
    if it.ptr == it.end {
        return nil, false
    }
    it.ptr += it.step
    value = transmute(^Val)(it.ptr)
    return value, true
}


// The handle isn't exposed directly, but it's stored in the iterator through base pointer.
Iter_Sub :: struct($Val_Union: typeid, $Sub_Union: typeid, $Sub: typeid) {
    sys:        ^System(Val_Union, Sub_Union) `fmt:"-"`,
    using ptr:  ^Base,
    step:       uintptr,
    offset:     uintptr,
    end:        uintptr,
    variant:    int,
    sub_index:  int,
}

@(require_results)
begin_sub :: proc(sys: ^$S/System($Val_Union, $Sub_Union), $Sub: typeid) -> (result: Iter_Sub(Val_Union, Sub_Union, Sub)) where UNION_HAS(Sub_Union, Sub) {
    result.sys = sys
    result.variant = -1
    result.sub_index = UNION_INDEX(Sub_Union, Sub)
    _iter_sub_next_variant(&result)
    return result
}

next_sub :: proc(it: ^Iter_Sub($Val_Union, $Sub_Union, $Sub)) -> (value: ^Sub, ok: bool) {
    for uintptr(it.ptr) >= it.end {
        if !_iter_sub_next_variant(it) {
            return
        }
    }

    it.ptr = cast(^Base)(uintptr(it.ptr) + it.step)
    value = cast(^Sub)(uintptr(it.ptr) + it.offset)
    return value, true
}

_iter_sub_next_variant :: proc(it: ^Iter_Sub($Val_Union, $Sub_Union, $Sub)) -> (ok: bool) {
    offsets := &it.sys.offsets[it.sub_index]

    it.variant += 1
    for ; it.variant < UNION_LEN(Val_Union); it.variant += 1 {
        if offsets[it.variant] != -1 {
            ok = true
            break
        }
    }

    if !ok {
        return false
    }

    offset := offsets[it.variant]
    size := it.sys.sizes[it.variant]
    buf := it.sys.buffers[it.variant]

    it.ptr = cast(^Base)buf.data
    it.step = uintptr(size)
    it.offset = uintptr(offset)
    it.end = uintptr(buf.data) + uintptr(buf.top) * uintptr(size)

    return true
}


@(require_results)
_reinterpret_bytes :: proc "contextless" ($T: typeid, bytes: []byte, loc := #caller_location) -> []T {
    n := len(bytes) / size_of(T)
    assert_contextless(n * size_of(T) == len(bytes))
    return ([^]T)(raw_data(bytes))[:n]
}

@(require_results)
_extract_variant_index :: proc "contextless" (val: ^$T) -> int where intrinsics.type_is_union(T) {
    tag := (cast(^intrinsics.type_union_tag_type(T))(uintptr(val) + intrinsics.type_union_tag_offset(T)))^
    return int(tag) - intrinsics.type_union_base_tag_value(T)
}
