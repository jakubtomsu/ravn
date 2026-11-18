#+test
#+private file
#+vet shadowing explicit-allocators
package ravn_collision

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:slice"
import "core:testing"
import "base:runtime"
import "../base"

@(test)
_test_collision_fuzz :: proc(t: ^testing.T) {
    init(nil, context.allocator)
    defer shutdown()

    arena, arena_ok := create_arena(16 * 1024 * 1024, context.allocator)
    testing.expect(t, arena_ok)
    defer destroy_arena(arena)

    arena_alloc := arena_allocator(arena)

    // Create varied procedural meshes: centered box, offset/non-centered pyramid, terrain grid
    NUM_TEST_MESHES :: 6
    meshes: [NUM_TEST_MESHES]Mesh_Handle
    for m_idx in 0..<NUM_TEST_MESHES {
        rand.reset(u64(m_idx + 1) * 0xBF58476D1CE4E5B9)
        meshes[m_idx] = _create_random_mesh(t, arena, arena_alloc, offset_center = (m_idx % 2 == 1))
    }

    NUM_STEPS :: 48
    QUERIES_PER_STEP :: 24

    for step_idx in 0..<NUM_STEPS {
        free_all(context.temp_allocator)
        rand.reset(u64(step_idx + 1) * 0x9E3779B97F4A7C15)

        delta := rand.float32_range(0.008, 0.06)
        begin_step(delta)

        num_shapes := 1 + rand.int_max(min(256, MAX_SHAPES))
        for shape_idx in 0..<num_shapes {
            _spawn_random_shape(meshes[:], u64(shape_idx + 1))
        }

        end_step()

        step := get_step_state()
        testing.expect_value(t, int(step.shape_used), num_shapes)

        // 1. Discrete overlap queries: test_sphere & overlap_sphere
        for q_idx in 0..<QUERIES_PER_STEP {
            pos := _random_vec3(-60, 60)
            rad := rand.float32() < 0.15 ? f32(0.0) : rand.float32_range(0.05, 6.0)
            ignore_layers := _random_layer_mask()

            api_test, api_any := test_sphere(pos, rad, ignore_layers)
            api_overlap, api_overlap_ok := overlap_sphere(
                pos = pos,
                rad = rad,
                max_overlaps = MAX_SHAPES,
                ignore_layers = ignore_layers,
                allocator = context.temp_allocator,
            )

            brute_shapes := make([dynamic]i32, 0, 32, context.temp_allocator)
            for s, idx in step.shape_data[:step.shape_used] {
                if int(s.layer) in ignore_layers {
                    continue
                }
                if _, hit := test_sphere_vs_shape(pos, rad, s); hit {
                    append(&brute_shapes, i32(idx))
                }
            }

            brute_any := len(brute_shapes) > 0
            testing.expectf(
                t,
                api_any == brute_any && api_overlap_ok == brute_any,
                "Step %d overlap query %d mismatch: test_sphere=%v, overlap_sphere=%v, brute=%v (pos=%v, rad=%v)",
                step_idx, q_idx, api_any, api_overlap_ok, brute_any, pos, rad,
            )

            if api_any {
                testing.expect(t, api_test.shape >= 0 && api_test.shape < step.shape_used)
                _, verified := test_sphere_vs_shape(pos, rad, step.shape_data[api_test.shape])
                testing.expectf(t, verified, "Step %d test_sphere returned non-overlapping shape %d", step_idx, api_test.shape)
            }

            got := slice.clone(api_overlap.shapes, context.temp_allocator)
            slice.sort(got)
            slice.sort(brute_shapes[:])
            testing.expectf(
                t,
                slice.equal(got, brute_shapes[:]),
                "Step %d overlap_sphere set mismatch on query %d: got=%v, want=%v",
                step_idx, q_idx, got, brute_shapes[:],
            )
        }

        // 2. Point sweep (raycast) queries: sweep_point
        for q_idx in 0..<QUERIES_PER_STEP {
            pos := _random_vec3(-65, 65)
            move := _random_move_vec()
            range := rand.float32_range(0.1, 80.0)
            ignore_layers := _random_layer_mask()

            api_sweep, api_ok := sweep_point(pos, move, range, ignore_layers)

            brute_t := range
            brute_shape: i32 = -1
            brute_ok := false
            for s, idx in step.shape_data[:step.shape_used] {
                if int(s.layer) in ignore_layers {
                    continue
                }
                if hit_t, _, hit := sweep_point_vs_shape(pos, move, s, brute_t); hit {
                    brute_t = hit_t
                    brute_shape = i32(idx)
                    brute_ok = true
                }
            }

            testing.expectf(
                t,
                api_ok == brute_ok,
                "Step %d sweep_point hit/miss mismatch on query %d: api=%v (t=%v, shape=%d) vs brute=%v (t=%v, shape=%d)",
                step_idx, q_idx, api_ok, api_sweep.t, api_sweep.shape, brute_ok, brute_t, brute_shape,
            )

            if api_ok && brute_ok {
                testing.expectf(
                    t,
                    abs(api_sweep.t - brute_t) <= 1e-3,
                    "Step %d sweep_point t mismatch on query %d: api_t=%v vs brute_t=%v (diff=%v)",
                    step_idx, q_idx, api_sweep.t, brute_t, abs(api_sweep.t - brute_t),
                )
                testing.expect(t, base.is_finite_vec(api_sweep.normal))
                nlen := linalg.length(api_sweep.normal)
                testing.expectf(t, abs(nlen - 1.0) <= 1e-2, "Step %d sweep_point non-unit normal %v (len=%v)", step_idx, api_sweep.normal, nlen)
            }
        }

        // 3. Sphere sweep queries: sweep_sphere
        for q_idx in 0..<QUERIES_PER_STEP {
            pos := _random_vec3(-65, 65)
            move := _random_move_vec()
            rad := rand.float32_range(0.02, 4.0)
            range := rand.float32_range(0.1, 80.0)
            ignore_layers := _random_layer_mask()

            api_sweep, api_ok := sweep_sphere(pos, move, rad, range, ignore_layers)

            brute_t := range
            brute_shape: i32 = -1
            brute_ok := false
            for s, idx in step.shape_data[:step.shape_used] {
                if int(s.layer) in ignore_layers {
                    continue
                }
                if hit_t, _, hit := sweep_sphere_vs_shape(pos, move, rad, s, brute_t); hit {
                    brute_t = hit_t
                    brute_shape = i32(idx)
                    brute_ok = true
                }
            }

            testing.expectf(
                t,
                api_ok == brute_ok,
                "Step %d sweep_sphere hit/miss mismatch on query %d: api=%v (t=%v, shape=%d) vs brute=%v (t=%v, shape=%d) pos=%v move=%v rad=%v range=%v",
                step_idx, q_idx, api_ok, api_sweep.t, api_sweep.shape, brute_ok, brute_t, brute_shape, pos, move, rad, range,
            )

            if api_ok && brute_ok {
                testing.expectf(
                    t,
                    abs(api_sweep.t - brute_t) <= 1e-3,
                    "Step %d sweep_sphere t mismatch on query %d: api_t=%v vs brute_t=%v (diff=%v)",
                    step_idx, q_idx, api_sweep.t, brute_t, abs(api_sweep.t - brute_t),
                )
                testing.expect(t, base.is_finite_vec(api_sweep.normal))
                nlen := linalg.length(api_sweep.normal)
                testing.expectf(t, abs(nlen - 1.0) <= 1e-2, "Step %d sweep_sphere non-unit normal %v (len=%v)", step_idx, api_sweep.normal, nlen)
            }
        }
    }
}

