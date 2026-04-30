#+vet shadowing explicit-allocators
package raven_collision

import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
import "../base"
import "../geometry"
import "../bvh"

// TODO: no_bounds_check once stable

_state: ^State

MAX_ARENAS :: 64
MAX_MESHES :: 1024
MAX_SHAPES :: 1024

BVH_EPS :: 1e-6
BVH_STACK :: 32

NO_RAD_EPS :: 0.001

Handle_Index :: u16
Handle_Gen :: u8

Handle :: struct {
    index:  Handle_Index,
    gen:    Handle_Gen,
}

Arena_Handle :: distinct Handle
Mesh_Handle :: distinct Handle

Layer :: u8
Layer_Mask :: [4]u64

ID :: u64

State :: struct {
    arena_data:         [MAX_ARENAS]Arena,
    arena_gen:          [MAX_ARENAS]Handle_Gen,
    arena_used:         base.Bit_Pool(MAX_ARENAS),

    mesh_data:          [MAX_MESHES]Mesh,
    mesh_gen:           [MAX_MESHES]Handle_Gen,
    mesh_used:          base.Bit_Pool(MAX_MESHES),

    step_read:          i32,
    step_write:         i32,
    step_data:          [2]Step_State,
}

Step_State :: struct {
    shape_data:     [MAX_SHAPES]Shape,
    shape_used:     i32,
    tlas:           bvh.BVH,
}

// Defines a single scope/lifetime for persistent collider data (meshes)
Arena :: struct {
    data:       []byte,
    used:       i64,
    backing:    runtime.Allocator,
}

Mesh :: struct {
    arena:          Arena_Handle,
    bounds_min:     [3]f32,
    bounds_max:     [3]f32,
    verts:          [][3]f32,
    triangles:      [][3]u16,
    blas:           bvh.BVH,
}

Body :: struct {
    pos:    [3]f32,
    vel:    [3]f32,
}

#assert(size_of(Shape) == 64)
Shape :: struct #all_or_none #align(64) {
    using _: struct #raw_union {
        pos:        [3]f32,
        pos_simd:   #simd[4]f32,
    },
    using _: struct #raw_union {
        ext:        [3]f32,
        ext_simd:   #simd[4]f32,
    },
    rot:    quaternion128,
    rad:    f32,
    handle: Mesh_Handle,
    kind:   Shape_Kind,
}

Shape_Kind :: enum u8 {
    Sphere,
    Aligned_Box,
    Oriented_Box,
    Capsule,
    Mesh,
}

Sweep :: struct {
    t:      f32,
    pos:    [3]f32,
    normal: [3]f32,
    shape:  i32,
    prim:   i32,
}



init :: proc(state: ^State, allocator := context.allocator) {
    _state = state
    base.bit_pool_set_1(&_state.arena_used, 0)
    base.bit_pool_set_1(&_state.mesh_used, 0)

    for &step in _state.step_data {
        bvh.init(&step.tlas,
            prims = nil,
            nodes = runtime.make_aligned([]bvh.Node, bvh.max_nodes_for_prims(MAX_SHAPES), 64, allocator),
            indices = make([]u16, MAX_SHAPES, allocator),
            max_leaf_prims = 1,
        )
    }
}

shutdown :: proc() {
    for arena in _state.arena_data {
        if arena.data != nil {
            delete(arena.data, arena.backing)
        }
    }
}



///////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Step
//

is_step_in_progress :: proc() -> bool {
    return _state.step_read != _state.step_write
}

get_step_state :: proc() -> ^Step_State {
    return &_state.step_data[_state.step_read]
}

begin_step :: proc() {
    if is_step_in_progress() {
        assert(false)
        return
    }

    _state.step_write = 1 - _state.step_write
    step := &_state.step_data[_state.step_write]

    step.shape_used = 0
    step.tlas.nodes_used = 0
    step.tlas.prims = nil
}

end_step :: proc() {
    if !is_step_in_progress() {
        assert(false)
        return
    }

    _state.step_read = _state.step_write
    step := &_state.step_data[_state.step_read]

    prims := make([][2][3]f32, step.shape_used, context.temp_allocator)
    for shape, i in step.shape_data[:step.shape_used] {
        bb_min, bb_max := get_shape_aabb(shape)
        prims[i] = {bb_min, bb_max}
    }

    bvh.init_prims(&step.tlas, prims)

    bvh.build_mid(&step.tlas)

    step.tlas.prims = nil
}



///////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Resources
//

