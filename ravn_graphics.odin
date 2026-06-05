#+vet shadowing unused explicit-allocators style
package ravn

import "core:slice"
import "gpu"
import "base"
import "shader_compiler"
import "rscn"
import "base:intrinsics"
import "base:runtime"
import "core:math"
import "core:math/linalg"
import stbi "vendor:stb/image"

DRAW_BATCH_TABLE_LOOKUP :: 512
DRAW_BATCH_TABLE_BATCHES :: 256 // this is limited by gpu.MAX_PIPELINES anyway.
DRAW_BATCH_TABLE_MAX_PROBE :: 32

GPU_SAMPLER_SLOTS :: 4
GPU_CONSTANT_SLOTS :: 4
GPU_RESOURCE_SLOTS :: 4

when gpu.BACKEND == gpu.BACKEND_D3D11 {
    SHADER_TARGET :: shader_compiler.Target.DXBC
} else when gpu.BACKEND == gpu.BACKEND_WGPU {
    SHADER_TARGET :: shader_compiler.Target.WGSL
} else {
    SHADER_TARGET :: shader_compiler.Target.Invalid
}

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

#assert(size_of(Vertex) == 32)

Vertex :: struct #align(16) {
    pos:        [3]f32,
    uv:         [2]u16,

    normal:     [2]u8,
    _:          [2]u8,
    col:        [4]u8,
    joints:     [4]u8,
    weights:    [4]u8,
}


Texture_Pool :: struct {
    slices_used:    bit_set[0..<MAX_TEXTURE_POOL_SLICES],
    size:           [2]i32,
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
    No_Frustum_Cull,
    No_Transparent_Sort,
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
    keys:       [DRAW_BATCH_TABLE_BATCHES]Draw_Batch_Key,
    batches:    [DRAW_BATCH_TABLE_BATCHES]Draw_Batch(T),
    len:        i32,
}

Draw_Batch :: struct($Instance: typeid) #all_or_none {
    consts_offset:  u32,
    last_len:       u32,
    len:            u32,
    cap:            u32,
    inst_data:      [^]Instance,
    cull_data:      [^]Draw_Cull_Group,
}

Draw_Batch_Sort_Key_Integer :: u64

#assert(size_of(Draw_Batch_Sort_Key) == size_of(Draw_Batch_Sort_Key_Integer))
Draw_Batch_Sort_Key :: struct {
    index:  u16,
    batch:  u16,
    z:      f32,
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

#assert(size_of(Draw_Batch_Key) == 8)
Draw_Batch_Key :: struct #all_or_none {
    asset_index:    u16,
    texture:        u8,
    arena:          u8,
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
    size:   [2]i32,
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
    view_proj:      matrix[4, 4]f32,
    cam_pos:        [3]f32,
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
Mesh_Inst :: struct #all_or_none #align(64) {
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
// MARK: Meshes
//

create_mesh_from_data :: proc(
    name:               string,
    arena_handle:       Arena_Handle,
    verts:              []Vertex,
    indices:            []Vertex_Index,
) -> (result: Mesh_Handle, ok: bool) #optional_ok {
    base.log_debug("Creating mesh '%s' with %i verts and %i tris", name, len(verts), len(indices) / 3)

    arena := _get_arena(arena_handle) or_return

    if
        len(verts) > len(arena.vert_upload_buf) - int(arena.vert_upload_offs) ||
        len(indices) > len(arena.index_upload_buf) - int(arena.index_upload_offs)
    {
        base.log_err("Failed to create mesh '%s': doesn't fit in the arena", name)
        return {}, false
    }

    mesh := Mesh{
        arena = arena_handle,
        vert_num = i32(len(verts)),
        index_num = i32(len(indices)),
        vert_offs = arena.vert_upload_offs,
        index_offs = arena.index_upload_offs,
        bounds_min = max(f32),
        bounds_max = min(f32),
        bounds_rad = 0.001,
        verts = verts,
        indices = indices,
        collision_mesh = {},
    }

    for vert in verts {
        mesh.bounds_min = linalg.min(mesh.bounds_min, vert.pos)
        mesh.bounds_max = linalg.max(mesh.bounds_max, vert.pos)
        mesh.bounds_rad = max(mesh.bounds_rad, linalg.length(vert.pos))
    }

    handle, handle_ok := insert_mesh_by_name(name, mesh)
    if !handle_ok {
        base.log_err("Failed to create mesh '%s', table is full", name)
        return {}, false
    }

    copy(arena.vert_upload_buf[arena.vert_upload_offs:], verts)
    copy(arena.index_upload_buf[arena.index_upload_offs:], indices)
    arena.vert_upload_offs += i32(len(verts))
    arena.index_upload_offs += i32(len(indices))
    arena.dirty = true

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
create_texture_pool :: proc(size: [2]i32, slices: i32) -> (ok: bool) {
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

_get_texture :: proc(handle: Texture_Handle) -> (result: ^Texture, ok: bool) #optional_ok {
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
    res := gpu._get_resource(handle) or_return

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
    texture, texture_ok := _get_texture(handle)
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
    return create_vertex_shader_from_bin(name, data)
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

    return create_pixel_shader_from_bin(name, data)
}

@(require_results)
create_vertex_shader_from_bin :: proc(name: string, data: []byte) -> (result: Vertex_Shader_Handle, ok: bool) #optional_ok {
    shader: gpu.Shader_Handle
    shader, ok = gpu.create_shader(name, data, .Vertex)

    if !ok {
        base.log_err("Failed to create vertex shader")
        return
    }

    // TODO: if this fails the shader gets leaked.
    // TODO: fix for ALL table inserts, including rscn loading and custom mesh creation etc.
    return insert_vertex_shader_by_name(name, Vertex_Shader(shader))
}

