#+test
#+private file
package ravn_bvh

import "core:math/rand"
import "core:slice"
import "core:testing"

@(test)
_test_fuzz :: proc(t: ^testing.T) {
    for i in 0..<64 {
        free_all(context.temp_allocator)
        context.allocator = context.temp_allocator

        rand.reset(u64(i) * 0x9E3779B97F4A7C15 + 1)

        num := 1 + rand.int_max(1024)
        max_leaf := 1 + rand.int_max(64)

        prims := make([][2][3]f32, num)
        for &p in prims {
            for j in 0..<3 {
                pos := rand.float32_range(-100, 100)
                p[0][j] = pos
                p[1][j] = pos + rand.float32_range(0, 4) * rand.float32_range(0, 4)
            }
        }

        nodes := make([]Node, max_nodes_for_prims(num))
        indices := make([]u32, num)

        bvh: BVH
        init(&bvh, nodes, indices, prims, max_leaf)
        switch i % 4 {
        case 0: build_mid(&bvh)
        case 1: build_binned(&bvh)
        case 2: build_mean_sah(&bvh)
        case 3: build_sah(&bvh)
        }

        for _ in 0..<8 {
            pos := random_point()
            rad := rand.float32_range(0, 3)
            got: [dynamic]int
            want: [dynamic]int
            query_sphere(&bvh, pos, rad, &got)
            for p, i in prims {
                if sphere_vs_aabb(pos, rad, p) {
                    append(&want, i)
                }
            }
            slice.sort(got[:])
            slice.sort(want[:])
            testing.expect(t, slice.equal(got[:], want[:]))
        }

        for _ in 0..<8 {
            pos := random_point()
            move := random_move()
            bvh_t, bvh_hit := query_ray(&bvh, pos, move)

            brute_t: f32 = 1
            brute_hit: bool
            for p in prims {
                if t, ok := ray_vs_aabb(pos, move, p); ok && t < brute_t {
                    brute_t = t
                    brute_hit = true
                }
            }

            testing.expect(t, bvh_hit == brute_hit && bvh_t == brute_t)
        }
    }

    return

    random_point :: proc() -> [3]f32 {
        return {rand.float32_range(-120, 120), rand.float32_range(-120, 120), rand.float32_range(-120, 120)}
    }

    random_move :: proc() -> [3]f32 {
        m: [3]f32
        for i in 0..<3 {
            m[i] = rand.float32_range(-100, 100) * (rand.float32() < 0.1 ? 0 : 1)
        }
        return m
    }

    sphere_vs_aabb :: proc(pos: [3]f32, rad: f32, box: [2][3]f32) -> bool {
        d2: f32 = 0
        for i in 0..<3 {
            if pos[i] < box[0][i] {
                d2 += (box[0][i] - pos[i]) * (box[0][i] - pos[i])
            } else if pos[i] > box[1][i] {
                d2 += (pos[i] - box[1][i]) * (pos[i] - box[1][i])
            }
        }
        return d2 <= rad * rad
    }

    ray_vs_aabb :: proc(pos, move: [3]f32, box: [2][3]f32, range: f32 = 1) -> (f32, bool) {
        inv := 1.0 / move
        t1 := (box[0] - pos) * inv
        t2 := (box[1] - pos) * inv
        tmin := max(min(t1.x, t2.x), min(t1.y, t2.y), min(t1.z, t2.z))
        tmax := min(max(t1.x, t2.x), max(t1.y, t2.y), max(t1.z, t2.z))
        ok := tmax >= max(0, tmin) && tmin < range
        return tmin, ok
    }

    query_sphere :: proc(bvh: ^BVH, pos: [3]f32, rad: f32, out: ^[dynamic]int) {
        for it := iter(bvh); it.node != nil; {
            if it.len != 0 { // leaf
                for i in 0..<int(it.len) {
                    pi := bvh.indices[int(it.first) + i]
                    if sphere_vs_aabb(pos, rad, bvh.prims[pi]) {
                        append(out, int(pi))
                    }
                }
                iter_pop(&it) or_break
            } else { // internal
                c0 := bvh.nodes[it.first + 0]
                c1 := bvh.nodes[it.first + 1]
                h0 := sphere_vs_aabb(pos, rad, {c0.min, c0.max})
                h1 := sphere_vs_aabb(pos, rad, {c1.min, c1.max})
                iter_unordered_next(&it, h0, h1) or_break
            }
        }
    }

    query_ray :: proc(bvh: ^BVH, pos, move: [3]f32) -> (best_t: f32, hit: bool) {
        best_t = 1
        for it := iter(bvh); it.node != nil; {
            if it.len != 0 { // leaf
                for i in 0..<int(it.len) {
                    pi := bvh.indices[int(it.first) + i]
                    if t, ok := ray_vs_aabb(pos, move, bvh.prims[pi]); ok && t < best_t {
                        best_t = t
                        hit = true
                    }
                }
                iter_pop(&it) or_break
            } else { // internal
                c0 := bvh.nodes[it.first + 0]
                c1 := bvh.nodes[it.first + 1]
                t0 := ray_vs_aabb(pos, move, {c0.min, c0.max}, best_t) or_else max(f32)
                t1 := ray_vs_aabb(pos, move, {c1.min, c1.max}, best_t) or_else max(f32)
                iter_next(&it, t0, t1) or_break
            }
        }
        return
    }
}