@(require_results)
create_arena :: proc(
    size_in_bytes:  u64,
    allocator       := context.allocator,
    loc             := #caller_location,
) -> (Arena_Handle, bool) #optional_ok {
    assert(_state != nil)

    index, index_ok := base.bit_pool_find_0(_state.arena_used)
    if !index_ok {
        return {}, false
    }

    arena := Arena{
        data = runtime.make_aligned([]byte, size_in_bytes, 4096, allocator = allocator, loc = loc),
        backing = allocator,
        used = 0,
    }

    if arena.data == nil {
        return {}, false
    }

    _state.arena_data[index] = arena
    base.bit_pool_set_1(&_state.arena_used, index)

    return {
        index = Handle_Index(index),
        gen = _state.arena_gen[index],
    }, true
}

destroy_arena :: proc(handle: Arena_Handle) -> bool {
    arena := get_arena(handle) or_return

    delete(arena.data, arena.backing)

    for i in 0..<MAX_MESHES {
        mesh := &_state.mesh_data[i]
        if mesh.arena == handle {
            destroy_mesh(Mesh_Handle{
                index = Handle_Index(i),
                gen = _state.mesh_gen[i],
            })
        }
    }

    return true
}

@(require_results)
arena_allocator :: proc(handle: Arena_Handle) -> runtime.Allocator {
    return {
        procedure = _arena_allocator_proc,
        data = rawptr(uintptr(transmute(u32)handle)),
    }
}

_arena_allocator_proc :: proc(
    allocator_data: rawptr,
    mode:           runtime.Allocator_Mode,
    size:           int,
    alignment:      int,
    old_memory:     rawptr,
    old_size:       int,
    location:       runtime.Source_Code_Location = #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
    handle := transmute(Arena_Handle)u32(uintptr(allocator_data))
    arena, arena_ok := get_arena(handle)
    if !arena_ok {
        return nil, .Invalid_Argument
    }

    switch mode {
    case .Alloc, .Alloc_Non_Zeroed:
        space := len(arena.data) - int(arena.used)
        if size > space {
            return nil, .Out_Of_Memory
        }

        start := uintptr(raw_data(arena.data)) + uintptr(arena.used)
        aligned_start := runtime.align_forward_uintptr(start, uintptr(alignment))

        data := transmute([]byte)runtime.Raw_Slice{
            data = rawptr(aligned_start),
            len = size,
        }

        total_allocated := i64(size) + i64(aligned_start) - i64(start)
        arena.used += total_allocated

        return data, nil

    case .Free_All:
        arena.used = 0
        return nil, nil

    case .Query_Features:
        set := (^runtime.Allocator_Mode_Set)(old_memory)
        if set != nil {
            set^ = {.Alloc, .Alloc_Non_Zeroed, .Free_All, .Query_Features}
        }
        return nil, nil

    case .Free, .Resize, .Resize_Non_Zeroed, .Query_Info:
        return nil, .Mode_Not_Implemented

    }

    return nil, .Invalid_Argument
}

@(require_results)
get_arena :: proc(handle: Arena_Handle) -> (^Arena, bool) {
    if handle.index <= 0 || handle.index > MAX_ARENAS {
        return nil, false
    }

    if _state.arena_gen[handle.index] != handle.gen {
        return nil, false
    }

    return &_state.arena_data[handle.index], true
}

@(require_results)
get_mesh :: proc(handle: Mesh_Handle) -> (^Mesh, bool) {
    if handle.index <= 0 || handle.index > MAX_MESHES {
        return nil, false
    }

    if _state.mesh_gen[handle.index] != handle.gen {
        return nil, false
    }

    return &_state.mesh_data[handle.index], true
}