@(require_results)
create_pixel_shader_from_bin :: proc(name: string, data: []byte) -> (result: Pixel_Shader_Handle, ok: bool) #optional_ok {
    shader: gpu.Shader_Handle
    shader, ok = gpu.create_shader(name, data, .Pixel)

    if !ok {
        base.log_err("Failed to create pixel shader")
        return
    }

    return insert_pixel_shader_by_name(name, Pixel_Shader(shader))
}

when SHADER_COMPILER_ENABLED {
    @(require_results)
    create_vertex_shader_from_source :: proc(name: string, source: []byte) -> (result: Vertex_Shader_Handle, ok: bool) #optional_ok {
        compiled: []byte
        if _state.shader_compiler_target == .Invalid {
            base.log_err("Cannot compile shader from source, failed to init shader compiler")
        } else {
            compiled, ok = shader_compiler.compile(&_state.shader_compiler_state,
                name = name,
                source = string(source),
                opts = {
                    stage = .Vertex,
                    include_proc = _shader_include_proc,
                },
            )

            if !ok {
                base.log_err("Failed to compile vertex shader '%s'", name)
                return {}, false
            }
        }

        return create_vertex_shader_from_bin(name, compiled)
    }

    @(require_results)
    create_pixel_shader_from_source :: proc(name: string, source: []byte) -> (result: Pixel_Shader_Handle, ok: bool) #optional_ok {
        compiled: []byte
        if _state.shader_compiler_target == .Invalid {
            base.log_err("Cannot compile shader from source, failed to init shader compiler")
        } else {
            compiled, ok = shader_compiler.compile(&_state.shader_compiler_state,
                name = name,
                source = string(source),
                opts = {
                    stage = .Pixel,
                    include_proc = _shader_include_proc,
                },
            )

            if !ok {
                base.log_err("Failed to compile pixel shader '%s'", name)
                return {}, false
            }
        }

        return create_pixel_shader_from_bin(name, compiled)
    }
}

