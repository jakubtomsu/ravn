#+vet shadowing explicit-allocators
package raven_collision

import "core:math/linalg"
import "base:runtime"
import "../base"
import "../geometry"
import "../bvh"

// TODO: no_bounds_check once stable

_state: ^State

MAX_ARENAS :: #config(COLLISIION_MAX_ARENAS, 64)
MAX_MESHES :: #config(COLLISIION_MAX_MESHES, 1024)
MAX_SHAPES :: #config(COLLISIION_MAX_SHAPES, 1024)
NUM_LAYERS :: #config(COLLISIION_NUM_LAYERS, 64)

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
    init_allocator:     runtime.Allocator,

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
        using _:    struct {
            pos:    [3]f32,
            handle: Mesh_Handle,
        },
        pos_simd:   #simd[4]f32,
    },
    using _: struct #raw_union {
        using _: struct {
            ext:    [3]f32,
            rad:    f32,
        },
        ext_simd:   #simd[4]f32,
    },
    rot:            quaternion128,

    // id:             u64,
    // ignored_layers: bit_set[0..<NUM_LAYERS],
    layer:          u8,
    kind:           Shape_Kind,
}

Shape_Kind :: enum u8 {
    Sphere,
    Aligned_Box,
    Oriented_Box,
    Capsule,
    Mesh,
}

// Sweep query result
Sweep :: struct {
    // Initial
    pos:        [3]f32,
    move:       [3]f32,
    rad:        f32,
    range:      f32,

    t:          f32,
    shape:      i32,
    prim:       i32,

    end:        [3]f32, // Hit point
    normal:     [3]f32,
}

// Test query result
Test :: struct {
    // Initial
    pos:    [3]f32,
    rad:    f32,

    shape:  i32,
    prim:   i32,
}

// Overlap query result
Overlap :: struct {
    pos:    [3]f32,
    rad:    f32,

    shapes: []i32,
}