_create_random_mesh :: proc(t: ^testing.T, arena: Arena_Handle, alloc: runtime.Allocator, offset_center: bool) -> Mesh_Handle {
    num_tris := 4 + rand.int_max(28)
    verts := make([][3]f32, num_tris * 3, alloc)
    tris := make([][3]u16, num_tris, alloc)

    base_offset := offset_center ? _random_vec3(-8, 8) : [3]f32{0, 0, 0}

    for i in 0..<num_tris {
        c := base_offset + _random_vec3(-2.5, 2.5)
        v0 := c + _random_vec3(-1.2, 1.2)
        v1 := c + _random_vec3(-1.2, 1.2)
        v2 := c + _random_vec3(-1.2, 1.2)
        // Avoid degenerate zero-area triangles in random mesh generator
        if linalg.length2(linalg.cross(v1 - v0, v2 - v0)) < 1e-4 {
            v1 = v0 + {1.0, 0.0, 0.0}
            v2 = v0 + {0.0, 1.0, 0.0}
        }
        verts[i * 3 + 0] = v0
        verts[i * 3 + 1] = v1
        verts[i * 3 + 2] = v2
        tris[i] = {u16(i * 3 + 0), u16(i * 3 + 1), u16(i * 3 + 2)}
    }

    handle, ok := create_mesh(arena, verts, tris)
    testing.expect(t, ok)
    return handle
}

