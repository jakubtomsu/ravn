#+test
#+vet unused shadowing
package ravn_base

import "core:testing"
import "core:math/rand"

@(test)
_test_bit_pool_basic :: proc(t: ^testing.T) {
    N :: 128
    d_pool, _ := dynamic_bit_pool_create(N)
    defer dynamic_bit_pool_destroy(&d_pool)

    s_pool: Static_Bit_Pool(N)
    bit_pool_clear(&s_pool)
    bit_pool_clear(&d_pool)

    // Initial zero search
    d_index, d_ok := bit_pool_find_0(d_pool)
    s_index, s_ok := bit_pool_find_0(s_pool)
    testing.expect(t, d_ok && d_index == 0)
    testing.expect(t, s_ok && s_index == 0)

    // Interleaved sets
    bit_pool_set_1(&d_pool, 0)
    bit_pool_set_1(&s_pool, 0)
    bit_pool_set_1(&d_pool, 63)
    bit_pool_set_1(&s_pool, 63)

    testing.expect(t, bit_pool_is_1(d_pool, 0) == true)
    testing.expect(t, bit_pool_is_1(s_pool, 0) == true)
    testing.expect(t, bit_pool_is_1(d_pool, 1) == false)
    testing.expect(t, bit_pool_is_1(s_pool, 1) == false)

    // Find next 0 skips 0, hits 1
    d_index, d_ok = bit_pool_find_0(d_pool)
    s_index, s_ok = bit_pool_find_0(s_pool)
    testing.expect(t, d_ok && d_index == 1)
    testing.expect(t, s_ok && s_index == 1)

    // Unset 0, find_0 should jump back to 0
    bit_pool_set_0(&d_pool, 0)
    bit_pool_set_0(&s_pool, 0)
    d_index, d_ok = bit_pool_find_0(d_pool)
    s_index, s_ok = bit_pool_find_0(s_pool)
    testing.expect(t, d_ok && d_index == 0)
    testing.expect(t, s_ok && s_index == 0)
}

@(test)
_test_bit_pool_exhaustion :: proc(t: ^testing.T) {
    N :: 64
    d_pool, _ := dynamic_bit_pool_create(N)
    defer dynamic_bit_pool_destroy(&d_pool)

    s_pool: Static_Bit_Pool(N)
    bit_pool_clear(&s_pool)

    for i in 0..<N {
        bit_pool_set_1(&d_pool, u64(i))
        bit_pool_set_1(&s_pool, u64(i))
    }

    // Search should fail gracefully
    d_index, d_ok := bit_pool_find_0(d_pool)
    s_index, s_ok := bit_pool_find_0(s_pool)
    testing.expect(t, !d_ok)
    testing.expect(t, !s_ok)

    // Make space at the very end
    bit_pool_set_0(&d_pool, 63)
    bit_pool_set_0(&s_pool, 63)
    d_index, d_ok = bit_pool_find_0(d_pool)
    s_index, s_ok = bit_pool_find_0(s_pool)
    testing.expect(t, d_ok && d_index == 63)
    testing.expect(t, s_ok && s_index == 63)
}

@(test)
_test_bit_pool_l1_crossing :: proc(t: ^testing.T) {
    N :: 4160
    d_pool, _ := dynamic_bit_pool_create(N)
    defer dynamic_bit_pool_destroy(&d_pool)

    s_pool: Static_Bit_Pool(N)
    bit_pool_clear(&s_pool)

    for i in 0..<4096 {
        bit_pool_set_1(&d_pool, u64(i))
        bit_pool_set_1(&s_pool, u64(i))
    }

    // The first 0 should be exactly at the start of the next L1 block
    d_index, d_ok := bit_pool_find_0(d_pool)
    s_index, s_ok := bit_pool_find_0(s_pool)
    testing.expect(t, d_ok && d_index == 4096)
    testing.expect(t, s_ok && s_index == 4096)
}

@(test)
_test_bit_pool_clear :: proc(t: ^testing.T) {
    N :: 128
    d_pool, _ := dynamic_bit_pool_create(N)
    defer dynamic_bit_pool_destroy(&d_pool)

    s_pool: Static_Bit_Pool(N)

    // Set garbage data
    for i in 0..<N {
        bit_pool_set_1(&d_pool, u64(i))
        bit_pool_set_1(&s_pool, u64(i))
    }

    bit_pool_clear(&d_pool)
    bit_pool_clear(&s_pool)

    // Should be fully zeroed, so index 0 is first
    d_index, d_ok := bit_pool_find_0(d_pool)
    s_index, s_ok := bit_pool_find_0(s_pool)
    testing.expect(t, d_ok && d_index == 0)
    testing.expect(t, s_ok && s_index == 0)
}

@(test)
_test_dynamic_bit_pool_fuzz :: proc(t: ^testing.T) {
    ITERATIONS :: 50
    OPS_PER_ITERATION :: 500

    for _ in 0..<ITERATIONS {
        num_blocks := rand.int31_max(1024) + 1
        N := int(num_blocks * 64)

        pool, ok := dynamic_bit_pool_create(N)
        testing.expect(t, ok, "Pool creation failed")
        defer dynamic_bit_pool_destroy(&pool)

        shadow := make([]bool, N)
        defer delete(shadow)

        for _ in 0..<OPS_PER_ITERATION {
            op := rand.int31_max(100)

            if op < 40 {
                index := int(rand.int31_max(i32(N)))
                bit_pool_set_1(&pool, u64(index))
                shadow[index] = true
                testing.expectf(t, bit_pool_is_1(pool, u64(index)), "Fuzz failed: Expected bit %v to be 1", index)

            } else if op < 80 {
                index := int(rand.int31_max(i32(N)))
                bit_pool_set_0(&pool, u64(index))
                shadow[index] = false
                testing.expectf(t, !bit_pool_is_1(pool, u64(index)), "Fuzz failed: Expected bit %v to be 0", index)

            } else if op < 95 {
                pool_index, pool_ok := bit_pool_find_0(pool)

                shadow_index := -1
                for val, i in shadow {
                    if !val {
                        shadow_index = i
                        break
                    }
                }

                if shadow_index == -1 {
                    testing.expect(t, !pool_ok, "Fuzz failed: Pool found a 0 but shadow state is full")
                } else {
                    testing.expectf(
                        t,
                        pool_ok && pool_index == shadow_index,
                        "Fuzz failed: find_0 mismatch. Pool returned %v, shadow expected %v",
                        pool_index, shadow_index,
                    )
                }

            } else {
                bit_pool_clear(&pool)
                for i in 0..<N {
                    shadow[i] = false
                }
                pool_index, pool_ok := bit_pool_find_0(pool)
                testing.expect(t, pool_ok && pool_index == 0, "Fuzz failed: Clear did not reset pool to index 0")
            }
        }
    }
}
