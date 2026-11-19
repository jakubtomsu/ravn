#+test
#+private file
#+vet shadowing explicit-allocators
package ravn_collision

import "core:math/linalg"
import "core:math/rand"
import "core:slice"
import "core:testing"

@(test)
_test_brute_force_parity :: proc(t: ^testing.T) {
	rng := rand.create(t.seed)
	context.random_generator = rand.default_random_generator(&rng)

	init(nil, context.allocator)
	defer shutdown()

	arena, arena_ok := create_arena(4 * 1024 * 1024, context.allocator)
	testing.expect(t, arena_ok)
	defer destroy_arena(arena)

	arena_alloc := arena_allocator(arena)

	meshes: [4]Mesh_Handle
	for &mesh in meshes {
		num_tris := 4 + rand.int_max(20)
		verts := make([][3]f32, num_tris * 3, arena_alloc)
		tris := make([][3]u16, num_tris, arena_alloc)
		offset := _rand_vec3(-8, 8)
		for tri_idx in 0..<num_tris {
			c := offset + _rand_vec3(-2.5, 2.5)
			v0 := c + _rand_vec3(-1.2, 1.2)
			v1 := c + _rand_vec3(-1.2, 1.2)
			v2 := c + _rand_vec3(-1.2, 1.2)
			if linalg.length2(linalg.cross(v1 - v0, v2 - v0)) < 1e-4 {
				v1 = v0 + {1, 0, 0}
				v2 = v0 + {0, 1, 0}
			}
			verts[tri_idx * 3 + 0] = v0
			verts[tri_idx * 3 + 1] = v1
			verts[tri_idx * 3 + 2] = v2
			tris[tri_idx] = {u16(tri_idx * 3 + 0), u16(tri_idx * 3 + 1), u16(tri_idx * 3 + 2)}
		}
		ok: bool
		mesh, ok = create_mesh(arena, verts, tris)
		testing.expect(t, ok)
	}

	for step_idx in 0..<64 {
		begin_step(rand.float32_range(0.008, 0.06))

		num_shapes := 1 + rand.int_max(min(256, MAX_SHAPES))
		for shape_idx in 0..<num_shapes {
			pos := _rand_vec3(-50, 50)
			layer := u8(rand.int_max(NUM_LAYERS))
			rad := rand.float32() < 0.4 ? f32(0) : rand.float32_range(0.05, 1.5)
			switch Shape_Kind(rand.int_max(len(Shape_Kind))) {
			case .Sphere:
				add_sphere_shape(pos, rand.float32_range(0.1, 4.0), layer = layer, id = u64(shape_idx))
			case .Capsule:
				p1 := pos + _rand_vec3(-4, 4)
				if linalg.length2(p1 - pos) < 1e-4 { p1 = pos + {0, 1, 0} }
				add_capsule_shape(pos, p1, rand.float32_range(0.1, 2.5), layer = layer, id = u64(shape_idx))
			case .Aligned_Box:
				add_box_shape(pos, _rand_vec3(0.2, 4.0), rad = rad, layer = layer, id = u64(shape_idx))
			case .Oriented_Box:
				add_oriented_box_shape(pos, _rand_vec3(0.2, 4.0), _rand_quat(), rad = rad, layer = layer, id = u64(shape_idx))
			case .Mesh:
				add_mesh_shape(meshes[rand.int_max(len(meshes))], pos, _rand_vec3(0.4, 2.5), _rand_quat(), rad = rad, layer = layer, id = u64(shape_idx))
			}
		}

		end_step()

		for q_idx in 0..<64 {
			free_all(context.temp_allocator)

			pos := _rand_vec3(-60, 60)
			rad := rand.float32() < 0.15 ? f32(0) : rand.float32_range(0.05, 6.0)
			move := _rand_dir()
			range := rand.float32_range(0.1, 80.0)

			ignore: bit_set[0..<NUM_LAYERS]
			for bit_idx in 0..<NUM_LAYERS {
				if rand.float32() < 0.25 { ignore += {bit_idx} }
			}

			// test_sphere
			bvh_test, bvh_test_ok := test_sphere(pos, rad, ignore, brute_force = false)
			brute_test, brute_test_ok := test_sphere(pos, rad, ignore, brute_force = true)
			testing.expectf(t, bvh_test_ok == brute_test_ok, "step %d q %d test_sphere ok mismatch", step_idx, q_idx)
			if bvh_test_ok {
				if bvh_test.shape == brute_test.shape {
					testing.expect_value(t, bvh_test.prim, brute_test.prim)
				} else if s, s_ok := get_shape(bvh_test.shape); s_ok {
					_, hit := test_sphere_vs_shape(pos, rad, s)
					testing.expect(t, hit)
				}
			}

			// overlap_sphere
			bvh_ov, bvh_ov_ok := overlap_sphere(pos, rad, MAX_SHAPES, ignore, context.temp_allocator, brute_force = false)
			brute_ov, brute_ov_ok := overlap_sphere(pos, rad, MAX_SHAPES, ignore, context.temp_allocator, brute_force = true)
			testing.expectf(t, bvh_ov_ok == brute_ov_ok, "step %d q %d overlap_sphere ok mismatch", step_idx, q_idx)
			slice.sort(bvh_ov.shapes)
			slice.sort(brute_ov.shapes)
			testing.expectf(t, slice.equal(bvh_ov.shapes, brute_ov.shapes), "step %d q %d overlap_sphere shapes mismatch", step_idx, q_idx)

			// find_contacts_sphere (asserts rad > 1e-6)
			if rad > 1e-3 {
				bvh_ct := find_contacts_sphere(pos, rad, 64, 256, ignore, context.temp_allocator, brute_force = false)
				brute_ct := find_contacts_sphere(pos, rad, 64, 256, ignore, context.temp_allocator, brute_force = true)
				testing.expectf(t, len(bvh_ct) == len(brute_ct), "step %d q %d find_contacts_sphere len mismatch: %d vs %d", step_idx, q_idx, len(bvh_ct), len(brute_ct))
				if len(bvh_ct) == len(brute_ct) {
					slice.sort_by(bvh_ct, _contact_less)
					slice.sort_by(brute_ct, _contact_less)
					for idx in 0..<len(bvh_ct) {
						testing.expect_value(t, bvh_ct[idx].shape, brute_ct[idx].shape)
						testing.expectf(t, abs(bvh_ct[idx].separation - brute_ct[idx].separation) <= 1e-3, "step %d q %d contact separation mismatch", step_idx, q_idx)
						testing.expectf(t, linalg.distance(bvh_ct[idx].normal, brute_ct[idx].normal) <= 1e-3, "step %d q %d contact normal mismatch", step_idx, q_idx)
					}
				}
			}

			// sweep_point
			bvh_pt, bvh_pt_ok := sweep_point(pos, move, range, ignore, brute_force = false)
			brute_pt, brute_pt_ok := sweep_point(pos, move, range, ignore, brute_force = true)
			testing.expectf(t, bvh_pt_ok == brute_pt_ok, "step %d q %d sweep_point ok mismatch", step_idx, q_idx)
			if bvh_pt_ok {
				testing.expectf(t, abs(bvh_pt.t - brute_pt.t) <= 1e-3, "step %d q %d sweep_point t mismatch: %v vs %v", step_idx, q_idx, bvh_pt.t, brute_pt.t)
			}

			// sweep_sphere
			bvh_sp, bvh_sp_ok := sweep_sphere(pos, move, rad, range, ignore, brute_force = false)
			brute_sp, brute_sp_ok := sweep_sphere(pos, move, rad, range, ignore, brute_force = true)
			testing.expectf(t, bvh_sp_ok == brute_sp_ok, "step %d q %d sweep_sphere ok mismatch", step_idx, q_idx)
			if bvh_sp_ok {
				testing.expectf(t, abs(bvh_sp.t - brute_sp.t) <= 1e-3, "step %d q %d sweep_sphere t mismatch: %v vs %v", step_idx, q_idx, bvh_sp.t, brute_sp.t)
			}
		}
	}
}

