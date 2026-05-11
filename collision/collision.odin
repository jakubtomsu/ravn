#+vet shadowing explicit-allocators
package ravn_collision

import "base:intrinsics"
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
PENETRATION_SOLVER_CORRECTION_FACTOR :: 0.1

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
    delta:          f32,
    beta:           f32,
    shape_used:     i32,
    tlas:           bvh.BVH,
    shape_data:     [MAX_SHAPES]Shape,
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

Contact :: struct {
    normal:     [3]f32,
    separation: f32, // distance
    shape:      i32,
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

begin_step :: proc(delta: f32) {
    if is_step_in_progress() {
        assert(false)
        return
    }

    _state.step_write = 1 - _state.step_write
    step := &_state.step_data[_state.step_write]

    step.delta = clamp(delta, 0.008, 0.06)
    step.beta = PENETRATION_SOLVER_CORRECTION_FACTOR / step.delta

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
    _add_shape({
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
    _add_shape({
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
    _add_shape({
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
    _add_shape({
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
    _add_shape({
        kind = .Mesh,
        pos = pos,
        ext = scale,
        rot = rot,
        rad = rad,
        handle = handle,
        layer = layer,
    })
}

_add_shape :: proc(shape: Shape) {
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
// MARK: Queries
//

// Immediate-mode discrete collision.
collide_sphere :: proc(
    pos:            [3]f32,
    vel:            [3]f32,
    rad:            f32,
    ignore_layers:  bit_set[0..<NUM_LAYERS] = {},
    max_contacts    := 8,
    max_triangles   := 32,
    allocator       := context.temp_allocator,
) -> (new_pos: [3]f32, new_vel: [3]f32, contacts: []Contact) {
    new_vel = vel

    step := get_step_state()

    contacts = find_contacts_sphere(
        pos = pos,
        rad = rad,
        max_contacts = max_contacts,
        max_triangles = max_triangles,
        allocator = allocator,
    )

    if len(contacts) == 0 {
        return pos + vel * step.delta, vel, nil
    }

    ITERS :: 2
    for _ in 0..<ITERS {
        for contact in contacts {
            shape := &step.shape_data[contact.shape]

            normal_mass: f32 = 1.0 // / (1.0 / mass + 1.0 / shape.mass)
            // normal_vel := dot(vel - shape.vel, contact.normal)

            bias := step.beta * min(0.0, contact.separation * 0.5)
            normal_vel := -linalg.dot(new_vel, contact.normal)

            impulse := max(0, normal_vel - bias) * normal_mass

            new_vel += contact.normal * impulse
        }
    }

    new_pos = pos + new_vel * step.delta

    return new_pos, new_vel, contacts
}



// Immediate-mode continous shape-swept collision
collide_sphere_swept :: proc(
    pos:            [3]f32,
    vel:            [3]f32,
    rad:            f32,
    ignore_layers:  bit_set[0..<NUM_LAYERS] = {},
    max_sweeps      := 4,
) -> (new_pos: [3]f32, new_vel: [3]f32) {
    pos := pos
    vel := vel

    step := get_step_state()
    range := linalg.length(vel * step.delta)

    for i in 0..<max_sweeps {
        pos, vel, _ = collide_sphere(pos, vel, rad, ignore_layers, allocator = context.temp_allocator)

        dir := linalg.normalize0(vel)

        if dir == 0 || range < rad {
            pos += dir * range
            return pos, vel
        }

        sweep, sweep_hit := sweep_sphere(pos, move = dir, rad = rad, range = range, ignore_layers = ignore_layers)

        if !sweep_hit {
            pos += dir * range
            return pos, vel
        }

        pos += dir * max(sweep.t - 0.001, 0.0)
        range -= sweep.t

        vel -= sweep.normal * linalg.dot(vel, sweep.normal)

        if range <= 0.001 {
            break
        }
    }

    pos, vel, _ = collide_sphere(pos, vel, rad, ignore_layers, allocator = context.temp_allocator)

    return pos, vel
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



// Checks for *any* collider overlap.
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


// Returns all overlapping colliders
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

Triangle_Contact :: struct {
    verts:  [3][3]f32,
    shape:  i32,
}

@(require_results)
find_contacts_sphere :: proc(
    pos:            [3]f32,
    rad:            f32,
    max_contacts    := 8,
    max_triangles   := 32,
    ignore_layers:  bit_set[0..<NUM_LAYERS] = {},
    allocator       := context.temp_allocator,
) -> (result_contacts: []Contact) #no_bounds_check {
    contacts := make([]Contact, max_contacts, allocator)
    triangles := make([]Triangle_Contact, max_triangles, allocator)

    num_contacts, num_triangles := find_contacts_sphere_buf(
        pos = pos,
        rad = rad,
        out_contacts = contacts,
        out_triangles = triangles,
        ignore_layers = ignore_layers,
    )

    num_tri_contacts := generate_filtered_sphere_vs_triangle_contacts(
        pos = pos,
        rad = rad,
        out_contacts = contacts[num_contacts:],
        triangles = triangles[:num_triangles],
    )

    num_contacts += num_tri_contacts

    return contacts[:num_contacts]
}

@(require_results)
find_contacts_sphere_buf :: proc(
    pos:            [3]f32,
    rad:            f32,
    out_contacts:   []Contact,
    out_triangles:  []Triangle_Contact,
    ignore_layers:  bit_set[0..<NUM_LAYERS] = {},
) -> (num_contacts: i32, num_triangles: i32) #no_bounds_check {
    assert(len(out_contacts) > 0)

    step := &_state.step_data[_state.step_read]
    pos_simd := transmute(#simd[4]f32)pos.xyzz

    node_loop: for iter := bvh.iter(&step.tlas); iter.node != nil; {
        if iter.len != 0 {
            for offs in 0..<int(iter.len) {
                index := step.tlas.indices[int(iter.first) + offs]
                shape := step.shape_data[index]
                if int(shape.layer) in ignore_layers {
                    continue
                }

                num_new_contacts, num_new_triangles := find_contacts_sphere_vs_shape(
                    pos = pos,
                    rad = rad,
                    shape = shape,
                    out_contacts = out_contacts[num_contacts:],
                    out_triangles = out_triangles[num_triangles:],
                )

                contacts := out_contacts[num_contacts:][:num_new_contacts]
                tris := out_triangles[:num_triangles][:num_new_triangles]

                for &c in contacts {
                    c.shape = i32(index)
                }

                for &t in tris {
                    t.shape = i32(index)
                }

                num_contacts += num_new_contacts
                num_triangles += num_new_triangles

                if
                    int(num_contacts) >= len(out_contacts) &&
                    int(num_triangles) >= len(out_triangles)
                {
                    break node_loop
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

    return num_contacts, num_triangles
}

// https://www.codercorner.com/MeshContacts.pdf
@(require_results)
generate_filtered_sphere_vs_triangle_contacts :: proc(
    pos:            [3]f32,
    rad:            f32,
    out_contacts:   []Contact,
    triangles:      []Triangle_Contact,
) -> (num_contacts: i32) {
    assert(rad > 1e-6)

    Feature :: struct {
        rel:        [3]f32,
        kind:       geometry.Voronoi_Feature_Kind,
        index:      u8,
    }

    Sort_Info :: struct {
        index:      i32,
        dist_sq:    f32,
    }

    sort_info := make([]Sort_Info, len(triangles), context.temp_allocator)
    features := make([]Feature, len(triangles), context.temp_allocator)

    num_tris := 0
    rad_sq := rad * rad

    for tri, i in triangles {
        closest, feature_kind, feature_index := geometry.get_triangle_closest_point(pos, tri.verts)
        rel := pos - closest
        dist_sq := linalg.length2(rel)

        if dist_sq > rad_sq {
            continue
        }

        // Backface culling
        // if feature_kind == .Face && linalg.dot(linalg.cross(tri[1] - tri[0], tri[2] - tri[0]), rel) < 0 {
        //     continue
        // }

        features[i] = {
            index = u8(feature_index),
            kind = feature_kind,
            rel = rel,
        }

        sort_info[num_tris] = {
            index = i32(i),
            dist_sq = max(1e-6, dist_sq),
        }
        num_tris += 1
    }

    #assert(size_of(Sort_Info) == size_of(u64))
    _insertion_sort(transmute([]u64)(sort_info[:num_tris]))

    void_set: [128][3]f32
    void_len: i32

    inv_rad := 1.0 / rad
    void_loop: for sort in sort_info[:num_tris] {
        feature := features[sort.index]
        tri := triangles[sort.index]

        switch feature.kind {
        case .Face:
            // never voided

        case .Edge:
            vert0 := tri.verts[feature.index == 2 ? 1 : 0]
            vert1 := tri.verts[feature.index == 0 ? 1 : 2]
            for v in void_set[:void_len] {
                if vert0 == v || vert1 == v {
                    continue void_loop
                }
            }

        case .Vertex:
            vert := tri.verts[feature.index]
            for v in void_set[:void_len] {
                if vert == v {
                    continue void_loop
                }
            }
        }


        dist := intrinsics.sqrt(sort.dist_sq)
        out_contacts[num_contacts] = Contact{
            normal = feature.rel / dist,
            separation = dist - rad,
            shape = tri.shape,
        }

        num_contacts += 1

        vert_loop: for vert in tri.verts {
            for v in void_set[:void_len] {
                if vert == v {
                    continue vert_loop
                }
            }
            void_set[void_len] = vert
            void_len += 1
        }
    }

    return num_contacts
}

_insertion_sort :: proc "contextless" (data: $T/[]$E) #no_bounds_check {
    // Insert right-to-left into the already sorted part of the array
    for i in 1..<len(data) {
        val := data[i]
        j := i
        for ; j > 0 && data[j - 1] > val; j -= 1 {
            data[j] = data[j - 1]
        }
        data[j] = val
    }
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
