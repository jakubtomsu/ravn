package ravn_collision

import "../geometry"
import "../bvh"
import "core:math/linalg"

@(require_results)
sweep_point_vs_shape :: proc(
    pos:    [3]f32,
    move:   [3]f32,
    shape:  Shape,
    range:  f32,
) -> (t: f32, prim: i32, ok: bool) #no_bounds_check {
    t = range

    switch shape.kind {
    case .Sphere:
        t, ok = geometry.sweep_point_vs_sphere(pos, move, shape.pos, shape.rad, range = range)
        return t, 0, ok

    case .Capsule:
        t, ok = geometry.sweep_point_vs_capsule(pos, move, {shape.pos, shape.ext}, shape.rad, range = range)
        return t, 0, ok

    case .Aligned_Box:
        if shape.rad < NO_RAD_EPS {
            t, ok = geometry.sweep_point_vs_aabb(pos, move, shape.pos - shape.ext, shape.pos + shape.ext, range = range)
        } else {
            t, ok = geometry.sweep_sphere_vs_aabb(pos, move, shape.rad, shape.pos - shape.ext, shape.pos + shape.ext, range = range)
        }
        return t, 0, ok

    case .Oriented_Box:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, pos - shape.pos)
        local_move := linalg.quaternion128_mul_vector3(inv, move)
        if shape.rad < NO_RAD_EPS {
            t, ok = geometry.sweep_point_vs_aabb(local_pos, local_move, -shape.ext, +shape.ext, range = range)
        } else {
            t, ok = geometry.sweep_sphere_vs_aabb(local_pos, local_move, shape.rad, -shape.ext, +shape.ext, range = range)
        }
        return t, 0, ok

    case .Mesh:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, pos - shape.pos)
        local_move := linalg.quaternion128_mul_vector3(inv, move)
        if shape.rad < NO_RAD_EPS {
            inv_scale := 1.0 / shape.ext
            t, prim, ok = sweep_point_vs_mesh_local(
                pos = local_pos * inv_scale,
                move = local_move * inv_scale,
                handle = shape.handle,
                range = range,
            )
        } else {
            t, prim, ok = sweep_sphere_vs_mesh_local(
                pos = local_pos,
                move = local_move,
                rad = shape.rad,
                handle = shape.handle,
                scale = shape.ext,
                range = range,
            )
        }
        return t, prim, ok
    }

    return 0, 0, false
}

@(require_results)
sweep_sphere_vs_shape :: proc(
    pos:    [3]f32,
    move:   [3]f32,
    rad:    f32,
    shape:  Shape,
    range:  f32,
) -> (t: f32, prim: i32, ok: bool) {
    t = range
    r := shape.rad + rad

    if range <= 1e-5 {
        return 0, 0, false
    }

    assert(r > 0)

    switch shape.kind {
    case .Sphere:
        t, ok = geometry.sweep_point_vs_sphere(pos, move, shape.pos, r, range = range)
        return t, 0, ok

    case .Capsule:
        t, ok = geometry.sweep_point_vs_capsule(pos, move, {shape.pos, shape.ext}, r, range = range)
        return t, 0, ok

    case .Aligned_Box:
        t, ok = geometry.sweep_sphere_vs_aabb(pos, move, r, shape.pos - shape.ext, shape.pos + shape.ext, range = range)
        return t, 0, ok

    case .Oriented_Box:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, pos - shape.pos)
        local_move := linalg.quaternion128_mul_vector3(inv, move)
        t, ok = geometry.sweep_sphere_vs_aabb(local_pos, local_move, r, -shape.ext, +shape.ext, range = range)
        return t, 0, ok

    case .Mesh:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, pos - shape.pos)
        local_move := linalg.quaternion128_mul_vector3(inv, move)
        return sweep_sphere_vs_mesh_local(
            pos = local_pos,
            move = local_move,
            rad = r,
            handle = shape.handle,
            scale = shape.ext,
            range = range,
        )
    }

    return 0, 0, false
}