_shader_include_proc :: proc(path: string, user: rawptr) -> (result: string, ok: bool) {
    npath := normalize_path(path, context.temp_allocator)
    data := get_file_data(npath, flush = false) or_return
    return string(data), true
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

    tex^ = {
        size = size,
        color = {},
        depth = {},
    }

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
    tex, tex_ok := _get_render_texture(handle)
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
//     _, tex_ok := _get_render_texture(handle)
//     if !tex_ok {
//         return
//     }
// }

@(require_results)
_get_render_texture :: proc(handle: Render_Texture_Handle) -> (result: ^Render_Texture, ok: bool) {
    return _table_get(&_state.render_textures, _state.render_textures_gen, handle)
}

@(require_results)
get_render_texture_size :: proc(handle: Render_Texture_Handle) -> (result: [2]i32, ok: bool) {
    rt := _get_render_texture(handle) or_return
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

set_draw_shader :: proc {
    set_draw_pixel_shader,
    set_draw_vertex_shader,
}

set_draw_pixel_shader :: proc(handle: Pixel_Shader_Handle) {
    if _, ok := _get_pixel_shader(handle); ok {
        _state.draw_state.ps = u8(handle.index)
    } else {
        _state.draw_state.ps = u8(_state.builtin_pixel_shader[.Default].index)
    }
}

set_draw_vertex_shader :: proc(handle: Vertex_Shader_Handle) {
    if _, ok := _get_vertex_shader(handle); ok {
        _state.draw_state.vs = u8(handle.index)
    } else {
        _state.draw_state.vs = u8(_state.builtin_vertex_shader[.Default].index)
    }
}

set_draw_texture :: proc(handle: Texture_Handle) {
    if !_set_draw_texture(handle) {
        _set_draw_texture(_state.builtin_texture[.Error])
    }
}

_set_draw_texture :: proc(handle: Texture_Handle) -> bool {
    tex := _get_texture(handle) or_return
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
set_draw_render_texture :: proc(handle: Render_Texture_Handle) {
    assert(handle != DEFAULT_RENDER_TEXTURE)
    tex, tex_ok := _get_render_texture(handle)
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


// Set up layer draw parameters for this frame.
// NOTE: Prefer calling this before any draw_* commands.
// But the params persist between frames.
update_draw_layer :: proc(
    #any_int layer: i32,
    camera:         Camera,
    flags:          bit_set[Draw_Layer_Flag] = {},
) {
    layer, layer_ok := _get_draw_layer(layer)
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

draw_sprite :: proc(
    pos:        [3]f32,
    rect:       Rect = {0, 1},
    scale:      [2]f32 = 1,
    col:        [4]f32 = 1,
    rot:        matrix[3, 3]f32 = 1,
    anchor:     [2]f32 = 0,
    add_col:    [4]f32 = 0,
    scaling:    Sprite_Scaling = .Pixel,
    param:      u32 = 0,
) {
    perf_scope()
    assert(base.is_finite_vec(pos))

    rect_size := rect_full_size(rect)
    draw_layer := &_state.draw_layers[_state.draw_state.draw_layer]

    size := scale.xy * 0.5
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

    log_dump(_state.draw_state.texture_kind)
    log_dump(_state.draw_state.texture_size)
    log_dump(size)

    center := pos
    center -= rot[0] * anchor.x * size.x
    center -= rot[1] * anchor.y * size.y

    inst := pack_sprite_inst(
        pos = center,
        mat_x = rot[0] * size.x,
        mat_y = rot[1] * size.y,
        uv_min = rect.min + UV_EPS,
        uv_size = rect_size - UV_EPS * 2,
        col = col,
        add_col = add_col,
        tex_slice = _state.draw_state.texture_slice,
        param = param,
    )

    key := _state.draw_state.key
    key.vs = u8(_state.builtin_vertex_shader[.Default_Sprite].index) // for now the VS is fixed

    _draw_batch_table_push(&draw_layer.sprites, key, inst)
}

draw_sprite_2d :: proc(
    pos:        [2]f32,
    rect:       Rect = {0, 1},
    scale:      [2]f32 = 1,
    col:        [4]f32 = 1,
    rot:        f32 = 0,
    anchor:     [2]f32 = 0,
    add_col:    [4]f32 = 0,
    scaling:    Sprite_Scaling = .Pixel,
    z:          f32 = 0,
    param:      u32 = 0,
) {
    right := [2]f32{
        math.cos_f32(rot),
        math.sin_f32(rot),
    }
    draw_sprite(
        pos = {pos.x, pos.y, z},
        rect = rect,
        col = col,
        rot = matrix[3, 3]f32{
            right.x, right.y, 0,
            right.y, -right.x, 0,
            0, 0, 1,
        },
        anchor = anchor,
        scale = scale,
        add_col = add_col,
        scaling = scaling,
        param = param,
    )
}

draw_rect_2d :: proc(
    rect:       Rect,
    tex_rect:   Rect = {0, 1},
    z:          f32 = 0,
    col:        [4]f32 = 1,
    add_col:    [4]f32 = 0,
    param:      u32 = 0,
) {
    center := rect_center(rect)
    size := rect_full_size(rect)

    inst := pack_sprite_inst(
        pos = {center.x, center.y, z},
        mat_x = {size.x * 0.5, 0, 0},
        mat_y = {0, size.y * 0.5, 0},
        uv_min = tex_rect.min + UV_EPS,
        uv_size = rect_full_size(tex_rect) - UV_EPS * 2,
        col = col,
        add_col = add_col,
        tex_slice = _state.draw_state.texture_slice,
        param = param,
    )

    key := _state.draw_state.key
    key.vs = u8(_state.builtin_vertex_shader[.Default_Sprite].index) // for now the VS is fixed

    draw_layer := &_state.draw_layers[_state.draw_state.draw_layer]
    _draw_batch_table_push(&draw_layer.sprites, key, inst)
}


draw_mesh :: proc(
    handle:     Mesh_Handle,
    pos:        [3]f32,
    scale:      [3]f32 = 1,
    rot:        quaternion128 = 1,
    col:        [4]f32 = 1,
    add_col:    [4]f32 = 0,
    param:      u32 = 0,
) {
    perf_scope()

    mesh, mesh_ok := _get_mesh(handle)

    assert(mesh_ok && base.is_finite_vec(pos))

    mat := linalg.matrix3_from_quaternion_f32(rot)

    key := _state.draw_state.key
    key.asset_index = u16(handle.index)
    key.arena = u8(mesh.arena.index)

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

    draw_layer := &_state.draw_layers[_state.draw_state.draw_layer]
    _draw_batch_table_push(&draw_layer.meshes, key, inst)
}

draw_sphere :: proc(
    pos:        [3]f32,
    scale:      [3]f32 = 1,
    rot:        quaternion128 = 1,
    col:        [4]f32 = 1,
    add_col:    [4]f32 = 0,
    param:      u32 = 0,
) {
    draw_mesh(
        get_builtin_mesh(.UV_Sphere_1),
        pos = pos,
        scale = scale,
        rot = rot,
        col = col,
        add_col = add_col,
        param = param,
    )
}

draw_box :: proc(
    pos:        [3]f32,
    scale:      [3]f32 = 1,
    rot:        quaternion128 = 1,
    col:        [4]f32 = 1,
    add_col:    [4]f32 = 0,
    param:      u32 = 0,
) {
    draw_mesh(
        get_builtin_mesh(.Cube),
        pos = pos,
        scale = scale,
        rot = rot,
        col = col,
        add_col = add_col,
        param = param,
    )
}

draw_capsule :: proc(
    pos0:       [3]f32,
    pos1:       [3]f32,
    rad:        f32 = 1,
    col:        [4]f32 = 1,
    add_col:    [4]f32 = 0,
    param:      u32 = 0,
) {
    axis := linalg.normalize(pos1 - pos0)
    tangent: [3]f32 = {0, 1, 0}
    if abs(axis.y) > 0.9 {
        tangent = {1, 0, 0}
    }

    mat: matrix[3, 3]f32
    mat[1] = axis
    mat[0] = linalg.normalize(linalg.cross(axis, tangent))
    mat[2] = linalg.normalize(linalg.cross(mat[0], axis))

    rot := linalg.quaternion_from_matrix3_f32(mat)

    draw_mesh(get_builtin_mesh(.UV_Sphere_1), pos0, scale = rad, rot = rot, col = col, add_col = add_col, param = param)
    draw_mesh(get_builtin_mesh(.UV_Sphere_1), pos1, scale = rad, rot = rot, col = col, add_col = add_col, param = param)
    draw_mesh(get_builtin_mesh(.Cylinder_1), (pos0 + pos1) * 0.5,
        scale = {rad, linalg.length(pos1 - pos0) * 0.5, rad},
        rot = rot,
        col = col,
        add_col = add_col,
        param = param,
    )
}

draw_triangles :: proc(
    verts:      ..Vertex,
    pos:        [3]f32 = 0,
    scale:      [3]f32 = 1,
    rot:        quaternion128 = 1,
    col:        [4]f32 = WHITE,
    add_col:    [4]f32 = 0,
    param:      u32 = 0,
) {
    perf_scope()

    assert(base.is_finite_vec(pos) && base.is_finite_vec(transmute([4]f32)rot))
    assert(len(verts) % 3 == 0)

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

    _draw_batch_table_push(&draw_layer.triangles, key, inst)
}

draw_lines :: proc(
    verts:      ..Vertex,
    pos:        [3]f32 = 0,
    scale:      [3]f32 = 1,
    rot:        quaternion128 = 1,
    col:        [4]f32 = WHITE,
    add_col:    [4]f32 = 0,
    param:      u32 = 0,
) {
    perf_scope()

    assert(len(verts) % 2 == 0)
    assert(base.is_finite_vec(pos) && base.is_finite_vec(transmute([4]f32)rot))

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

    _draw_batch_table_push(&draw_layer.lines, key, inst)
}

// Prefer draw_triangles if you need to efficiently draw many triangles.
draw_triangle :: proc(
    pos:        [3][3]f32,
    col:        [3][4]f32 = WHITE,
    uvs:        [3][2]f32 = {{0, 0}, {1, 0}, {0, 1}},
    add_col:    [4]f32 = BLACK,
    normals:    Maybe([3][3]f32) = nil,
) {
    assert(base.is_finite_vec(pos[0]) && base.is_finite_vec(pos[1]) && base.is_finite_vec(pos[2]))

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

draw_triangle_2d :: proc(
    pos:        [3][2]f32,
    col:        [3][4]f32 = WHITE,
    uvs:        [3][2]f32 = {{0, 0}, {1, 0}, {0, 1}},
    add_col:    [4]f32 = BLACK,
    z:          f32 = 0,
) {
    verts: [3]Vertex
    for i in 0..<3 {
        verts[i] = pack_vertex(
            pos = {pos[i].x, pos[i].y, z},
            uv = uvs[i],
            normal = {0, 0, -1},
            col = col[i],
        )
    }
    draw_triangles(..verts[:])
}

// Prefer draw_lines if you need to efficiently draw many lines.
draw_line :: proc(
    pos0:       [3]f32,
    pos1:       [3]f32,
    col:        [2][4]f32 = WHITE,
    uvs:        [2][2]f32 = {{0, 0.5}, {1, 0.5}},
    add_col:    [4]f32 = BLACK,
    normals:    Maybe([2][3]f32) = nil,
) {
    assert(base.is_finite_vec(pos0))
    assert(base.is_finite_vec(pos1))

    norm, norm_ok := normals.?
    if !norm_ok {
        norm = [3]f32{0, 1, 0}
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

draw_line_2d :: proc(
    pos0:       [2]f32,
    pos1:       [2]f32,
    col:        [2][4]f32 = WHITE,
    uvs:        [2][2]f32 = {{0, 0.5}, {1, 0.5}},
    add_col:    [4]f32 = BLACK,
    z:          f32 = 0,
) {
    verts: [2]Vertex
    for &v, i in verts {
        v = pack_vertex(
            pos = i == 0 ? {pos0.x, pos0.y, z} : {pos1.x, pos1.y, z},
            uv = uvs[i],
            normal = {0, 0, -1},
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



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Draw Text
//

// Returns a slice of the GPU sprite instances.
// TODO: real text draw iterator?
// TODO: text only bind state texture
draw_text :: proc(
    text:       string, // UTF-8
    pos:        [3]f32,
    scale:      [2]f32 = 1,
    anchor:     [2]f32 = -1, // Anchor point in local space. -1 = left aligned, 0 = centered, 1.0 = right aligned
    spacing:    [2]f32 = {0, 8}, // x = character spacing, y = line spacing
    col:        [4]f32 = 1,
    add_col:    [4]f32 = 0,
    rot:        matrix[3, 3]f32 = 1,
) -> []Sprite_Inst {
    perf_scope()

    char_size := [2]i32{
        i32(_state.draw_state.texture_size.x) / 16,
        i32(_state.draw_state.texture_size.y) / 16,
    }

    full_size := calc_text_size(
        text = text,
        scale = scale,
        char_size = char_size,
        spacing = spacing,
    )

    center := pos +
        rot[0] * f32(char_size.x) * scale.x * 0.5 +
        rot[1] * f32(char_size.y) * scale.y * 0.5 +
        rot[0] * full_size.x * -(anchor.x * 0.5 + 0.5) +
        rot[1] * full_size.y * -(anchor.y * 0.5 + 0.5)

    offs: [2]f32

    key := _state.draw_state.key
    key.vs = u8(_state.builtin_vertex_shader[.Default_Sprite].index) // for now the VS is fixed

    table := &_state.draw_layers[_state.draw_state.draw_layer].sprites
    batch_index, batch_ok := _draw_batch_table_find_or_create(table, key)

    if !batch_ok {
        return nil
    }

    batch := &table.batches[batch_index]

    initial_offs := batch.len

    for r in text {
        if rune_is_drawable(r) {
            ch := rune_to_char(r)

            p := center + (
                rot[0] * offs.x +
                rot[1] * offs.y
            )

            rect := font_slot(ch)

            rect_size := rect_full_size(rect)
            draw_layer := &_state.draw_layers[_state.draw_state.draw_layer]

            size := scale.xy * 0.5
            size.y = .Flip_Y in draw_layer.flags ? -size.y : size.y

            // Pixel scaling
            size *= {
                f32(_state.draw_state.texture_size.x) * rect_size.x,
                f32(_state.draw_state.texture_size.y) * rect_size.y,
            }

            inst_center := p
            inst_center -= rot[0] * anchor.x * size.x
            inst_center -= rot[1] * anchor.y * size.y

            eps := [2]f32{
                rect_size.x > 0 ? UV_EPS : -UV_EPS,
                rect_size.y > 0 ? UV_EPS : -UV_EPS,
            }

            inst := pack_sprite_inst(
                pos = inst_center,
                mat_x = rot[0] * size.x,
                mat_y = rot[1] * size.y,
                uv_min = rect.min + eps,
                uv_size = rect_size - eps * 2,
                col = col,
                add_col = add_col,
                tex_slice = _state.draw_state.texture_slice,
            )

            _draw_batch_push(batch, inst)
        }

        offs = text_glyph_apply(offs, r, scale = scale, char_size = char_size, spacing = spacing)
    }

    return batch.inst_data[:batch.len][initial_offs:]
}

draw_text_2d :: proc(
    text:       string, // UTF-8
    pos:        [2]f32,
    scale:      [2]f32 = 1,
    anchor:     [2]f32 = -1,
    spacing:    [2]f32 = {0, 8},
    col:        [4]f32 = 1,
    add_col:    [4]f32 = 0,
    z:          f32 = 0,
) -> []Sprite_Inst {
    return draw_text(
        text = text,
        pos = {pos.x, pos.y, z},
        scale = scale,
        anchor = anchor,
        spacing = spacing,
        col = col,
        add_col = add_col,
        rot = 1,
    )
}

rune_is_drawable :: proc(r: rune) -> bool {
    switch r {
    case ' ', '\n', '\t':
        return false
    }
    return true
}

calc_text_size :: proc(text: string, scale: [2]f32, char_size: [2]i32 = 8, spacing: [2]f32 = 0) -> [2]f32 {
    offs: [2]f32

    size: [2]f32

    for r in text {
        offs = text_glyph_apply(offs, r, scale = scale, char_size = char_size, spacing = spacing)
        size = {
            max(size.x, offs.x),
            max(size.y, offs.y),
        }
    }

    return size + {0, (f32(char_size.y) + spacing.y) * scale.y}
}

text_glyph_apply :: proc(offs: [2]f32, r: rune, scale: [2]f32, char_size: [2]i32 = 8, spacing: [2]f32 = 0) -> [2]f32 {
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



////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Line shapes
//
// TODO: some shapes could use a single inst + linear transform
//

_BOX_CORNER_POSITIONS :: [8][3]f32 {
    0 = [3]f32{-1, -1, -1},
    1 = [3]f32{-1, -1, +1},
    2 = [3]f32{-1, +1, -1},
    3 = [3]f32{-1, +1, +1},
    4 = [3]f32{+1, -1, -1},
    5 = [3]f32{+1, -1, +1},
    6 = [3]f32{+1, +1, -1},
    7 = [3]f32{+1, +1, +1},
}

draw_line_triangle :: proc(verts: [3][3]f32, col := WHITE) {
    if col.a < 0.01 do return
    draw_lines(
        pack_vertex(verts[0], col = col), pack_vertex(verts[1], col = col),
        pack_vertex(verts[1], col = col), pack_vertex(verts[2], col = col),
        pack_vertex(verts[2], col = col), pack_vertex(verts[0], col = col),
    )
}

draw_line_point :: proc(pos: [3]f32, rad: [3]f32 = 1, col := WHITE) {
    if col.a < 0.01 do return
    draw_lines(
        pack_vertex(pos + {-rad.x, 0, 0}, col = col), pack_vertex(pos + {rad.x, 0, 0}, col = col),
        pack_vertex(pos + {0, -rad.y, 0}, col = col), pack_vertex(pos + {0, rad.y, 0}, col = col),
        pack_vertex(pos + {0, 0, -rad.z}, col = col), pack_vertex(pos + {0, 0, rad.z}, col = col),
    )
}

draw_line_box :: proc(pos: [3]f32, mat: matrix[3, 3]f32 = 1, col := WHITE) {
    if col.a < 0.01 do return
    corners := _BOX_CORNER_POSITIONS
    for &c in corners {
        c = pos + mat * c
    }
    _draw_line_box_corners(corners, col)
}

draw_line_mat3 :: proc(pos: [3]f32, mat: matrix[3, 3]f32 = 1) {
    draw_lines(
        pack_vertex(pos, col = WHITE),    pack_vertex(pos + mat[0], col = RED),
        pack_vertex(pos, col = WHITE),  pack_vertex(pos + mat[1], col = GREEN),
        pack_vertex(pos, col = WHITE),   pack_vertex(pos + mat[2], col = BLUE),
    )
}

draw_line_aabb :: proc(min: [3]f32, max: [3]f32, col := WHITE) {
    if col.a < 0.01 do return
    corners := [8][3]f32 {
        0 = [3]f32{min.x, min.y, min.z},
        1 = [3]f32{min.x, min.y, max.z},
        2 = [3]f32{min.x, max.y, min.z},
        3 = [3]f32{min.x, max.y, max.z},
        4 = [3]f32{max.x, min.y, min.z},
        5 = [3]f32{max.x, min.y, max.z},
        6 = [3]f32{max.x, max.y, min.z},
        7 = [3]f32{max.x, max.y, max.z},
    }
    _draw_line_box_corners(corners, col)
}

draw_line_circle :: proc(
    pos:        [3]f32,
    rad:        [2]f32 = 1,
    axis:       [3]f32 = {0, 1, 0},
    col         := WHITE,
    segments    := 12,
) {
    if col.a < 0.01 do return

    circle := _calc_circle_points(segments)

    u := rad.x * linalg.normalize0(linalg.cross(axis, abs(axis.y) > 0.9 ? [3]f32{1, 0, 0} : [3]f32{0, 1, 0}))
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
    pos:        [3]f32,
    mat:        matrix[3, 3]f32 = 1,
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

draw_line_cylinder :: proc(pos: [2][3]f32, rad: f32 = 1.0, col := WHITE, segments := 12) {
    if col.a < 0.01 do return

    axis := linalg.normalize0(pos[1] - pos[0])

    u := rad * linalg.normalize0(linalg.cross(axis, abs(axis.y) > 0.9 ? [3]f32{1, 0, 0} : [3]f32{0, 1, 0}))
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
    pos:        [3]f32 = 0,
    axis_a:     [3]f32 = {1, 0, 0},
    axis_b:     [3]f32 = {0, 0, 1},
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

_draw_line_box_corners :: proc(corners: [8][3]f32, col: [4]f32) {
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

_calc_circle_points :: proc(segments: int) -> [][2]f32 {
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
    _circle_points := [12][2]f32{
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

    buf := make([][2]f32, segments, context.temp_allocator)
    for &p, i in buf {
        t := f32(i) * math.TAU / f32(segments)
        p = {math.cos_f32(t), math.sin_f32(t)}
    }
    return buf
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Batch Table
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

_draw_batch_table_copy_batches :: proc(
    dst_table:  ^$T/Draw_Batch_Table($Inst),
    src_table:  ^T,
) {
    assert(dst_table != src_table)
    copied_len := min(src_table.len, DRAW_BATCH_TABLE_BATCHES - dst_table.len)

    intrinsics.mem_copy_non_overlapping(
        &dst_table.keys[dst_table.len],
        &src_table.keys[0],
        copied_len * size_of(dst_table.keys[0]),
    )

    for batch, i in src_table.batches[:src_table.len] {
        dst_batch := &dst_table.batches[int(dst_table.len) + i]

        dst_batch^ = {
            consts_offset = 0,
            last_len = batch.last_len,
            len = batch.len,
            cap = batch.cap,
            inst_data = _clone(batch.inst_data, batch.len),
            cull_data = nil,
        }

        intrinsics.mem_copy_non_overlapping(
            &dst_table.batches[dst_table.len],
            &src_table.batches[0],
            copied_len * size_of(dst_table.batches[0]),
        )

    }

    dst_table.len += copied_len

    return

    _clone :: proc(ptr: [^]$T, #any_int len: int) -> [^]T {
        data, err := runtime.mem_alloc_non_zeroed(size_of(T) * len, align_of(T), context.temp_allocator)
        if err != nil {
            return nil
        }

        intrinsics.mem_copy_non_overlapping(raw_data(data), ptr, size_of(T) * len)

        return cast([^]T)raw_data(data)
    }
}

_draw_batch_table_push :: proc(table: ^$T/Draw_Batch_Table($Inst), key: Draw_Batch_Key, inst: Inst) #no_bounds_check {
    index, index_ok := _draw_batch_table_find_or_create(table, key)
    if !index_ok {
        return
    }
    batch := &table.batches[index]
    #force_inline _draw_batch_push(batch, inst)
}

_draw_batch_table_find_or_create :: proc(table: ^$T/Draw_Batch_Table($Inst), key: Draw_Batch_Key) -> (int, bool) #no_bounds_check {
    hash := #force_inline hash_splittable64(transmute(u64)key)

    lookup_index := u64(hash % DRAW_BATCH_TABLE_LOOKUP)
    index := -1

    for _ in 0..<DRAW_BATCH_TABLE_MAX_PROBE {
        batch_index := table.lookup[lookup_index]

        if batch_index == max(u16) {
            index = 0
            break
        }

        if key == table.keys[batch_index] {
            return int(batch_index), true
        }

        lookup_index += 1
        lookup_index = lookup_index == DRAW_BATCH_TABLE_LOOKUP ? 0 : lookup_index
    }

    if index == -1 || table.len >= DRAW_BATCH_TABLE_BATCHES {
        assert(false, "Failed to create draw batch")
        return -1, false
    }

    index = int(table.len)
    table.keys[index] = key
    table.lookup[lookup_index] = u16(index)
    table.len += 1

    return index, true
}

ceil_div :: proc(a, b: $T) -> T where intrinsics.type_is_integer(T) {
    return (a + b) / b
}

_draw_batch_push :: proc(batch: ^Draw_Batch($Inst), inst: Inst) #no_bounds_check {
    // Note: the reallocation should be extremely infrequent,
    // as we're tracking the last frame "waterline".
    if batch.len >= batch.cap {
        batch.cap = max(256 + batch.last_len, batch.cap * 2)
        new_inst := make([^]Inst, batch.cap, context.temp_allocator)

        if batch.len > 0 {
            intrinsics.mem_copy_non_overlapping(rawptr(new_inst), batch.inst_data, size_of(Inst) * batch.len)
        }

        batch.inst_data = new_inst
    }

    batch.inst_data[batch.len] = inst
    batch.len += 1
}

_prepare_mesh_draw_batch_cull :: proc(batch: ^Draw_Batch(Mesh_Inst), key: Draw_Batch_Key) #no_bounds_check {
    batch_num := (int(batch.len) + LANES) / LANES
    batch.cull_data = make([^]Draw_Cull_Group, batch_num, context.temp_allocator)

    mesh := &_state.meshes[key.asset_index]

    for i in 0..<batch_num {
        group: Draw_Cull_Group

        for j in 0..<LANES {
            index := i * LANES + j
            if index >= int(batch.len) {
                break
            }

            inst := batch.inst_data[index]
            rad := intrinsics.sqrt(max(
                linalg.length2(inst.mat_x),
                linalg.length2(inst.mat_y),
                linalg.length2(inst.mat_z),
            )) * mesh.bounds_rad

            group.pos_scalar[0][j] = inst.pos.x
            group.pos_scalar[1][j] = inst.pos.y
            group.pos_scalar[2][j] = inst.pos.z
            group.rad_scalar[j] = rad
        }

        batch.cull_data[i] = group
    }
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

copy_layer_batches :: proc(
    #any_int dst_layer_index:   i32,
    #any_int src_layer_index:   i32,
) {
    if dst_layer_index == src_layer_index {
        assert(false, "Copy must be between two distinc layers, got same src/dst index")
        return
    }

    dst_layer := &_state.draw_layers[dst_layer_index]
    src_layer := &_state.draw_layers[src_layer_index]

    _draw_batch_table_copy_batches(&dst_layer.meshes, &src_layer.meshes)
    _draw_batch_table_copy_batches(&dst_layer.sprites, &src_layer.sprites)
    _draw_batch_table_copy_batches(&dst_layer.triangles, &src_layer.triangles)
    _draw_batch_table_copy_batches(&dst_layer.lines, &src_layer.lines)
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

        if layer.camera == {} {
            continue
        }

        if .No_Frustum_Cull not_in layer.flags {
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

            for &batch, i in layer.meshes.batches[:layer.meshes.len] {
                _prepare_mesh_draw_batch_cull(
                    batch = &batch,
                    key = layer.meshes.keys[i],
                )

                _cull_draw_batch(
                    batch = &batch,
                    frustum = fru,
                    fru_pos = fru_pos,
                    fru_rad = fru_rad,
                    fru_planes = fru_planes,
                )
            }

            // for &batch in layer.sprites.batches[:layer.sprites.len] {
            //     _cull_draw_batch(
            //         batch = &batch,
            //         frustum = fru,
            //         fru_pos = fru_pos,
            //         fru_rad = fru_rad,
            //         fru_planes = fru_planes,
            //     )
            // }
        }

        // Transparent: combine, sort, re-batch. Also remove old non-sorted batches.
        // This is expensive.
        transparent_block: if false && .No_Transparent_Sort not_in layer.flags {
            total_inst_len := 0

            Batch :: struct {
                key:            Draw_Batch_Key,
                using batch:    Draw_Batch(Mesh_Inst),
            }

            sort_batches := make([dynamic]Batch, layer.meshes.len, context.temp_allocator)

            for batch_index := 0; batch_index < int(layer.meshes.len); /**/ {
                batch := layer.meshes.batches[batch_index]
                key := layer.meshes.keys[batch_index]
                if is_blend_mode_order_dependent(key.blend_mode) {
                    total_inst_len += int(batch.len)
                    append(&sort_batches, Batch{
                        key = key,
                        batch = batch,
                    })

                    // Unordered remove
                    layer.meshes.batches[batch_index] = layer.meshes.batches[layer.meshes.len - 1]
                    layer.meshes.len -= 1
                } else {
                    batch_index += 1
                }
            }

            if len(sort_batches) == 0 || total_inst_len == 0 {
                break transparent_block
            }

            sort_keys := make([]Draw_Batch_Sort_Key, total_inst_len, context.temp_allocator)
            sort_write := 0

            cam_pos := layer.camera.pos
            cam_forw := linalg.quaternion128_mul_vector3(layer.camera.rot, [3]f32{0, 0, 1})

            for &batch, batch_index in sort_batches {

                for inst_index in 0..<int(batch.len) {
                    pos := batch.inst_data[inst_index].pos
                    depth := linalg.vector_dot(pos - cam_pos, cam_forw)

                    sort_keys[sort_write] = {
                        batch = u16(batch_index),
                        index = u16(inst_index),
                        z = depth,
                    }

                    sort_write += 1
                }
            }

            slice.sort(transmute([]Draw_Batch_Sort_Key_Integer)sort_keys)

            sort_insts := make([]Mesh_Inst, total_inst_len, context.temp_allocator)

            for key, i in sort_keys {
                inst := sort_batches[key.batch].inst_data[key.index]
                sort_insts[i] = inst
            }

            prev_batch_index := sort_keys[0].batch
            new_batch_len := 0
            rebatch_loop: for key, i in sort_keys {
                if key.batch != prev_batch_index { // Flush
                    batch_index := layer.meshes.len

                    if batch_index >= len(layer.meshes.batches) {
                        break rebatch_loop
                    }

                    layer.meshes.len += 1

                    layer.meshes.keys[batch_index] = sort_batches[prev_batch_index].key
                    layer.meshes.batches[batch_index] = {
                        consts_offset = 0,
                        last_len = 0,
                        len = u32(new_batch_len),
                        cap = 0,
                        inst_data = &sort_insts[i],
                        cull_data = nil,
                    }

                    new_batch_len = 0
                    prev_batch_index = key.batch
                }

                new_batch_len += 1
            }
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

// NOTE: the instance bind data only use a few of the available sots (consts/resources/blends/etc)
// We could possibly expose a direct way for the user to control this on per-layer basis.
// Custom pipeline and pass desc input?
@(optimization_mode="favor_size")
render_layer :: proc(
    #any_int layer_index:   i32,
    ren_tex_handle:         Render_Texture_Handle = DEFAULT_RENDER_TEXTURE,
    clear_color:            Maybe([3]f32) = nil,
    clear_depth:            bool = true,
    // User configurable GPU parameters.
    // Only first few slots are consumed by built-in ravn resources,
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

    ren_tex, ren_tex_ok := _get_render_texture(ren_tex_handle)
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

    gpu.scope_pass("ravn-layer", pass_desc)

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


    for batch_index in 0..<layer.meshes.len {
        batch := layer.meshes.batches[batch_index]

        if batch.len == 0 {
            continue
        }

        key := layer.meshes.keys[batch_index]

        _perf_counter_add(.Num_Draw_Calls, 1)
        _gpu_pipeline_desc_apply_draw_key(&pip_desc, key)

        pip_desc.index.resource = _state.arenas[key.arena].ibuf
        pip_desc.resources[1] = _state.arenas[key.arena].vbuf

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
    pos:        [3]f32,
    rot:        quaternion128,
    // View to clip transform.
    // NDC box is -1..1 on X and Y, and 0..1 on Z axis.
    projection: matrix[4, 4]f32,
}

FRUSTUM_FAR_PLANE_INDEX :: 5

Frustum :: struct {
    planes:     [6][4]f32, // xyz normal, w offset
    corners:    [8][3]f32,
    bounds_min: [3]f32,
    bounds_max: [3]f32,
}

orthographic_projection :: proc(left, right, top, bottom: f32, near: f32 = 0.01, far: f32 = 1000.0) -> (result: matrix[4, 4]f32) {
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
perspective_projection :: proc(screen: [2]f32, fov: f32, near: f32 = 0.01, far: f32 = 1000.0) -> (result: matrix[4, 4]f32) {
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

calc_camera_world_to_view_matrix :: proc(camera: Camera) -> (result: matrix[4, 4]f32) {
    result =
        linalg.matrix4_from_quaternion_f32(linalg.quaternion_inverse(camera.rot)) *
        linalg.matrix4_translate_f32(-camera.pos)
    return result
}

calc_camera_world_to_clip_matrix :: proc(camera: Camera) -> (result: matrix[4, 4]f32) {
    result = camera.projection * calc_camera_world_to_view_matrix(camera)
    return result
}

calc_camera_frustum :: proc(cam: Camera) -> Frustum {
    mvp := calc_camera_world_to_clip_matrix(cam)
    inv := linalg.matrix4_inverse_f32(mvp)
    return calc_matrix_frustum(inv)
}

calc_matrix_frustum :: proc(clip_to_world: matrix[4, 4]f32) -> (result: Frustum) {
    // https://iquilezles.org/articles/frustumcorrect/
    // https://iquilezles.org/articles/frustum/

    fru := [8][4]f32{
        0 = clip_to_world * [4]f32{-1, -1,  0, 1.0},
        1 = clip_to_world * [4]f32{+1, -1,  0, 1.0},
        2 = clip_to_world * [4]f32{-1, +1,  0, 1.0},
        3 = clip_to_world * [4]f32{+1, +1,  0, 1.0},
        4 = clip_to_world * [4]f32{-1, -1, +1, 1.0},
        5 = clip_to_world * [4]f32{+1, -1, +1, 1.0},
        6 = clip_to_world * [4]f32{-1, +1, +1, 1.0},
        7 = clip_to_world * [4]f32{+1, +1, +1, 1.0},
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

    center: [3]f32
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

    _tri_plane :: proc(center: [3]f32, a, b, c: [3]f32) -> [4]f32 {
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

is_box_in_frustum :: proc(fru: Frustum, pos: [3]f32, rad: [3]f32) -> bool #no_bounds_check {
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

is_sphere_in_frustum :: proc(fru: Frustum, pos: [3]f32, rad: f32) -> bool #no_bounds_check {
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

// TODO: early out path? Most objects are small.
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
screen_to_world_ray :: proc(pos: [2]f32, cam: Camera) -> [3]f32 {
    cam_mvp := calc_camera_world_to_clip_matrix(cam)
    cam_inv := linalg.matrix4_inverse_f32(cam_mvp)

    p := pos

    p.x = (p.x / f32(get_screen_size().x)) * 2.0 - 1.0
    p.y = 1.0 - 2.0 * (p.y / f32(get_screen_size().y))

    p0 := cam_inv * [4]f32{p.x, p.y, 0.0, 1.0}
    p1 := cam_inv * [4]f32{p.x, p.y, 1.0, 1.0}
    p0.xyz /= p0.w
    p1.xyz /= p1.w

    return linalg.normalize0(p1.xyz - p0.xyz)
}

