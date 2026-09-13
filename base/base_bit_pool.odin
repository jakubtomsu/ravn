#+vet unused shadowing style explicit-allocators
package ravn_base

import "base:runtime"
import "base:intrinsics"

// 2-level bitset with accelerated zero search.
// Size overhead is 1 bit per 4096 items.

Dynamic_Bit_Pool :: struct {
    l1: []u64,
    l0: []u64, // Lowest level with the actual item bits
}

Static_Bit_Pool :: struct($N: int) where N % 64 == 0 {
    l1: [(N + 4095) / 4096]u64,
    l0: [N / 64]u64, // Lowest level with the actual individual item bits
}


bit_pool_clear :: proc {
    dynamic_bit_pool_clear,
    static_bit_pool_clear,
}

bit_pool_find_0 :: proc {
    dynamic_bit_pool_find_0,
    static_bit_pool_find_0,
}

bit_pool_set_1 :: proc {
    dynamic_bit_pool_set_1,
    static_bit_pool_set_1,
}

bit_pool_set_0 :: proc {
    dynamic_bit_pool_set_0,
    static_bit_pool_set_0,
}

bit_pool_is_1 :: proc {
    dynamic_bit_pool_is_1,
    static_bit_pool_is_1,
}



// MARK: dynamic

@(require_results)
dynamic_bit_pool_create :: proc(num_bits: int, allocator := context.allocator, loc := #caller_location) -> (result: Dynamic_Bit_Pool, ok: bool) {
    assert(num_bits > 0)
    assert(num_bits % 64 == 0, loc = loc)

    err: runtime.Allocator_Error

    result.l0, err = make([]u64, num_bits / 64, allocator = allocator)
    if err != nil {
        return {}, false
    }

    if num_bits > 64 {
        result.l1, err = make([]u64, (num_bits + 4095) / 4096, allocator = allocator)
        if err != nil {
            return {}, false
        }
    }

    return result, true
}

dynamic_bit_pool_destroy :: proc(bp: ^Dynamic_Bit_Pool, allocator := context.allocator) {
    if bp.l0 != nil {
        delete(bp.l0, allocator = allocator)
    }
    if bp.l1 != nil {
        delete(bp.l1, allocator = allocator)
    }
    bp^ = {}
}

dynamic_bit_pool_clear :: proc "contextless" (bp: ^Dynamic_Bit_Pool) {
    intrinsics.mem_zero(raw_data(bp.l1), len(bp.l1))
    intrinsics.mem_zero(raw_data(bp.l0), len(bp.l0))
}

@(require_results)
dynamic_bit_pool_find_0 :: proc "contextless" (bp: Dynamic_Bit_Pool) -> (index: int, ok: bool) {
    l0_index := -1
    if len(bp.l0) > 1 {
        for used, i in bp.l1 {
            l1_slot := int(intrinsics.count_trailing_zeros(~used))
            if l1_slot != 64 {
                l0_index = 64 * i + l1_slot
                break
            }
        }

        if l0_index == -1 || l0_index >= len(bp.l0) {
            return -1, false
        }
    } else {
        l0_index = 0
    }

    l0_slot := int(intrinsics.count_trailing_zeros(~bp.l0[l0_index]))
    if l0_slot != 64 {
        return l0_index * 64 + l0_slot, true
    }

    return -1, false
}

dynamic_bit_pool_set_1 :: proc(bp: ^Dynamic_Bit_Pool, #any_int index: u64) {
    assert(index >= 0 && index * 64 < u64(len(bp.l0)))

    l0_index, l0_slot := _bit_pool_decompose_index(index)
    l1_index, l1_slot := _bit_pool_decompose_index(l0_index)

    bucket := bp.l0[l0_index]
    bucket |= 1 << l0_slot
    if bucket == max(u64) { // if full
        bp.l1[l1_index] |= 1 << l1_slot
    }
    bp.l0[l0_index] = bucket
}

dynamic_bit_pool_set_0 :: proc(bp: ^Dynamic_Bit_Pool, #any_int index: u64) {
    assert(index >= 0 && index * 64 < u64(len(bp.l0)))
    l0_index, l0_slot := _bit_pool_decompose_index(index)
    l1_index, l1_slot := _bit_pool_decompose_index(l0_index)
    // Always clear L0, it must be non-empty after deleting from L1
    bp.l1[l1_index] &= ~(1 << l1_slot)
    bp.l0[l0_index] &= ~(1 << l0_slot)
}

@(require_results)
dynamic_bit_pool_is_1 :: proc(bp: Dynamic_Bit_Pool, #any_int index: u64) -> bool {
    assert(index >= 0 && index * 64 < u64(len(bp.l0)))
    l0_index, l0_slot := _bit_pool_decompose_index(index)
    return (bp.l0[l0_index] & (1 << l0_slot)) != 0
}



// MARK: static

static_bit_pool_clear :: proc "contextless" (bp: ^Static_Bit_Pool($N)) {
    intrinsics.mem_zero(&bp.l1, size_of(bp.l1))
    intrinsics.mem_zero(&bp.l0, size_of(bp.l0))
}

@(require_results)
static_bit_pool_find_0 :: proc "contextless" (bp: Static_Bit_Pool($N)) -> (index: int, ok: bool) {
    l0_index := -1
    if N > 64 {
        for used, i in bp.l1 {
            l1_slot := int(intrinsics.count_trailing_zeros(~used))
            if l1_slot != 64 {
                l0_index = 64 * i + l1_slot
                break
            }
        }

        if l0_index == -1 || l0_index >= (N / 64) {
            return -1, false
        }
    } else {
        l0_index = 0
    }

    l0_slot := int(intrinsics.count_trailing_zeros(~bp.l0[l0_index]))
    if l0_slot != 64 {
        return l0_index * 64 + l0_slot, true
    }

    return -1, false
}

static_bit_pool_set_1 :: proc(bp: ^Static_Bit_Pool($N), #any_int index: u64) {
    assert(index >= 0 && index < u64(N))

    l0_index, l0_slot := _bit_pool_decompose_index(index)
    l1_index, l1_slot := _bit_pool_decompose_index(l0_index)

    bucket := bp.l0[l0_index]
    bucket |= 1 << l0_slot
    if bucket == max(u64) { // if full
        bp.l1[l1_index] |= 1 << l1_slot
    }
    bp.l0[l0_index] = bucket
}

static_bit_pool_set_0 :: proc(bp: ^Static_Bit_Pool($N), #any_int index: u64) {
    assert(index >= 0 && index < u64(N))
    l0_index, l0_slot := _bit_pool_decompose_index(index)
    l1_index, l1_slot := _bit_pool_decompose_index(l0_index)
    // Always clear L0, it must be non-empty after deleting from L1
    bp.l1[l1_index] &= ~(1 << l1_slot)
    bp.l0[l0_index] &= ~(1 << l0_slot)
}

// static_bit_pool_get
@(require_results)
static_bit_pool_is_1 :: proc(bp: Static_Bit_Pool($N), #any_int index: u64) -> bool {
    assert(index >= 0 && index < u64(N))
    l0_index, l0_slot := _bit_pool_decompose_index(index)
    return (bp.l0[l0_index] & (1 << l0_slot)) != 0
}



// MARK: shared

@(require_results)
_bit_pool_decompose_index :: #force_inline proc "contextless" (#any_int _index: u64) -> (index: u64, slot: u64) {
    return _index / 64, _index % 64
}
