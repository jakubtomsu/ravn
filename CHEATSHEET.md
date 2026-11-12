# RAVN Cheatsheet
> Generated with `build/cheatsheet`

## Packages

- [base](#base) - 62 procedures
- [bvh](#bvh) - 18 procedures
- [collision](#collision) - 43 procedures
- [debugdraw](#debugdraw) - 32 procedures
- [entities](#entities) - 19 procedures
- [geometry](#geometry) - 39 procedures
- [gpu](#gpu) - 71 procedures
- [imgui](#imgui) - 1 procedures
- [imgui_impl_gpu](#imgui_impl_gpu) - 5 procedures
- [imgui_impl_platform](#imgui_impl_platform) - 5 procedures
- [imgui_util](#imgui_util) - 6 procedures
- [input](#input) - 24 procedures
- [platform](#platform) - 28 procedures
- [scene](#scene) - 8 procedures
- [shaderc](#shaderc) - 8 procedures
- [util](#util) - 75 procedures

## base

### base.odin

```odin
is_finite_f32(x: f32) -> bool // Quickly checks if x is not NaN or Inf
is_finite_vec(v: [$N]f32) -> bool
hash_fnv64a(data: []byte, seed: u64) -> u64
hash_murmurhash32_mix32(x: u32) -> u32
hash_splittable64(x: u64) -> u64
```

### base_bit_pool.odin

```odin
bit_pool_clear :: proc{dynamic_bit_pool_clear, static_bit_pool_clear}
bit_pool_find_0 :: proc{dynamic_bit_pool_find_0, static_bit_pool_find_0}
bit_pool_set_1 :: proc{dynamic_bit_pool_set_1, static_bit_pool_set_1}
bit_pool_set_0 :: proc{dynamic_bit_pool_set_0, static_bit_pool_set_0}
bit_pool_is_1 :: proc{dynamic_bit_pool_is_1, static_bit_pool_is_1}
dynamic_bit_pool_init(pool: ^Dynamic_Bit_Pool, num_bits: int, allocator := context.allocator, loc := #caller_location) -> (ok: bool)
dynamic_bit_pool_destroy(bp: ^Dynamic_Bit_Pool, allocator := context.allocator)
dynamic_bit_pool_clear(bp: ^Dynamic_Bit_Pool)
dynamic_bit_pool_find_0(bp: Dynamic_Bit_Pool) -> (index: int, ok: bool)
dynamic_bit_pool_set_1(bp: ^Dynamic_Bit_Pool, #any_int index: u64)
dynamic_bit_pool_set_0(bp: ^Dynamic_Bit_Pool, #any_int index: u64)
dynamic_bit_pool_is_1(bp: Dynamic_Bit_Pool, #any_int index: u64) -> bool
static_bit_pool_clear(bp: ^Static_Bit_Pool($N))
static_bit_pool_find_0(bp: Static_Bit_Pool($N)) -> (index: int, ok: bool)
static_bit_pool_set_1(bp: ^Static_Bit_Pool($N), #any_int index: u64)
static_bit_pool_set_0(bp: ^Static_Bit_Pool($N), #any_int index: u64)
static_bit_pool_is_1(bp: Static_Bit_Pool($N), #any_int index: u64) -> bool // static_bit_pool_get
```

### base_debug_id.odin

```odin
create_debug_id(name: string, loc := #caller_location, allocator := context.allocator) -> Debug_ID
destroy_debug_id(id: ^Debug_ID, allocator := context.allocator)
format_debug_id(id: Debug_ID, allocator := context.temp_allocator) -> string
get_debug_id_name(id: Debug_ID) -> string
get_debug_id_file(id: Debug_ID) -> string
assert_id(id: Debug_ID, condition: bool, message: string = "", expr := #caller_expression(condition), loc := #caller_location)
panic_id(id: Debug_ID, message: string, loc := #caller_location)
```

### base_pool.odin

```odin
pool_clear :: proc{dynamic_pool_clear, static_pool_clear}
pool_has :: proc{dynamic_pool_has, static_pool_has}
pool_find_free :: proc{dynamic_pool_find_free, static_pool_find_free}
pool_insert :: proc{dynamic_pool_insert, static_pool_insert}
pool_set :: proc{dynamic_pool_set, static_pool_set}
pool_remove :: proc{dynamic_pool_remove, static_pool_remove}
pool_get :: proc{dynamic_pool_get, static_pool_get}
pool_iter :: proc{dynamic_pool_iter, static_pool_iter}
pool_next :: proc{dynamic_pool_next, static_pool_next}
dynamic_pool_init(pool: ^$T/Dynamic_Pool($D, $H), size: int, allocator := context.allocator, loc := #caller_location) -> bool
dynamic_pool_destroy(pool: ^$T/Dynamic_Pool($D, $H), allocator := context.allocator)
dynamic_pool_clear(pool: ^$T/Dynamic_Pool($D, $H))
dynamic_pool_has(pool: $T/Dynamic_Pool($D, $H), handle: H) -> bool
dynamic_pool_find_free(pool: $T/Dynamic_Pool($D, $H)) -> (handle: H, ok: bool)
dynamic_pool_insert(pool: ^$T/Dynamic_Pool($D, $H), handle: H, data: D) -> bool
dynamic_pool_set(pool: ^$T/Dynamic_Pool($D, $H), handle: H, data: D) -> bool
dynamic_pool_remove(pool: ^$T/Dynamic_Pool($D, $H), handle: H) -> bool
dynamic_pool_get(pool: ^$T/Dynamic_Pool($D, $H), handle: H) -> (: ^D, : bool)
static_pool_clear(pool: ^$T/Static_Pool($N, $D, $H)) // Call to initialize and destroy. Does not clear generation counters and values - garbage is fine.
static_pool_has(pool: $T/Static_Pool($N, $D, $H), handle: H) -> bool
static_pool_find_free(pool: $T/Static_Pool($N, $D, $H)) -> (handle: H, ok: bool)
static_pool_insert(pool: ^$T/Static_Pool($N, $D, $H), handle: H, data: D) -> bool
static_pool_set(pool: ^$T/Static_Pool($N, $D, $H), handle: H, data: D) -> bool
static_pool_remove(pool: ^$T/Static_Pool($N, $D, $H), handle: H) -> bool
static_pool_get(pool: ^$T/Static_Pool($N, $D, $H), handle: H) -> (: ^D, : bool)
dynamic_pool_iter(pool: ^$T/Dynamic_Pool($D, $H)) -> Dynamic_Pool_Iter(D, H)
dynamic_pool_next(iter: ^$T/Dynamic_Pool_Iter($D, $H)) -> (handle: H, data: ^D, ok: bool)
static_pool_iter(pool: ^$T/Static_Pool($N, $D, $H)) -> Static_Pool_Iter(N, D, H)
static_pool_next(iter: ^$T/Static_Pool_Iter($N, $D, $H)) -> (handle: H, data: ^D, ok: bool)
```

### base_spsc.odin

```odin
spsc_push_elems(q: ^$T/SPSC($N, $V), vals: ..V) -> int
spsc_pop_elems(q: ^$T/SPSC($N, $V), buf: []V) -> []V
spsc_push(q: ^$T/SPSC($N, $V), val: V) -> bool
spsc_pop(q: ^$T/SPSC($N, $V)) -> (result: V, ok: bool)
```

## bvh

### bvh.odin

```odin
max_nodes_for_prims(#any_int num_prims: int) -> int
init(bvh: ^BVH, nodes: []Node, indices: []u32, prims: [][2][3]f32 = nil, #any_int max_leaf_prims := 3)
init_prims(bvh: ^BVH, prims: [][2][3]f32) // Re-initialize the primitive buffer only and clears the existing nodes.
build_none(bvh: ^BVH) // Not actual BVH, contains a single huge node with all prims.
build_mid(bvh: ^BVH, curr_index := 0) // Very fast but the result isn't a high-quality tree.
build_mean_sah(bvh: ^BVH, curr_index := 0) // Similar to mid, spends more time selecting better split.
build_sah(bvh: ^BVH, curr_index := 0) // Very slow, each node is O(n_prims^2).
build_binned(bvh: ^BVH, num_bins := 8, curr_index := 0)
iter(bvh: ^BVH) -> Iter
iter_pop(iter: ^Iter) -> bool
iter_next(iter: ^Iter, t0, t1: f32) -> bool // t0, t1: intersection times for the children of the current node. Use max(f32) on miss.
iter_unordered_next(iter: ^Iter, hit0, hit1: bool) -> bool
refit(bvh: ^BVH, index := 0)
calc_sah(bvh: BVH, index := 0) -> f32 // Can be normalized by root surface area.
calc_height(bvh: BVH, index := 0) -> int
vec_min(a, b: [3]f32) -> [3]f32
vec_max(a, b: [3]f32) -> [3]f32
surface_area(min, max: [3]f32) -> f32
```

## collision

### collision.odin

```odin
init(state: ^State = nil, allocator := context.allocator)
shutdown()
is_step_in_progress() -> bool
get_step_state() -> ^Step_State
begin_step(delta: f32)
end_step()
create_arena(size_in_bytes: u64, allocator := context.allocator, loc := #caller_location) -> (result: Arena_Handle, ok: bool)
destroy_arena(handle: Arena_Handle) -> bool
arena_allocator(handle: Arena_Handle) -> runtime.Allocator
get_arena(handle: Arena_Handle) -> (: ^Arena, : bool)
get_mesh(handle: Mesh_Handle) -> (: ^Mesh, : bool)
create_mesh(arena_handle: Arena_Handle, verts: [][3]f32, triangles: [][3]u16) -> (result: Mesh_Handle, ok: bool) // WARNING: doesn't clone the data. You must allocate it yourself with the
destroy_mesh(handle: Mesh_Handle) -> bool
add_sphere_shape(pos: [3]f32, rad: f32, #any_int layer: u8 = 0, #any_int id: u64 = 0)
add_capsule_shape(p0, p1: [3]f32, rad: f32, #any_int layer: u8 = 0, #any_int id: u64 = 0)
add_box_shape(pos: [3]f32, scale: [3]f32, rad: f32 = 0.0, #any_int layer: u8 = 0, #any_int id: u64 = 0)
add_oriented_box_shape(pos: [3]f32, scale: [3]f32, rot: quaternion128, rad: f32 = 0.0, #any_int layer: u8 = 0, #any_int id: u64 = 0)
add_mesh_shape(handle: Mesh_Handle, pos: [3]f32 = 0, scale: [3]f32 = 1, rot: quaternion128 = 1, rad: f32 = 0.0, #any_int layer: u8 = 0, #any_int id: u64 = 0)
collide_sphere(pos: [3]f32, vel: [3]f32, rad: f32, ignore_layers: bit_set[0 ..< NUM_LAYERS] = {}, max_contacts := 8, max_triangles := 32, allocator := context.temp_allocator) -> (new_pos: [3]f32, new_vel: [3]f32, contacts: []Contact) // Immediate-mode discrete collision.
collide_sphere_swept(pos: [3]f32, vel: [3]f32, rad: f32, ignore_layers: bit_set[0 ..< NUM_LAYERS] = {}, max_sweeps := 4) -> (new_pos: [3]f32, new_vel: [3]f32) // Immediate-mode continous shape-swept collision
make_sweep(pos: [3]f32, move: [3]f32, rad: f32 = 0, range: f32 = 1) -> Sweep
sweep_point(pos: [3]f32, move: [3]f32, range: f32 = 1, ignore_layers: bit_set[0 ..< NUM_LAYERS] = {}) -> (result: Sweep, ok: bool) // World raycast
sweep_sphere(pos: [3]f32, move: [3]f32, rad: f32, range: f32 = 1, ignore_layers: bit_set[0 ..< NUM_LAYERS] = {}) -> (result: Sweep, ok: bool) // World spherecast
eval_sweep(sweep: ^Sweep)
test_sphere(pos: [3]f32, rad: f32, ignore_layers: bit_set[0 ..< NUM_LAYERS] = {}) -> (result: Test, ok: bool) // Checks for *any* collider overlap.
overlap_sphere(pos: [3]f32, rad: f32, max_overlaps := 16, ignore_layers: bit_set[0 ..< NUM_LAYERS] = {}, allocator := context.temp_allocator) -> (result: Overlap, ok: bool) // Returns all overlapping colliders
overlap_sphere_buf(pos: [3]f32, rad: f32, shapes: []i32, ignore_layers: bit_set[0 ..< NUM_LAYERS] = {}) -> (result: Overlap, ok: bool)
find_contacts_sphere(pos: [3]f32, rad: f32, max_contacts := 8, max_triangles := 32, ignore_layers: bit_set[0 ..< NUM_LAYERS] = {}, allocator := context.temp_allocator) -> (result_contacts: []Contact)
find_contacts_sphere_buf(pos: [3]f32, rad: f32, out_contacts: []Contact, out_triangles: []Triangle_Contact, ignore_layers: bit_set[0 ..< NUM_LAYERS]) -> (num_contacts: i32, num_triangles: i32)
generate_filtered_sphere_vs_triangle_contacts(pos: [3]f32, rad: f32, out_contacts: []Contact, triangles: []Triangle_Contact) -> (num_contacts: i32) // https://www.codercorner.com/MeshContacts.pdf
get_shape(shape: i32) -> (: Shape, : bool)
get_mesh_triangle(handle: Mesh_Handle, #any_int tri_index: int) -> (verts: [3][3]f32, ok: bool)
clone_slice(a: $T/[]$E, align: int, allocator := context.allocator, loc := #caller_location) -> (: []E, : bool)
```

### collision_shape.odin

```odin
sweep_point_vs_shape(pos: [3]f32, move: [3]f32, shape: Shape, range: f32) -> (t: f32, prim: i32, ok: bool)
sweep_sphere_vs_shape(pos: [3]f32, move: [3]f32, rad: f32, shape: Shape, range: f32) -> (t: f32, prim: i32, ok: bool)
sweep_point_vs_mesh_local(pos: [3]f32, move: [3]f32, handle: Mesh_Handle, range: f32 = 1) -> (t: f32, prim: i32, ok: bool)
find_contacts_sphere_vs_shape(pos: [3]f32, rad: f32, shape: Shape, out_contacts: []Contact, out_triangles: []Triangle_Contact) -> (num_contacts: i32, num_triangles: i32)
sweep_sphere_vs_mesh_local(pos: [3]f32, move: [3]f32, rad: f32, handle: Mesh_Handle, scale: [3]f32 = 1, range: f32 = 1) -> (t: f32, prim: i32, ok: bool)
test_sphere_vs_mesh_local(pos: [3]f32, rad: f32, handle: Mesh_Handle, scale: [3]f32 = 1) -> (: i32, : bool)
find_potential_contact_triangles_sphere_vs_mesh_local(pos: [3]f32, rad: f32, handle: Mesh_Handle, scale: [3]f32 = 1, out_triangles: []Triangle_Contact) -> (num_triangles: i32)
test_sphere_vs_shape(pos: [3]f32, rad: f32, shape: Shape) -> (prim: i32, ok: bool)
get_shape_aabb(shape: Shape) -> (bb_min, bb_max: [3]f32)
get_shape_gradient(shape: Shape, query_origin_pos: [3]f32, hit: [3]f32, prim: i32) -> (result: [3]f32)
```

## debugdraw

### debugdraw.odin

```odin
init(state: ^State = nil, target_color: gpu.Resource_Handle = gpu.SWAPCHAIN_HANDLE, target_depth: gpu.Resource_Handle = {}, depth_comparison: gpu.Comparison_Op = .Always, depth_write := false, line_cap := 1024 * 16, tri_cap := 1024 * 16, shape_buffer_caps := DEFAULT_SHAPE_BUFFER_CAPS, allocator := context.allocator) -> bool
shutdown()
render_pass(camera_proj: matrix[4, 4]f32, delta: f32, color_clear_mode: gpu.Clear_Mode = .Keep, color_clear_val: [4]f32 = 0, depth_clear_mode: gpu.Clear_Mode = .Keep, depth_clear_val: f32 = 1)
upload_frame(camera_proj: matrix[4, 4]f32, delta: f32)
render_frame()
draw_vert_buffer(buf: $T/Buffer($E))
draw_inst_buffer(buf: $T/Buffer($E), vert_num: int, vert_offset: int)
buffer_init(buf: ^$T/Buffer($E), cap: int, allocator := context.allocator)
buffer_destroy(buf: ^$T/Buffer($E), allocator := context.allocator)
buffer_push(buf: ^$T/Buffer($E), data: E, time: f32)
buffer_flush(buf: ^$T/Buffer($E), delta: f32)
upload_buffers_make(allocator := context.temp_allocator) -> (result: Upload_Buffers)
upload_buffers_push(upload: ^Upload_Buffers, buf: ^$T/Buffer($E), elem_verts: u32 = 1)
```

### debugdraw_3d.odin

```odin
line(pos0: [3]f32, pos1: [3]f32, col: [2][4]u8 = WHITE, time: f32 = 0)
tri(pos0: [3]f32, pos1: [3]f32, pos2: [3]f32, col: [3][4]u8 = WHITE, time: f32 = 0, fill := false)
box(pos: [3]f32, mat: matrix[3, 3]f32 = 1, col := WHITE, time: f32 = 0, fill := false)
circle(pos: [3]f32, mat: matrix[3, 3]f32 = 1, col := WHITE, time: f32 = 0, fill := false)
sphere(pos: [3]f32, mat: matrix[3, 3]f32 = 1, col := WHITE, time: f32 = 0, fill := false)
hemisphere(pos: [3]f32, mat: matrix[3, 3]f32 = 1, col := WHITE, time: f32 = 0, fill := false)
cone(pos: [3]f32, mat: matrix[3, 3]f32 = 1, col := WHITE, time: f32 = 0, fill := false)
cylinder(pos: [3]f32, mat: matrix[3, 3]f32 = 1, col := WHITE, time: f32 = 0, fill := false)
basis(pos: [3]f32, mat: matrix[3, 3]f32 = 1, time: f32 = 0, fill := false)
aabb(min: [3]f32, max: [3]f32, col := WHITE, time: f32 = 0, fill := false)
box_line(pos0: [3]f32, pos1: [3]f32, rad: f32, col: [4]u8 = WHITE, time: f32 = 0, fill := true)
cylinder_line(pos0: [3]f32, pos1: [3]f32, rad: f32, col: [4]u8 = WHITE, time: f32 = 0, fill := true)
cone_line(pos0: [3]f32, pos1: [3]f32, rad: f32, col: [4]u8 = WHITE, time: f32 = 0, fill := true)
arrow(pos0: [3]f32, pos1: [3]f32, rad: f32, col: [4]u8 = WHITE, time: f32 = 0, fill := true)
grid(pos: [3]f32 = 0, axis_a: [3]f32 = {1, 0, 0}, axis_b: [3]f32 = {0, 0, 1}, col: [2][4]u8 = {WHITE, LIGHT_GRAY}, segments: [2]i32 = 5, time: f32 = 0)
calc_line_mat(dir: [3]f32, rad: [2]f32) -> (result: matrix[3, 3]f32) // Y is "forward"
shape(kind: Shape_Kind, pos: [3]f32, mat: matrix[3, 3]f32 = 1, col: [4]u8 = WHITE, time: f32 = 0)
make_shape_inst(pos: [3]f32, mat: matrix[3, 3]f32, col: [4]u8) -> Shape_Instance
```

### debugdraw_color.odin

```odin
pack_color(col: [4]f32) -> [4]u8
```

## entities

### entities.odin

```odin
init(ents: ^$Ents/Entities($Val_Union, $Sub_Union), default_cap: int = 4096, caps: []int = nil, allocator := context.allocator) // TODO: we cannot do caps: [UNION_LEN(Val_Union)] due to a compiler bug.
shutdown(ents: ^$Ents/Entities($Val_Union, $Sub_Union)) // Frees buffers and zeroes the entire container
clear(ents: ^$Ents/Entities($Val_Union, $Sub_Union))
clone(src: ^$Ents/Entities($Val_Union, $Sub_Union), allocator := context.allocator) -> (result: Ents)
create :: proc{create_val, create_sub}
create_val(ents: ^$Ents/Entities($Val_Union, $Sub_Union), val: Val_Union) -> (result: Handle, ok: bool)
create_sub(ents: ^$Ents/Entities($Val_Union, $Sub_Union), val: $Val) -> (result: Handle, ok: bool)
destroy(ents: ^$Ents/Entities($Val_Union, $Sub_Union), handle: Handle) -> bool
get(ents: ^$Ents/Entities($Val_Union, $Sub_Union), handle: Handle) -> (result: Entity_Ptr(Val_Union), ok: bool)
get_sub(ents: ^$Ents/Entities($Val_Union, $Sub_Union), handle: Handle, $Sub: typeid) -> (result: ^Sub, ok: bool)
get_values(ents: $Ents/Entities($Val_Union, $Sub_Union), $Val: typeid) -> []Val
get_buffer(ents: ^$Ents/Entities($Val_Union, $Sub_Union), variant: Handle_Variant) -> (: ^Buffer, : bool)
get_entity_base(ents: $Ents/Entities($Val_Union, $Sub_Union), buf: Buffer, handle: Handle) -> (: ^Base, : bool)
begin :: proc{begin_val, begin_sub}
next :: proc{next_val, next_sub}
begin_val(ents: ^$Ents/Entities($Val_Union, $Sub_Union), $Val: typeid) -> (it: Iter_Val(Val))
next_val(it: ^Iter_Val($Val)) -> (value: ^Val, ok: bool)
begin_sub(ents: ^$Ents/Entities($Val_Union, $Sub_Union), $Sub: typeid) -> (result: Iter_Sub(Val_Union, Sub_Union, Sub))
next_sub(it: ^Iter_Sub($Val_Union, $Sub_Union, $Sub)) -> (value: ^Sub, ok: bool)
```

## geometry

### geometry_bounds.odin

```odin
get_oriented_box_bounds(pos: [3]f32, rad: [3]f32, rot: matrix[3, 3]f32) -> (min, max: [3]f32)
```

### geometry_dist.odin

```odin
get_sphere_dist_sq(pos: [3]f32, center: [3]f32, rad: f32) -> f32
get_sphere_dist(pos: [3]f32, center: [3]f32, rad: f32) -> f32
get_sphere_dist_grad(pos: [3]f32, center: [3]f32, rad: f32) -> (dist: f32, grad: [3]f32)
get_box_dist(pos: [3]f32, center: [3]f32, rad: [3]f32) -> f32
get_box_dist_grad(pos: [3]f32, center: [3]f32, rad: [3]f32) -> (dist: f32, grad: [3]f32)
get_line_dist(pos: [3]f32, points: [2][3]f32) -> f32 // Capsule
get_line_dist_sq(pos: [3]f32, points: [2][3]f32) -> f32
get_line_dist_grad(pos: [3]f32, points: [2][3]f32) -> (dist: f32, grad: [3]f32) // Capsule
get_triangle_dist(pos: [3]f32, tri: [3][3]f32) -> (dist: f32)
get_triangle_dist_sq(pos: [3]f32, tri: [3][3]f32) -> (dist: f32)
get_triangle_dist_grad(pos: [3]f32, tri: [3][3]f32) -> (dist: f32, grad: [3]f32)
```

### geometry_overlap.odin

```odin
test_point_vs_aabb(pos: [3]f32, min, max: [3]f32) -> bool
test_point_vs_aabb_simd_single(pos: #simd[4]f32, min, _max: #simd[4]f32) -> bool
test_point_vs_sphere(pos: [3]f32, center: [3]f32, rad: f32) -> bool
test_point_vs_capsule(pos: [3]f32, points: [2][3]f32, rad: f32) -> bool
test_sphere_vs_sphere(pos_a: [3]f32, rad_a: f32, pos_b: [3]f32, rad_b: f32) -> bool
test_sphere_vs_box(pos: [3]f32, rad: f32, center, extent: [3]f32) -> bool
test_sphere_vs_triangle(pos: [3]f32, rad: f32, tri: [3][3]f32) -> bool
test_aabb_vs_aabb(a_min, a_max: [3]f32, b_min, b_max: [3]f32) -> bool
```

### geometry_sweep.odin

```odin
sweep_point_vs_plane(pos: [3]f32, move: [3]f32, normal: [3]f32, dist: f32, range: f32 = 1) -> (t: f32, ok: bool)
sweep_point_vs_sphere(pos: [3]f32, move: [3]f32, center: [3]f32, rad: f32, range: f32 = 1) -> (t: f32, ok: bool)
sweep_point_vs_sphere_simd(pos: [3]#simd[LANES]f32, move: [3]#simd[LANES]f32, move_len2: #simd[LANES]f32, move_len2_inv: #simd[LANES]f32, center: [3]#simd[LANES]f32, rad: #simd[LANES]f32, range: #simd[LANES]f32 = 1) -> (t: #simd[LANES]f32, ok: #simd[LANES]u32) // NOTE: move vector must have length greater than zero.
sweep_point_vs_aabb(pos: [3]f32, move: [3]f32, aabb_min: [3]f32, aabb_max: [3]f32, range: f32 = 1) -> (t: f32, ok: bool) // NOTE: rays running exactly parallel to one of the planes return miss.
sweep_point_vs_aabb_simd_single(pos: #simd[4]f32, inv_move: #simd[4]f32, aabb_min: #simd[4]f32, aabb_max: #simd[4]f32, range: f32 = 1) -> (t: f32, ok: bool) // W component is ignored
sweep_point_vs_aabb_simd(pos: [3]#simd[LANES]f32, inv_move: [3]#simd[LANES]f32, aabb_min: [3]#simd[LANES]f32, aabb_max: [3]#simd[LANES]f32, range: #simd[LANES]f32 = 1) -> (t: #simd[LANES]f32, ok: #simd[LANES]u32)
sweep_point_vs_triangle(pos: [3]f32, move: [3]f32, tri: [3][3]f32, range: f32 = 1) -> (t: f32, ok: bool)
sweep_point_vs_triangle_simd(pos: [3]#simd[LANES]f32, move: [3]#simd[LANES]f32, tri: [3][3]#simd[LANES]f32, range: #simd[LANES]f32 = 1) -> (t: #simd[LANES]f32, ok: #simd[LANES]u32)
sweep_point_vs_triangle_slab(pos: [3]f32, move: [3]f32, tri: [3][3]f32, rad: f32, range: f32 = 1) -> (t: f32, uv: [2]f32, ok: bool) // Triangle expanded by 2*radius along the normal.
sweep_point_vs_uncapped_cylinder(pos: [3]f32, move: [3]f32, points: [2][3]f32, rad: f32, range: f32 = 1) -> (t: f32, ok: bool)
sweep_point_vs_uncapped_cylinder_simd(pos: [3]#simd[LANES]f32, move: [3]#simd[LANES]f32, points: [2][3]#simd[LANES]f32, rad: #simd[LANES]f32, range: #simd[LANES]f32 = 1) -> (t: #simd[LANES]f32, ok: #simd[LANES]u32)
sweep_point_vs_cylinder(pos: [3]f32, move: [3]f32, points: [2][3]f32, rad: f32, range: f32 = 1) -> (t: f32, ok: bool)
sweep_point_vs_capsule(pos: [3]f32, move: [3]f32, points: [2][3]f32, rad: f32, range: f32 = 1) -> (t: f32, ok: bool) // FIXME: broken endcaps
sweep_sphere_vs_aabb(pos: [3]f32, move: [3]f32, rad: f32, aabb_min: [3]f32, aabb_max: [3]f32, range: f32 = 1) -> (t: f32, ok: bool)
sweep_sphere_vs_triangle(pos: [3]f32, move: [3]f32, rad: f32, tri: [3][3]f32, range: f32 = 1) -> (t: f32, ok: bool)
dot_simd(a, b: [3]#simd[LANES]f32) -> #simd[LANES]f32
cross_simd(a, b: [3]#simd[LANES]f32) -> [3]#simd[LANES]f32
length2_simd(a: [3]#simd[LANES]f32) -> #simd[LANES]f32
```

### geometry_voronoi.odin

```odin
get_triangle_closest_point(pos: [3]f32, tri: [3][3]f32) -> (closest: [3]f32, feature_kind: Voronoi_Feature_Kind, feature_index: i32) // Edges: 01, 02, 12
```

## gpu

### gpu.odin

```odin
make_blend_desc(src_color: Blend_Factor = .Src_Alpha, dst_color: Blend_Factor = .One_Minus_Src_Alpha, src_alpha: Blend_Factor = .Src_Alpha, dst_alpha: Blend_Factor = .One_Minus_Src_Alpha, op_color: Blend_Op = .Add, op_alpha: Blend_Op = .Add) -> Blend_Desc // Alpha blending is default
make_sampler_desc(filter: bit_set[Filter], bounds: [3]Texture_Bounds = {.Wrap, .Wrap, .Wrap}, mip_min: f32 = 0, mip_max: f32 = 10, mip_bias: f32 = 0, max_aniso: i32 = 1) -> Sampler_Desc
init(state: ^State = nil, window: rawptr, allocator := context.allocator) -> bool // window: platform-specific window pointer. You may use platform.get_native_window_ptr(). Use nil for headless rendering.
shutdown()
begin_frame() -> (ok: bool) // return value of false means skip frame
end_frame(sync: bool = true, loc := #caller_location)
make_graphics_pipeline_desc(ps: Shader_Handle, vs: Shader_Handle, bind_layouts: [dynamic; MAX_PIPELINE_BIND_GROUPS]Bind_Layout_Handle = {}, vertex_layouts: [dynamic; MAX_PIPELINE_VERTEX_LAYOUTS]Vertex_Layout_Desc, color_formats: [dynamic; MAX_BOUND_RENDER_TEXTURES]Texture_Format, blends: [dynamic; MAX_BOUND_RENDER_TEXTURES]Blend_Desc = {}, index_format: Index_Format = .Invalid, topo: Topology = .Triangles, cull: Cull_Mode = .None, fill: Fill_Mode = .Solid, depth_format: Texture_Format = .Invalid, depth_comparison: Comparison_Op = .Always, depth_write: bool = false, depth_bias: i32 = 0) -> (result: Graphics_Pipeline_Desc)
make_compute_pipeline_desc(cs: Shader_Handle, layouts: [MAX_PIPELINE_BIND_GROUPS]Bind_Layout_Handle) -> (result: Compute_Pipeline_Desc)
create_bind_layout(handle: ^Bind_Layout_Handle, desc: Bind_Layout_Desc, name := #caller_expression(handle), loc := #caller_location) -> (ok: bool) // Creates a binding layout used for bind groups and pipelines.
create_bind_group(handle: ^Bind_Group_Handle, desc: Bind_Group_Desc, name := #caller_expression(handle), loc := #caller_location) -> (ok: bool)
create_graphics_pipeline(handle: ^Graphics_Pipeline_Handle, desc: Graphics_Pipeline_Desc, name := #caller_expression(handle), loc := #caller_location) -> (ok: bool)
create_compute_pipeline(handle: ^Compute_Pipeline_Handle, desc: Compute_Pipeline_Desc, name := #caller_expression(handle), loc := #caller_location) -> (ok: bool)
create_shader(handle: ^Shader_Handle, data: []byte, kind: Shader_Kind, name := #caller_expression(handle), loc := #caller_location) -> (ok: bool)
create_constants(handle: ^Resource_Handle, item_size: i32, item_num: i32 = 1, name := #caller_expression(handle), loc := #caller_location) -> (ok: bool)
make_texture_desc(format: Texture_Format, size: [3]i32, usage: Usage = .Default, #any_int mips: int = 1, flags: bit_set[Texture_Flag] = {}) -> (result: Texture_Desc)
create_texture_2d(handle: ^Resource_Handle, desc: Texture_Desc, data: []byte = nil, name := #caller_expression(handle), loc := #caller_location) -> (ok: bool)
create_texture_3d(handle: ^Resource_Handle, desc: Texture_Desc, data: []byte = nil, name := #caller_expression(handle), loc := #caller_location) -> (ok: bool)
create_buffer(handle: ^Resource_Handle, kind: Buffer_Kind, #any_int stride: int, #any_int size: int = 0, usage: Usage = .Default, data: []u8 = nil, name := #caller_expression(handle), loc := #caller_location) -> (ok: bool) // Must set size or data.
resize_swapchain(window: rawptr, size: [2]i32) -> (ok: bool)
resize_texture(handle: ^Resource_Handle, size: [3]i32) -> (ok: bool) // Recreates and clears the texture! Use purely as an util for keeping the old handle.
destroy :: proc{destroy_shader, destroy_resource, destroy_bind_group, destroy_bind_layout, destroy_graphics_pipeline, destroy_compute_pipeline}
destroy_shader(handle: Shader_Handle) -> bool
destroy_resource(handle: Resource_Handle) -> bool
destroy_bind_group(handle: Bind_Group_Handle) -> bool
destroy_bind_layout(handle: Bind_Layout_Handle) -> bool
destroy_graphics_pipeline(handle: Graphics_Pipeline_Handle) -> bool
destroy_compute_pipeline(handle: Compute_Pipeline_Handle) -> bool
scope_graphics_pass(name: string, desc: Graphics_Pass_Desc) -> bool
begin_graphics_pass(name: string, desc: Graphics_Pass_Desc, loc := #caller_location)
end_graphics_pass()
set_bind_group(#any_int slot: int, handle: Bind_Group_Handle, offsets: []u32 = nil)
set_vertex_buffer(slot: int, handle: Resource_Handle, #any_int offset: int = 0)
set_index_buffer(handle: Resource_Handle, format: Index_Format, #any_int offset: int = 0)
set_graphics_pipeline(handle: Graphics_Pipeline_Handle)
scope_compute_pass(name: string) -> bool
begin_compute_pass(name: string, loc := #caller_location)
end_compute_pass()
set_compute_pipeline(handle: Compute_Pipeline_Handle)
update_constants(handle: Resource_Handle, data: []byte, loc := #caller_location)
update_buffer(handle: Resource_Handle, offset := 0, buffers: ..[]byte, loc := #caller_location) -> bool // "buffers" can be multiple separate slices of CPU memory, written consecutively to the GPU memory.
update_texture_2d(handle: Resource_Handle, data: []byte, #any_int slice: i32 = 0) -> bool
draw_non_indexed(#any_int vertex_num: int, #any_int instance_num: int = 1, #any_int vertex_offset: int = 0, #any_int instance_offset: int = 0)
draw_indexed(#any_int index_num: int, #any_int instance_num: int = 1, #any_int index_offset: int = 0, #any_int vertex_offset: int = 0, #any_int instance_offset: int = 0)
dispatch_compute(size: [3]i32)
copy_texture(dst_handle: Resource_Handle, src_handle: Resource_Handle) -> bool
map_texture(handle: Resource_Handle) -> (: Mapped_Data, : bool)
unmap_texture(handle: Resource_Handle) -> bool
set_scissor(min: [2]i32, max: [2]i32)
get_buffer_size(handle: Resource_Handle) -> (result: int, ok: bool)
get_resource_kind(handle: Resource_Handle) -> (result: Resource_Kind, ok: bool)
get_texture_format(handle: Resource_Handle) -> (result: Texture_Format, ok: bool)
validate_pass_desc(id: base.Debug_ID, desc: Graphics_Pass_Desc, loc := #caller_location)
validate_bind_layout_desc(id: base.Debug_ID, desc: Bind_Layout_Desc, loc := #caller_location)
validate_bind_group_desc(id: base.Debug_ID, desc: Bind_Group_Desc, loc := #caller_location)
validate_graphics_pipeline_desc(id: base.Debug_ID, desc: Graphics_Pipeline_Desc, loc := #caller_location)
validate_graphics_pipeline_for_pass(id: base.Debug_ID, pip: Graphics_Pipeline_Desc, pass: Graphics_Pass_Desc, loc := #caller_location)
validate_compute_pipeline_desc(id: base.Debug_ID, desc: Compute_Pipeline_Desc, loc := #caller_location)
is_texture_format_depth_stencil(format: Texture_Format) -> bool
get_texture_format_num_channels(format: Texture_Format) -> int
get_texture_format_pixel_size(format: Texture_Format) -> int
get_vertex_format_size(format: Vertex_Format) -> int
```

### gpu_util.odin

```odin
arena_create($T: typeid, kind: Buffer_Kind, #any_int size: i32, usage: Usage = .Default, loc := #caller_location, allocator := context.allocator) -> (result: Arena, ok: bool)
arena_create_raw(kind: Buffer_Kind, #any_int stride: i32, #any_int size: i32, usage: Usage = .Default, loc := #caller_location, allocator := context.allocator) -> (result: Arena, ok: bool)
arena_destroy(arena: ^Arena)
arena_reset(arena: ^Arena)
arena_alloc_bytes(arena: ^Arena, num_bytes: int) -> (: []byte, : bool) // NOTE: no alignment for now
arena_push_val(arena: ^Arena, val: ^$T) -> bool
arena_push_data(arena: ^Arena, data: []byte) -> bool // Write the data to the CPU-side staging buffer
arena_submit(arena: ^Arena, loc := #caller_location) -> bool // Flush the CPU-side staging buffer to the GPU
arena_allocator(arena: ^Arena) -> runtime.Allocator
make_vertex_layout($T: typeid, mode: Vertex_Step_Mode, loc := #caller_location) -> (result: Vertex_Layout_Desc) // Make vertex layout from a struct type using RTTI.
```

## imgui

### imgui.odin

```odin
CHECKVERSION() // Verify ABI compatibility between caller code and compiled version of Dear ImGui.
```

## imgui_impl_gpu

### imgui_impl_gpu.odin

```odin
init(target_format: gpu.Texture_Format = .Swapchain, allocator := context.allocator) -> bool
shutdown()
new_frame()
upload_draw_data(data: ^imgui.DrawData) // Call outside a draw pass
render_draw_data(data: ^imgui.DrawData) // Call inside a draw pass
```

## imgui_impl_platform

### imgui_impl_platform.odin

```odin
init(window: platform.Window, allocator := context.allocator)
shutdown()
new_frame()
update_mouse_cursor()
process_event(event: platform.Event)
```

## imgui_util

### imgui_impl_platform.odin

```odin
process_event(event: platform.Event)
```

### imgui_util.odin

```odin
init(window: platform.Window)
shutdown()
new_frame()
render_pass(color := gpu.SWAPCHAIN_HANDLE, clear_mode: gpu.Clear_Mode = .Keep, clear_val: [4]f32 = 0)
```

### imgui_util_style.odin

```odin
set_palette_style(palette := RAVN_DARK_PALETTE, style: ^imgui.Style = nil)
```

## input

### input.odin

```odin
init(state: ^State = nil, allocator := context.allocator)
shutdown()
update(delta: f32)
apply_event(event: platform.Event)
button_down(button: Button) -> bool
button_down_time(button: Button) -> f32 // Down time is 0 on pressed.
button_repeated(button: Button) -> bool
button_released(button: Button) -> bool
button_pressed(button: Button, buf: f32 = 0) -> bool // buf: buffering window duration in seconds
mouse_pos() -> [2]f32 // NOTE: [0, 0] is the bottom left corner.
mouse_delta() -> [2]f32 // Positive Y is up.
scroll_delta() -> [2]f32
gamepad_connected(gamepad_index: int) -> bool
gamepad_axis(gamepad_index: int, axis: Gamepad_Axis, deadzone: f32 = DEFAULT_DEADZONE) -> f32
gamepad_stick(gamepad_index: int, stick: Gamepad_Stick, deadzone: f32 = DEFAULT_DEADZONE) -> [2]f32
gamepad_down(gamepad_index: int, button: Gamepad_Button) -> bool
gamepad_down_time(gamepad_index: int, button: Gamepad_Button) -> f32 // Down time is 0 on pressed
gamepad_repeated(gamepad_index: int, button: Gamepad_Button) -> bool
gamepad_released(gamepad_index: int, button: Gamepad_Button) -> bool
gamepad_pressed(gamepad_index: int, button: Gamepad_Button, buf: f32 = 0) -> bool // buf: buffering window duration in seconds
button_buffer_update(buf: ^Button_Buffer($T), delta: f32)
button_buffer_apply_press(buf: ^Button_Buffer($T), elem: T)
button_buffer_apply_release(buf: ^Button_Buffer($T), elem: T)
gamepad_apply_state(gpad: ^Gamepad, state: platform.Gamepad_State)
```

## platform

### platform.odin

```odin
init(state: ^State = nil, allocator := context.allocator)
shutdown()
clipboard_set(data: string) -> bool
clipboard_get(allocator := context.temp_allocator) -> (: string, : bool)
get_gamepad_state(#any_int index: int) -> (result: Gamepad_State, ok: bool)
set_gamepad_feedback(#any_int index: int, output: Gamepad_Feedback) -> bool
get_user_data_dir(allocator := context.allocator) -> string
set_mouse_relative(window: Window, relative: bool)
register_default_exception_handler()
open_url(url: string)
set_cursor_visible(visible: bool)
set_cursor_icon(icon: Cursor_Icon)
create_window(name: string, style: Window_Style = .Regular, rect: Rect = {}, high_dpi := true) -> Window
destroy_window(window: Window)
set_window_title(window: Window, name: string)
set_window_style(window: Window, style: Window_Style)
set_window_pos(window: Window, pos: [2]i32)
set_window_size(window: Window, size: [2]i32)
get_window_rect(window: Window) -> Rect // Drawable area within the window, without decorators.
set_mouse_pos_window_relative(window: Window, pos: [2]i32)
is_window_minimized(window: Window) -> bool
is_window_focused(window: Window) -> bool
get_window_dpi_scale(window: Window) -> f32
get_native_window_ptr(window: Window) -> rawptr // HWND on windows
poll_window_events(window: Window) -> (event: Event, should_continue: bool)
get_main_monitor_rect() -> Rect
file_dialog(mode: File_Dialog_Mode, default_path: string, patterns: []File_Pattern, title := "") -> (: string, : bool)
```

### platform_windows.odin

```odin
win32_set_message_hook_proc(message_hook: Win32_Message_Hook_Proc, data: rawptr = nil)
```

## scene

### scene.odin

```odin
load :: proc{load_from_path, load_from_data}
load_from_path(path: string, allocator := context.allocator) -> (scene: Scene, err: Error)
load_from_data(data: []byte) -> (scene: Scene, err: Error)
range_is_valid(data: []$T, range: [2]$Int) -> bool // Range is offset + len
get_range_slice(data: []$T, range: [2]$Int) -> []T // Range is offset + len
get_string(scene: Scene, range: [2]u32) -> string
```

### scene_main.odin

```odin
main() // Dump util
```

### scene_string.odin

```odin
to_string(scene: Scene, include_data := false, allocator := context.allocator) -> string
```

## shaderc

### shaderc.odin

```odin
init(state_ptr: ^State = nil, allocator := context.allocator) -> bool
shutdown()
get_target_file_ext(target: Target) -> string
compile :: proc{compile_from_path, compile_from_source}
compile_from_path(path: string, opts: Options = DEFAULT_OPTIONS, loc := #caller_location, allocator := context.allocator) -> (result: []byte, ok: bool)
compile_from_source(name: string, source: string, opts: Options = DEFAULT_OPTIONS, loc := #caller_location, allocator := context.allocator) -> (result: []byte, ok: bool)
file_system_include_proc(path: string, opts: Options) -> (: string, : bool)
```

### shaderc_main.odin

```odin
main() // Commandline shader compilation util
```

## util

### specific.odin

```odin
quaternion_angle_axis_f32(angle_radians: f32, axis: Vector3f32) -> (q: Quaternionf32)
```

### util_camera.odin

```odin
make_perspective_3d_camera(screen: [2]f32, pos: [3]f32, rot: quaternion128, fov: f32 = math.PI * 0.5) -> Camera
make_orthographic_3d_camera(screen: [2]f32, pos: [3]f32, rot: quaternion128, fov: f32 = 1) -> Camera
make_2d_camera(screen: [2]f32, pos: [3]f32 = 0, fov: [2]f32 = 1.0, angle: f32 = 0) -> Camera
make_screen_camera(screen: [2]f32, pos: [3]f32 = 0) -> Camera
orthographic_projection(left, right, top, bottom: f32, near: f32 = 0.01, far: f32 = 1000.0) -> (result: matrix[4, 4]f32)
perspective_projection(screen: [2]f32, fov: f32, near: f32 = 0.01, far: f32 = 1000.0) -> (result: matrix[4, 4]f32) // left handed reverse Z
calc_camera_world_to_view_matrix(camera: Camera) -> (result: matrix[4, 4]f32)
calc_camera_world_to_clip_matrix(camera: Camera) -> (result: matrix[4, 4]f32)
calc_camera_frustum(cam: Camera) -> Frustum
calc_matrix_frustum(clip_to_world: matrix[4, 4]f32) -> (result: Frustum)
is_box_in_frustum(fru: Frustum, pos: [3]f32, rad: [3]f32) -> bool
is_sphere_in_frustum(fru: Frustum, pos: [3]f32, rad: f32) -> bool
screen_to_world_ray(pos: [2]f32, cam: Camera, screen_size: [2]f32) -> [3]f32 // Returns the ray direction.
```

### util_cp437.odin

```odin
rune_to_cp437(r: rune) -> u8
cp437_to_rune(ch: u8) -> rune // CP437 -> Unicode. Use when iterating over encoded text to print it.
```

### util_math.odin

```odin
deg(degrees: f32) -> (radians: f32)
lerp(a, b: $T, t: f32) -> T
lexp(a, b: $T, rate: f32) -> T // Exponential lerp. Multiply rate by delta to get frame rate independent interpolation
slexp(a, b: $T, rate: f32) -> T
nlerp(a, b: $T, t: f32) -> T
nlexp(a, b: $T, rate: f32) -> T
move_towards :: proc{move_towards_scalar, move_towards_vec, move_towards_quat}
move_towards_scalar(x, target: f32, rate: f32) -> f32
move_towards_vec(x, target: [$N]$E, rate: f32) -> [N]E
move_towards_quat(x, target: $Q, rate: f32) -> Q
fade(alpha: f32) -> [4]f32
gray(val: f32) -> [4]f32
addz(v: [2]f32, z: f32 = 0.0) -> [3]f32
nsin(x: f32) -> f32
vcast($T: typeid, v: [$N]$E) -> (result: [N]T)
int_cast($Dst: typeid, v: $Src) -> Dst
rot90(v: [2]$T) -> [2]T // Counter-clockwise. Negate to do clockwise.
unlerp(a, b: f32, x: f32) -> f32 // Returns value in 0..1 range.
remap(x, a0, a1: f32, b0: f32 = 0, b1: f32 = 1) -> f32 // Linearly transform x from range a0..a1 to b0..b1
remap_clamped(x, a0, a1: f32, b0: f32 = 0, b1: f32 = 1) -> f32
remap_smooth(x, a0, a1: f32, b0: f32 = 0, b1: f32 = 1) -> f32
smoothstep(edge0, edge1, x: f32) -> f32
luminance(rgb: [3]f32) -> f32
floor :: proc{floor_f32, floor_vec}
floor_vec(x: [$N]f32) -> [N]f32
floor_f32(x: f32) -> f32
hex_color(hex: u32) -> [4]f32 // RGB only!
oklerp(a, b: [4]f32, t: f32) -> (result: [4]f32) // Oklab lerp - Better color gradients than regular lerp()
heatmap_color(val: f32) -> (result: [4]f32) // 0 -> Red, 0.5 -> Blue, 1 -> Green
euler_rot(angles: [3]f32) -> quaternion128 // ZXY order for first-person view.
clamp_length(v: [$N]f32, min: f32 = 0, max: f32 = 1) -> [N]f32
spring(x, v: ^$T, x_target: T, damp: f32, freq: f32, delta: f32) // Spring Integration
spring2(xv: ^[2]$T, x_target: T, damp: f32, freq: f32, delta: f32) // Utility for springs where X and V are packed in an array.
approx_nexp(x: f32) -> (result: f32) // https://gist.github.com/jakubtomsu/d25210b55037858c3ed35fe00182f92a
rcp(denom: f32) -> (result: f32)
encode_octahedral(n: [3]f32) -> [2]f32 // Input is vector from a sphere.
decode_octahedral(f: [2]f32) -> [3]f32 // Result is normalized vector on a sphere
rect_make(min: [2]f32, full_size: [2]f32) -> Rect
rect_make_centered(pos: [2]f32, half_size: [2]f32) -> Rect
rect_center(r: Rect) -> [2]f32
rect_anchor(r: Rect, anchor: [2]f32) -> [2]f32
rect_full_size(r: Rect) -> [2]f32
rect_expand(r: Rect, a: [2]f32) -> Rect
rect_scale(r: Rect, a: [2]f32) -> Rect
rect_contains_point(r: Rect, p: [2]f32) -> bool
rect_clamp_point(r: Rect, p: [2]f32) -> [2]f32
rect_cut_left(r: ^Rect, a: f32) -> Rect
rect_cut_right(r: ^Rect, a: f32) -> Rect
rect_cut_top(r: ^Rect, a: f32) -> Rect
rect_cut_bottom(r: ^Rect, a: f32) -> Rect
rect_split_left(r: ^Rect, t: f32) -> Rect
rect_split_right(r: ^Rect, t: f32) -> Rect
rect_split_top(r: ^Rect, t: f32) -> Rect
rect_split_bottom(r: ^Rect, t: f32) -> Rect
transform_make(pos: [3]f32 = 0, scale: [3]f32 = 1, rot: quaternion128 = 1) -> Transform
transform_make_angle_axis(pos: [3]f32 = 0, scale: [3]f32 = 1, angle: f32 = 0, axis: [3]f32 = {0, 1, 0}) -> Transform
transform_point(tran: Transform, point: [3]f32) -> [3]f32
transform_mul(parent, child: Transform) -> Transform
transform_inv(tran: Transform) -> Transform
```

