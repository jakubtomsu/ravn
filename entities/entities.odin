/* Lightweight entity container package

Entity is a union of structs - entity variants.
The container manages a separate free-list-based pool for each entity variant.

Entities can be iterated by types or by subtypes (components).
*/
#+vet shadowing explicit-allocators unused style semicolon cast
package ravn_entities

import "base:intrinsics"
import "base:runtime"

_ :: runtime

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

#assert(size_of(Handle) == 4)

/* Base type of each entity, must be at offset 0.
Example usage:

My_Entity :: struct {
    using base:     Base,
    // Other fields
}
*/
Base :: struct {
    handle:     Handle, // Self
    _next_free: Handle_Index,
}

// Raw pointer to an entity, exposing the shared base plus the variants.
// Never store this pointer beyond quick usage. Always use the handle.
Entity_Ptr :: struct($U: typeid) #raw_union where intrinsics.type_is_union(U) {
    using base: ^Base,
    variant:    intrinsics.type_convert_variants_to_pointers(U),
}

/*
Container for all the entities.

Variant_Union:
    - union of all possible entity types
    - all fields must be a struct with 'Base' at offset 0

Subtype_Union:
    - union of subtypes present in values
    - doesn't have to contain all subtypes, but only these will be query-able
*/
Entities :: struct($Variant_Union: typeid, $Subtype_Union: typeid)
    where
        intrinsics.type_is_union(Variant_Union),
        intrinsics.type_is_union(Subtype_Union),
        UNION_LEN(Variant_Union) > 1,
        UNION_LEN(Variant_Union) < 256,
        size_of(intrinsics.type_convert_variants_to_pointers(Variant_Union)) == 2*size_of(rawptr),
        intrinsics.type_union_tag_offset(intrinsics.type_convert_variants_to_pointers(Variant_Union)) == size_of(uintptr)
{
    buffers:    [UNION_LEN(Variant_Union)]Buffer,
    sizes:      [UNION_LEN(Variant_Union)]i64,
    offsets:    [UNION_LEN(Subtype_Union)][UNION_LEN(Variant_Union)]i64,
    allocator:  runtime.Allocator,
}

Buffer :: struct {
    data:       [^]byte,
    cap:        i32, // In number of values, not bytes!
    top:        i32, // Inclusive index watermark
    free:       i32,
}

// TODO: we cannot do caps: [UNION_LEN(Variant_Union)] due to a compiler bug.
init :: proc(
    ents:           ^$Ents/Entities($Variant_Union, $Subtype_Union),
    default_cap:    int = 4096,
    caps:           []int = nil, // Use UNION_INDEX to set specific fields
    allocator       := context.allocator,
) {
    assert(allocator != {})
    assert(ents.allocator == {}, "Already initialized")

    ents.allocator = allocator

    var_ti := runtime.type_info_core(type_info_of(Variant_Union))
    var_ti_union := var_ti.variant.(^runtime.Type_Info_Union)

    sub_ti := runtime.type_info_core(type_info_of(Subtype_Union))
    sub_ti_union := sub_ti.variant.(^runtime.Type_Info_Union)

    for var_var_ti, var_var_index in var_ti_union.variants {
        ents.sizes[var_var_index] = i64(var_var_ti.size)
    }

    for i in 0..<UNION_LEN(Variant_Union) {
        cap := i < len(caps) ? caps[i] : default_cap
        assert(cap >= 2)
        assert(cap < int(max(Handle_Index)))
        data := runtime.make_aligned([]byte, cap * int(ents.sizes[i]), alignment = 64, allocator = allocator)
        ents.buffers[i] = {
            data = raw_data(data),
            cap = i32(cap),
            top = 0,
            free = 0,
        }
    }

    ents.offsets = -1
    for sub_var_ti, sub_var_index in sub_ti_union.variants {
        for var_var_ti, var_var_index in var_ti_union.variants {
            sti := runtime.type_info_core(var_var_ti).variant.(^runtime.Type_Info_Struct) or_continue

            offs: i64 = -1
            for fi in 0..<sti.field_count {
                if sti.types[fi].id == sub_var_ti.id {
                    offs = i64(sti.offsets[fi])
                    break
                }
            }

            ents.offsets[sub_var_index][var_var_index] = offs
        }
    }
}

