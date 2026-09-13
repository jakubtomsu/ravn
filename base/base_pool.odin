#+vet unused shadowing style explicit-allocators
package ravn_base

import "base:runtime"
import "base:intrinsics"

_ :: runtime

Dynamic_Pool :: struct($D: typeid, $H: typeid) where
    intrinsics.type_has_field(H, "index"),
    intrinsics.type_has_field(H, "gen")
{
    used:   Dynamic_Bit_Pool,
    gen:    []Handle_Gen,
    data:   []D,
}

Static_Pool :: struct($N: int, $D: typeid, $H: typeid) where
    intrinsics.type_has_field(H, "index"),
    intrinsics.type_has_field(H, "gen")
{
    used:   Static_Bit_Pool(N),
    gen:    [N]Handle_Gen,
    data:   [N]D,
}

pool_clear :: proc {
    dynamic_pool_clear,
    static_pool_clear,
}

pool_has :: proc {
    dynamic_pool_has,
    static_pool_has,
}

pool_find_free :: proc {
    dynamic_pool_find_free,
    static_pool_find_free,
}

pool_insert :: proc {
    dynamic_pool_insert,
    static_pool_insert,
}

pool_set :: proc {
    dynamic_pool_set,
    static_pool_set,
}

pool_remove :: proc {
    dynamic_pool_remove,
    static_pool_remove,
}

pool_get :: proc {
    dynamic_pool_get,
    static_pool_get,
}

pool_iter :: proc{
    dynamic_pool_iter,
    static_pool_iter,
}

pool_next :: proc{
    dynamic_pool_next,
    static_pool_next,
}



// MARK: Dynamic

dynamic_pool_create :: proc(pool: ^$T/Dynamic_Pool($D, $H), size: int, allocator := context.allocator, loc := #caller_location) -> bool {
    assert(size > 0)
    if !dynamic_bit_pool_create(size, allocator = allocator, loc = loc) {
        return false
    }

    err: runtime.Allocator_Error

    pool.data, err = make([]D, size, allocator = allocator)
    if err != nil {
        return false
    }

    pool.gen, err = make([]Handle_Gen, size, allocator = allocator)
    if err != nil {
        return false
    }

    return true
}

dynamic_pool_destroy :: proc(pool: ^$T/Dynamic_Pool($D, $H), allocator := context.allocator) {
    dynamic_bit_pool_destroy(&pool.used, allocator = allocator)
    if pool.gen != nil {
        destroy(pool.gen, allocator = allocator)
    }
    if pool.data != nil {
        destroy(pool.data, allocator = allocator)
    }
    pool^ = {}
}

dynamic_pool_clear :: proc(pool: ^$T/Dynamic_Pool($D, $H)) {
    static_bit_pool_clear(&pool.used)
    static_bit_pool_set_1(&pool.used, 0)
}

@(require_results)
dynamic_pool_has :: proc "contextless" (pool: $T/Dynamic_Pool($D, $H), handle: H) -> bool {
    return \
        handle.index > 0 &&
        handle.index < Handle_Index(N) &&
        handle.gen == pool.gen[handle.index]
}

@(require_results)
dynamic_pool_find_free :: proc(pool: $T/Dynamic_Pool($D, $H)) -> (handle: H, ok: bool) {
    index := static_bit_pool_find_0(pool.used) or_return
    assert(index != 0, "Pool must be cleared before allocating.")
    return {index = Handle_Index(index), gen = pool.gen[index]}, true
}

@(require_results)
dynamic_pool_insert :: proc(pool: ^$T/Dynamic_Pool($D, $H), handle: H, data: D) -> bool {
    assert(handle != {})
    if !dynamic_pool_has(pool^, handle) || static_bit_pool_is_1(pool.used, handle.index) {
        return false
    }
    static_bit_pool_set_1(&pool.used, handle.index)
    pool.data[handle.index] = data
    return true
}

dynamic_pool_set :: proc(pool: ^$T/Dynamic_Pool($D, $H), handle: H, data: D) -> bool {
    assert(handle != {})
    if !dynamic_pool_has(pool^, handle) {
        return false
    }
    static_bit_pool_set_1(&pool.used, handle.index)
    pool.data[handle.index] = data
    return true
}

@(require_results)
dynamic_pool_remove :: proc(pool: ^$T/Dynamic_Pool($D, $H), handle: H) -> bool {
    if !dynamic_pool_has(pool^, handle) || !static_bit_pool_is_1(pool.used, handle.index) {
        return false
    }
    static_bit_pool_set_0(&pool.used, handle.index)
    pool.gen[handle.index] += 1
    pool.data[handle.index] = {}
    return true
}

