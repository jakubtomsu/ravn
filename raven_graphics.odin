package raven

import "gpu"
import "base"
import "shader_compiler"
import "rscn"
import "base:intrinsics"
import "core:math"
import "core:math/linalg"
import stbi "vendor:stb/image"

DRAW_BATCH_TABLE_LOOKUP :: 512
DRAW_BATCH_TABLE_BATCHES :: 256 // this is limited by gpu.MAX_PIPELINES anyway.
DRAW_BATCH_TABLE_MAX_PROBE :: 32


DEFAULT_SAMPLER :: gpu.Sampler_Desc{
    filter = .Unfiltered,
    bounds = {.Wrap, .Wrap, .Wrap},
    mip_max = 10,
}


Vertex_Index :: u16 // GPU Vertex Index
Spline_Vertex :: rscn.Spline_Vertex


#assert(len(Blend_Mode) <= 4)
// NOTE: if you want an Alpha Clip mode, you must do it yourself in a shader with 'discard'.
Blend_Mode :: enum u8 {
    Opaque, // No blending
    Premultiplied_Alpha, // For certain sprites.
    Alpha, // Regular alpha transparency.
    Add, // Additive blend mode, only makes things brighter.
}

#assert(len(Fill_Mode) <= 4)
Fill_Mode :: enum u8 {
    All, // Fill both front and back. Default for simplicity.
    Front, // Fill the default front side of the triangles.
    Back, // Inverted
    Wire, // Two-sided wireframe mode
}

Mesh :: struct {
    group:          Group_Handle,

    vert_num:       i32,
    vert_offs:      i32,
    index_num:      i32,
    index_offs:     i32,

    param:          u64, // user param

    bounds_min:     Vec3,
    bounds_max:     Vec3,
    bounds_rad:     f32, // Centered sphere
}

Spline :: struct {
    group:          Group_Handle,

    vert_num:       i32,
    vert_offs:      i32,

    param:          u64, // user param

    bounds_min:     Vec3,
    bounds_max:     Vec3,
}

// TODO: pack vertex data into the following format:
// [3]u16    pos         6
// [2]u8     normal      2
// [2]u16    uv          4
// [3]u8     color       3
// [1]u8     _pad        1
// total 16 bytes

Vertex :: struct #align(16) {
    pos:    [3]f32,
    _pad:   f32,
    uv:     [2]f32,
    normal: [3]u8,
    p0:     u8, // NOTE: this padding could store user parameters..?
    col:    [4]u8,
}


Texture_Pool :: struct {
    slices_used:    bit_set[0..<MAX_TEXTURE_POOL_SLICES],
    size:           IVec2,
    slices:         i32,
    resource:       gpu.Resource_Handle,
}

Texture :: struct {
    size:       [2]u16,
    pool_index: u8, // set to max(u8) for non-pooled
    slice:      u8,
    resource:   gpu.Resource_Handle,
}

Texture_Data :: struct {
    size:   [2]i32,
    pixels: [][4]u8,
}

Draw_State :: struct {
    using key:              Draw_Batch_Key,
    draw_layer:             u8,
    texture_slice:          u8,
    texture_size:           [2]u16, // cached
}

Draw_Layer_Flag :: enum u8 {
    // Disable frustum culling.
    No_Cull,
    // Disable all sorting.
    // NOTE: this doesn't affect just transparent objects, it's how batching optimization is done.
    No_Reorder,
    // Flips the entire coordinate system vertically.
    // Toggled automatically based on the projection matrix.
    Flip_Y,
}

Draw_Layer :: struct {
    camera:     Camera,
    flags:      bit_set[Draw_Layer_Flag],

    sprites:    Draw_Batch_Table(Sprite_Inst),
    meshes:     Draw_Batch_Table(Mesh_Inst),
    triangles:  Draw_Batch_Table(Mesh_Inst),
    lines:      Draw_Batch_Table(Mesh_Inst),
}

Draw_Batch_Table :: struct($T: typeid) {
    lookup:     [DRAW_BATCH_TABLE_LOOKUP]u16,
    keys:       [DRAW_BATCH_TABLE_LOOKUP]Draw_Batch_Key,
    batches:    [DRAW_BATCH_TABLE_BATCHES]Draw_Batch(T),
    len:        u32,
}

// TODO: rename to batch something idk
// TODO: #simd[4]f32 cull sphere
// TODO: Sort key?
Draw_Batch :: struct($Instance: typeid) {
    consts_offset:  u32,
    last_len:       u32,
    len:            u32,
    cap:            u32,
    inst_data:      [^]Instance,
    cull_data:      [^]Draw_Cull_Group,
}

// Per 8 instances
Draw_Cull_Group :: struct #raw_union {
    using _simd: struct {
        pos:    [3]#simd[LANES]f32,
        rad:    #simd[LANES]f32,
    },
    using _scalar: struct {
        pos_scalar: [3][LANES]f32,
        rad_scalar: [LANES]f32,
    },
}

Depth_Mode :: enum u8 {
    None        = 0b00,
    Only_Test   = 0b01,
    Only_Write  = 0b10,
    Depth       = 0b11,
}

Draw_Sort_Key :: struct {
    index:          u16,
    dist:           u16,
}

#assert(size_of(Draw_Batch_Key) == 8)
Draw_Batch_Key :: struct #all_or_none {
    asset_index:    u16,
    texture:        u8,
    group:          u8,
    ps:             u8,
    vs:             u8,
    using packed:   bit_field u16 {
        texture_kind:   Draw_Texture_Kind   | 2,
        depth_mode:     Depth_Mode          | 2,
        fill_mode:      Fill_Mode           | 2,
        blend_mode:     Blend_Mode          | 2,
    },
}

Draw_Texture_Kind :: enum u8 {
    Non_Pooled,
    Pooled,
    Render_Texture,
}

Render_Texture :: struct #all_or_none {
    size:   IVec2,
    color:  gpu.Resource_Handle,
    depth:  gpu.Resource_Handle,
}

// (CPU) Draw instance data

// GPU data

// Shared across all layers and everything.
Draw_Global_Constants :: struct #all_or_none #align(16) {
    time:           f32,
    delta_time:     f32,
    frame:          u32,
    resolution:     [2]i32,
    rand_seed:      u32,
    param:          [4]u32, // user params
}

Draw_Layer_Constants :: struct #all_or_none #align(16) {
    view_proj:      Mat4,
    cam_pos:        Vec3,
    layer_index:    i32,
}

#assert(size_of(Draw_Batch_Constants) == 16)
Draw_Batch_Constants :: struct #align(16) {
    instance_offset:    u32,
}


#assert(size_of(Sprite_Inst) == 64)
Sprite_Inst :: struct #all_or_none #align(16) {
    pos:        [3]f32,
    col:        [4]u8,

    mat_x:      [3]f32,
    uv_min:     [2]u16,

    mat_y:      [3]f32,
    uv_size:    [2]u16,

    add_col:    [4]u8,
    param:      u32,
    tex_slice:  u8,
    _:          [3]u8,
    _:          u32,
}

#assert(size_of(Mesh_Inst) == 64)
Mesh_Inst :: struct #all_or_none #align(16) {
    pos:        [3]f32,
    col:        [4]u8,

    mat_x:      [3]f32,
    add_col:    [4]u8,

    mat_y:      [3]f32,
    tex_slice:  u8,
    vert_offs:  [3]u8, // 24 bit packed

    mat_z:      [3]f32,
    param:      u32, // user param
}

Sprite_Scaling :: enum u8 {
    // Scale of 1 means each pixel is exactly one screen pixel.
    Pixel = 0,
    // No scaling, sprite scale is the final scale in pixels
    // Scale of 1 means the ENTIRE sprite is 1x1 pixels.
    Absolute,
}




/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Group
//

@(require_results)
get_internal_group :: proc(handle: Group_Handle) -> (result: ^Group, ok: bool) {
    return _table_get(&_state.groups, _state.groups_gen, handle)
}

@(require_results)
create_group :: proc(
    max_mesh_verts:     i32 = 1024 * 16,
    max_mesh_indices:   i32 = 1024 * 32,
    max_spline_verts:   i32 = 1024,
    max_total_children: i32 = 1024,
    vertex_data:        []Vertex = {},
    index_data:         []Vertex_Index = {},
) -> (result: Group_Handle, ok: bool) #optional_ok {
    used_set := (transmute(u64)_state.groups_used) | 1
    index := intrinsics.count_trailing_zeros(~used_set)
    if index == 64 {
        base.log_err("Failed to create group: There is already max number of groups")
        return {}, false
    }

    group := &_state.groups[index]

    _state.groups_used += {int(index)}

    group^ = Group{
        object_child_buf    = make([]Object_Handle, max_total_children, _state.allocator),
        spline_vert_buf     = make([]Spline_Vertex, max_spline_verts, _state.allocator),
    }

    // TODO: allow creating mutable groups with default data..?
    if vertex_data != nil {
        group.vbuf, ok = gpu.create_buffer("rv-group-vert-buf",
            stride  = size_of(Vertex),
            // size    = size_of(Vertex) * len(vertex_data),
            usage   = .Immutable,
            data    = gpu.slice_bytes(vertex_data),
        )
    } else {
        group.vbuf, ok = gpu.create_buffer("rv-group-vert-buf",
            stride  = size_of(Vertex),
            size    = size_of(Vertex) * max_mesh_verts,
            usage   = .Default,
        )
    }

    assert(ok)

    if index_data != nil {
        group.ibuf, ok = gpu.create_index_buffer("rv-group-index-buf",
            // size = size_of(Vertex_Index) * len(index_data),
            data = gpu.slice_bytes(index_data),
            usage = .Immutable,
        )
    } else {
        group.ibuf, ok = gpu.create_index_buffer("rv-group-index-buf",
            size = size_of(Vertex_Index) * max_mesh_indices,
            usage = .Default,
        )
    }

    assert(ok)

    handle := Group_Handle{
        index = Handle_Index(index),
        gen = _state.groups_gen[index],
    }

    return handle, true
}

clear_group :: proc(handle: Group_Handle) {
    group, group_ok := get_internal_group(handle)
    if !group_ok {
        return
    }

    group.spline_vert_num = 0
    group.mesh_vert_num = 0
    group.mesh_index_num = 0
    group.object_child_num = 0
}