@(require_results)
sweep_point_vs_mesh_local :: proc(
    pos:        [3]f32,
    move:       [3]f32,
    handle:     Mesh_Handle,
    range:      f32 = 1,
) -> (t: f32, prim: i32, ok: bool) #no_bounds_check {
    mesh, mesh_ok := get_mesh(handle)
    if !mesh_ok {
        return range, -1, false
    }

    t = range
    prim = -1

    inv_move := 1.0 / move
    inv_move_simd := transmute(#simd[4]f32)inv_move.xyzz
    pos_simd := transmute(#simd[4]f32)pos.xyzz

    for iter := bvh.iter(&mesh.blas); iter.node != nil; {
        if iter.len != 0 {
            for offs in 0..<int(iter.len) {
                index := mesh.blas.indices[int(iter.first) + offs]
                tri := mesh.triangles[index]
                verts := [3][3]f32{
                    mesh.verts[tri[0]],
                    mesh.verts[tri[1]],
                    mesh.verts[tri[2]],
                }

                t = geometry.sweep_point_vs_triangle(pos, move, verts, t) or_continue
                prim = i32(index)
                ok = true
            }

            bvh.iter_pop(&iter) or_break

        } else {

            child0 := transmute(bvh.Node_SIMD4)mesh.blas.nodes[iter.first + 0]
            child1 := transmute(bvh.Node_SIMD4)mesh.blas.nodes[iter.first + 1]
            t0 := geometry.sweep_point_vs_aabb_simd_single(pos_simd, inv_move_simd, child0.min, child0.max, t) or_else max(f32)
            t1 := geometry.sweep_point_vs_aabb_simd_single(pos_simd, inv_move_simd, child1.min, child1.max, t) or_else max(f32)

            bvh.iter_next(&iter, t0, t1) or_break
        }
    }

    return t, prim, ok
}

@(require_results)
find_contacts_sphere_vs_shape :: proc(
    pos:            [3]f32,
    rad:            f32,
    shape:          Shape,
    out_contacts:   []Contact,
    out_triangles:  []Triangle_Contact, // potential mesh contacts.
) -> (num_contacts: i32, num_triangles: i32) {
    assert(len(out_contacts) > 0)

    r := shape.rad + rad

    assert(r > 0.0001)

    dist: f32
    grad: [3]f32
    switch shape.kind {
    case .Sphere:
        dist, grad = geometry.get_sphere_dist_grad(pos, shape.pos, r)

    case .Capsule:
        dist, grad = geometry.get_line_dist_grad(pos, {shape.pos, shape.ext})
        dist -= r

    case .Aligned_Box:
        dist, grad = geometry.get_box_dist_grad(pos, shape.pos, shape.ext)
        dist -= r

    case .Oriented_Box:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, pos - shape.pos)
        dist, grad = geometry.get_box_dist_grad(local_pos, 0, shape.ext)
        dist -= r
        grad = linalg.quaternion128_mul_vector3(shape.rot, grad)

    case .Mesh:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, pos - shape.pos)
        num_new_triangles := find_potential_contact_triangles_sphere_vs_mesh_local(
            pos = local_pos,
            rad = r,
            handle = shape.handle,
            scale = shape.ext,
            out_triangles = out_triangles[num_triangles:],
        )

        offset := shape.pos
        mat := linalg.matrix3_from_quaternion_f32(shape.rot)

        tris := out_triangles[num_triangles:][:num_new_triangles]
        for &tri in tris {
            for &v in tri.verts {
                v = offset + mat * v
            }
        }

        num_triangles += num_new_triangles

        return 0, num_triangles
    }

    if dist > 0 {
        return 0, 0
    }

    out_contacts[0] = {
        normal = grad,
        separation = dist,
        shape = -1,
    }

    return 1, 0
}