// Frees buffers and zeroes the entire container
shutdown :: proc(ents: ^$Ents/Entities($Variant_Union, $Subtype_Union)) {
    assert(ents.allocator != {}, "You must call init() first")
    for buf in ents.buffers {
        free(buf.data, ents.allocator)
    }
    ents^ = {}
}

clear :: proc(ents: ^$Ents/Entities($Variant_Union, $Subtype_Union)) {
    assert(ents.allocator != {}, "You must call init() first")
    for &buf, var_index in ents.buffers {
        for i in 1..=buf.top {
            base, base_ok := get_entity_base(ents^, buf, Handle{
                index = Handle_Index(i),
                gen = 0,
                variant = Handle_Variant(var_index),
            })
            assert(base_ok)
            base.handle.gen += 1
        }
        buf.top = 0
        buf.free = 0
    }
}

@(require_results)
clone :: proc(src: ^$Ents/Entities($Variant_Union, $Subtype_Union), allocator := context.allocator) -> (result: Ents) {
    assert(ents.allocator != {}, "You must call init() first")
    // Extract exact capacities from the source
    caps: [UNION_LEN(Variant_Union)]int
    for buf, i in src.buffers {
        caps[i] = int(buf.cap)
    }

    init(&result, caps = caps[:], allocator = allocator)

    for src_buf, i in src.buffers {
        dst_buf := &result.buffers[i]

        dst_buf.top = src_buf.top
        dst_buf.free = src_buf.free

        elements_to_copy := int(src_buf.top) + 1
        if elements_to_copy > 0 && result.sizes[i] > 0 {
            intrinsics.mem_copy_non_overlapping(
                dst_buf.data,
                src_buf.data,
                elements_to_copy * int(result.sizes[i]),
            )
        }
    }

    return result
}

// Creates an entity. Returns null handle and false if an empty slot couldn't be found.
create :: proc {
    create_union,
    create_variant,
}

// Creates entity from a dynamic union.
create_union :: proc(ents: ^$Ents/Entities($Variant_Union, $Subtype_Union), var: Variant_Union) -> (result: Handle, ok: bool) #optional_ok {
    assert(ents.allocator != {}, "You must call init() first")
    var := var
    variant_index := _extract_variant_index(&var)
    base, index := _create_empty(ents, variant_index) or_return

    result = {
        index = Handle_Index(index),
        gen = base.handle.gen,
        variant = Handle_Variant(variant_index),
    }

    intrinsics.mem_copy_non_overlapping(base, &var, ents.sizes[variant_index])
    base.handle = result
    base._next_free = 0

    return result, true
}

// Creates an entity from a statically typed entity value.
create_variant :: proc(ents: ^$Ents/Entities($Variant_Union, $Subtype_Union), var: $Var) -> (result: Handle, ok: bool) where UNION_HAS(Variant_Union, Var) #optional_ok {
    assert(ents.allocator != {}, "You must call init() first")
    VARIANT_INDEX :: UNION_INDEX(Variant_Union, Var)
    base, index := _create_empty(ents, VARIANT_INDEX) or_return

    result = {
        index = Handle_Index(index),
        gen = base.handle.gen,
        variant = Handle_Variant(VARIANT_INDEX),
    }

    (cast(^Var)base)^ = var
    base.handle = result
    base._next_free = 0

    return result, true
}

// Internal use, allocates slot in one of the variant buffers.
_create_empty :: proc(ents: ^$Ents/Entities($Variant_Union, $Subtype_Union), variant_index: int) -> (result: ^Base, index: i32, ok: bool) {
    assert(ents.allocator != {}, "You must call init() first")
    buf := &ents.buffers[variant_index]

    index = buf.free
    result = cast(^Base)(uintptr(buf.data) + uintptr(index) * uintptr(ents.sizes[variant_index]))

    if index > 0 && index < buf.cap {
        buf.free = i32(result._next_free)
    } else if buf.top >= (buf.cap - 1) {
        return nil, -1, false
    } else {
        buf.top += 1
        index = buf.top
        result = cast(^Base)(uintptr(buf.data) + uintptr(index) * uintptr(ents.sizes[variant_index]))
    }

    return result, index, true
}