destroy_group :: proc(handle: Group_Handle) {
    group, group_ok := get_internal_group(handle)
    if !group_ok {
        return
    }

    gpu.destroy_resource(group.vbuf)
    gpu.destroy_resource(group.ibuf)

    for i in 0..<MAX_MESHES {
        mesh := &_state.meshes[i]
        if mesh.group != handle {
            continue
        }

        mesh^ = {}
        _state.meshes_hash[i] = 0
        _state.meshes_gen[i] += 1
    }


    for i in 0..<MAX_OBJECTS {
        object := &_state.objects[i]
        if object.group != handle {
            continue
        }

        object^ = {}
        _state.objects_hash[i] = 0
        _state.objects_gen[i] += 1
    }

    for i in 0..<MAX_SPLINES {
        spline := &_state.splines[i]
        if spline.group != handle {
            continue
        }

        spline^ = {}
        _state.splines_hash[i] = 0
        _state.splines_gen[i] += 1
    }

    delete(group.spline_vert_buf, _state.allocator)
    delete(group.object_child_buf, _state.allocator)

    _state.groups[handle.index] = {}
    _state.groups_gen[handle.index] += 1
    _state.groups_used -= {int(handle.index)}
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Meshes
//

create_mesh_from_data :: proc(
    name:           string,
    group_handle:   Group_Handle,
    vertices:       []Vertex,
    indices:        []Vertex_Index,
) -> (result: Mesh_Handle, ok: bool) #optional_ok {
    base.log_debug("Creating Mesh '%s' with %i verts and %i tris", name, len(vertices), len(indices) / 3)

    group := get_internal_group(group_handle) or_return

    mesh: Mesh
    mesh.group = group_handle

    mesh.vert_num = i32(len(vertices))
    mesh.index_num = i32(len(indices))
    mesh.vert_offs = group.mesh_vert_num
    mesh.index_offs = group.mesh_index_num

    mesh.bounds_min = max(f32)
    mesh.bounds_max = min(f32)
    mesh.bounds_rad = 0.001
    for vert in vertices {
        mesh.bounds_min = linalg.min(mesh.bounds_min, vert.pos)
        mesh.bounds_max = linalg.max(mesh.bounds_max, vert.pos)
        mesh.bounds_rad = max(mesh.bounds_rad, linalg.length(vert.pos))
    }

    handle, handle_ok := insert_mesh_by_name(name, mesh)
    if !handle_ok {
        base.log_err("Failed to create mesh '%s', table is full", name)
        return {}, false
    }

    gpu.update_buffer(group.vbuf, int(mesh.vert_offs) * size_of(Vertex), gpu.slice_bytes(vertices))
    gpu.update_buffer(group.ibuf, int(mesh.index_offs) * size_of(Vertex_Index), gpu.slice_bytes(indices))

    return handle, true
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Textures
//

// Texture pool allows for better batching when textures are the same size.
// When you create textures with the same size after this call they will get inserted into the pool.
// NOTE: Strongly prefer square and power-of-two sizes for texture pools.
// NOTE: A texture pool may not be destroyed.
// NOTE: Beware of the memory consumed by high-res texture pools!
create_texture_pool :: proc(size: IVec2, slices: i32) -> (ok: bool) {
    if _state.texture_pools_len >= len(_state.texture_pools) {
        base.log_err("Failed to create texture pool, too many texture pools")
        return false
    }

    pool: Texture_Pool
    pool.size = size
    pool.slices = slices
    pool.resource, ok = gpu.create_texture_2d("rv-tex-pool",
        format = .RGBA_U8_Norm,
        size = size,
        array_depth = slices,
    )

    assert(ok)

    if pool.resource == {} {
        base.log_err("Failed to create %ix%ix%i texture pool GPU resource", size.x, size.y, slices)
        return false
    }

    index := _state.texture_pools_len
    _state.texture_pools[index] = pool
    _state.texture_pools_len += 1

    return true
}

get_internal_texture :: proc(handle: Texture_Handle) -> (result: ^Texture, ok: bool) #optional_ok {
    return _table_get(&_state.textures, _state.textures_gen, handle)
}

load_texture :: proc(path: string) -> (result: Texture_Handle, ok: bool) #optional_ok {
    npath := normalize_path(path, context.temp_allocator)
    name := strip_path_name(npath)
    base.log_info("Loading texture '%s' from path '%s'", name, npath)
    data, data_ok := get_file_data(npath)
    if !data_ok {
        base.log_err("Failed to load texture '%s', couldn't get file data", name)
        return {}, false
    }
    return create_texture_from_encoded_data(name, data)
}

create_texture_from_encoded_data :: proc(name: string, data: []byte) -> (result: Texture_Handle, ok: bool) {
    tex, tex_ok := decode_texture_data(data)
    if !tex_ok {
        base.log_err("Failed to decode texture '%s'", name)
    }

    result, ok = create_texture_from_data(name, tex)

    destroy_decoded_texture_data(&tex)

    return result, ok
}

create_texture_from_data :: proc(name: string, data: Texture_Data) -> (result: Texture_Handle, ok: bool) {
    assert(data.size.x > 0)
    assert(data.size.y > 0)
    assert(len(data.pixels) == int(data.size.x * data.size.y))

    hash := hash_name(name)

    index, prev := _table_insert_hash(&_state.textures_hash, hash) or_return

    texture := &_state.textures[index]

    create_resource := true

    for &pool, pool_index in _state.texture_pools[:_state.texture_pools_len] {
        if pool.size != data.size {
            continue
        }

        full_set := (u64(1) << u64(pool.slices)) - 1

        used_set := (transmute(u64)pool.slices_used)

        if full_set == used_set {
            log_internal("Pool {} is full", pool_index)
            continue
        }

        slice_index := intrinsics.count_trailing_zeros(~used_set)

        assert(slice_index < 64)

        base.log_info("Creating a pooled texture '%s' of size %ix%i with index %i", name, data.size.x, data.size.y, index)

        create_resource = false

        pool.slices_used += {int(slice_index)}

        texture^ = Texture{
            size = {u16(data.size.x), u16(data.size.y)},
            pool_index = u8(pool_index),
            slice = u8(slice_index),
            resource = {},
        }

        gpu.update_texture_2d(
            pool.resource,
            gpu.slice_bytes(data.pixels),
            slice_index,
        )

        break
    }

    if create_resource {
        base.log_info("Creating a non-pooled texture '%s' of size %ix%i with index %i", name, data.size.x, data.size.y, index)

        // Already exists, replace the old one.
        // Possibly a name hash collision.
        if prev == hash {
            gpu.destroy_resource(texture.resource)
            texture^ = {}
        }

        res, res_ok := gpu.create_texture_2d(strings_join("rv-tex-", name, allocator = context.temp_allocator),
            format = .RGBA_U8_Norm,
            size = data.size,
            usage = .Immutable,
            data = gpu.slice_bytes(data.pixels),
        )

        assert(res_ok)

        texture^ = Texture{
            size = {u16(data.size.x), u16(data.size.y)},
            pool_index = max(u8),
            slice = 0,
            resource = res,
        }
    }

    result = {
        index = Handle_Index(index),
        gen = _state.textures_gen[index],
    }

    return result, true
}

create_texture_from_resource :: proc(name: string, handle: gpu.Resource_Handle) -> (result: Texture_Handle, ok: bool) {
    res := gpu.get_internal_resource(handle) or_return

    if res.kind != .Texture2D {
        return {}, false
    }

    hash := hash_name(name)

    index, prev := _table_insert_hash(&_state.textures_hash, hash) or_return
    assert(prev == 0, "Collision")

    texture := &_state.textures[index]
    texture^ = {
        size = {u16(res.size.x), u16(res.size.y)},
        pool_index = max(u8),
        slice = 0,
        resource = handle,
    }

    result = {
        index = Handle_Index(index),
        gen = _state.textures_gen[index],
    }

    return result, true
}

destroy_texture :: proc(handle: Texture_Handle) {
    texture, texture_ok := get_internal_texture(handle)
    if !texture_ok {
        return
    }

    gpu.destroy_resource(texture.resource)
    texture^ = {}

    _state.textures_gen[handle.index] += 1
    _state.textures_hash[handle.index] = 0
}

@(require_results)
decode_texture_data :: proc(data: []byte) -> (result: Texture_Data, ok: bool) {
    size: [2]i32
    channels: i32

    stbi.set_flip_vertically_on_load(1)

    data := stbi.load_from_memory(
        buffer = raw_data(data),
        len = i32(len(data)),
        x = &size.x,
        y = &size.y,
        channels_in_file = &channels,
        desired_channels = 4,
    )

    if data == nil {
        base.log_err("Failed to decode texture: %s", stbi.failure_reason())
        return {}, false
    }

    result = {
        size = size,
        pixels = (cast([^][4]u8)data)[:size.x * size.y],
    }

    return result, true
}

// NOTE: this is potentially unsafe.
destroy_decoded_texture_data :: proc(data: ^Texture_Data) {
    stbi.image_free(raw_data(data.pixels))
    data^ = {}
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Shaders
//
// TODO:
// Two ways to create:
// - from source: run shaderprep with VFS includes. Primarily for development.
// - from native: load HLSL/GLSL or whatever directly. Primarily for pakfiles.
//

@(require_results)
load_vertex_shader :: proc(path: string) -> (result: Vertex_Shader_Handle, ok: bool) #optional_ok {
    npath := normalize_path(path, context.temp_allocator)
    data, data_ok := get_file_data(npath)

    if !data_ok {
        base.log_err("Failed to load vertex shader: couldn't load '%s'", path)
        return {}, false
    }

    name := strip_path_name(npath)
    return create_vertex_shader(name, data)
}

@(require_results)
load_pixel_shader :: proc(path: string) -> (result: Pixel_Shader_Handle, ok: bool) #optional_ok {
    npath := normalize_path(path, context.temp_allocator)
    data, data_ok := get_file_data(npath)

    if !data_ok {
        base.log_err("Failed to load pixel shader: couldn't load '%s'", path)
        return {}, false
    }

    name := strip_path_name(npath)

    return create_pixel_shader(name, data)
}

_shader_include_proc :: proc(path: string, user: rawptr) -> (result: string, ok: bool) {
    npath := normalize_path(path, context.temp_allocator)
    data := get_file_data(npath, flush = false) or_return
    return string(data), true
}