init :: proc(state: ^State, allocator := context.allocator) {
    _state = state
    _state.init_allocator = allocator
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
    for step in _state.step_data {
        delete(step.tlas.nodes, _state.init_allocator)
        delete(step.tlas.indices, _state.init_allocator)
    }

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
    assert(arena_ok)
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

// NOTE: doesn't clone the data. You must allocate it yourself with the
// specified arena or ensure it's alive for the lifetime of this mesh.
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


sphere_shape :: proc(pos: [3]f32, rad: f32, #any_int layer: u8 = 0) {
    _push_shape({
        kind = .Sphere,
        pos = pos,
        rad = rad,
        ext = 0,
        rot = 1,
        handle = {},
        layer = layer,
    })
}

capsule_shape :: proc(p0, p1: [3]f32, rad: f32, #any_int layer: u8 = 0) {
    _push_shape({
        kind = .Capsule,
        pos = p0,
        ext = p1,
        rad = rad,
        rot = 1,
        handle = {},
        layer = layer,
    })
}

box_shape :: proc(pos: [3]f32, scale: [3]f32, rad: f32 = 0.0, #any_int layer: u8 = 0) {
    _push_shape({
        kind = .Aligned_Box,
        pos = pos,
        rad = rad,
        ext = scale,
        rot = 1,
        handle = {},
        layer = layer,
    })
}

oriented_box_shape :: proc(pos: [3]f32, scale: [3]f32, rot: quaternion128, rad: f32 = 0.0, #any_int layer: u8 = 0) {
    _push_shape({
        kind = .Oriented_Box,
        pos = pos,
        ext = scale,
        rad = rad,
        rot = rot,
        handle = {},
        layer = layer,
    })
}

mesh_shape :: proc(
    handle: Mesh_Handle,
    pos:    [3]f32,
    scale:  [3]f32 = 1,
    rot:    quaternion128 = 1,
    rad:    f32 = 0.0,
    #any_int layer: u8 = 0
) {
    _, ok := get_mesh(handle)
    if !ok {
        base.log_warn("Pushing invalid mesh: %v", handle)
        return
    }
    _push_shape({
        kind = .Mesh,
        pos = pos,
        ext = scale,
        rot = rot,
        rad = rad,
        handle = handle,
        layer = layer,
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
// MARK: Sweep query
//

move_and_slide :: proc(
    pos:            [3]f32,
    vel:            [3]f32,
    delta:          f32,
    rad:            f32,
    ignore_layers:  bit_set[0..<NUM_LAYERS] = {},
    max_iters       := 8,
    bounce:         f32 = 0.05,
    damp:           f32 = 0.01,
    sweep_buf:      []Sweep = nil,
) -> (new_pos: [3]f32, new_vel: [3]f32, num_hits: int) {
    pos := pos
    move := vel * delta
    t: f32 = 0

    for i in 0..<max_iters {
        sweep, sweep_hit := sweep_sphere(pos, move, rad = rad, ignore_layers = ignore_layers)

        if sweep.t < 0.001 {
            move += sweep.normal * 0.001
        } else {
            pos += sweep.move * clamp(sweep.t - 0.001, 0.0, 1.0)
            t += sweep.t
        }

        if sweep_hit {
            solid_move := move - sweep.normal * linalg.dot(move, sweep.normal)
            bounce_move := linalg.reflect(move, sweep.normal)
            move =
                solid_move * (1.0 - bounce) +
                bounce_move * bounce
            move *= 1.0 - damp

            if num_hits < len(sweep_buf) {
                sweep_buf[num_hits] = sweep
                num_hits += 1
            }
        }

        if t >= 1.0 {
            break
        }
    }

    return pos, delta <= 1e-9 ? 0 : move / delta, num_hits
}

@(require_results)
make_sweep :: proc(pos: [3]f32, move: [3]f32, rad: f32 = 0, range: f32 = 1) -> Sweep {
    return {
        pos = pos,
        move = move,
        rad = rad,
        range = range,
        t = range,
        shape = -1,
        prim = -1,
        end = pos + move * range,
        normal = {0, 1, 0},
    }
}

// World raycast
@(require_results)
sweep_point :: proc(
    pos:            [3]f32,
    move:           [3]f32,
    range:          f32 = 1,
    ignore_layers:  bit_set[0..<NUM_LAYERS] = {},
) -> (result: Sweep, ok: bool) #no_bounds_check {
    result = make_sweep(pos, move, rad = 0, range = range)

    step := &_state.step_data[_state.step_read]

    inv_move := 1.0 / move
    inv_move_simd := transmute(#simd[4]f32)inv_move.xyzz
    pos_simd := transmute(#simd[4]f32)pos.xyzz

    for iter := bvh.iter(&step.tlas); iter.node != nil; {
        if iter.len != 0 {
            for offs in 0..<int(iter.len) {
                index := step.tlas.indices[int(iter.first) + offs]
                shape := step.shape_data[index]
                if int(shape.layer) in ignore_layers {
                    continue
                }

                result.t, result.prim = sweep_point_vs_shape(pos, move, shape, result.t) or_continue
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

    eval_sweep(&result)

    return result, ok
}


// World spherecast
@(require_results)
sweep_sphere :: proc(
    pos:            [3]f32,
    move:           [3]f32,
    rad:            f32,
    range:          f32 = 1,
    ignore_layers:  bit_set[0..<NUM_LAYERS] = {},
) -> (result: Sweep, ok: bool) #optional_ok #no_bounds_check {
    result = make_sweep(pos, move, rad = rad, range = range)

    step := &_state.step_data[_state.step_read]

    inv_move := 1.0 / move
    inv_move_simd := transmute(#simd[4]f32)inv_move.xyzz
    pos_simd := transmute(#simd[4]f32)pos.xyzz

    for iter := bvh.iter(&step.tlas); iter.node != nil; {
        if iter.len != 0 {
            for offs in 0..<int(iter.len) {
                index := step.tlas.indices[int(iter.first) + offs]
                shape := step.shape_data[index]
                if int(shape.layer) in ignore_layers {
                    continue
                }

                result.t, result.prim = sweep_sphere_vs_shape(pos, move, rad, shape, result.t) or_continue
                assert(base.is_finite_f32(result.t))
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

    eval_sweep(&result)

    return result, ok
}

eval_sweep :: proc(sweep: ^Sweep) {
    if sweep.shape == -1 {
        return
    }

    step := get_step_state()
    shape := &step.shape_data[sweep.shape]

    sweep.end = sweep.pos + sweep.move * sweep.t
    sweep.normal = get_shape_gradient(shape^, sweep.pos, sweep.end, sweep.prim)
    assert(base.is_finite_vec(sweep.normal))
}



////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Test Query
//
// Checks for *any* collider overlap.
//

@(require_results)
test_sphere :: proc(
    pos:            [3]f32,
    rad:            f32,
    ignore_layers:  bit_set[0..<NUM_LAYERS] = {},
) -> (result: Test, ok: bool) #no_bounds_check {
    result = {
        pos = pos,
        rad = rad,
        shape = -1,
        prim = -1,
    }

    step := &_state.step_data[_state.step_read]

    pos_simd := transmute(#simd[4]f32)pos.xyzz

    for iter := bvh.iter(&step.tlas); iter.node != nil; {
        if iter.len != 0 {
            for offs in 0..<int(iter.len) {
                index := step.tlas.indices[int(iter.first) + offs]
                shape := step.shape_data[index]
                if int(shape.layer) in ignore_layers {
                    continue
                }

                prim, overlaps := test_sphere_vs_shape(pos, rad, shape)
                if overlaps {
                    result.shape = i32(index)
                    result.prim = prim
                    return result, true
                }
            }

            bvh.iter_pop(&iter) or_break

        } else {

            child0 := transmute(bvh.Node_SIMD4)step.tlas.nodes[iter.first + 0]
            child1 := transmute(bvh.Node_SIMD4)step.tlas.nodes[iter.first + 1]
            t0 := geometry.test_point_vs_aabb_simd_single(pos_simd, child0.min - rad, child0.max + rad)
            t1 := geometry.test_point_vs_aabb_simd_single(pos_simd, child1.min - rad, child1.max + rad)

            bvh.iter_unordered_next(&iter, t0, t1) or_break
        }
    }

    return result, ok
}


////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Overlap Query
//
// Returns all overlapping colliders
//


@(require_results)
overlap_sphere :: proc(
    pos:            [3]f32,
    rad:            f32,
    max_overlaps    := 16,
    ignore_layers:  bit_set[0..<NUM_LAYERS] = {},
    allocator       := context.temp_allocator,
) -> (result: Overlap, ok: bool) #optional_ok #no_bounds_check {
    buf := make([]i32, max_overlaps, allocator)
    return overlap_sphere_buf(pos, rad, buf, ignore_layers)
}

@(require_results)
overlap_sphere_buf :: proc(
    pos:            [3]f32,
    rad:            f32,
    shapes:         []i32,
    ignore_layers:  bit_set[0..<NUM_LAYERS] = {},
) -> (result: Overlap, ok: bool) #optional_ok #no_bounds_check {
    assert(len(shapes) > 0)
    result = {
        pos = pos,
        rad = rad,
    }

    step := &_state.step_data[_state.step_read]
    used_shapes := 0
    pos_simd := transmute(#simd[4]f32)pos.xyzz

    node_loop: for iter := bvh.iter(&step.tlas); iter.node != nil; {
        if iter.len != 0 {
            for offs in 0..<int(iter.len) {
                index := step.tlas.indices[int(iter.first) + offs]
                shape := step.shape_data[index]
                if int(shape.layer) in ignore_layers {
                    continue
                }

                _, overlaps := test_sphere_vs_shape(pos, rad, shape)
                if overlaps {
                    shapes[used_shapes] = i32(index)
                    used_shapes += 1
                    if int(used_shapes) >= len(shapes) {
                        break node_loop
                    }
                }
            }

            bvh.iter_pop(&iter) or_break

        } else {

            child0 := transmute(bvh.Node_SIMD4)step.tlas.nodes[iter.first + 0]
            child1 := transmute(bvh.Node_SIMD4)step.tlas.nodes[iter.first + 1]
            t0 := geometry.test_point_vs_aabb_simd_single(pos_simd, child0.min - rad, child0.max + rad)
            t1 := geometry.test_point_vs_aabb_simd_single(pos_simd, child1.min - rad, child1.max + rad)

            bvh.iter_unordered_next(&iter, t0, t1) or_break
        }
    }

    result.shapes = shapes[:used_shapes]
    return result, used_shapes > 0
}




/////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Shape
//


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
collide_sphere_vs_shape :: proc(
    pos:            [3]f32,
    rad:            f32,
    shape:          Shape,
    out_contacts:   [][4]f32,
) -> (num_contacts: i32) {
    assert(len(out_contacts) > 0)

    r := shape.rad + rad

    dist: f32
    grad: [3]f32
    switch shape.kind {
    case .Sphere:
        dist, grad = geometry.get_sphere_dist_grad(pos, shape.pos, r)

    case .Capsule:
        dist, grad = geometry.get_line_dist_grad(pos, {shape.pos, shape.ext})
        dist -= r

    case .Aligned_Box:
        dist, grad = geometry.get_box_dist_grad(pos, shape.pos, r)

    case .Oriented_Box:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, pos - shape.pos)
        dist, grad = geometry.get_box_dist_grad(local_pos, 0, r)

    case .Mesh:
        inv := conj(shape.rot)
        local_pos := linalg.quaternion128_mul_vector3(inv, pos - shape.pos)
        return collide_sphere_vs_mesh_local(local_pos, r, shape.handle, scale = shape.ext, out_contacts = out_contacts)
    }

    if dist > 0 {
        return 0
    }

    out_contacts[0] = {
        grad.x,
        grad.y,
        grad.z,
        dist,
    }

    return 1
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
            t0 := geometry.sweep_point_vs_aabb_simd_single(pos_simd, inv_move_simd, child0.min - rad, child0.max + rad, t) or_else max(f32)
            t1 := geometry.sweep_point_vs_aabb_simd_single(pos_simd, inv_move_simd, child1.min - rad, child1.max + rad, t) or_else max(f32)

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
            hit0 := geometry.test_point_vs_aabb_simd_single(pos_simd, child0.min - rad, child0.max + rad)
            hit1 := geometry.test_point_vs_aabb_simd_single(pos_simd, child1.min - rad, child1.max + rad)

            bvh.iter_unordered_next(&iter, hit0, hit1) or_break
        }
    }

    return -1, false
}

@(require_results)
collide_sphere_vs_mesh_local :: proc(
    pos:            [3]f32,
    rad:            f32,
    handle:         Mesh_Handle,
    scale:          [3]f32 = 1,
    out_contacts:   [][4]f32,
) -> (num_contacts: i32) #no_bounds_check {
    assert(len(out_contacts) > 0)

    mesh, mesh_ok := get_mesh(handle)
    if !mesh_ok {
        return 0
    }

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

                dist, grad := geometry.get_triangle_dist_grad(pos, verts)

                if dist > rad {
                    continue
                }

                dist -= rad

                out_contacts[num_contacts] = {
                    grad.x,
                    grad.y,
                    grad.z,
                    dist,
                }

                num_contacts += 1

                if int(num_contacts) >= len(out_contacts) {
                    break
                }
            }

            bvh.iter_pop(&iter) or_break

        } else {

            child0 := transmute(bvh.Node_SIMD4)mesh.blas.nodes[iter.first + 0]
            child1 := transmute(bvh.Node_SIMD4)mesh.blas.nodes[iter.first + 1]
            hit0 := geometry.test_point_vs_aabb_simd_single(pos_simd, child0.min - rad, child0.max + rad)
            hit1 := geometry.test_point_vs_aabb_simd_single(pos_simd, child1.min - rad, child1.max + rad)

            bvh.iter_unordered_next(&iter, hit0, hit1) or_break
        }
    }

    return num_contacts
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

@(require_results)
get_shape_gradient :: proc(shape: Shape, origin_pos: [3]f32, hit: [3]f32, prim: i32) -> (result: [3]f32) {
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
        if linalg.dot(result, origin_pos - hit) < 0 {
            result = -result
        }

        return result
    }

    return 0
}



/////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Util
//

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