@(require_results)
dynamic_pool_get :: proc(pool: ^$T/Dynamic_Pool($D, $H), handle: H) -> (^D, bool) {
    if !dynamic_pool_has(pool^, handle) || !static_bit_pool_is_1(pool.used, handle.index) {
        return nil, false
    }
    return &pool.data[handle.index], true
}



// MARK: Static

// Call to initialize and destroy. Does not clear generation counters and values - garbage is fine.
static_pool_clear :: proc(pool: ^$T/Static_Pool($N, $D, $H)) {
    static_bit_pool_clear(&pool.used)
    static_bit_pool_set_1(&pool.used, 0)
}

@(require_results)
static_pool_has :: proc "contextless" (pool: $T/Static_Pool($N, $D, $H), handle: H) -> bool {
    return \
        handle.index > 0 &&
        handle.index < Handle_Index(N) &&
        handle.gen == pool.gen[handle.index]
}

@(require_results)
static_pool_find_free :: proc(pool: $T/Static_Pool($N, $D, $H)) -> (handle: H, ok: bool) {
    index := static_bit_pool_find_0(pool.used) or_return
    assert(index != 0, "Pool must be cleared before allocating.")
    return {index = Handle_Index(index), gen = pool.gen[index]}, true
}

@(require_results)
static_pool_insert :: proc(pool: ^$T/Static_Pool($N, $D, $H), handle: H, data: D) -> bool {
    assert(handle != {})
    if !pool_has(pool^, handle) || static_bit_pool_is_1(pool.used, handle.index) {
        return false
    }
    static_bit_pool_set_1(&pool.used, handle.index)
    pool.data[handle.index] = data
    return true
}

static_pool_set :: proc(pool: ^$T/Static_Pool($N, $D, $H), handle: H, data: D) -> bool {
    assert(handle != {})
    if !pool_has(pool^, handle) {
        return false
    }
    static_bit_pool_set_1(&pool.used, handle.index)
    pool.data[handle.index] = data
    return true
}

@(require_results)
static_pool_remove :: proc(pool: ^$T/Static_Pool($N, $D, $H), handle: H) -> bool {
    if !pool_has(pool^, handle) || !static_bit_pool_is_1(pool.used, handle.index) {
        return false
    }
    static_bit_pool_set_0(&pool.used, handle.index)
    pool.gen[handle.index] += 1
    pool.data[handle.index] = {}
    return true
}

@(require_results)
static_pool_get :: proc(pool: ^$T/Static_Pool($N, $D, $H), handle: H) -> (^D, bool) {
    if !pool_has(pool^, handle) || !static_bit_pool_is_1(pool.used, handle.index) {
        return nil, false
    }
    return &pool.data[handle.index], true
}

// MARK: Iter

Dynamic_Pool_Iter :: struct($D: typeid, $H: typeid) {
    pool:       ^Dynamic_Pool(N, D, H),
    index:      int,
}

@(require_results)
dynamic_pool_iter :: proc(pool: ^$T/Dynamic_Pool($D, $H)) -> Dynamic_Pool_Iter(N, D, H) {
    return {
        pool = pool,
    }
}

@(require_results)
dynamic_pool_next :: proc(iter: ^$T/Dynamic_Pool_Iter($D, $H)) -> (handle: H, data: ^D, ok: bool) {
    for iter.index < N {
        defer iter.index += 1
        if static_bit_pool_is_1(iter.pool.used, iter.index) {
            return {index = Handle_Index(iter.index), gen = iter.pool.gen[iter.index]}, &iter.pool.data[iter.index], true
        }
    }
    return {}, nil, false
}


Static_Pool_Iter :: struct($N: int, $D: typeid, $H: typeid) {
    pool:       ^Static_Pool(N, D, H),
    index:      int,
}

@(require_results)
static_pool_iter :: proc(pool: ^$T/Static_Pool($N, $D, $H)) -> Static_Pool_Iter(N, D, H) {
    return {
        pool = pool,
    }
}

@(require_results)
static_pool_next :: proc(iter: ^$T/Static_Pool_Iter($N, $D, $H)) -> (handle: H, data: ^D, ok: bool) {
    for iter.index < N {
        defer iter.index += 1
        if static_bit_pool_is_1(iter.pool.used, iter.index) {
            return {index = Handle_Index(iter.index), gen = iter.pool.gen[iter.index]}, &iter.pool.data[iter.index], true
        }
    }
    return {}, nil, false
}