when gpu.BACKEND == gpu.BACKEND_D3D11 {
    SHADER_COMPILER_TARGET :: shader_compiler.Target.DXBC
} else when gpu.BACKEND == gpu.BACKEND_WGPU {
    SHADER_COMPILER_TARGET :: shader_compiler.Target.WGSL
} else {
    SHADER_COMPILER_TARGET :: shader_compiler.Target.Invalid
}

@(require_results)
create_vertex_shader :: proc(name: string, data: []byte) -> (result: Vertex_Shader_Handle, ok: bool) {
    compiled: []byte
    when RELEASE {
        compiled = data
    } else {
        compiled, ok = shader_compiler.compile(
            name = name,
            source = string(data),
            opts = {
                target = SHADER_COMPILER_TARGET,
                stage = .Vertex,
                include_proc = _shader_include_proc,
            },
        )

        if !ok {
            base.log_err("Failed to compile vertex shader '%s'", name)
            return {}, false
        }
    }

    shader: gpu.Shader_Handle
    shader, ok = gpu.create_shader(name, compiled, .Vertex)

    if !ok {
        base.log_err("Failed to create vertex shader")
        return
    }

    // TODO: if this fails the shader gets leaked.
    // TODO: fix for ALL table inserts, including rscn loading and custom mesh creation etc.
    return insert_vertex_shader_by_name(name, Vertex_Shader(shader))
}


