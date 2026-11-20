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

        prims := make([]Primitive, num)
        for &p in prims {
            for j in 0..<3 {
                pos := rand.float32_range(-100, 100)
                p.min[j] = pos
                p.max[j] = pos + rand.float32_range(0, 4) * rand.float32_range(0, 4)
            }
        }

        nodes := make([]Node, max_nodes_for_prims(num))
        indices := make([]u32, num)

        bvh: BVH
        init(&bvh, max_prims = len(prims), max_leaf_prims = max_leaf)
        switch i % 4 {
        case 0: build_midpoint(&bvh, prims)
        case 1: build_binned(&bvh, prims, num_bins = 2 + rand.int_max(30))
        case 2: build_mean_sah(&bvh, prims)
        case 3: build_sah(&bvh, prims)
        }

        for _ in 0..<8 {
            pos := random_point()
            rad := rand.float32_range(0, 3)
            got: [dynamic]int
            want: [dynamic]int
            query_sphere(&bvh, prims, pos, rad, &got)
            for p, i in prims {
                if sphere_vs_aabb(pos, rad, p.min, p.max) {
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
            bvh_t, bvh_hit := query_ray(&bvh, prims, pos, move)

            brute_t: f32 = 1
            brute_hit: bool
            for p in prims {
                if t, ok := ray_vs_aabb(pos, move, p.min, p.max); ok && t < brute_t {
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

    sphere_vs_aabb :: proc(pos: [3]f32, rad: f32, box_min, box_max: [3]f32) -> bool {
        d2: f32 = 0
        for i in 0..<3 {
            if pos[i] < box_min[i] {
                d2 += (box_min[i] - pos[i]) * (box_min[i] - pos[i])
            } else if pos[i] > box_max[i] {
                d2 += (pos[i] - box_max[i]) * (pos[i] - box_max[i])
            }
        }
        return d2 <= rad * rad
    }

    ray_vs_aabb :: proc(pos, move: [3]f32, box_min, box_max: [3]f32, range: f32 = 1) -> (f32, bool) {
        inv := 1.0 / move
        t1 := (box_min - pos) * inv
        t2 := (box_max - pos) * inv
        tmin := max(min(t1.x, t2.x), min(t1.y, t2.y), min(t1.z, t2.z))
        tmax := min(max(t1.x, t2.x), max(t1.y, t2.y), max(t1.z, t2.z))
        ok := tmax >= max(0, tmin) && tmin <= range
        return tmin, ok
    }

    query_sphere :: proc(bvh: ^BVH, prims: []Primitive, pos: [3]f32, rad: f32, out: ^[dynamic]int) {
        for it := iter(bvh); it.node != nil; {
            if it.len != 0 { // leaf
                for i in 0..<int(it.len) {
                    pi := int(it.first) + i
                    prim := prims[pi]
                    if sphere_vs_aabb(pos, rad, prim.min, prim.max) {
                        append(out, int(pi))
                    }
                }
                iter_pop(&it) or_break
            } else { // internal
                c0 := bvh.nodes[it.first + 0]
                c1 := bvh.nodes[it.first + 1]
                h0 := sphere_vs_aabb(pos, rad, c0.min, c0.max)
                h1 := sphere_vs_aabb(pos, rad, c1.min, c1.max)
                iter_unordered_next(&it, h0, h1) or_break
            }
        }
    }

    query_ray :: proc(bvh: ^BVH, prims: []Primitive, pos, move: [3]f32) -> (best_t: f32, hit: bool) {
        best_t = 1
        for it := iter(bvh); it.node != nil; {
            if it.len != 0 { // leaf
                for i in 0..<int(it.len) {
                    prim := prims[int(it.first) + i]
                    if t, ok := ray_vs_aabb(pos, move, prim.min, prim.max); ok && t < best_t {
                        best_t = t
                        hit = true
                    }
                }
                iter_pop(&it) or_break
            } else { // internal
                c0 := bvh.nodes[it.first + 0]
                c1 := bvh.nodes[it.first + 1]
                t0 := ray_vs_aabb(pos, move, c0.min, c0.max, best_t) or_else max(f32)
                t1 := ray_vs_aabb(pos, move, c1.min, c1.max, best_t) or_else max(f32)
                iter_next(&it, t0, t1) or_break
            }
        }
        return
    }
}
