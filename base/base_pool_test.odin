#+test
#+vet unused shadowing
package ravn_base

import "core:math/rand"
import "core:testing"

@(test)
_test_pool_consistency :: proc(t: ^testing.T) {
    d_pool: Dynamic_Pool(int, Handle)
    dynamic_pool_init(&d_pool, 64)
    defer dynamic_pool_destroy(&d_pool)

    s_pool: Static_Pool(64, int, Handle)
    pool_clear(&s_pool)

    h1_d, _ := pool_find_free(d_pool)
    testing.expect(t, pool_insert(&d_pool, h1_d, 10) == true)
    h1_s, _ := pool_find_free(s_pool)
    testing.expect(t, pool_insert(&s_pool, h1_s, 10) == true)

    h2_d, _ := pool_find_free(d_pool)
    testing.expect(t, pool_insert(&d_pool, h2_d, 20) == true)
    h2_s, _ := pool_find_free(s_pool)
    testing.expect(t, pool_insert(&s_pool, h2_s, 20) == true)

    v_d, ok_d := pool_get(&d_pool, h1_d)
    v_s, ok_s := pool_get(&s_pool, h1_s)
    testing.expect(t, ok_d && v_d^ == 10)
    testing.expect(t, ok_s && v_s^ == 10)

    pool_remove(&d_pool, h1_d)
    pool_remove(&s_pool, h1_s)

    _, ok_d = pool_get(&d_pool, h1_d)
    _, ok_s = pool_get(&s_pool, h1_s)
    testing.expect(t, !ok_d)
    testing.expect(t, !ok_s)
}

@(test)
_test_pool_iterator :: proc(t: ^testing.T) {
    d_pool: Dynamic_Pool(int, Handle)
    dynamic_pool_init(&d_pool, 64)
    defer dynamic_pool_destroy(&d_pool)

    s_pool: Static_Pool(64, int, Handle)
    pool_clear(&s_pool)

    handles: [3]Handle
    for v, i in ([]int{111, 222, 333}) {
        hd, _ := pool_find_free(d_pool)
        testing.expect(t, pool_insert(&d_pool, hd, v) == true)

        hs, _ := pool_find_free(s_pool)
        testing.expect(t, pool_insert(&s_pool, hs, v) == true)

        handles[i] = hd
    }

    pool_remove(&d_pool, handles[1])
    pool_remove(&s_pool, handles[1])

    d_sum, s_sum := 0, 0

    iter_d := dynamic_pool_iter(&d_pool)
    for _, d in dynamic_pool_next(&iter_d) {
        d_sum += d^
    }

    iter_s := static_pool_iter(&s_pool)
    for _, d in static_pool_next(&iter_s) {
        s_sum += d^
    }

    testing.expect(t, d_sum == 444)
    testing.expect(t, s_sum == 444)
}

@(test)
_test_pool_fuzz :: proc(t: ^testing.T) {
    d_pool: Dynamic_Pool(int, Handle)
    dynamic_pool_init(&d_pool, 1024)
    defer dynamic_pool_destroy(&d_pool)

    s_pool: Static_Pool(1024, int, Handle)
    pool_clear(&s_pool)

    shadow := make(map[Handle]int)
    defer delete(shadow)

    active_handles := make([dynamic]Handle)
    defer delete(active_handles)

    for _ in 0..<10000 {
        op := rand.int31_max(100)

        if op < 40 {
            hd, ok_d := pool_find_free(d_pool)
            hs, ok_s := pool_find_free(s_pool)
            testing.expect(t, ok_d && ok_s && hd.index == hs.index)

            if ok_d {
                val := int(rand.int31())
                testing.expect(t, pool_insert(&d_pool, hd, val) == true)
                testing.expect(t, pool_insert(&s_pool, hs, val) == true)

                shadow[hd] = val
                append(&active_handles, hd)
            }

        } else if op < 70 && len(active_handles) > 0 {
            idx := rand.int31_max(i32(len(active_handles)))
            h := active_handles[idx]

            pool_remove(&d_pool, h)
            pool_remove(&s_pool, h)
            delete_key(&shadow, h)
            unordered_remove(&active_handles, int(idx))

            _, ok_d := pool_get(&d_pool, h)
            _, ok_s := pool_get(&s_pool, h)
            testing.expect(t, !ok_d && !ok_s)

        } else if op < 90 && len(active_handles) > 0 {
            idx := rand.int31_max(i32(len(active_handles)))
            h := active_handles[idx]

            vd, ok_d := pool_get(&d_pool, h)
            vs, ok_s := pool_get(&s_pool, h)
            testing.expect(t, ok_d && ok_s)
            testing.expect(t, vd^ == shadow[h] && vs^ == shadow[h])

        } else if op < 95 {
            pool_clear(&d_pool)
            pool_clear(&s_pool)
            clear(&shadow)
            clear(&active_handles)

        } else {
            count_d, count_s := 0, 0

            iter_d := pool_iter(&d_pool)
            for h, d in pool_next(&iter_d) {
                testing.expect(t, shadow[h] == d^)
                count_d += 1
            }

            iter_s := pool_iter(&s_pool)
            for h, d in pool_next(&iter_s) {
                testing.expect(t, shadow[h] == d^)
                count_s += 1
            }

            testing.expect(t, count_d == len(shadow))
            testing.expect(t, count_s == len(shadow))
        }
    }
}