// Immediately destroys an entity. Returns false if doesn't exist.
destroy :: proc(ents: ^$Ents/Entities($Variant_Union, $Subtype_Union), handle: Handle) -> bool  {
    assert(ents.allocator != {}, "You must call init() first")
    buf := get_buffer(ents, handle.variant) or_return
    base := get_entity_base(ents^, buf^, handle) or_return
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

// Looks up a generic entity using a handle handle. Returns nil if the entity doesn't exist.
@(require_results)
get :: proc(ents: ^$Ents/Entities($Variant_Union, $Subtype_Union), handle: Handle) -> (result: Entity_Ptr(Variant_Union), ok: bool) #optional_ok {
    assert(ents.allocator != {}, "You must call init() first")
    Raw_Pointer_Union :: struct {
        value:  rawptr,
        tag:    uintptr,
    }

    #assert(size_of(intrinsics.type_convert_variants_to_pointers(Variant_Union)) == size_of(Raw_Pointer_Union))
    #assert(intrinsics.type_union_tag_offset(intrinsics.type_convert_variants_to_pointers(Variant_Union)) == offset_of(Raw_Pointer_Union, tag))

    buf := get_buffer(ents, handle.variant) or_return
    base := get_entity_base(ents^, buf^, handle) or_return
    if handle != base.handle {
        return {}, false
    }

    raw_result := transmute(^Raw_Pointer_Union)&result
    raw_result.value = base
    raw_result.tag = intrinsics.type_union_base_tag_value(intrinsics.type_convert_variants_to_pointers(Variant_Union)) + uintptr(handle.variant)
    return result, true
}

// Utility for looking up an entity of a specific variant using a handle. Returns nil if the entity is a different variant or doesn't exist.
@(require_results)
get_var :: proc(ents: ^$Ents/Entities($Variant_Union, $Subtype_Union), handle: Handle, $Var: typeid) -> (result: ^Var, ok: bool)
    where UNION_HAS(Variant_Union, Var) #optional_ok
{
    assert(ents.allocator != {}, "You must call init() first")
    ent := get(ents, handle) or_return
    var := ent.variant.(^Var) or_return
    return var, true
}

// Looks up an entity sub-component using a handle. Returns nil if the entity doesn't have the component or doesn't exist.
@(require_results)
get_sub :: proc(ents: ^$Ents/Entities($Variant_Union, $Subtype_Union), handle: Handle, $Sub: typeid) -> (result: ^Sub, ok: bool)
    where UNION_HAS(Subtype_Union, Sub) #optional_ok
{
    assert(ents.allocator != {}, "You must call init() first")
    buf := get_buffer(ents, handle.variant) or_return
    offset := ents.offsets[UNION_INDEX(Subtype_Union, Sub)][handle.variant]
    if offset == -1 {
        return nil, false
    }

    base := get_entity_base(ents^, buf^, handle) or_return
    if handle != base.handle {
        return nil, false
    }

    return transmute(^Sub)(uintptr(base) + uintptr(offset)), true
}

@(require_results)
get_values :: proc(ents: $Ents/Entities($Variant_Union, $Subtype_Union), $Var: typeid) -> []Var where UNION_HAS(Variant_Union, Var) {
    assert(ents.allocator != {}, "You must call init() first")
    buf := ents.buffers[UNION_INDEX(Variant_Union, Var)]
    return (cast([^]Var)buf.data)[1:buf.top+1]
}

@(require_results)
get_buffer :: proc(ents: ^$Ents/Entities($Variant_Union, $Subtype_Union), variant: Handle_Variant) -> (^Buffer, bool) {
    assert(ents.allocator != {}, "You must call init() first")
    if variant >= UNION_LEN(Variant_Union) {
        return {}, false
    }
    return &ents.buffers[variant], true
}