@(require_results)
create_mesh :: proc(
    arena_handle:   Arena_Handle,
    verts:          [][3]f32,
    triangles:      [][3]u16,
) -> (Mesh_Handle, bool) #optional_ok {
    assert(_state != nil)

    _, arena_ok := get_arena(arena_handle)
    if !arena_ok {
        return {}, false
    }

    index, index_ok := base.bit_pool_find_0(_state.mesh_used)
    if !index_ok {
        return {}, false
    }

    allocator := arena_allocator(arena_handle)

    // NOTE: is this necessary?
    cloned_verts := clone_slice(verts, 64, allocator)
    cloned_triangles := clone_slice(triangles, 64, allocator)

    vert_tri := make([]u16, len(verts), allocator)
    tri_bbs := make([][2][3]f32, len(triangles), context.temp_allocator)

    for tri, tri_index in triangles {
        v := [3][3]f32{
            verts[tri[0]],
            verts[tri[1]],
            verts[tri[2]],
        }

        tri_bbs[tri_index] = {
            bvh.vec_min(v[0], bvh.vec_min(v[1], v[2])) - BVH_EPS,
            bvh.vec_max(v[0], bvh.vec_max(v[1], v[2])) + BVH_EPS,
        }

        for index in tri {
            assert(int(index) < len(verts))

            vert_tri[index] = u16(tri_index)
        }
    }

    base.log_debug("Creating collision mesh with %i verts and %i tris", len(verts), len(triangles))

    mesh: Mesh = {
        arena = arena_handle,
        verts = verts,
        bounds_min = max(f32),
        bounds_max = min(f32),
        triangles = triangles,
    }

    bvh.init(&mesh.blas,
        prims = tri_bbs,
        nodes = runtime.make_aligned([]bvh.Node, bvh.max_nodes_for_prims(len(triangles)), 64, allocator),
        indices = make([]u16, len(triangles), allocator),
        max_leaf_prims = 4,
    )

    bvh.build_binned(&mesh.blas, num_bins = bvh.MAX_BINS)

    for vert in verts {
        mesh.bounds_min = linalg.min(mesh.bounds_min, vert)
        mesh.bounds_max = linalg.max(mesh.bounds_max, vert)
    }

    _state.mesh_data[index] = mesh
    base.bit_pool_set_1(&_state.mesh_used, index)

    return {
        index = Handle_Index(index),
        gen = _state.arena_gen[index],
    }, true
}


destroy_mesh :: proc(handle: Mesh_Handle) -> bool {
    unimplemented()
}



////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Collider submission
//


sphere_shape :: proc(pos: [3]f32, rad: f32) {
    _push_shape({
        kind = .Sphere,
        pos = pos,
        rad = rad,
        ext = 0,
        rot = 1,
        handle = {},
    })
}

capsule_shape :: proc(p0, p1: [3]f32, rad: f32) {
    _push_shape({
        kind = .Capsule,
        pos = p0,
        ext = p1,
        rad = rad,
        rot = 1,
        handle = {},
    })
}

box_shape :: proc(pos: [3]f32, scale: [3]f32, rad: f32 = 0.0) {
    _push_shape({
        kind = .Aligned_Box,
        pos = pos,
        rad = rad,
        ext = scale,
        rot = 1,
        handle = {},
    })
}

oriented_box_shape :: proc(pos: [3]f32, scale: [3]f32, rot: quaternion128, rad: f32 = 0.0) {
    _push_shape({
        kind = .Oriented_Box,
        pos = pos,
        ext = scale,
        rad = rad,
        rot = rot,
        handle = {},
    })
}

mesh_shape :: proc(
    handle: Mesh_Handle,
    pos:    [3]f32,
    scale:  [3]f32 = 1,
    rot:    quaternion128 = 1,
    rad:    f32 = 0.0,
) {
    _, ok := get_mesh(handle)
    if !ok {
        return
    }
    _push_shape({
        kind = .Mesh,
        pos = pos,
        ext = scale,
        rot = rot,
        rad = rad,
        handle = handle,
    })
}

_push_shape :: proc(shape: Shape) {
    assert(is_step_in_progress())
    step := &_state.step_data[_state.step_write]

    if step.shape_used >= len(step.shape_data) {
        return
    }

    index := step.shape_used
    step.shape_data[index] = shape
    step.shape_used += 1
}



////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Sweep queries
//