_spawn_random_shape :: proc(meshes: []Mesh_Handle, id: u64) {
    pos := _random_vec3(-50, 50)
    layer := u8(rand.int_max(NUM_LAYERS))
    kind := Shape_Kind(rand.int_max(len(Shape_Kind)))

    switch kind {
    case .Sphere:
        rad := rand.float32_range(0.1, 4.0)
        add_sphere_shape(pos, rad, layer = layer, id = id)

    case .Capsule:
        p1 := pos + _random_vec3(-4.0, 4.0)
        if linalg.length2(p1 - pos) < 1e-4 {
            p1 = pos + {0, 1, 0}
        }
        rad := rand.float32_range(0.1, 2.5)
        add_capsule_shape(pos, p1, rad, layer = layer, id = id)

    case .Aligned_Box:
        ext := _random_vec3(0.2, 4.0)
        rad := rand.float32() < 0.5 ? f32(0.0) : rand.float32_range(0.05, 1.5)
        add_box_shape(pos, ext, rad = rad, layer = layer, id = id)

    case .Oriented_Box:
        ext := _random_vec3(0.2, 4.0)
        rot := _random_quat()
        rad := rand.float32() < 0.5 ? f32(0.0) : rand.float32_range(0.05, 1.5)
        add_oriented_box_shape(pos, ext, rot, rad = rad, layer = layer, id = id)

    case .Mesh:
        handle := meshes[rand.int_max(len(meshes))]
        scale := _random_vec3(0.4, 2.5)
        rot := _random_quat()
        rad := rand.float32() < 0.5 ? f32(0.0) : rand.float32_range(0.05, 1.0)
        add_mesh_shape(handle, pos = pos, scale = scale, rot = rot, rad = rad, layer = layer, id = id)
    }
}

_random_vec3 :: proc(lo, hi: f32) -> [3]f32 {
    return {
        rand.float32_range(lo, hi),
        rand.float32_range(lo, hi),
        rand.float32_range(lo, hi),
    }
}

_random_move_vec :: proc() -> [3]f32 {
    // Include axis-aligned / zero-component directions to exercise slab division edge cases
    for {
        v: [3]f32
        for i in 0..<3 {
            v[i] = rand.float32() < 0.15 ? 0.0 : rand.float32_range(-1.0, 1.0)
        }
        if linalg.length2(v) > 1e-4 {
            return linalg.normalize(v)
        }
    }
}

_random_quat :: proc() -> quaternion128 {
    // Marsaglia / Shoemake uniform unit quaternion
    u1 := rand.float32()
    u2 := rand.float32() * 2.0 * math.PI
    u3 := rand.float32() * 2.0 * math.PI
    s1 := math.sqrt(1.0 - u1)
    s2 := math.sqrt(u1)
    return quaternion(
        x = s1 * math.sin(u2),
        y = s1 * math.cos(u2),
        z = s2 * math.sin(u3),
        w = s2 * math.cos(u3),
    )
}

_random_layer_mask :: proc() -> bit_set[0..<NUM_LAYERS] {
    mask: bit_set[0..<NUM_LAYERS]
    for i in 0..<NUM_LAYERS {
        if rand.float32() < 0.25 {
            mask += {i}
        }
    }
    return mask
}