@(require_results)
sweep_sphere_vs_mesh_local :: proc(
    pos:        [3]f32,
    move:       [3]f32,
    rad:        f32,
    handle:     Mesh_Handle,
    scale:      [3]f32 = 1,
    range:      f32 = 1,
) -> (t: f32, prim: i32, ok: bool) #no_bounds_check {
    mesh, mesh_ok := get_mesh(handle)
    if !mesh_ok {
        return range, -1, false
    }

    t = range
    prim = -1

    inv_move := 1.0 / move
    inv_move_simd := transmute(#simd[4]f32)inv_move.xyzz
    pos_simd := transmute(#simd[4]f32)pos.xyzz
    scale_simd := transmute(#simd[4]f32)scale.xyzz

    for iter := bvh.iter(&mesh.blas); iter.node != nil; {
        if iter.len != 0 {
            for offs in 0..<int(iter.len) {
                index := mesh.blas.indices[int(iter.first) + offs]
                tri := mesh.triangles[index]
                verts := [3][3]f32{
                    scale * mesh.verts[tri[0]],
                    scale * mesh.verts[tri[1]],
                    scale * mesh.verts[tri[2]],
                }

                t = geometry.sweep_sphere_vs_triangle(pos, move, rad, verts, t) or_continue
                prim = i32(index)
                ok = true
            }

            bvh.iter_pop(&iter) or_break

        } else {

            child0 := transmute(bvh.Node_SIMD4)mesh.blas.nodes[iter.first + 0]
            child1 := transmute(bvh.Node_SIMD4)mesh.blas.nodes[iter.first + 1]
            t0 := geometry.sweep_point_vs_aabb_simd_single(pos_simd, inv_move_simd, child0.min * scale_simd - rad, child0.max * scale_simd + rad, t) or_else max(f32)
            t1 := geometry.sweep_point_vs_aabb_simd_single(pos_simd, inv_move_simd, child1.min * scale_simd - rad, child1.max * scale_simd + rad, t) or_else max(f32)

            bvh.iter_next(&iter, t0, t1) or_break
        }
    }

    return max(t, 0), prim, ok
}


@(require_results)
test_sphere_vs_mesh_local :: proc(
    pos:        [3]f32,
    rad:        f32,
    handle:     Mesh_Handle,
    scale:      [3]f32 = 1,
) -> (prim: i32, ok: bool) #no_bounds_check {
    mesh, mesh_ok := get_mesh(handle)
    if !mesh_ok {
        return -1, false
    }

    pos_simd := transmute(#simd[4]f32)pos.xyzz
    scale_simd := transmute(#simd[4]f32)scale.xyzz

    for iter := bvh.iter(&mesh.blas); iter.node != nil; {
        if iter.len != 0 {
            for offs in 0..<int(iter.len) {
                index := mesh.blas.indices[int(iter.first) + offs]
                tri := mesh.triangles[index]
                verts := [3][3]f32{
                    scale * mesh.verts[tri[0]],
                    scale * mesh.verts[tri[1]],
                    scale * mesh.verts[tri[2]],
                }

                if geometry.test_sphere_vs_triangle(pos, rad, verts) {
                    return i32(prim), true
                }
            }

            bvh.iter_pop(&iter) or_break

        } else {

            child0 := transmute(bvh.Node_SIMD4)mesh.blas.nodes[iter.first + 0]
            child1 := transmute(bvh.Node_SIMD4)mesh.blas.nodes[iter.first + 1]
            hit0 := geometry.test_point_vs_aabb_simd_single(pos_simd, child0.min * scale_simd - rad, child0.max * scale_simd + rad)
            hit1 := geometry.test_point_vs_aabb_simd_single(pos_simd, child1.min * scale_simd - rad, child1.max * scale_simd + rad)

            bvh.iter_unordered_next(&iter, hit0, hit1) or_break
        }
    }

    return -1, false
}

@(require_results)
find_potential_contact_triangles_sphere_vs_mesh_local :: proc(
    pos:            [3]f32,
    rad:            f32,
    handle:         Mesh_Handle,
    scale:          [3]f32 = 1,
    out_triangles:  []Triangle_Contact,
) -> (num_triangles: i32) #no_bounds_check {
    assert(len(out_triangles) > 0)

    mesh, mesh_ok := get_mesh(handle)
    if !mesh_ok {
        return 0
    }

    pos_simd := transmute(#simd[4]f32)pos.xyzz
    scale_simd := transmute(#simd[4]f32)scale.xyzz

    for iter := bvh.iter(&mesh.blas); iter.node != nil; {
        if iter.len != 0 {
            for offs in 0..<int(iter.len) {
                index := mesh.blas.indices[int(iter.first) + offs]
                tri := mesh.triangles[index]
                verts := [3][3]f32{
                    scale * mesh.verts[tri[0]],
                    scale * mesh.verts[tri[1]],
                    scale * mesh.verts[tri[2]],
                }

                out_triangles[num_triangles].verts = verts
                num_triangles += 1

                if int(num_triangles) >= len(out_triangles) {
                    return num_triangles
                }
            }

            bvh.iter_pop(&iter) or_break

        } else {

            child0 := transmute(bvh.Node_SIMD4)mesh.blas.nodes[iter.first + 0]
            child1 := transmute(bvh.Node_SIMD4)mesh.blas.nodes[iter.first + 1]
            hit0 := geometry.test_point_vs_aabb_simd_single(pos_simd, child0.min * scale_simd - rad, child0.max * scale_simd + rad)
            hit1 := geometry.test_point_vs_aabb_simd_single(pos_simd, child1.min * scale_simd - rad, child1.max * scale_simd + rad)

            bvh.iter_unordered_next(&iter, hit0, hit1) or_break
        }
    }

    return num_triangles
}

@(require_results)
test_sphere_vs_shape :: proc(
    pos:    [3]f32,
    rad:    f32,
    shape:  Shape,
) -> (prim: i32, ok: bool) {
    r := shape.rad + rad

    switch shape.kind {
    case .Sphere:
        return 0, geometry.test_point_vs_sphere(pos, shape.pos, r)

    case .Capsule:
        return 0, geometry.test_point_vs_capsule(pos, {shape.pos, shape.ext}, r)

    case .Aligned_Box:
        return 0, geometry.test_sphere_vs_box(pos, r, shape.pos, shape.ext)

    case .Oriented_Box:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, pos - shape.pos)
        return 0, geometry.test_sphere_vs_box(local_pos, r, 0, shape.ext)

    case .Mesh:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, pos - shape.pos)
        return test_sphere_vs_mesh_local(
            pos = local_pos,
            rad = r,
            handle = shape.handle,
            scale = shape.ext,
        )
    }

    return -1, false
}



@(require_results)
get_shape_aabb :: proc(shape: Shape) -> (bb_min, bb_max: [3]f32) {
    switch shape.kind {
    case .Sphere:
        return shape.pos - shape.rad,
               shape.pos + shape.rad

    case .Aligned_Box:
        return shape.pos - shape.ext - shape.rad,
               shape.pos + shape.ext + shape.rad

    case .Oriented_Box:
        mat := linalg.matrix3_from_quaternion_f32(shape.rot)
        bb_min, bb_max = geometry.get_oriented_box_bounds(shape.pos, shape.ext, mat)
        bb_min -= shape.rad
        bb_max += shape.rad
        return bb_min, bb_max

    case .Capsule:
        return bvh.vec_min(shape.pos, shape.ext) - shape.rad,
               bvh.vec_max(shape.pos, shape.ext) + shape.rad

    case .Mesh:
        mesh, mesh_ok := get_mesh(shape.handle)
        assert(mesh_ok)

        mat := linalg.matrix3_from_quaternion_f32(shape.rot)

        mid := (mesh.bounds_min + mesh.bounds_max) * 0.5
        ext := (mesh.bounds_max - mesh.bounds_min) * 0.5

        bb_min, bb_max =  geometry.get_oriented_box_bounds(
            pos = shape.pos + mat * mid,
            rad = ext * shape.ext,
            rot = mat,
        )

        bb_min -= shape.rad
        bb_max += shape.rad
        return bb_min, bb_max
    }

    assert(false)
    return 0, 0
}

@(require_results)
get_shape_gradient :: proc(shape: Shape, query_origin_pos: [3]f32, hit: [3]f32, prim: i32) -> (result: [3]f32) {
    switch shape.kind {
    case .Sphere:
        return linalg.normalize(hit - shape.pos)

    case .Capsule:
        _, result = geometry.get_line_dist_grad(hit, {shape.pos, shape.ext})
        return result

    case .Aligned_Box:
        _, result = geometry.get_box_dist_grad(hit, shape.pos, shape.ext)
        return result

    case .Oriented_Box:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, hit - shape.pos)
        _, result = geometry.get_box_dist_grad(local_pos, 0, shape.ext)
        result = linalg.quaternion128_mul_vector3(shape.rot, result)
        return result

    case .Mesh:
        mesh, mesh_ok := get_mesh(shape.handle)
        assert(mesh_ok)
        assert(prim >= 0 && prim <= i32(len(mesh.triangles)))

        inv := conj(shape.rot)
        inv_scale := 1.0 / shape.ext
        local_pos := linalg.quaternion128_mul_vector3(inv, hit - shape.pos) * inv_scale

        tri := mesh.triangles[prim]
        verts := [3][3]f32{
            mesh.verts[tri[0]],
            mesh.verts[tri[1]],
            mesh.verts[tri[2]],
        }

        _, result = geometry.get_triangle_dist_grad(local_pos, verts)

        result = linalg.quaternion128_mul_vector3(shape.rot, result)
        if linalg.dot(result, query_origin_pos - hit) < 0 {
            result = -result
        }

        return result
    }

    return 0
}
