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

BVH_EPS :: 1e-6
BVH_STACK :: 32

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
    arena_data:     [MAX_ARENAS]Arena,
    arena_gen:      [MAX_ARENAS]Handle_Gen,
    arena_used:     base.Bit_Pool(MAX_ARENAS),

    mesh_data:      [MAX_MESHES]Mesh,
    mesh_gen:       [MAX_MESHES]Handle_Gen,
    mesh_used:      base.Bit_Pool(MAX_MESHES),
}

// Defines a single scope/lifetime for persistent collider data (meshes)
Arena :: struct {
    data:       []byte,
    used:       i64,
    backing:    runtime.Allocator,
}

LANES :: geometry.LANES

Mesh :: struct {
    arena:          Arena_Handle,
    bounds_min:     [3]f32,
    bounds_max:     [3]f32,
    verts:          [][3]f32,
    triangles:      [][3]u16,
    edges:          [][2]u16,
    vert_tri:       []u16,
    edge_tri:       []u16,
    blas:           bvh.BVH,
}

init :: proc(state: ^State) {
    _state = state
    base.bit_pool_set_1(&_state.arena_used, 0)
    base.bit_pool_set_1(&_state.mesh_used, 0)
}

shutdown :: proc() {
    for arena in _state.arena_data {
        if arena.data != nil {
            delete(arena.data, arena.backing)
        }
    }
}