@(require_results)
create_pixel_shader :: proc(name: string, data: []byte) -> (result: Pixel_Shader_Handle, ok: bool) {
    compiled: []byte
    when RELEASE {
        compiled = data
    } else {
        compiled, ok = shader_compiler.compile(
            name = name,
            source = string(data),
            opts = {
                target = SHADER_COMPILER_TARGET,
                stage = .Pixel,
                include_proc = _shader_include_proc,
            },
        )

        if !ok {
            base.log_err("Failed to compile pixel shader '%s'", name)
            return {}, false
        }
    }

    shader: gpu.Shader_Handle
    shader, ok = gpu.create_shader(name, compiled, .Pixel)

    if !ok {
        base.log_err("Failed to create pixel shader")
        return
    }

    return insert_pixel_shader_by_name(name, Pixel_Shader(shader))
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Render Texture
//

@(require_results)
create_render_texture :: proc(size: [2]i32, depth := true) -> (result: Render_Texture_Handle, ok: bool) {
    assert(size.x > 0)
    assert(size.y > 0)
    assert(size.x <= 4096) // arbitrary
    assert(size.y <= 4096)

    used_set := (transmute(u64)_state.render_textures_used) | 1
    index := intrinsics.count_trailing_zeros(~used_set)
    if index == 64 {
        base.log_err("Failed to create render texture: there is already max number of render textures")
        return {}, false
    }

    tex := &_state.render_textures[index]

    tex.color, ok = gpu.create_texture_2d("rv-render-tex",
        format = .RGBA_U8_Norm, // HDR option in the future?
        size = size,
        render_texture = true,
    )

    if !ok {
        base.log_err("Failed to create render texture color buffer")
        return {}, false
    }

    if depth {
        // WARNING: depth SRVs not yet implemented in gpu package
        tex.depth, ok = gpu.create_texture_2d("rv-depth-tex",
            format = .D_F32,
            size = size,
            render_texture = true,
        )

        if !ok {
            base.log_err("Failed to create render texture depth buffer")
            return {}, false
        }
    }

    result = Render_Texture_Handle{
        index = Handle_Index(index),
        gen = _state.render_textures_gen[index],
    }

    _state.render_textures_used += {int(index)}

    return result, true
}

destroy_render_texture :: proc(handle: Render_Texture_Handle) {
    assert(handle.index != DEFAULT_RENDER_TEXTURE.index)
    tex, tex_ok := get_internal_render_texture(handle)
    if !tex_ok {
        // Completely fine, No-op
        return
    }

    _destroy_render_texture(tex)

    _state.render_textures_gen[handle.index] += 1
    _state.render_textures_used -= {int(handle.index)}
}

_destroy_render_texture :: proc(tex: ^Render_Texture) {
    gpu.destroy_resource(tex.color)
    gpu.destroy_resource(tex.depth)
    tex^ = {}
}

// resize_render_texture :: proc(handle: Render_Texture_Handle, size: [2]i32) {
//     assert(handle.index != DEFAULT_RENDER_TEXTURE.index)
//     _, tex_ok := get_internal_render_texture(handle)
//     if !tex_ok {
//         return
//     }
// }

@(require_results)
get_internal_render_texture :: proc(handle: Render_Texture_Handle) -> (result: ^Render_Texture, ok: bool) {
    return _table_get(&_state.render_textures, _state.render_textures_gen, handle)
}

@(require_results)
get_render_texture_size :: proc(handle: Render_Texture_Handle) -> (result: [2]i32, ok: bool) {
    rt := get_internal_render_texture(handle) or_return
    return rt.size.xy, true
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Draw State
//

@(deferred_none = pop_draw_state)
scope_draw_state :: proc() -> bool {
    push_draw_state()
    return true
}

push_draw_state :: proc() {
    if _state.draw_states_len >= MAX_DRAW_STATE_DEPTH {
        base.log_err("Cannot set bind state, reached max depth")
        return
    }

    _state.draw_states[_state.draw_states_len] = _state.draw_state
    _state.draw_states_len += 1
}

pop_draw_state :: proc() {
    assert(_state.draw_states_len > 0)
    _state.draw_states_len -= 1
    _state.draw_state = _state.draw_states[_state.draw_states_len]
}

@(require_results)
get_draw_state :: proc() -> Draw_State {
    return _state.draw_state
}

// NOTE: be very careful when changing fields in Draw_State.
// This proc should be used mostly to revert state returned by 'get_binds'
set_draw_state :: proc(binds: Draw_State) {
    _state.draw_state = binds
}

set_draw_layer :: proc(#any_int layer: i32) {
    assert(layer >= 0 && layer <= MAX_DRAW_LAYERS)
    _state.draw_state.draw_layer = u8(layer)
}

set_draw_blend :: proc(blend: Blend_Mode) {
    _state.draw_state.blend_mode = blend
}

set_draw_fill :: proc(fill: Fill_Mode) {
    _state.draw_state.fill_mode = fill
}

set_draw_depth :: proc(depth: Depth_Mode) {
    _state.draw_state.depth_mode = depth
}

set_draw_pixel_shader :: proc {
    set_draw_pixel_shader_by_name,
    set_draw_pixel_shader_by_handle,
}

set_draw_vertex_shader :: proc {
    set_draw_vertex_shader_by_name,
    set_draw_vertex_shader_by_handle,
}

set_draw_texture :: proc {
    set_draw_texture_by_const,
    set_draw_texture_by_name,
    set_draw_texture_by_handle,
    set_draw_render_texture_by_handle,
}


set_draw_pixel_shader_by_name :: proc(name: string) -> bool {
    set_draw_pixel_shader_by_handle(get_pixel_shader_by_name(name))
    return true
}

set_draw_vertex_shader_by_name :: proc(name: string) -> bool {
    set_draw_vertex_shader_by_handle(get_vertex_shader_by_name(name))
    return true
}

set_draw_texture_by_const :: proc($Name: string) -> bool {
    set_draw_texture_by_handle(get_texture_by_hash(hash_const_name(Name)))
    return true
}

set_draw_texture_by_name :: proc(name: string) -> bool {
    set_draw_texture_by_handle(get_texture_by_name(name))
    return true
}


set_draw_pixel_shader_by_handle :: proc(handle: Pixel_Shader_Handle) {
    if _, ok := get_internal_pixel_shader(handle); ok {
        _state.draw_state.ps = u8(handle.index)
    } else {
        _state.draw_state.ps = u8(_state.builtin_pixel_shader[.Default].index)
    }
}

set_draw_vertex_shader_by_handle :: proc(handle: Vertex_Shader_Handle) {
    if _, ok := get_internal_vertex_shader(handle); ok {
        _state.draw_state.vs = u8(handle.index)
    } else {
        _state.draw_state.vs = u8(_state.builtin_vertex_shader[.Default].index)
    }
}

set_draw_texture_by_handle :: proc(handle: Texture_Handle) {
    if !_set_draw_texture(handle) {
        _set_draw_texture(_state.builtin_texture[.Error])
    }
}

_set_draw_texture :: proc(handle: Texture_Handle) -> bool {
    tex := get_internal_texture(handle) or_return
    if tex.resource != {} {
        // Standalone tex
        _state.draw_state.texture_kind = .Non_Pooled
        _state.draw_state.texture = u8(handle.index)
        _state.draw_state.texture_slice = 0
        _state.draw_state.texture_size = tex.size
    } else {
        // Pool slice index
        pool := _state.texture_pools[tex.pool_index]
        assert(int(tex.slice) < int(pool.slices))
        assert(int(tex.slice) in pool.slices_used)

        _state.draw_state.texture_kind = .Pooled
        _state.draw_state.texture = u8(tex.pool_index)
        _state.draw_state.texture_slice = u8(tex.slice)
        _state.draw_state.texture_size = {
            u16(pool.size.x),
            u16(pool.size.y),
        }
    }
    return true
}

// Bind render texture for READING like a regular texture.
// In order to WRITE to a render texture, use layers.
set_draw_render_texture_by_handle :: proc(handle: Render_Texture_Handle) {
    assert(handle != DEFAULT_RENDER_TEXTURE)
    tex, tex_ok := get_internal_render_texture(handle)
    if !tex_ok {
        _set_draw_texture(_state.builtin_texture[.Error])
        return
    }
    assert(tex.color != {})

    _state.draw_state.texture_kind = .Render_Texture
    _state.draw_state.texture = u8(handle.index)
    _state.draw_state.texture_slice = 0
    _state.draw_state.texture_size = {
        u16(tex.size.x),
        u16(tex.size.y),
    }
}


// NOTE: Prefer calling this before any draw_* commands.
// But the params persist between frames.
set_layer_params :: proc(
    #any_int layer: i32,
    camera:         Camera,
    flags:          bit_set[Draw_Layer_Flag] = {},
) {
    layer, layer_ok := get_internal_draw_layer(layer)
    if !layer_ok {
        base.log_err("Invalid layer index")
        assert(false)
        return
    }

    layer.flags = flags
    layer.camera = camera

    // Inverts the flip flag based on matrix Y scaling
    if layer.camera.projection[1, 1] < 0 {
        flipped := .Flip_Y in layer.flags
        if flipped {
            layer.flags -= {.Flip_Y}
        } else {
            layer.flags += {.Flip_Y}
        }
    }
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Draw
//

// TODO: 2d variants!
draw_sprite :: proc(
    pos:        Vec3,
    rect:       Rect = {0, 1},
    scale:      Vec2 = 1,
    col:        Vec4 = 1,
    rot:        Quat = 1,
    anchor:     Vec2 = 0,
    add_col:    Vec4 = 0,
    scaling:    Sprite_Scaling = .Pixel,
    param:      u32 = 0,
) {
    perf_scope()

    validate_vec3(pos)

    mat := linalg.matrix3_from_quaternion_f32(rot)

    draw_layer := &_state.draw_layers[_state.draw_state.draw_layer]

    rect_size := rect_full_size(rect)

    size := Vec2{
        scale.x * 0.5,
        scale.y * 0.5,
    }

    size.y = .Flip_Y in draw_layer.flags ? -size.y : size.y


    switch scaling {
    case .Pixel:
        size *= {
            f32(_state.draw_state.texture_size.x) * rect_size.x,
            f32(_state.draw_state.texture_size.y) * rect_size.y,
        }

    case .Absolute:
        // No scaling
    }

    center := pos
    center -= mat[0] * anchor.x * size.x
    center -= mat[1] * anchor.y * size.y

    rect_size_sign := Vec2{
        rect_size.x > 0 ? 1 : -1,
        rect_size.y > 0 ? 1 : -1,
    }

    inst := pack_sprite_inst(
        pos = center,
        mat_x = mat[0] * size.x,
        mat_y = mat[1] * size.y,
        uv_min = rect.min + rect_size_sign * UV_EPS,
        uv_size = rect_size - rect_size_sign * UV_EPS * 2,
        col = col,
        add_col = add_col,
        tex_slice = _state.draw_state.texture_slice,
        param = param,
    )

    key := _state.draw_state.key
    key.vs = u8(_state.builtin_vertex_shader[.Default_Sprite].index) // for now the VS is fixed

    _draw_batch_table_push(&draw_layer.sprites, key, inst, max(size.x, size.y))
}

draw_rect :: proc(
    rect:       Rect,
    tex_rect:   Rect = {0, 1},
    z:          f32 = 0.0,
    col:        Vec4 = 1,
    add_col:    Vec4 = 0,
    param:      u32 = 0,
) {
    center := rect_center(rect)
    size := rect_full_size(rect)

    tex_size_sign := Vec2{
        math.sign_f32(size.x),
        math.sign_f32(size.y),
    }

    inst := pack_sprite_inst(
        pos = {center.x, center.y, z},
        mat_x = {size.x * 0.5, 0, 0},
        mat_y = {0, size.y * 0.5, 0},
        uv_min = tex_rect.min + tex_size_sign * UV_EPS,
        uv_size = rect_full_size(tex_rect) - tex_size_sign * UV_EPS * 2,
        col = col,
        add_col = add_col,
        tex_slice = _state.draw_state.texture_slice,
        param = param,
    )

    key := _state.draw_state.key
    key.vs = u8(_state.builtin_vertex_shader[.Default_Sprite].index) // for now the VS is fixed

    draw_layer := &_state.draw_layers[_state.draw_state.draw_layer]
    _draw_batch_table_push(&draw_layer.sprites, key, inst, max(size.x, size.y))
}



// Returns a slice of the GPU sprite instances.
// TODO: real text draw iterator?
draw_text :: proc(
    text:       string, // UTF-8
    pos:        [3]f32,
    scale:      Vec2 = 1,
    anchor:     Vec2 = -1, // Anchor point in local space. -1 = left aligned, 0 = centered, 1.0 = right aligned
    spacing:    Vec2 = {0, 8}, // x = character spacing, y = line spacing
    col:        Vec4 = 1,
    rot:        Quat = 1,
) -> []Sprite_Inst {
    perf_scope()

    char_size := IVec2{
        i32(_state.draw_state.texture_size.x) / 16,
        i32(_state.draw_state.texture_size.y) / 16,
    }

    full_size := calc_text_size(
        text = text,
        scale = scale,
        char_size = char_size,
        spacing = spacing,
    )

    // TODO: check layer Flip_Y

    mat := linalg.matrix3_from_quaternion_f32(rot)

    center := pos +
        mat[0] * f32(char_size.x) * scale.x * 0.5 +
        mat[1] * f32(char_size.y) * scale.y * 0.5 +
        mat[0] * full_size.x * -(anchor.x * 0.5 + 0.5) +
        mat[1] * full_size.y * -(anchor.y * 0.5 + 0.5)

    offs: Vec2

    for r in text {
        if rune_is_drawable(r) {
            ch := rune_to_char(r)

            p := center + (
                mat[0] * offs.x +
                mat[1] * offs.y
            )

            // TODO: correct anchor
            draw_sprite(
                pos = p,
                rect = font_slot(ch),
                scale = scale,
                col = col,
                rot = rot,
            )
        }

        offs = text_glyph_apply(offs, r, scale = scale, char_size = char_size, spacing = spacing)
    }

    // TODO:
    // return draw_layer.sprites.inst[:len(draw_layer.sprites)][start_offs:]
    return {}
}

rune_is_drawable :: proc(r: rune) -> bool {
    switch r {
    case ' ', '\n', '\t':
        return false
    }
    return true
}

calc_text_size :: proc(text: string, scale: Vec2, char_size: IVec2 = 8, spacing: Vec2 = 0) -> Vec2 {
    offs: Vec2

    size: Vec2

    for r in text {
        offs = text_glyph_apply(offs, r, scale = scale, char_size = char_size, spacing = spacing)
        size = {
            max(size.x, offs.x),
            max(size.y, offs.y),
        }
    }

    return size + {0, (f32(char_size.y) + spacing.y) * scale.y}
}

text_glyph_apply :: proc(offs: Vec2, r: rune, scale: Vec2, char_size: IVec2 = 8, spacing: Vec2 = 0) -> Vec2 {
    offs := offs

    switch r {
    case '\n':
        offs.x = 0
        offs.y += scale.y * (f32(char_size.y) + spacing.y)
        return offs

    case '\t':
        tab_size := scale.x * (f32(char_size.x) + spacing.x) * 4
        offs.x = math.ceil_f32(offs.x / tab_size + 1) * tab_size
        return offs
    }

    offs.x += scale.x * (f32(char_size.x) + spacing.x)

    return offs
}

draw_mesh :: proc(
    handle:     Mesh_Handle,
    pos:        Vec3,
    rot:        Quat = 1,
    scale:      Vec3 = 1,
    col:        Vec4 = 1,
    add_col:    Vec4 = 0,
    param:      u32 = 0,
) {
    perf_scope()

    validate_vec3(pos)

    mesh, mesh_ok := get_internal_mesh(handle)
    validate(mesh_ok)

    mat := linalg.matrix3_from_quaternion_f32(rot)

    key := _state.draw_state.key
    key.asset_index = u16(handle.index)
    key.group = u8(mesh.group.index)

    // Scale diag mat determinant
    if scale.x * scale.y * scale.z < 0 {
        switch key.fill_mode {
        case .All, .Wire: // no op
        case .Front: key.fill_mode = .Back
        case .Back: key.fill_mode = .Front
        }
    }

    inst := pack_mesh_inst(
        pos = pos,
        mat_x = mat[0] * scale.x,
        mat_y = mat[1] * scale.y,
        mat_z = mat[2] * scale.z,
        tex_slice = _state.draw_state.texture_slice,
        vert_offs = u32(mesh.vert_offs),
        param = param,
        col = col,
        add_col = add_col,
    )

    rad := mesh.bounds_rad * max(scale.x, scale.y, scale.z)

    draw_layer := &_state.draw_layers[_state.draw_state.draw_layer]
    _draw_batch_table_push(&draw_layer.meshes, key, inst, rad)
}

draw_triangles :: proc(
    verts:      ..Vertex,
    pos:        Vec3 = 0,
    rot:        Quat = 1,
    scale:      Vec3 = 1,
    col:        Vec4 = WHITE,
    add_col:    Vec4 = 0,
    param:      u32 = 0,
) {
    perf_scope()

    validate_vec3(pos)
    validate_quat(rot)
    validate_vec4(col)
    validate_vec4(add_col)
    validate(len(verts) % 3 == 0)

    if len(verts) == 0 {
        return
    }

    draw_layer := &_state.draw_layers[_state.draw_state.draw_layer]
    offset, num := _push_draw_dynamic_verts(verts)
    mat := linalg.matrix3_from_quaternion_f32(rot)

    key := _state.draw_state.key
    key.asset_index = int_cast(u16, num)

    inst := pack_mesh_inst(
        pos = pos,
        mat_x = mat[0] * scale.x,
        mat_y = mat[1] * scale.y,
        mat_z = mat[2] * scale.z,
        tex_slice = _state.draw_state.texture_slice,
        vert_offs = u32(offset),
        param = param,
        col = col,
        add_col = add_col,
    )

    _draw_batch_table_push(&draw_layer.triangles, key, inst, 0)
}

draw_lines :: proc(
    verts:      ..Vertex,
    pos:        Vec3 = 0,
    rot:        Quat = 1,
    scale:      Vec3 = 1,
    col:        Vec4 = WHITE,
    add_col:    Vec4 = 0,
    param:      u32 = 0,
) {
    perf_scope()

    validate(len(verts) % 2 == 0)
    validate_vec3(pos)
    validate_quat(rot)
    validate_vec4(col)
    validate_vec4(add_col)

    if len(verts) == 0 {
        return
    }

    draw_layer := &_state.draw_layers[_state.draw_state.draw_layer]
    offset, num := _push_draw_dynamic_verts(verts)
    mat := linalg.matrix3_from_quaternion_f32(rot)

    key := _state.draw_state.key
    key.asset_index = int_cast(u16, num)

    inst := pack_mesh_inst(
        pos = pos,
        mat_x = mat[0] * scale.x,
        mat_y = mat[1] * scale.y,
        mat_z = mat[2] * scale.z,
        tex_slice = _state.draw_state.texture_slice,
        vert_offs = u32(offset),
        param = param,
        col = col,
        add_col = add_col,
    )

    _draw_batch_table_push(&draw_layer.lines, key, inst, 0)
}

// Prefer draw_triangles if you need to efficiently draw many triangles.
draw_triangle :: proc(
    pos:        [3]Vec3,
    col:        [3]Vec4 = WHITE,
    uvs:        [3]Vec2 = {{0, 0}, {1, 0}, {0, 1}},
    add_col:    Vec4 = BLACK,
    normals:    Maybe([3]Vec3) = nil,
) {
    validate_vec3(pos[0])
    validate_vec3(pos[1])
    validate_vec3(pos[2])

    norm, norm_ok := normals.?
    if !norm_ok {
        norm = linalg.normalize0(linalg.cross(pos[1] - pos[0], pos[2] - pos[0]))
    }

    verts: [3]Vertex
    for i in 0..<3 {
        verts[i] = pack_vertex(
            pos = pos[i],
            uv = uvs[i],
            normal = norm[i],
            col = col[i],
        )
    }

    draw_triangles(..verts[:])
}

// Prefer draw_lines if you need to efficiently draw many lines.
draw_line :: proc(
    pos0:       Vec3,
    pos1:       Vec3,
    col:        [2]Vec4 = WHITE,
    uvs:        [2]Vec2 = {{0, 0.5}, {1, 0.5}},
    add_col:    Vec4 = BLACK,
    normals:    Maybe([2]Vec3) = nil,
) {
    validate_vec3(pos0)
    validate_vec3(pos1)

    norm, norm_ok := normals.?
    if !norm_ok {
        norm = Vec3{0, 1, 0}
    }

    verts: [2]Vertex
    for &v, i in verts {
        v = pack_vertex(
            pos = i == 0 ? pos0 : pos1,
            uv = uvs[i],
            normal = norm[i],
            col = col[i],
        )
    }

    draw_lines(..verts[:])
}


_init_draw_array :: #force_inline proc(arr: ^$T/#soa[dynamic]$V, #any_int last_len: int) {
    if len(arr) == 0 {
        arr ^= make_soa_dynamic_array_len_cap(
            #soa[dynamic]V,
            0,
            256 + last_len,
            context.temp_allocator,
        )
    }
    assert(arr.allocator == context.temp_allocator)
}

_push_draw_dynamic_verts :: proc(verts: []Vertex) -> (offset: int, length: int) {
    offset = int(_state.dynamic_vert_upload_offs)
    length = min(len(verts), len(_state.dynamic_vert_upload_buf) - offset)

    _state.dynamic_vert_upload_offs += u32(length)
    intrinsics.mem_copy_non_overlapping(raw_data(_state.dynamic_vert_upload_buf[offset:]), raw_data(verts), length * size_of(Vertex))

    return offset, length
}


// MARK: Line shapes

_BOX_CORNER_POSITIONS :: [8]Vec3 {
    0 = Vec3{-1, -1, -1},
    1 = Vec3{-1, -1, +1},
    2 = Vec3{-1, +1, -1},
    3 = Vec3{-1, +1, +1},
    4 = Vec3{+1, -1, -1},
    5 = Vec3{+1, -1, +1},
    6 = Vec3{+1, +1, -1},
    7 = Vec3{+1, +1, +1},
}

draw_line_triangle :: proc(verts: [3]Vec3, col := WHITE) {
    if col.a < 0.01 do return
    draw_lines(
        pack_vertex(verts[0], col = col), pack_vertex(verts[1], col = col),
        pack_vertex(verts[1], col = col), pack_vertex(verts[2], col = col),
        pack_vertex(verts[2], col = col), pack_vertex(verts[0], col = col),
    )
}

draw_line_point :: proc(pos: Vec3, rad: Vec3 = 1, col := WHITE) {
    if col.a < 0.01 do return
    draw_lines(
        pack_vertex(pos + {-rad.x, 0, 0}, col = col), pack_vertex(pos + {rad.x, 0, 0}, col = col),
        pack_vertex(pos + {0, -rad.y, 0}, col = col), pack_vertex(pos + {0, rad.y, 0}, col = col),
        pack_vertex(pos + {0, 0, -rad.z}, col = col), pack_vertex(pos + {0, 0, rad.z}, col = col),
    )
}

draw_line_box :: proc(pos: Vec3, mat: Mat3 = 1, col := WHITE) {
    if col.a < 0.01 do return
    corners := _BOX_CORNER_POSITIONS
    for &c in corners {
        c = pos + mat * c
    }
    _draw_line_box_corners(corners, col)
}

draw_line_mat3 :: proc(pos: Vec3, mat: Mat3 = 1) {
    draw_lines(
        pack_vertex(pos, col = WHITE),    pack_vertex(pos + mat[0], col = RED),
        pack_vertex(pos, col = WHITE),  pack_vertex(pos + mat[1], col = GREEN),
        pack_vertex(pos, col = WHITE),   pack_vertex(pos + mat[2], col = BLUE),
    )
}

draw_line_aabb :: proc(min: Vec3, max: Vec3, col := WHITE) {
    if col.a < 0.01 do return
    corners := [8]Vec3 {
        0 = Vec3{min.x, min.y, min.z},
        1 = Vec3{min.x, min.y, max.z},
        2 = Vec3{min.x, max.y, min.z},
        3 = Vec3{min.x, max.y, max.z},
        4 = Vec3{max.x, min.y, min.z},
        5 = Vec3{max.x, min.y, max.z},
        6 = Vec3{max.x, max.y, min.z},
        7 = Vec3{max.x, max.y, max.z},
    }
    _draw_line_box_corners(corners, col)
}

draw_line_circle :: proc(
    pos:        Vec3,
    rad:        Vec2 = 1,
    axis:       Vec3 = {0, 1, 0},
    col         := WHITE,
    segments    := 12,
) {
    if col.a < 0.01 do return

    circle := _calc_circle_points(segments)

    u := rad.x * linalg.normalize0(linalg.cross(axis, abs(axis.y) > 0.9 ? Vec3{1, 0, 0} : Vec3{0, 1, 0}))
    v := rad.y * linalg.normalize0(linalg.cross(u, axis))

    verts := make([]Vertex, segments * 2, context.temp_allocator)
    p0 := circle[len(circle) - 1]
    for p1, i in circle {
        verts[i * 2 + 0] = pack_vertex(pos + u * p0.x + v * p0.y, col = col)
        verts[i * 2 + 1] = pack_vertex(pos + u * p1.x + v * p1.y, col = col)
        p0 = p1
    }

    draw_lines(..verts)
}

draw_line_sphere :: proc(
    pos:        Vec3,
    mat:        Mat3 = 1,
    col         := WHITE,
    segments    := 12,
) {
    if col.a < 0.01 do return

    circle := _calc_circle_points(segments)

    verts := make([]Vertex, segments * 2 * 3, context.temp_allocator)
    p0 := circle[len(circle) - 1]
    for p1, i in circle {
        // XY, YZ, ZX
        verts[i * 6 + 0] = pack_vertex(pos + mat[0] * p0.x + mat[1] * p0.y, col = col)
        verts[i * 6 + 1] = pack_vertex(pos + mat[0] * p1.x + mat[1] * p1.y, col = col)
        verts[i * 6 + 2] = pack_vertex(pos + mat[1] * p0.x + mat[2] * p0.y, col = col)
        verts[i * 6 + 3] = pack_vertex(pos + mat[1] * p1.x + mat[2] * p1.y, col = col)
        verts[i * 6 + 4] = pack_vertex(pos + mat[2] * p0.x + mat[0] * p0.y, col = col)
        verts[i * 6 + 5] = pack_vertex(pos + mat[2] * p1.x + mat[0] * p1.y, col = col)
        p0 = p1
    }

    draw_lines(..verts)
}

draw_line_cylinder :: proc(pos: [2]Vec3, rad: f32 = 1.0, col := WHITE, segments := 12) {
    if col.a < 0.01 do return

    axis := linalg.normalize0(pos[1] - pos[0])

    u := rad * linalg.normalize0(linalg.cross(axis, abs(axis.y) > 0.9 ? Vec3{1, 0, 0} : Vec3{0, 1, 0}))
    v := rad * linalg.normalize0(linalg.cross(u, axis))

    circle := _calc_circle_points(segments)

    verts := make([]Vertex, 4 * 2 + segments * 2 * 2, context.temp_allocator)
    verts[0] = pack_vertex(pos[0] + u, col = col); verts[1] = pack_vertex(pos[1] + u, col = col)
    verts[2] = pack_vertex(pos[0] - u, col = col); verts[3] = pack_vertex(pos[1] - u, col = col)
    verts[4] = pack_vertex(pos[0] + v, col = col); verts[5] = pack_vertex(pos[1] + v, col = col)
    verts[6] = pack_vertex(pos[0] - v, col = col); verts[7] = pack_vertex(pos[1] - v, col = col)

    offs := 8
    p0 := circle[len(circle) - 1]
    for p1 in circle {
        verts[offs + 0] = pack_vertex(pos[0] + u * p0.x + v * p0.y, col = col)
        verts[offs + 1] = pack_vertex(pos[0] + u * p1.x + v * p1.y, col = col)
        verts[offs + 2] = pack_vertex(pos[1] + u * p0.x + v * p0.y, col = col)
        verts[offs + 3] = pack_vertex(pos[1] + u * p1.x + v * p1.y, col = col)
        p0 = p1
        offs += 4
    }

    draw_lines(..verts)
}

// The axis vectors determine a single cell size.
// Segments are the number of lines in ONE QUADRANT.
draw_line_grid :: proc(
    pos:        Vec3 = 0,
    axis_a:     Vec3 = {1, 0, 0},
    axis_b:     Vec3 = {0, 0, 1},
    col         := WHITE,
    segments:   [2]i32 = 5,
) {
    buf := make([]Vertex,  (segments.x * 2 + 1 + segments.y * 2 + 1) * 2, context.temp_allocator)
    index := 0

    for i in -segments.x..=segments.x {
        c := i == 0 ? col + 0.1 : col * 0.8
        offs := axis_a * f32(i)
        buf[index + 0] = pack_vertex(pos + offs - axis_b * f32(segments.y), col = c)
        buf[index + 1] = pack_vertex(pos + offs + axis_b * f32(segments.y), col = c)
        index += 2
    }

    for i in -segments.y..=segments.y {
        c := i == 0 ? col + 0.1 : col * 0.8
        offs := axis_b * f32(i)
        buf[index + 0] = pack_vertex(pos + offs - axis_a * f32(segments.x), col = c)
        buf[index + 1] = pack_vertex(pos + offs + axis_a * f32(segments.x), col = c)
        index += 2
    }

    draw_lines(..buf)
}

_draw_line_box_corners :: proc(corners: [8]Vec3, col: Vec4) {
    if col.a <= 0.01 do return
    draw_lines(
        pack_vertex(corners[0], col = col), pack_vertex(corners[1], col = col),
        pack_vertex(corners[0], col = col), pack_vertex(corners[2], col = col),
        pack_vertex(corners[3], col = col), pack_vertex(corners[1], col = col),
        pack_vertex(corners[3], col = col), pack_vertex(corners[2], col = col),

        pack_vertex(corners[4], col = col), pack_vertex(corners[5], col = col),
        pack_vertex(corners[4], col = col), pack_vertex(corners[6], col = col),
        pack_vertex(corners[7], col = col), pack_vertex(corners[5], col = col),
        pack_vertex(corners[7], col = col), pack_vertex(corners[6], col = col),

        pack_vertex(corners[4], col = col), pack_vertex(corners[0], col = col),
        pack_vertex(corners[5], col = col), pack_vertex(corners[1], col = col),
        pack_vertex(corners[6], col = col), pack_vertex(corners[2], col = col),
        pack_vertex(corners[7], col = col), pack_vertex(corners[3], col = col),
    )
}

_calc_circle_points :: proc(segments: int) -> []Vec2 {
    /* Can be approximated with:
    import "core:math"
    import "core:fmt"
    main :: proc() {
        for i in 0..<12 {
            a := f32(i) * math.TAU / 12
            fmt.println(math.sin_f32(a), math.cos_f32(a))
        }
    }
    */
    @(rodata, static)
    _circle_points := [12]Vec2{
        {0, 1},
        {0.5, 0.86602539},
        {0.86602545, 0.5},
        {1, 0},
        {0.86602539, -0.5},
        {0.5, -0.8660255},
        {0, -1},
        {-0.5, -0.86602527},
        {-0.86602545, -0.5},
        {-1, 0},
        {-0.8660252, 0.5},
        {-0.5, 0.86602557},
    }

    // Fast default path
    if segments == len(_circle_points) {
        return _circle_points[:]
    }

    buf := make([]Vec2, segments, context.temp_allocator)
    for &p, i in buf {
        t := f32(i) * math.TAU / f32(segments)
        p = {math.cos_f32(t), math.sin_f32(t)}
    }
    return buf
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Draw Batching
//

_draw_batch_table_init :: proc(table: ^$T/Draw_Batch_Table($Inst)) {
    for &batch in table.batches[:table.len] {
        batch.last_len = align_up(batch.len, LANES)

        batch.inst_data = nil
        batch.cull_data = nil
        batch.cap = 0
        batch.len = 0
    }

    table.len = 0
    for &lookup in table.lookup {
        lookup = max(u16)
    }
}

_draw_batch_table_push :: proc(
    table:      ^$T/Draw_Batch_Table($Inst),
    key:        Draw_Batch_Key,
    inst:       Inst,
    cull_rad:   f32,
) #no_bounds_check {
    hash := #force_inline hash_splittable64(transmute(u64)key)

    lookup_index := u64(hash % DRAW_BATCH_TABLE_LOOKUP)
    index := -1
    found := false

    for _ in 0..<DRAW_BATCH_TABLE_MAX_PROBE {
        batch_index := table.lookup[lookup_index]

        if batch_index == max(u16) {
            found = true
            break
        }

        batch_key := table.keys[batch_index]

        if batch_key == key {
            index = int(batch_index)
            found = true
            break
        }

        lookup_index = (lookup_index + 1) % DRAW_BATCH_TABLE_LOOKUP
    }

    if !found {
        assert(false)
        return
    }

    if index == -1 {
        if table.len >= DRAW_BATCH_TABLE_BATCHES {
            assert(false)
            return
        }

        index = int(table.len)

        table.keys[index] = key
        table.lookup[lookup_index] = u16(index)

        table.len += 1
    }

    ELEM_SIZE :: size_of(Inst)

    batch := &table.batches[index]

    // Note: the reallocation should be extremely infrequent,
    // as we're tracking the last frame "waterline".
    if batch.len >= batch.cap {
        batch.cap = max(256 + batch.last_len, batch.cap * 2)
        new_inst := make([^]Inst, batch.cap, context.temp_allocator)
        new_cull := make([^]Draw_Cull_Group, batch.cap, context.temp_allocator)

        if batch.len > 0 {
            intrinsics.mem_copy_non_overlapping(rawptr(new_inst), batch.inst_data, size_of(Inst) * batch.len)
            intrinsics.mem_copy_non_overlapping(rawptr(new_cull), batch.cull_data, size_of(Draw_Cull_Group) * batch.len / LANES)
        }

        // if batch.inst_data != nil {
        //     base.log_warn("REALLOC %x %i %i", uintptr(batch), batch.last_len, batch.cap)
        // }

        batch.inst_data = new_inst
        batch.cull_data = new_cull
    }

    batch.inst_data[batch.len] = inst

    lane_id := batch.len % LANES
    batch.cull_data[batch.len / LANES].pos_scalar.x[lane_id] = inst.pos.x
    batch.cull_data[batch.len / LANES].pos_scalar.y[lane_id] = inst.pos.y
    batch.cull_data[batch.len / LANES].pos_scalar.z[lane_id] = inst.pos.z
    batch.cull_data[batch.len / LANES].rad_scalar[lane_id] = cull_rad

    batch.len += 1
}

_cull_draw_batch :: proc(
    batch:      ^Draw_Batch($Inst),
    frustum:    Frustum,
    fru_pos:    [3]#simd[LANES]f32,
    fru_rad:    [3]#simd[LANES]f32,
    fru_planes: [6][4]#simd[LANES]f32,
) #no_bounds_check {
    culled_insts := make([]Inst, batch.len, context.temp_allocator)
    culled_len := 0

    num_lane_groups := (batch.len + LANES - 1) / LANES

    for group_index in 0..<num_lane_groups {
        batch_cull := batch.cull_data[group_index]

        mask: [LANES]b32
        if true {
            mask_vec := #force_inline is_sphere_in_frustum_simd(
                fru_pos = fru_pos,
                fru_rad = fru_rad,
                fru_planes = fru_planes,
                pos = batch_cull.pos,
                rad = batch_cull.rad,
            )

            mask = transmute([LANES]b32)mask_vec

        } else {

            for &m, i in mask {
                m = b32(is_sphere_in_frustum(
                    frustum,
                    {
                        batch_cull.pos_scalar.x[i],
                        batch_cull.pos_scalar.y[i],
                        batch_cull.pos_scalar.z[i],
                    },
                    batch_cull.rad_scalar[i],
                ))
            }
        }

        for lane_index in 0..<u32(LANES) {
            read_index := group_index * LANES + lane_index
            if mask[lane_index] && read_index < batch.len {
                culled_insts[culled_len] = batch.inst_data[read_index]
                culled_len += 1
            }
        }
    }

    // Re-map the data to a new final buffer just for rendering.
    // From this point it cannot be pushed to!
    batch.cull_data = nil
    batch.inst_data = raw_data(culled_insts)
    batch.cap = 0
    batch.len = u32(culled_len)
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: GPU Data Upload
//

_upload_gpu_global_constants :: proc() {
    perf_scope()

    gpu.update_constants(_state.global_consts, gpu.ptr_bytes(&Draw_Global_Constants{
        time = get_time(),
        delta_time = get_delta_time(),
        frame = u32(get_frame_index()),
        resolution = _state.screen_size,
        rand_seed = 0,
        param = 0,
    }))
}

_upload_gpu_layer_constants :: proc() {
    perf_scope()

    consts_buf: [MAX_DRAW_LAYERS]Draw_Layer_Constants

    for &layer, i in _state.draw_layers {
        const_data: Draw_Layer_Constants = {
            view_proj = calc_camera_world_to_clip_matrix(layer.camera),
            cam_pos = layer.camera.pos,
            layer_index = i32(i),
        }

        consts_buf[i] = const_data
    }

    gpu.update_constants(_state.draw_layers_consts, gpu.ptr_bytes(&consts_buf))
}

// Finishes drawing for this frame.
// This takes all the draw_* command data and uploads them to GPU buffers.
// Call render_layer(...) to actually draw.
// NOTE: until the start of the next frame, all draw_* commands after this call will be ignored.
@(optimization_mode="favor_size")
submit_layers :: proc() {
    assert(!_state.submitted_layers)
    _state.submitted_layers = true

    perf_scope()

    for &layer in _state.draw_layers {
        perf_scope("submit_layers cull")

        if layer.camera == {} || .No_Cull in layer.flags {
            continue
        }

        fru := calc_camera_frustum(layer.camera)

        fru_pos_vec := (fru.bounds_min + fru.bounds_max) * 0.5
        fru_rad_vec := (fru.bounds_max - fru.bounds_min) * 0.5

        fru_pos: [3]#simd[LANES]f32 = {fru_pos_vec.x, fru_pos_vec.y, fru_pos_vec.z}
        fru_rad: [3]#simd[LANES]f32 = {fru_rad_vec.x, fru_rad_vec.y, fru_rad_vec.z}

        fru_planes: [6][4]#simd[LANES]f32
        for &pl, i in fru_planes {
            pl = {
                fru.planes[i].x,
                fru.planes[i].y,
                fru.planes[i].z,
                fru.planes[i].w,
            }
        }

        for &batch in layer.meshes.batches[:layer.meshes.len] {
            #force_inline _cull_draw_batch(
                batch = &batch,
                frustum = fru,
                fru_pos = fru_pos,
                fru_rad = fru_rad,
                fru_planes = fru_planes,
            )
        }

        for &batch in layer.sprites.batches[:layer.sprites.len] {
            #force_inline _cull_draw_batch(
                batch = &batch,
                frustum = fru,
                fru_pos = fru_pos,
                fru_rad = fru_rad,
                fru_planes = fru_planes,
            )
        }
    }

    _upload_gpu_global_constants()

    _upload_gpu_layer_constants()

    Batcher_State :: struct {
        consts:         [MAX_TOTAL_DRAW_BATCHES]Draw_Batch_Constants,
        consts_num:     u32,
    }

    batcher: Batcher_State

    // Dynamic Verts
    {
        perf_scope("submit_layers dynverts")

        gpu.update_buffer(
            _state.dynamic_vert_buf,
            offset = 0,
            buffers = {
                gpu.slice_bytes(_state.dynamic_vert_upload_buf[:_state.dynamic_vert_upload_offs]),
            },
        )
    }

    // Generate upload ranges for sprite data
    sprite_upload_offs := 0
    sprite_upload_bufs := make([dynamic][]byte, 0, 256, context.temp_allocator)
    for &layer in _state.draw_layers {
        for &batch in layer.sprites.batches[:layer.sprites.len] {
            batch.consts_offset = _batcher_consts_push(&batcher, sprite_upload_offs)
            append(&sprite_upload_bufs, gpu.slice_bytes(batch.inst_data[:batch.len]))
            sprite_upload_offs += int(batch.len)
        }
    }

    gpu.update_buffer(
        _state.sprite_inst_buf,
        offset = 0,
        buffers = sprite_upload_bufs[:],
    )

    // Generate upload ranges for mesh-like data
    mesh_upload_offs := 0
    mesh_upload_bufs := make([dynamic][]byte, 0, 256, context.temp_allocator)
    for &layer in _state.draw_layers {
        for &batch in layer.meshes.batches[:layer.meshes.len] {
            batch.consts_offset = _batcher_consts_push(&batcher, mesh_upload_offs)
            append(&mesh_upload_bufs, gpu.slice_bytes(batch.inst_data[:batch.len]))
            mesh_upload_offs += int(batch.len)
        }

        for &batch in layer.triangles.batches[:layer.triangles.len] {
            batch.consts_offset = _batcher_consts_push(&batcher, mesh_upload_offs)
            append(&mesh_upload_bufs, gpu.slice_bytes(batch.inst_data[:batch.len]))
            mesh_upload_offs += int(batch.len)
        }

        for &batch in layer.lines.batches[:layer.lines.len] {
            batch.consts_offset = _batcher_consts_push(&batcher, mesh_upload_offs)
            append(&mesh_upload_bufs, gpu.slice_bytes(batch.inst_data[:batch.len]))
            mesh_upload_offs += int(batch.len)
        }
    }

    gpu.update_buffer(
        _state.mesh_inst_buf,
        offset = 0,
        buffers = mesh_upload_bufs[:],
    )

    gpu.update_constants(
        _state.draw_batch_consts,
        gpu.slice_bytes(batcher.consts[:batcher.consts_num]),
    )

    return

    _batcher_consts_push :: proc(batcher: ^Batcher_State, #any_int offset: u32) -> (result: u32) {
        assert(batcher.consts_num < len(batcher.consts))
        batcher.consts[batcher.consts_num] = {
            instance_offset = offset,
        }
        result = batcher.consts_num
        batcher.consts_num += 1
        return result
    }
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: GPU Drawing
//

