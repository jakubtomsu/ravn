#+vet unused shadowing style explicit-allocators
package ravn_base

import "base:intrinsics"

HASH_POOL_MAX_PROBE_DIST :: 32

Hash_Pool :: struct($N: int, $D: typeid, $H: typeid) where
    intrinsics.type_has_field(H, "index"),
    intrinsics.type_has_field(H, "gen")
{
    gen:    [N]Handle_Gen,
    hash:   [N]u64,
    data:   [N]D,
}

// Call to initialize and destroy. Does not clear generation counters and values - garbage is fine.
hash_pool_clear :: proc "contextless" (pool: ^$T/Hash_Pool($N, $D, $H)) {
    intrinsics.mem_zero(&pool.hash, size_of(pool.hash))
}

@(require_results)
hash_pool_has :: proc "contextless" (pool: $T/Hash_Pool($N, $D, $H), handle: H) -> bool {
    return handle.index > 0 && handle.index < Handle_Index(N) && handle.gen == pool.gen[handle.index]
}

@(require_results)
hash_pool_find_free :: proc "contextless" (pool: $T/Hash_Pool($N, $D, $H), hash: u64) -> (handle: H, found_existing: bool, ok: bool) {
    if hash == 0 {
        return {}, false, false
    }
    hole := -1
    for offs in 0..<u64(HASH_POOL_MAX_PROBE_DIST) {
        slot := (hash + offs) %% u64(N)
        if slot == 0 {
            continue
        }
        if pool.hash[slot] == hash {
            return {index = Handle_Index(slot), gen = pool.gen[slot]}, true, true
        }
        if pool.hash[slot] == 0 {
            hole = int(slot)
        }
    }
    if hole != -1 {
        return {index = Handle_Index(hole), gen = pool.gen[hole]}, false, true
    }
    return {}, false, false
}

@(require_results)
hash_pool_find :: proc "contextless" (pool: ^$T/Hash_Pool($N, $D, $H), hash: u64) -> (H, ^D, bool) {
    if hash == 0 {
        return {}, nil, false
    }
    for offs in 0..<u64(HASH_POOL_MAX_PROBE_DIST) {
        slot := (hash + offs) %% u64(N)
        if pool.hash[slot] == hash {
            return {index = Handle_Index(slot), gen = pool.gen[slot]}, &pool.data[slot], true
        }
    }
    return {}, nil, false
}

@(require_results)
hash_pool_insert :: proc "contextless" (pool: ^$T/Hash_Pool($N, $D, $H), hash: u64, handle: H, data: D) -> bool {
    if !hash_pool_has(pool^, handle) {
        return false
    }
    pool.hash[handle.index] = hash
    pool.data[handle.index] = data
    return true
}

@(require_results)
hash_pool_remove :: proc(pool: ^$T/Hash_Pool($N, $D, $H), handle: H) -> bool {
    if !hash_pool_has(pool^, handle) {
        return false
    }
    pool.gen[handle.index] += 1
    pool.hash[handle.index] = 0
    return true
}

@(require_results)
hash_pool_get :: proc(pool: ^$T/Hash_Pool($N, $D, $H), handle: H) -> (^D, bool) {
    if !hash_pool_has(pool^, handle) {
        return nil, false
    }
    assert(pool.hash[handle.index] != 0, "Corrupted state")
    return &pool.data[handle.index], true
}


Hash_Pool_Iter :: struct($N: int, $D: typeid, $H: typeid) where
    intrinsics.type_has_field(H, "index"),
    intrinsics.type_has_field(H, "gen")
{
    pool:       ^Hash_Pool(N, D, H),
    index:      int,
}

@(require_results)
hash_pool_iter :: proc(pool: ^$T/Hash_Pool($N, $D, $H)) -> Hash_Pool_Iter(N, D, H) {
    return {
        pool = pool,
    }
}

@(require_results)
hash_pool_next :: proc(iter: ^$T/Hash_Pool_Iter($N, $D, $H)) -> (handle: H, data: ^D, ok: bool) {
    for iter.index < N {
        defer iter.index += 1
        if iter.pool.hash[iter.index] != 0 {
            return {index = Handle_Index(iter.index), gen = iter.pool.gen[iter.index]}, &iter.pool.data[iter.index], true
        }
    }
    return {}, nil, false
}
