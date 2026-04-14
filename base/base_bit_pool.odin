package raven_base

import "base:intrinsics"

// 2-level bitset with accelerated 0 search.
// Size overhead is 1 bit per 4096 "fields"
Bit_Pool :: struct($N: int) where N % 64 == 0 {
    l1: [(N + 4095) / 4096]u64,
    l0: [N / 64]u64,
}

@(require_results)
bit_pool_alloc :: proc "contextless" (bp: ^Bit_Pool($N)) -> (result: int, ok: bool) {
    result = bit_pool_find_0(bp^) or_return
    bit_pool_set_1(bp, result)
    return result, true
}

@(require_results)
bit_pool_find_0 :: proc "contextless" (bp: Bit_Pool($N)) -> (index: int, ok: bool) {
    l0_index := -1
    when N > 64 {
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

bit_pool_set_1 :: proc "contextless" (bp: ^Bit_Pool($N), #any_int index: u64) {
    assert_contextless(index >= 0 && index < u64(N))

    l0_index := index / 64
    l0_slot := index % 64

    l1_index := l0_index / 64
    l1_slot := l0_index % 64

    bucket := bp.l0[l0_index]
    bucket |= 1 << l0_slot

    if bucket == max(u64) { // if full
        bp.l1[l1_index] |= 1 << l1_slot
    }

    bp.l0[l0_index] = bucket
}

bit_pool_set_0 :: proc "contextless" (bp: ^Bit_Pool($N), #any_int index: u64) {
    assert_contextless(index >= 0 && index < u64(N))

    l0_index := index / 64
    l0_slot := index % 64

    l1_index := l0_index / 64
    l1_slot := l0_index % 64

    // Always clear L0, it must be non-empty after deleting from L1
    bp.l1[l1_index] &= ~(1 << l1_slot)
    bp.l0[l0_index] &= ~(1 << l0_slot)
}

// bit_pool_get
@(require_results)
bit_pool_check_1 :: proc "contextless" (bp: Bit_Pool($N), #any_int index: u64) -> bool {
    assert_contextless(index >= 0 && index < u64(N))

    l0_index := index / 64
    l0_slot := index % 64
    return (bp.l0[l0_index] & (1 << l0_slot)) != 0
}