GPU_SAMPLER_SLOTS :: 4
GPU_CONSTANT_SLOTS :: 4
GPU_RESOURCE_SLOTS :: 4

// NOTE: the instance bind data only use a few of the available sots (consts/resources/blends/etc)
// We could possibly expose a direct way for the user to control this on per-layer basis.
// Custom pipeline and pass desc input?
@(optimization_mode="favor_size")
render_layer :: proc(
    #any_int layer_index:   i32,
    ren_tex_handle:         Render_Texture_Handle = DEFAULT_RENDER_TEXTURE,
    clear_color:            Maybe(Vec3),
    clear_depth:            bool,
    // User configurable GPU parameters.
    // Only first few slots are consumed by built-in raven resources,
    // so the rest is free to use.
    //
    // See GPU_*_SLOTS for the offsets.
    //
    // NOTE: if you need even more configurability, there's nothing
    // stopping you from writing a completely custom render_layer replacement.
    // All you need to do is create a custom GPU pass and call _render_layer_* procs.
    user_samplers:          []gpu.Sampler_Desc = nil,
    user_constants:         []gpu.Resource_Handle = nil,
    user_resources:         []gpu.Resource_Handle = nil,
) {
    assert(ren_tex_handle != {})

    perf_scope()

    if !_state.submitted_layers {
        submit_layers()
    }

    ren_tex, ren_tex_ok := get_internal_render_texture(ren_tex_handle)
    if !ren_tex_ok {
        base.log_err("Trying to submit GPU commands of an invalid render texture:", ren_tex_handle)
        return
    }

    clear_color_val: [4]f32 = {0, 0, 0, 1}
    clear_color_val.rgb = clear_color.? or_else {}
    pass_desc := gpu.Pass_Desc{
        colors = {
            0 = {
                resource = ren_tex.color,
                clear_mode = clear_color == nil ? .Keep : .Clear,
                clear_val = clear_color_val,
            },
        },
        depth = {
            resource = ren_tex.depth,
            clear_mode = clear_depth ? .Clear : .Keep,
            clear_val = 0.0,
        },
    }

    gpu.scope_pass("raven-layer", pass_desc)

    // BIG WARNING:
    // On certain GPU backends, the pipeline state has to be baked and a new pipeline has to be created,
    // when it's not already in pipeline cache.
    // For this reason a lot of care should be taken to minimize possible states.
    pip_desc := gpu.Pipeline_Desc {
        color_format = {
            0 = .RGBA_U8_Norm,
        },
        depth_format = .D_F32,
        topo = .Triangles,
        constants = {
            0 = _state.global_consts,
            1 = _state.draw_layers_consts,
            2 = _state.draw_batch_consts,
        },
        samplers = {
            0 = DEFAULT_SAMPLER,
        },
    }

    copy(pip_desc.samplers[GPU_SAMPLER_SLOTS:], user_samplers)
    copy(pip_desc.constants[GPU_CONSTANT_SLOTS:], user_constants)
    copy(pip_desc.resources[GPU_RESOURCE_SLOTS:], user_resources)

    _render_layer_sprites(layer_index, pip_desc)
    _render_layer_meshes(layer_index, pip_desc)
    _render_layer_triangles(layer_index, pip_desc)
    _render_layer_lines(layer_index, pip_desc)

    return
}