// Resources

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

    cloned_verts := clone_slice(verts, 64, allocator)
    cloned_triangles := clone_slice(triangles, 64, allocator)

    // Find de-duplicated triangle edges and fill primitive mapping buffers

    vert_tri := make([]u16, len(verts), allocator)

    tri_bbs := make([][2][3]f32, len(triangles), context.temp_allocator)

    edge_map := make(map[[2]u16]u16, len(triangles) * 2, context.temp_allocator)

    for tri, tri_index in triangles {
        _insert_edge(&edge_map, tri[0], tri[1], u16(tri_index))
        _insert_edge(&edge_map, tri[0], tri[2], u16(tri_index))
        _insert_edge(&edge_map, tri[1], tri[2], u16(tri_index))

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

    edges := make([][2]u16, len(edge_map), allocator)
    edge_tri := make([]u16, len(edges), allocator)

    edge_index := 0
    for key, val in edge_map {
        edges[edge_index] = key
        edge_tri[edge_index] = val
        edge_index += 1
    }

    base.log_debug("Creating collision mesh with %i verts, %i edges, %i tris", len(verts), len(edges), len(triangles))

    mesh: Mesh = {
        arena = arena_handle,
        verts = verts,
        bounds_min = max(f32),
        bounds_max = min(f32),
        triangles = triangles,
        edges = edges,
        edge_tri = edge_tri,
        vert_tri = vert_tri,
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

    _insert_edge :: proc(m: ^map[[2]u16]u16, a, b: u16, tri_index: u16) {
        pair := [2]u16{
            min(a, b),
            max(a, b)
        }
        m[pair] = tri_index
    }
}


destroy_mesh :: proc(handle: Mesh_Handle) -> bool {
    unimplemented()
}


// Immediate-mode collider submission

collide_sphere :: proc()
collide_capsule :: proc()
collide_aabb :: proc()
collide_mesh :: proc()


// Queries

Sweep :: struct {
    t:      f32,
    hit:    [3]f32,
    normal: [3]f32,
    prim:   i32,
}

// Raycast vs world
sweep_point :: proc()
sweep_sphere :: proc()

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


    node := &mesh.blas.nodes[0]
    stack: [BVH_STACK]^bvh.Node
    stack_curr := 0

    for {
        if node.len != 0 {
            for offs in 0..<int(node.len) {
                index := mesh.blas.indices[int(node.first) + offs]
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

            if stack_curr == 0 {
                break
            }

            stack_curr -= 1
            node = stack[stack_curr]

            continue
        }

        child0 := &mesh.blas.nodes[node.first + 0]
        child1 := &mesh.blas.nodes[node.first + 1]

        t0 := geometry.sweep_point_vs_aabb(pos, move, child0.min, child0.max, t) or_else max(f32)
        t1 := geometry.sweep_point_vs_aabb(pos, move, child1.min, child1.max, t) or_else max(f32)

        if t0 > t1 {
            t0, t1 = t1, t0
            child0, child1 = child1, child0
        }

        if t0 == max(f32) {
            if stack_curr == 0 {
                break
            }

            stack_curr -= 1
            node = stack[stack_curr]
        } else {
            node = child0
            if t1 != max(f32) {
                stack[stack_curr] = child1
                stack_curr += 1
            }
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
    range:      f32 = 1,
) -> (t: f32, prim: int, ok: bool) #no_bounds_check {
    mesh, mesh_ok := get_mesh(handle)
    if !mesh_ok {
        return range, -1, false
    }

    t = range
    prim = -1

    node := &mesh.blas.nodes[0]
    stack: [BVH_STACK]^bvh.Node
    stack_curr := 0

    for {
        if node.len != 0 {
            for offs in 0..<int(node.len) {
                index := mesh.blas.indices[int(node.first) + offs]
                tri := mesh.triangles[index]
                verts := [3][3]f32{
                    mesh.verts[tri[0]],
                    mesh.verts[tri[1]],
                    mesh.verts[tri[2]],
                }

                t = geometry.sweep_sphere_vs_triangle(pos, move, rad, verts, t) or_continue
                prim = int(index)
                ok = true
            }

            if stack_curr == 0 {
                break
            }

            stack_curr -= 1
            node = stack[stack_curr]

            continue
        }

        child0 := &mesh.blas.nodes[node.first + 0]
        child1 := &mesh.blas.nodes[node.first + 1]

        t0 := geometry.sweep_point_vs_aabb(pos, move, child0.min - rad, child0.max + rad, t) or_else max(f32)
        t1 := geometry.sweep_point_vs_aabb(pos, move, child1.min - rad, child1.max + rad, t) or_else max(f32)

        if t0 > t1 {
            t0, t1 = t1, t0
            child0, child1 = child1, child0
        }

        if t0 == max(f32) {
            if stack_curr == 0 {
                break
            }

            stack_curr -= 1
            node = stack[stack_curr]
        } else {
            node = child0
            if t1 != max(f32) {
                stack[stack_curr] = child1
                stack_curr += 1
            }
        }
    }

    return max(t, 0), prim, ok
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

// Vs world
// overlap_point :: proc()
// overlap_sphere :: proc()
// overlap_aabb :: proc()
// overlap_mesh :: proc()
// overlap_capsule :: proc()

@(require_results)
clone_slice :: proc(a: $T/[]$E, align: int, allocator := context.allocator, loc := #caller_location) -> ([]E, bool) #optional_ok {
	d, err := runtime.make_aligned([]E, len(a), align, allocator, loc)
	copy(d[:], a)
	return d, err == nil
}

simd_insert :: #force_inline proc "contextless" (vec: ^#simd[$W]$T, val: T, #any_int index: int) {
    vec^ = intrinsics.simd_replace(vec, index, val)
}

// Broadcast
simd_insert_vec :: proc "contextless" (vec: ^[$N]#simd[$W]$T, val: [N]T, #any_int index: int) {
    #unroll for v, i in val {
        vec[i] = intrinsics.simd_replace(vec[i], index, v)
    }
}

simd_scalar :: proc "contextless" ($W: int, val: $T) -> (result: #simd[W]T) {
    return cast(#simd[W]T)val
}

simd_scalar_vec :: proc "contextless" ($W: int, val: [$N]$T) -> (result: [N]#simd[W]T) {
    for v, i in val {
        result[i] = cast(#simd[W]T)v
    }
    return result
}