// World raycast
@(require_results)
sweep_point :: proc(
    pos:    [3]f32,
    move:   [3]f32,
    range:  f32 = 1,
) -> (result: Sweep, ok: bool) #no_bounds_check {
    result.t = range

    step := &_state.step_data[_state.step_read]

    inv_move := 1.0 / move
    inv_move_simd := transmute(#simd[4]f32)inv_move.xyzz
    pos_simd := transmute(#simd[4]f32)pos.xyzz

    for iter := bvh.iter(&step.tlas); iter.node != nil; {
        if iter.len != 0 {
            for offs in 0..<int(iter.len) {
                index := step.tlas.indices[int(iter.first) + offs]
                shape := step.shape_data[index]

                t := sweep_point_vs_shape(pos, move, shape, result.t) or_continue

                result.t = t
                result.shape = i32(index)
                ok = true
            }

            bvh.iter_pop(&iter) or_break

        } else {

            child0 := transmute(bvh.Node_SIMD4)step.tlas.nodes[iter.first + 0]
            child1 := transmute(bvh.Node_SIMD4)step.tlas.nodes[iter.first + 1]
            t0 := geometry.sweep_point_vs_aabb_simd_single(pos_simd, inv_move_simd, child0.min, child0.max, result.t) or_else max(f32)
            t1 := geometry.sweep_point_vs_aabb_simd_single(pos_simd, inv_move_simd, child1.min, child1.max, result.t) or_else max(f32)

            bvh.iter_next(&iter, t0, t1) or_break
        }
    }

    return result, ok
}


// World spherecast
@(require_results)
sweep_sphere :: proc(
    pos:    [3]f32,
    move:   [3]f32,
    rad:    f32,
    range:  f32 = 1,
) -> (result: Sweep, ok: bool) #no_bounds_check {
    result.t = range

    step := &_state.step_data[_state.step_read]

    inv_move := 1.0 / move
    inv_move_simd := transmute(#simd[4]f32)inv_move.xyzz
    pos_simd := transmute(#simd[4]f32)pos.xyzz

    for iter := bvh.iter(&step.tlas); iter.node != nil; {
        if iter.len != 0 {
            for offs in 0..<int(iter.len) {
                index := step.tlas.indices[int(iter.first) + offs]
                shape := step.shape_data[index]

                result.t = sweep_sphere_vs_shape(pos, move, rad, shape, result.t) or_continue
                result.shape = i32(index)
                ok = true
            }

            bvh.iter_pop(&iter) or_break

        } else {

            child0 := transmute(bvh.Node_SIMD4)step.tlas.nodes[iter.first + 0]
            child1 := transmute(bvh.Node_SIMD4)step.tlas.nodes[iter.first + 1]
            t0 := geometry.sweep_point_vs_aabb_simd_single(pos_simd, inv_move_simd, child0.min - rad, child0.max + rad, result.t) or_else max(f32)
            t1 := geometry.sweep_point_vs_aabb_simd_single(pos_simd, inv_move_simd, child1.min - rad, child1.max + rad, result.t) or_else max(f32)

            bvh.iter_next(&iter, t0, t1) or_break
        }
    }

    return result, ok
}

sweep_point_vs_shape :: proc(
    pos:    [3]f32,
    move:   [3]f32,
    shape:  Shape,
    range:  f32,
) -> (t: f32, ok: bool) #optional_ok #no_bounds_check {
    t = range

    switch shape.kind {
    case .Sphere:
        return geometry.sweep_point_vs_sphere(pos, move, shape.pos, shape.rad, range = range)

    case .Capsule:
        return geometry.sweep_point_vs_capsule(pos, move, {shape.pos, shape.ext}, shape.rad, range = range)

    case .Aligned_Box:
        if shape.rad < NO_RAD_EPS {
            return geometry.sweep_point_vs_aabb(pos, move, shape.pos - shape.ext, shape.pos + shape.ext, range = range)
        } else {
            return geometry.sweep_sphere_vs_aabb(pos, move, shape.rad, shape.pos - shape.ext, shape.pos + shape.ext, range = range)
        }

    case .Oriented_Box:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, pos - shape.pos)
        local_move := linalg.quaternion128_mul_vector3(inv, move)
        if shape.rad < NO_RAD_EPS {
            return geometry.sweep_point_vs_aabb(local_pos, local_move, -shape.ext, +shape.ext, range = range)
        } else {
            return geometry.sweep_sphere_vs_aabb(local_pos, local_move, shape.rad, -shape.ext, +shape.ext, range = range)
        }

    case .Mesh:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, pos - shape.pos)
        local_move := linalg.quaternion128_mul_vector3(inv, move)
        prim: int
        if shape.rad < NO_RAD_EPS {
            t, prim, ok = sweep_point_vs_mesh_local(
                pos = local_pos,
                move = local_move,
                handle = shape.handle,
                range = range,
            )
        } else {
            inv_scale := 1.0 / shape.ext
            t, prim, ok = sweep_sphere_vs_mesh_local(
                pos = local_pos * inv_scale,
                move = local_move * inv_scale,
                rad = shape.rad,
                handle = shape.handle,
                scale = shape.ext,
                range = range,
            )
        }
        return t, ok
    }

    return 0, false
}