_render_layer_sprites :: proc(layer_index: i32, pip_desc: gpu.Pipeline_Desc) {
    perf_scope()

    pip_desc := pip_desc

    layer := _state.draw_layers[layer_index]

    pip_desc.index = {
        resource = _state.quad_ibuf,
        format = .U16,
    }

    pip_desc.resources = {
        0 = _state.sprite_inst_buf,
    }

    for batch_index in 0..<layer.sprites.len {
        key := layer.sprites.keys[batch_index]
        batch := layer.sprites.batches[batch_index]

        _gpu_pipeline_desc_apply_draw_key(&pip_desc, key)

        pipeline, pipeline_ok := gpu.create_pipeline("sprite-pip", pip_desc)
        if !pipeline_ok {
            base.log_err("Failed to create GPU pipeline")
            continue
        }

        gpu.set_pipeline(pipeline)

        gpu.draw_indexed(
            index_num = 6,
            instance_num = batch.len,
            index_offset = 0,
            const_offsets = {
                0 = max(u32),
                1 = u32(layer_index),
                2 = batch.consts_offset,
            },
        )
    }
}

_render_layer_meshes :: proc(layer_index: i32, pip_desc: gpu.Pipeline_Desc) {
    perf_scope()

    pip_desc := pip_desc

    layer := _state.draw_layers[layer_index]

    pip_desc.index = {
        resource = {},
        format = .U16,
    }

    pip_desc.resources = {
        0 = _state.mesh_inst_buf,
        1 = {},
    }

    _perf_counter_add(.Num_Draw_Calls, layer.meshes.len)

    for batch_index in 0..<layer.meshes.len {
        key := layer.meshes.keys[batch_index]
        batch := layer.meshes.batches[batch_index]
        _gpu_pipeline_desc_apply_draw_key(&pip_desc, key)

        pip_desc.index.resource = _state.groups[key.group].ibuf
        pip_desc.resources[1] = _state.groups[key.group].vbuf

        pipeline, pipeline_ok := gpu.create_pipeline("mesh-pip", pip_desc)
        if !pipeline_ok {
            continue
        }

        gpu.set_pipeline(pipeline)

        mesh := _state.meshes[key.asset_index]

        gpu.draw_indexed(
            index_num = mesh.index_num,
            instance_num = batch.len,
            index_offset = mesh.index_offs,
            const_offsets = {
                0 = max(u32),
                1 = u32(layer_index),
                2 = batch.consts_offset,
            },
        )
    }
}