@(require_results)
get_entity_base :: proc(ents: $Ents/Entities($Variant_Union, $Subtype_Union), buf: Buffer, handle: Handle) -> (^Base, bool) {
    assert(ents.allocator != {}, "You must call init() first")
    if  handle.index <= 0 || i32(handle.index) > buf.top {
        return {}, false
    }
    return cast(^Base)(uintptr(buf.data) + uintptr(handle.index) * uintptr(ents.sizes[handle.variant])), true
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Iterators
//
// Usage:
// for iter := begin(&s, Var_Or_Sub_Type); var := next(&iter) { ... }
//

begin :: proc {
    begin_var,
    begin_sub,
}

next :: proc {
    next_var,
    next_sub,
}

Iter_Variant :: struct($Var: typeid) {
    using var:  ^Var, // Current value
    _end:        uintptr,
}

@(require_results)
begin_var :: proc(ents: ^$Ents/Entities($Variant_Union, $Subtype_Union), $Var: typeid) -> (it: Iter_Variant(Var)) where UNION_HAS(Variant_Union, Var) {
    assert(ents.allocator != {}, "You must call init() first")
    buf := ents.buffers[UNION_INDEX(Variant_Union, Var)]
    it = {
        var = cast(^Var)buf.data,
        _end = uintptr(buf.data) + uintptr(buf.top) * size_of(Var),
    }
    return it
}

@(require_results)
next_var :: proc(it: ^Iter_Variant($Var)) -> (ok: bool) {
    for {
        it.var = cast(^Var)(uintptr(it.var) + size_of(Var))
        if uintptr(it.var) > it._end {
            break
        }
        if it.var.handle.index != 0 {
            return true
        }
    }
    return false
}



// MARK: Subtype iteration

// The handle isn't exposed directly, but it's stored in the iterator through base pointer.
Iter_Subtype :: struct($Variant_Union: typeid, $Subtype_Union: typeid, $Sub: typeid) {
    using base: ^Base, // Current value base
    using sub:  ^Sub, // Current value subtype
    _ents:      ^Entities(Variant_Union, Subtype_Union) `fmt:"-"`,
    _step:       uintptr,
    _offset:     uintptr,
    _end:        uintptr,
    _variant:    int,
    _sub_index:  int,
}

@(require_results)
begin_sub :: proc(ents: ^$Ents/Entities($Variant_Union, $Subtype_Union), $Sub: typeid) -> (result: Iter_Subtype(Variant_Union, Subtype_Union, Sub)) where UNION_HAS(Subtype_Union, Sub) {
    assert(ents.allocator != {}, "You must call init() first")
    result._ents = ents
    result._variant = -1
    result._sub_index = UNION_INDEX(Subtype_Union, Sub)
    result.base = nil
    result.sub = nil
    _iter_sub_next_variant(&result)
    return result
}

@(require_results)
next_sub :: proc(it: ^Iter_Subtype($Variant_Union, $Subtype_Union, $Sub)) -> (ok: bool) {
    for {
        it.base = cast(^Base)(uintptr(it.base) + it._step)
        if uintptr(it.base) > it._end {
            if !_iter_sub_next_variant(it) {
                return
            }
            continue
        }
        if it.base.handle.index != 0 {
            it.sub = cast(^Sub)(uintptr(it.base) + it._offset)
            return true
        }
    }

    return false
}

_iter_sub_next_variant :: proc(it: ^Iter_Subtype($Variant_Union, $Subtype_Union, $Sub)) -> (ok: bool) {
    offsets := &it._ents.offsets[it._sub_index]

    it._variant += 1
    for ; it._variant < UNION_LEN(Variant_Union); it._variant += 1 {
        if offsets[it._variant] != -1 {
            ok = true
            break
        }
    }

    if !ok {
        return false
    }

    offset := offsets[it._variant]
    size := it._ents.sizes[it._variant]
    buf := it._ents.buffers[it._variant]

    it.base = cast(^Base)buf.data
    it.sub = cast(^Sub)(uintptr(buf.data) + uintptr(offset))
    it._step = uintptr(size)
    it._offset = uintptr(offset)
    it._end = uintptr(buf.data) + uintptr(buf.top) * uintptr(size)

    return true
}


// MARK: Util

@(require_results)
_extract_variant_index :: proc "contextless" (var: ^$T) -> int where intrinsics.type_is_union(T) {
    tag := (cast(^intrinsics.type_union_tag_type(T))(uintptr(var) + intrinsics.type_union_tag_offset(T)))^
    return int(tag) - intrinsics.type_union_base_tag_value(T)
}