_contact_less :: proc(a, b: Contact) -> bool {
	if a.shape != b.shape { return a.shape < b.shape }
	if abs(a.separation - b.separation) > 1e-4 { return a.separation < b.separation }
	if abs(a.normal.x - b.normal.x) > 1e-4 { return a.normal.x < b.normal.x }
	if abs(a.normal.y - b.normal.y) > 1e-4 { return a.normal.y < b.normal.y }
	return a.normal.z < b.normal.z
}

_rand_vec3 :: proc(lo, hi: f32) -> [3]f32 {
	return {rand.float32_range(lo, hi), rand.float32_range(lo, hi), rand.float32_range(lo, hi)}
}

_rand_dir :: proc() -> [3]f32 {
	v := [3]f32{
		rand.float32() < 0.15 ? 0 : rand.float32_range(-1, 1),
		rand.float32() < 0.15 ? 0 : rand.float32_range(-1, 1),
		rand.float32() < 0.15 ? 0 : rand.float32_range(-1, 1),
	}
	return linalg.length2(v) > 1e-4 ? linalg.normalize(v) : {1, 0, 0}
}

_rand_quat :: proc() -> quaternion128 {
	v := [4]f32{rand.float32_range(-1, 1), rand.float32_range(-1, 1), rand.float32_range(-1, 1), rand.float32_range(-1, 1)}
	n := linalg.length2(v) > 1e-4 ? linalg.normalize(v) : [4]f32{0, 0, 0, 1}
	return quaternion(x = n.x, y = n.y, z = n.z, w = n.w)
}