_render_layer_triangles :: proc(layer_index: i32, pip_desc: gpu.Pipeline_Desc) {
    perf_scope()

    pip_desc := pip_desc

    layer := _state.draw_layers[layer_index]

    pip_desc.index = {}
    pip_desc.resources = {
        0 = _state.mesh_inst_buf,
        1 = _state.dynamic_vert_buf,
    }

    for batch_index in 0..<layer.triangles.len {
        key := layer.triangles.keys[batch_index]
        batch := layer.triangles.batches[batch_index]

        _gpu_pipeline_desc_apply_draw_key(&pip_desc, key)

        pipeline, pipeline_ok := gpu.create_pipeline("tri-pip", pip_desc)
        if !pipeline_ok {
            base.log_err("Failed to create GPU pipeline")
            continue
        }

        gpu.set_pipeline(pipeline)

        gpu.draw_non_indexed(
            vertex_num = key.asset_index,
            instance_num = batch.len,
            const_offsets = {
                0 = max(u32),
                1 = u32(layer_index),
                2 = batch.consts_offset,
            },
        )
    }
}

_render_layer_lines :: proc(layer_index: i32, pip_desc: gpu.Pipeline_Desc) {
    perf_scope()

    pip_desc := pip_desc

    layer := _state.draw_layers[layer_index]

    pip_desc.topo = .Lines

    pip_desc.index = {}

    pip_desc.resources = {
        0 = _state.mesh_inst_buf,
        1 = _state.dynamic_vert_buf,
    }

    for batch_index in 0..<layer.lines.len {
        key := layer.lines.keys[batch_index]
        batch := layer.lines.batches[batch_index]

        _gpu_pipeline_desc_apply_draw_key(&pip_desc, key)

        pipeline, pipeline_ok := gpu.create_pipeline("line-pip", pip_desc)
        if !pipeline_ok {
            continue
        }

        gpu.set_pipeline(pipeline)

        gpu.draw_non_indexed(
            vertex_num = key.asset_index,
            instance_num = batch.len,
            const_offsets = {
                0 = max(u32),
                1 = u32(layer_index),
                2 = batch.consts_offset,
            },
        )
    }
}