sweep_sphere_vs_shape :: proc(
    pos:    [3]f32,
    move:   [3]f32,
    rad:    f32,
    shape:  Shape,
    range:  f32,
) -> (t: f32, ok: bool) #optional_ok {
    t = range

    r := shape.rad + rad

    switch shape.kind {
    case .Sphere:
        return geometry.sweep_point_vs_sphere(pos, move, shape.pos, r, range = range)

    case .Capsule:
        return geometry.sweep_point_vs_capsule(pos, move, {shape.pos, shape.ext}, r, range = range)

    case .Aligned_Box:
        return geometry.sweep_sphere_vs_aabb(pos, move, r, shape.pos - shape.ext, shape.pos + shape.ext, range = range)

    case .Oriented_Box:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, pos - shape.pos)
        local_move := linalg.quaternion128_mul_vector3(inv, move)
        return geometry.sweep_sphere_vs_aabb(local_pos, local_move, r, -shape.ext, +shape.ext, range = range)

    case .Mesh:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, pos - shape.pos)
        local_move := linalg.quaternion128_mul_vector3(inv, move)
        prim: int
        t, prim, ok = sweep_sphere_vs_mesh_local(
            pos = local_pos,
            move = local_move,
            rad = r,
            handle = shape.handle,
            scale = shape.ext,
            range = range,
        )
        return t, ok
    }

    return 0, false
}


@(require_results)
sweep_point_vs_mesh_local :: proc(
    pos:        [3]f32,
    move:       [3]f32,
    handle:     Mesh_Handle,
    range:      f32 = 1,
) -> (t: f32, prim: int, ok: bool) #no_bounds_check {
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
                prim = int(index)
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
sweep_sphere_vs_mesh_local :: proc(
    pos:        [3]f32,
    move:       [3]f32,
    rad:        f32,
    handle:     Mesh_Handle,
    scale:      [3]f32 = 1,
    range:      f32 = 1,
) -> (t: f32, prim: int, ok: bool) #no_bounds_check {
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
                    scale * mesh.verts[tri[0]],
                    scale * mesh.verts[tri[1]],
                    scale * mesh.verts[tri[2]],
                }

                t = geometry.sweep_sphere_vs_triangle(pos, move, rad, verts, t) or_continue
                prim = int(index)
                ok = true
            }

            bvh.iter_pop(&iter) or_break

        } else {

            child0 := transmute(bvh.Node_SIMD4)mesh.blas.nodes[iter.first + 0]
            child1 := transmute(bvh.Node_SIMD4)mesh.blas.nodes[iter.first + 1]
            t0 := geometry.sweep_point_vs_aabb_simd_single(pos_simd, inv_move_simd, child0.min - rad, child0.max + rad, t) or_else max(f32)
            t1 := geometry.sweep_point_vs_aabb_simd_single(pos_simd, inv_move_simd, child1.min - rad, child1.max + rad, t) or_else max(f32)

            bvh.iter_next(&iter, t0, t1) or_break
        }
    }

    return max(t, 0), prim, ok
}



// MARK: Util

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
        return geometry.get_oriented_box_bounds(shape.pos, shape.ext, mat)

    case .Capsule:
        return bvh.vec_min(shape.pos, shape.ext) - shape.rad,
               bvh.vec_max(shape.pos, shape.ext) + shape.rad

    case .Mesh:
        mesh, mesh_ok := get_mesh(shape.handle)
        assert(mesh_ok)

        mat := linalg.matrix3_from_quaternion_f32(shape.rot)

        mid := (mesh.bounds_min + mesh.bounds_max) * 0.5
        ext := (mesh.bounds_max - mesh.bounds_min) * 0.5

        return geometry.get_oriented_box_bounds(
            pos = shape.pos + mat * mid,
            rad = ext * shape.ext + shape.rad,
            rot = mat,
        )
    }

    assert(false)
    return 0, 0
}

get_mesh_triangle :: proc(handle: Mesh_Handle, #any_int tri_index: int) -> (verts: [3][3]f32, ok: bool) #optional_ok {
    mesh := get_mesh(handle) or_return
    if tri_index < 0 || tri_index >= len(mesh.triangles) {
        return {}, false
    }

    tri := mesh.triangles[tri_index]

    return {
        mesh.verts[tri[0]],
        mesh.verts[tri[1]],
        mesh.verts[tri[1]],
    }, true
}



@(require_results)
clone_slice :: proc(a: $T/[]$E, align: int, allocator := context.allocator, loc := #caller_location) -> ([]E, bool) #optional_ok {
    d, err := runtime.make_aligned([]E, len(a), align, allocator, loc)
    copy(d[:], a)
    return d, err == nil
}