_gpu_pipeline_desc_apply_draw_key :: proc(pip_desc: ^gpu.Pipeline_Desc, key: Draw_Batch_Key, loc := #caller_location) {
    pip_desc.blends[0] = _gpu_blend_mode_desc(key.blend_mode)
    pip_desc.cull, pip_desc.fill = _gpu_fill_mode(key.fill_mode)
    pip_desc.depth_comparison = bool(u8(key.depth_mode) & (1 << 0)) ? .Greater_Equal : .Always
    pip_desc.depth_write = bool(u8(key.depth_mode) & (1 << 1))
    pip_desc.ps = gpu.Shader_Handle(_state.pixel_shaders[key.ps])
    pip_desc.vs = gpu.Shader_Handle(_state.vertex_shaders[key.vs])

    tex_res: gpu.Resource_Handle
    switch key.texture_kind {
    case .Non_Pooled:       tex_res = _state.textures[key.texture].resource
    case .Pooled:           tex_res = _state.texture_pools[key.texture].resource
    case .Render_Texture:   tex_res = _state.render_textures[key.texture].color
    case: panic("Invalid texture mode")
    }

    assert(tex_res != {}, "Invalid texture resource", loc = loc)
    pip_desc.resources[2] = tex_res
}

_gpu_blend_mode_desc :: proc(blend: Blend_Mode) -> gpu.Blend_Desc {
    switch blend {
    case .Opaque:
        return gpu.BLEND_OPAQUE
    case .Add:
        return gpu.BLEND_ADDITIVE
    case .Alpha:
        return gpu.BLEND_ALPHA
    case .Premultiplied_Alpha:
        return gpu.BLEND_PREMULTIPLIED_ALPHA
    }
    return gpu.BLEND_OPAQUE
}

_gpu_fill_mode :: proc(fill: Fill_Mode) -> (gpu.Cull_Mode, gpu.Fill_Mode) {
    switch fill {
    case .Front:
        return .Back, .Solid
    case .Back:
        return .Front, .Solid
    case .All:
        return .None, .Solid
    case .Wire:
        return .None, .Wireframe
    }
    return .Invalid, .Invalid
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Camera
//

Camera :: struct {
    pos:        Vec3,
    rot:        Quat,
    // View to clip transform.
    // NDC box is -1..1 on X and Y, and 0..1 on Z axis.
    projection: Mat4,
}

FRUSTUM_FAR_PLANE_INDEX :: 5

Frustum :: struct {
    planes:     [6][4]f32, // xyz normal, w offset
    corners:    [8]Vec3,
    bounds_min: Vec3,
    bounds_max: Vec3,
}

orthographic_projection :: proc(left, right, top, bottom: f32, near: f32 = 0.01, far: f32 = 1000.0) -> (result: Mat4) {
    // D3D11, LH 0..1 NDC
    // https://learn.microsoft.com/en-us/windows/win32/direct3d9/d3dxmatrixorthooffcenterlh

    result[0, 0] = 2 / (right - left)
    result[1, 1] = 2 / (top - bottom)
    result[2, 2] = 1 / (far - near)
    result[0, 3] = (left + right) / (left - right)
    result[1, 3] = (top + bottom) / (bottom - top)
    result[2, 3] = near / (near - far)
    result[3, 3] = 1

    return result
}

// left handed reverse Z
// https://iolite-engine.com/blog_posts/reverse_z_cheatsheet
// NOTE: use Greater depth comparison!
perspective_projection :: proc(screen: Vec2, fov: f32, near: f32 = 0.01, far: f32 = 1000.0) -> (result: Mat4) {
    assert(fov > 0)
    assert(screen.x > 0)
    assert(screen.y > 0)

    aspect := screen.x / screen.y
    tan_half_fovy := math.tan(0.5 * fov)
    result[0, 0] = 1.0 / (tan_half_fovy * aspect)
    result[1, 1] = 1.0 / tan_half_fovy
    result[2, 2] = -near / (far - near)
    result[2, 3] = (far * near) / (far - near)
    result[3, 2] = 1

    return result
}

calc_camera_world_to_view_matrix :: proc(camera: Camera) -> (result: Mat4) {
    result =
        linalg.matrix4_from_quaternion_f32(linalg.quaternion_inverse(camera.rot)) *
        linalg.matrix4_translate_f32(-camera.pos)
    return result
}

calc_camera_world_to_clip_matrix :: proc(camera: Camera) -> (result: Mat4) {
    result = camera.projection * calc_camera_world_to_view_matrix(camera)
    return result
}

calc_camera_frustum :: proc(cam: Camera) -> Frustum {
    mvp := calc_camera_world_to_clip_matrix(cam)
    inv := linalg.matrix4_inverse_f32(mvp)
    return calc_matrix_frustum(inv)
}

calc_matrix_frustum :: proc(clip_to_world: Mat4) -> (result: Frustum) {
    // https://iquilezles.org/articles/frustumcorrect/
    // https://iquilezles.org/articles/frustum/

    fru := [8]Vec4{
        0 = clip_to_world * Vec4{-1, -1,  0, 1.0},
        1 = clip_to_world * Vec4{+1, -1,  0, 1.0},
        2 = clip_to_world * Vec4{-1, +1,  0, 1.0},
        3 = clip_to_world * Vec4{+1, +1,  0, 1.0},
        4 = clip_to_world * Vec4{-1, -1, +1, 1.0},
        5 = clip_to_world * Vec4{+1, -1, +1, 1.0},
        6 = clip_to_world * Vec4{-1, +1, +1, 1.0},
        7 = clip_to_world * Vec4{+1, +1, +1, 1.0},
    }

    for p, i in fru {
        result.corners[i] = p.xyz / p.w
    }

    result.bounds_min = result.corners[0]
    result.bounds_max = result.corners[0]
    for p in result.corners[1:] {
        result.bounds_min = linalg.min(result.bounds_min, p)
        result.bounds_max = linalg.max(result.bounds_max, p)
    }

    center: Vec3
    for p in result.corners {
        center += p
    }
    center *= 1.0 / 8.0

    result.planes = {
        _tri_plane(center, result.corners[4], result.corners[6], result.corners[5]),
        _tri_plane(center, result.corners[0], result.corners[4], result.corners[1]),
        _tri_plane(center, result.corners[2], result.corners[3], result.corners[6]),
        _tri_plane(center, result.corners[0], result.corners[2], result.corners[4]),
        _tri_plane(center, result.corners[1], result.corners[5], result.corners[3]),
        _tri_plane(center, result.corners[0], result.corners[1], result.corners[2]),
    }

    return result

    _tri_plane :: proc(center: Vec3, a, b, c: Vec3) -> Vec4 {
        normal := linalg.normalize0(linalg.cross(b - a, c - a))

        if linalg.dot(a - center, normal) < 0 {
            normal = -normal
        }

        return {
            normal.x,
            normal.y,
            normal.z,
            linalg.dot(normal, a),
        }
    }
}

is_box_in_frustum :: proc(fru: Frustum, pos: Vec3, rad: Vec3) -> bool #no_bounds_check {
    EPS :: 1

    bounds_min := fru.bounds_min - rad - EPS
    bounds_max := fru.bounds_max + rad + EPS

    if pos.x < bounds_min.x ||
       pos.y < bounds_min.y ||
       pos.z < bounds_min.z ||
       pos.x > bounds_max.x ||
       pos.y > bounds_max.y ||
       pos.z > bounds_max.z
    {
        return false
    }

    for plane in fru.planes {
        rad_on_normal := rad.x * abs(plane.x) + rad.y * abs(plane.y) + rad.z * abs(plane.z)
        dist := linalg.dot(plane.xyz, pos) - plane.w - rad_on_normal
        if dist > EPS {
            return false
        }
    }

    return true
}

is_sphere_in_frustum :: proc(fru: Frustum, pos: Vec3, rad: f32) -> bool #no_bounds_check {
    EPS :: 1

    bounds_min := fru.bounds_min - rad - EPS
    bounds_max := fru.bounds_max + rad + EPS

    if pos.x < bounds_min.x ||
       pos.y < bounds_min.y ||
       pos.z < bounds_min.z ||
       pos.x > bounds_max.x ||
       pos.y > bounds_max.y ||
       pos.z > bounds_max.z
    {
        return false
    }

    for plane in fru.planes {
        dist := linalg.dot(plane.xyz, pos) - plane.w - rad
        if dist > EPS {
            return false
        }
    }

    return true
}

is_sphere_in_frustum_simd :: proc(
    fru_pos:    [3]#simd[LANES]f32,
    fru_rad:    [3]#simd[LANES]f32,
    fru_planes: [6][4]#simd[LANES]f32,
    pos:        [3]#simd[LANES]f32,
    rad:        #simd[LANES]f32,
) -> (result: #simd[LANES]u32) #no_bounds_check {
    EPS :: 1

    r := fru_rad + rad

    xin := intrinsics.simd_lanes_lt(intrinsics.simd_abs(pos.x - fru_pos.x), r.x)
    yin := intrinsics.simd_lanes_lt(intrinsics.simd_abs(pos.y - fru_pos.y), r.y)
    zin := intrinsics.simd_lanes_lt(intrinsics.simd_abs(pos.z - fru_pos.z), r.z)
    result = xin & yin & zin

    for i in 0..<len(fru_planes) {
        dists :=
            fru_planes[i].x * pos.x +
            fru_planes[i].y * pos.y +
            fru_planes[i].z * pos.z -
            fru_planes[i].w - rad

        result &= intrinsics.simd_lanes_lt(dists, EPS)
    }

    return result
}

// Returns the ray direction.
screen_to_world_ray :: proc(pos: Vec2, cam: Camera) -> Vec3 {
    cam_mvp := calc_camera_world_to_clip_matrix(cam)
    cam_inv := linalg.matrix4_inverse_f32(cam_mvp)

    p := pos

    p.x = (p.x / f32(get_screen_size().x)) * 2.0 - 1.0
    p.y = 1.0 - 2.0 * (p.y / f32(get_screen_size().y))

    p0 := cam_inv * Vec4{p.x, p.y, 0.0, 1.0}
    p1 := cam_inv * Vec4{p.x, p.y, 1.0, 1.0}
    p0.xyz /= p0.w
    p1.xyz /= p1.w

    return linalg.normalize0(p1.xyz - p0.xyz)
}

