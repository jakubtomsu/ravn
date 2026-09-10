// Rendering Hardware Interface.
// The goal is to expose a stable API roughly. The target is something like a simplified D3D11 API.
#+vet explicit-allocators shadowing unused
package ravn_gpu

import "../base"
import "core:hash/xxhash"
import "base:runtime"

// TODO: assertion messages
// TODO: the non-backend-specific code should use #caller_location for validation
// TODO: compress pipelines

RELEASE :: #config(GPU_RELEASE, base.RELEASE)
VALIDATION :: #config(GPU_VALIDATION, !RELEASE)

BACKEND :: #config(GPU_BACKEND, DEFAULT_BACKEND)

BACKEND_D3D11 :: "D3D11"
BACKEND_WGPU :: "WGPU"
BACKEND_DUMMY :: "Dummy"

when ODIN_OS == .Windows {
    DEFAULT_BACKEND :: BACKEND_D3D11
} else when ODIN_OS == .JS {
    DEFAULT_BACKEND :: BACKEND_WGPU
} else when ODIN_OS == .Linux || ODIN_OS == .Darwin {
    DEFAULT_BACKEND :: BACKEND_WGPU
} else {
    #panic("Platform not supported")
    DEFAULT_BACKEND :: BACKEND_DUMMY
}

// Base metric for the minimum recommended triangles per mesh draw, to fully utilize the HW.
// https://www.g-truc.net/post-0666.html
// https://www.yosoygames.com.ar/wp/2018/03/vertex-formats-part-2-fetch-vs-pull/
MINIMUM_TRIANGLES_PER_DRAW :: 256


// Limits are based on the D3D11 resource limits, sometimes smaller to keep things in a reasonable range.
// https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-resources-limits

MAX_TEXTURE_2D_SIZE         :: 4096
MAX_TEXTURE_3D_SIZE         :: 1024
MAX_TEXTURE_ARRAY_DEPTH     :: 1024
MAX_CONSTANT_BUFFER_SIZE    :: 4096
MAX_DISPATCH_SIZE           :: 1024 * 16 // per dimension

CONSTANTS_BIND_SLOTS :: 8
SAMPLER_BIND_SLOTS :: 8
RESOURCE_BIND_SLOTS :: 32
RW_RESOURCE_BIND_SLOTS :: 32

// Used in APIs which don't have per-resource-type spaces like D3D11.
SAMPLER_SLOT_SHIFT :: 0
CONSTANTS_SLOT_SHIFT :: SAMPLER_SLOT_SHIFT + SAMPLER_BIND_SLOTS
RESOURCE_SLOT_SHIFT :: CONSTANTS_SLOT_SHIFT + CONSTANTS_BIND_SLOTS
RW_RESOURCE_SLOT_SHIFT :: RESOURCE_SLOT_SHIFT + RESOURCE_BIND_SLOTS

RENDER_TEXTURE_BIND_SLOTS :: 4

// If you ever hit the pipeline limit it's probably a good idea to investigate
// *why* you have so many pipelines in the first place, before raising it.
MAX_PIPELINES           :: #config(GPU_MAX_PIPELINES, 256)
MAX_COMPUTE_PIPELINES   :: #config(GPU_MAX_COMPUTE_PIPELINES, 128)
MAX_RESOURCES           :: #config(GPU_MAX_RESOURCES, 1024)
MAX_SHADERS             :: #config(GPU_MAX_SHADERS, 128)
MAX_CONSTANTS           :: #config(GPU_MAX_CONSTANTS, 64)

HASH_SEED :: #config(GPU_HASH_SEED, 0xf8dff210ad)
MAX_HASH_PROBE_DIST :: 64

Handle :: base.Handle
Handle_Gen :: u8
Handle_Index :: u16

Hash :: u64

Pipeline_Handle :: distinct Handle
Compute_Pipeline_Handle :: distinct Handle
Shader_Handle :: distinct Handle
Resource_Handle :: distinct Handle

// Holds all global state.
_state: ^State

State :: struct #align(4096) {
    using native:                   _State,
    in_frame:                       bool,
    init_context:                   runtime.Context,
    allocator:                      runtime.Allocator,
    swapchain_res:                  Resource_Handle,
    // On WebGPU, the initialization is async.
    init_done:                      bool,

    pipelines:                      base.Hash_Pool(MAX_PIPELINES, Pipeline_State, Pipeline_Handle),
    pipelines_desc:                 [MAX_PIPELINES]Pipeline_Desc,
    compute_pipelines:              base.Hash_Pool(MAX_COMPUTE_PIPELINES, Compute_Pipeline_State, Compute_Pipeline_Handle),
    compute_pipelines_desc:         [MAX_COMPUTE_PIPELINES]Compute_Pipeline_Desc,

    resources:                      base.Pool(MAX_RESOURCES, Resource_State, Resource_Handle),
    shaders:                        base.Pool(MAX_SHADERS, Shader_State, Shader_Handle),

    curr_pass_desc:                 Pass_Desc,
    curr_pipeline:                  Pipeline_Handle,
    curr_pipeline_desc:             Pipeline_Desc,
    curr_num_pip_consts:            i32,

    curr_compute_pass:              bool,
    curr_compute_pipeline:          Compute_Pipeline_Handle,
    curr_compute_pipeline_desc:     Compute_Pipeline_Desc,
}

Pipeline_State :: struct {
    using native:   _Pipeline,
    loc:            runtime.Source_Code_Location,
}

Compute_Pipeline_State :: struct {
    using native:   _Compute_Pipeline,
    loc:            runtime.Source_Code_Location,
}

Shader_State :: struct {
    using native:   _Shader,
    kind:           Shader_Kind,
    loc:            runtime.Source_Code_Location,
}

// TODO: more state validation
Resource_State :: struct {
    using native:   _Resource,
    kind:           Resource_Kind,
    format:         Texture_Format,
    usage:          Usage,
    size:           [3]i32,
    loc:            runtime.Source_Code_Location,
}

// Draw pipeline - contains all possible state for rendering.
// WARNING: This structure is quite big.
// TODO: figure out how to pack the data smaller.
#assert(size_of(Pipeline_Desc) == 64 * 6)
Pipeline_Desc :: struct #align(64) {
    topo:               Topology,
    cull:               Cull_Mode,
    fill:               Fill_Mode,
    depth_comparison:   Comparison_Op,
    depth_write:        bool,
    depth_bias:         i32,

    ps:                 Shader_Handle,
    vs:                 Shader_Handle,

    index:              Index_Buffer_Desc,

    blends:             [RENDER_TEXTURE_BIND_SLOTS]Blend_Desc,
    color_format:       [RENDER_TEXTURE_BIND_SLOTS]Texture_Format,
    depth_format:       Texture_Format,

    // partial Pipeline_Bindings
    samplers:           [SAMPLER_BIND_SLOTS]Sampler_Desc,
    constants:          [CONSTANTS_BIND_SLOTS]Resource_Handle,
    resources:          [RESOURCE_BIND_SLOTS]Resource_Handle,
}

Compute_Pipeline_Desc :: struct {
    cs:                 Shader_Handle,
    using bindings:     Pipeline_Bindings_Desc,
}

Pipeline_Bindings_Desc :: struct {
    samplers:           [SAMPLER_BIND_SLOTS]Sampler_Desc,
    constants:          [CONSTANTS_BIND_SLOTS]Resource_Handle,
    resources:          [RESOURCE_BIND_SLOTS]Resource_Handle,
    rw_resources:       [RW_RESOURCE_BIND_SLOTS]Resource_Handle,
}

Pass_Desc :: struct {
    colors: [RENDER_TEXTURE_BIND_SLOTS]Pass_Color_Desc,
    depth:  Pass_Depth_Desc,
}

Pass_Color_Desc :: struct {
    resource:   Resource_Handle,
    clear_mode: Clear_Mode,
    clear_val:  [4]f32,
}

Pass_Depth_Desc :: struct {
    resource:   Resource_Handle,
    clear_mode: Clear_Mode,
    clear_val:  f32,
}

Clear_Mode :: enum u8 {
    Keep = 0,
    Clear,
}


Index_Buffer_Desc :: struct {
    resource:   Resource_Handle,
    format:     Index_Format,
    offset:     i32,
}

Sampler_Desc :: struct {
    filter:         Filter,
    bounds:         [3]Texture_Bounds,
    comparison:     Comparison_Op,
    max_aniso:      u8,
    mip_min:        f32,
    mip_max:        f32,
    mip_bias:       f32,
}

// Note: zero value of this structure means no blending
Blend_Desc :: struct {
    src_color:  Blend_Factor,
    dst_color:  Blend_Factor,
    src_alpha:  Blend_Factor,
    dst_alpha:  Blend_Factor,
    op_color:   Blend_Op,
    op_alpha:   Blend_Op,
}

Blend_Op :: enum u8 {
    Add,
    Sub,
    Reverse_Sub,
    Min,
    Max,
}

Blend_Factor :: enum u8 {
    Zero = 0,
    Src_Alpha,
    One,
    Src_Color,
    One_Minus_Src_Color,
    One_Minus_Src_Alpha,
    Dst_Alpha,
    One_Minus_Dst_Alpha,
    Dst_Color,
    One_Minus_Dst_Color,
    Src_Alpha_Sat,
}


BLEND_OPAQUE :: Blend_Desc{}

BLEND_ALPHA :: Blend_Desc {
    src_color   = .Src_Alpha,
    dst_color   = .One_Minus_Src_Alpha,
    src_alpha   = .Src_Alpha,
    dst_alpha   = .One_Minus_Src_Alpha,
    op_color    = .Add,
    op_alpha    = .Add,
}

BLEND_PREMULTIPLIED_ALPHA :: Blend_Desc {
    src_color   = .One,
    dst_color   = .One_Minus_Src_Alpha,
    src_alpha   = .One,
    dst_alpha   = .One_Minus_Src_Alpha,
    op_color    = .Add,
    op_alpha    = .Add,
}

BLEND_ADDITIVE :: Blend_Desc {
    src_color   = .Src_Alpha,
    dst_color   = .Dst_Alpha,
    src_alpha   = .Src_Alpha,
    dst_alpha   = .Dst_Alpha,
    op_color    = .Add,
    op_alpha    = .Add,
}

Shader_Kind :: enum u8 {
    Invalid = 0,
    Vertex,
    Pixel,
    Compute,
}

Resource_Kind :: enum u8 {
    Invalid = 0,
    Constants,
    Index_Buffer,
    Buffer,
    Texture2D, // can be an array
    Texture3D,
    Swapchain,
}

Index_Format :: enum u8 {
    Invalid,
    U16,
    U32,
}

Usage :: enum u8 {
    // Expects occasional data changes.
    Default = 0,
    // The data is never gonna change after upload.
    Immutable,
    // Expects frequent data changes, every frame etc.
    Dynamic,
}

Topology :: enum u8 {
    Invalid,
    Triangles,
    Lines,
}

Fill_Mode :: enum u8 {
    Invalid = 0,
    Solid,
    // NOTE: Not supported on WebGPU. The triangles will default to 'Solid'.
    Wireframe,
}

Cull_Mode :: enum u8 {
    Invalid,
    None,
    Front,
    Back,
}

Filter :: enum u8 {
    Unfiltered = 0,
    Mip_Filtered,
    Mag_Filtered,
    Mag_Mip_Filtered,
    Min_Filtered,
    Min_Mip_Filtered,
    Min_Mag_Filtered,
    Filtered,
}

Texture_Bounds :: enum u8 {
    Wrap = 0,
    Mirror,
    Clamp,
}

Comparison_Op :: enum u8 {
    Always = 0,
    Less,
    Equal,
    Less_Equal,
    Greater,
    Not_Equal,
    Greater_Equal,
    Never,
}

// TODO: rename the formats?
Texture_Format :: enum u8 {
    Invalid,
    RGBA_F32,
    RGBA_U32,
    RGBA_S32,
    RGBA_F16,
    RGBA_U16,
    RGBA_S16,
    RGBA_U16_Norm,
    RGBA_S16_Norm,
    RG_F32,
    RG_U32,
    RG_S32,
    RG_U10_A_U2,
    RG_U10_A_U2_Norm,
    RG_F11_B_F10,
    RGBA_U8,
    RGBA_S8,
    RGBA_U8_Norm,
    RGBA_S8_Norm,
    RG_F16,
    RG_U16,
    RG_S16,
    RG_U16_Norm,
    RG_S16_Norm,
    D_F32,
    R_F32,
    R_U32,
    R_S32,
    D_U24_Norm_S_U8,
    RG_U8,
    RG_S8,
    RG_U8_Norm,
    RG_S8_Norm,
    R_F16,
    R_U16,
    R_S16,
    D_U16_Norm,
    R_U16_Norm,
    R_S16_Norm,
    R_U8,
    R_S8,
    R_S8_Norm,
    R_U8_Norm,
}



// Alpha blending is default
blend_desc :: proc(
    src_color:  Blend_Factor = .Src_Alpha,
    dst_color:  Blend_Factor = .One_Minus_Src_Alpha,
    src_alpha:  Blend_Factor = .Src_Alpha,
    dst_alpha:  Blend_Factor = .One_Minus_Src_Alpha,
    op_color:   Blend_Op = .Add,
    op_alpha:   Blend_Op = .Add,
) -> Blend_Desc {
    return {
        src_color = src_color,
        dst_color = dst_color,
        src_alpha = src_alpha,
        dst_alpha = dst_alpha,
        op_color = op_color,
        op_alpha = op_alpha,
    }
}

sampler_desc :: proc(
    filter:         Filter,
    bounds:         [3]Texture_Bounds = {.Wrap, .Wrap, .Wrap},
    mip_min:        f32 = 0,
    mip_max:        f32 = 10,
    mip_bias:       f32 = 0,
    max_aniso:      i32 = 1,
) -> Sampler_Desc {
    return {
        filter = filter,
        bounds = bounds,
        mip_min = mip_min,
        mip_max = mip_max,
        mip_bias = mip_bias,
        max_aniso = u8(max_aniso),
    }
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: General
//

set_state_ptr :: proc(state: ^State) {
    _state = state
}

get_state_ptr :: proc() -> (state: ^State) {
    return _state
}

init :: proc(state: ^State, native_window: rawptr) -> bool {
    if _state != nil {
        return true
    }

    _state = state
    _state.init_context = context

    base.pool_clear(&_state.shaders)
    base.pool_clear(&_state.resources)

    return _init(native_window)
}

is_init_done :: proc() -> bool {
    return _state.init_done
}

shutdown :: proc() {
    if _state == nil {
        return
    }

    assert(!_state.in_frame)

    _shutdown()

    _state = nil
}

// return value of false means skip frame
begin_frame :: proc() -> (ok: bool) {
    assert(is_init_done())

    _state.curr_pass_desc = {}
    _state.curr_pipeline = {}
    _state.curr_pipeline_desc = {}
    _state.curr_compute_pass = {}
    _state.curr_compute_pipeline = {}
    _state.curr_compute_pipeline_desc = {}
    _state.in_frame = true

    return _begin_frame()
}



end_frame :: proc(sync: bool = true, loc := #caller_location) {
    assert(_state != nil)
    assert(_state.in_frame)
    assert(_state.curr_pass_desc == {})
    assert(_state.curr_compute_pass == {})
    _end_frame(sync)
    _state.in_frame = false
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Create
//

@(require_results)
pipeline_desc :: proc(
    ps:                 Shader_Handle,
    vs:                 Shader_Handle,

    out_colors:         []Texture_Format,
    out_depth:          Texture_Format = .Invalid,
    blends:             []Blend_Desc = {},

    index_resource:     Resource_Handle = {},
    index_format:       Index_Format = .Invalid,
    index_offset:       i32 = 0,

    samplers:           []Sampler_Desc = {},
    consts:             []Resource_Handle = {},
    resources:          []Resource_Handle = {},

    topo:               Topology = .Triangles,
    cull:               Cull_Mode = .None,
    fill:               Fill_Mode = .Solid,

    depth_comparison:   Comparison_Op = .Always,
    depth_write:        bool = false,
    depth_bias:         i32 = 0,
) -> (result: Pipeline_Desc) {
    assert(len(result.color_format) >= len(out_colors))
    assert(len(result.blends) >= len(blends))
    assert(len(result.resources) >= len(resources))
    assert(len(result.constants) >= len(consts))
    assert(len(result.samplers) >= len(samplers))

    result = {
        ps = ps,
        vs = vs,
        index = {
            resource = index_resource,
            format = index_format,
            offset = index_offset,
        },
        topo = topo,
        cull = cull,
        fill = fill,
        depth_comparison = depth_comparison,
        depth_write = depth_write,
        depth_bias = depth_bias,
    }

    result.depth_format = out_depth

    copy(result.color_format[:], out_colors)
    copy(result.blends[:], blends)
    copy(result.resources[:], resources)
    copy(result.constants[:], consts)
    copy(result.samplers[:], samplers)

    return result
}

// The pipeline will get re-created only when necessary.
@(require_results)
create_pipeline :: proc(
    name:   string,
    desc:   Pipeline_Desc,
    loc     := #caller_location,
) -> (result: Pipeline_Handle, ok: bool) {
    validate_pipeline_desc(desc)

    hash := hash_pipeline_desc(desc)
    handle, existing := base.hash_pool_find_free(_state.pipelines, hash) or_return

    if existing {
        assert(_state.pipelines_desc[handle.index] != {})
        assert(desc == _state.pipelines_desc[handle.index], "Hash Collision")
        return handle, true
    }

    base.log_debug("Creating pipeline '%s' %x", name, hash)

    state: Pipeline_State
    state.native = _create_pipeline(name, desc) or_return
    state.loc = loc

    _state.pipelines_desc[handle.index] = desc
    base.hash_pool_insert(&_state.pipelines, hash, handle, state) or_return
    return handle, true
}

@(require_results)
hash_pipeline_desc :: proc(desc: Pipeline_Desc) -> Hash {
    data := transmute([size_of(desc)]u8)desc
    return xxhash.XXH3_64_with_seed(data[:], HASH_SEED)
}

@(require_results)
hash_pipeline_bindings_desc :: proc(desc: Pipeline_Bindings_Desc) -> Hash {
    data := transmute([size_of(desc)]u8)desc
    return xxhash.XXH3_64_with_seed(data[:], HASH_SEED)
}

@(require_results)
hash_compute_pipeline_desc :: proc(desc: Compute_Pipeline_Desc) -> Hash {
    data := transmute([size_of(desc)]u8)desc
    return xxhash.XXH3_64_with_seed(data[:], HASH_SEED)
}


@(require_results)
compute_pipeline_desc :: proc(
    cs:                 Shader_Handle,
    samplers:           []Sampler_Desc = {},
    consts:             []Resource_Handle = {},
    resources:          []Resource_Handle = {},
    rw_resources:       []Resource_Handle = {},
) -> (result: Compute_Pipeline_Desc) {
    assert(len(result.resources) >= len(resources))
    assert(len(result.constants) >= len(consts))
    assert(len(result.samplers) >= len(samplers))
    assert(len(result.rw_resources) >= len(rw_resources))

    result = {
        cs = cs,
    }

    copy(result.resources[:], resources)
    copy(result.rw_resources[:], rw_resources)
    copy(result.constants[:], consts)
    copy(result.samplers[:], samplers)

    return result
}

@(require_results)
create_compute_pipeline :: proc(
    name:   string,
    desc:   Compute_Pipeline_Desc,
    loc     := #caller_location,
) -> (result: Compute_Pipeline_Handle, ok: bool) {
    validate_compute_pipeline_desc(desc, loc = loc)

    hash := hash_compute_pipeline_desc(desc)
    handle, existing := base.hash_pool_find_free(_state.compute_pipelines, hash) or_return

    if existing {
        assert(_state.compute_pipelines_desc[handle.index] != {})
        assert(desc == _state.compute_pipelines_desc[handle.index], "Hash Collision")
        return handle, true
    }

    base.log_debug("Creating compute pipeline '%s' %x", name, hash)

    state: Compute_Pipeline_State
    state.native = _create_compute_pipeline(name, desc) or_return
    state.loc = loc

    _state.compute_pipelines_desc[handle.index] = desc
    base.hash_pool_insert(&_state.compute_pipelines, hash, handle, state) or_return
    return handle, true
}

// Set 'item_num' to 2 or more to enable multi const buffers with dynamic offsets.
@(require_results)
create_constants :: proc(name: string, item_size: i32, item_num: i32 = 1, loc := #caller_location) -> (result: Resource_Handle, ok: bool) {
    assert(item_size > 0)
    assert(item_num >= 1)
    assert(item_size < MAX_CONSTANT_BUFFER_SIZE)
    assert(item_size % 16 == 0)

    result, ok = base.pool_find_free(_state.resources)
    if !ok {
        base.log_err("GPU: Failed to find an empty slot for new constants")
        return {}, false
    }

    state: Resource_State
    state.size = {item_size, item_num, 1}
    state.kind = .Constants
    state.usage = .Dynamic
    state.loc = loc
    state.native, ok = _create_constants(name, item_size = item_size, item_num = item_num)
    if !ok {
        base.log_err("GPU: Failed to create native constants")
        return {}, false
    }

    base.pool_insert(&_state.resources, result, state) or_else panic("Failed to insert")
    return result, true
}

@(require_results)
create_shader :: proc(
    name: string,
    data: []byte,
    kind: Shader_Kind,
    loc := #caller_location,
) -> (result: Shader_Handle, ok: bool) {
    assert(kind != .Invalid)
    assert(len(data) > 0)

    result, ok = base.pool_find_free(_state.shaders)
    if !ok {
        base.log_err("GPU: Failed to find an empty slot for a new shader")
        return {}, false
    }

    state: Shader_State
    state.kind = kind
    state.loc = loc
    state.native, ok = _create_shader(name, data = data, kind = kind)
    if !ok {
        base.log_err("GPU: failed to create a native shader")
        return {}, false
    }

    base.pool_insert(&_state.shaders, result, state) or_else panic("Failed to insert")
    return result, true
}

// Resources

get_swapchain :: proc() -> (result: Resource_Handle) {
    return _state.swapchain_res
}

// This creates or re-creates the swapchain if already exists.
update_swapchain :: proc(window: rawptr, size: [2]i32, loc := #caller_location) -> (result: Resource_Handle, ok: bool) {
    assert(size.x > 0, "Swapchain must be non-zero width")
    assert(size.y > 0, "Swapchain must be non-zero height")

    existing, existing_ok := _get_resource(_state.swapchain_res)
    if existing_ok {
        assert(existing.kind == .Swapchain)
        if existing.size.xy == size {
            return _state.swapchain_res, true
        }

        existing.size = {size.x, size.y, 1}

        _update_swapchain(&existing.native, window, size) or_return

        result = _state.swapchain_res

    } else {
        result = base.pool_find_free(_state.resources) or_return

        state: Resource_State
        state.kind = .Swapchain
        state.size = {size.x, size.y, 1}
        state.usage = .Default
        state.loc = loc
        _update_swapchain(&state.native, window, size) or_return

        base.pool_insert(&_state.resources, result, state) or_else panic("Failed to insert")
        _state.swapchain_res = result
    }

    return result, true
}

// TODO: Mips to zero to gen?
@(require_results)
create_texture_2d :: proc(
    name:               string,
    format:             Texture_Format,
    size:               [2]i32,
    usage:              Usage = .Default,
    mips:               i32 = 1,
    array_depth:        i32 = 1,
    render_texture:     bool = false,
    rw_resource:        bool = false,
    data:               []byte = nil,
    loc                 := #caller_location,
) -> (result: Resource_Handle, ok: bool) {
    base.log_debug("Creating texture: %s", name)

    assert(format != .Invalid)
    assert(size.x > 0)
    assert(size.x <= MAX_TEXTURE_2D_SIZE)
    assert(size.y > 0)
    assert(size.y <= MAX_TEXTURE_2D_SIZE)
    assert(array_depth < MAX_TEXTURE_ARRAY_DEPTH)

    if render_texture {
        assert(array_depth == 1)
        assert(usage == .Default)
        assert(data == nil)
    }

    if usage == .Immutable {
        assert(data != nil)
    }

    if texture_format_is_depth_stencil(format) {
        assert(render_texture)
    }

    if data != nil {
        assert(mips == 1)
        assert(array_depth == 1)
        assert(len(data) == (int(size.x * size.y) * int(texture_pixel_size(format))))
    }

    result = base.pool_find_free(_state.resources) or_return

    state: Resource_State
    state.kind = .Texture2D
    state.size = {size.x, size.y, array_depth}
    state.usage = usage
    state.format = format
    state.loc = loc

    state.native = _create_texture_2d(
        name = name,
        format = format,
        usage = usage,
        size = size,
        mips = mips,
        array_depth = array_depth,
        render_texture = render_texture,
        rw_resource = rw_resource,
        data = data,
    ) or_return

    base.pool_insert(&_state.resources, result, state) or_else panic("Failed to insert")
    return result, true
}

// Must set size or data.
@(require_results)
create_buffer :: proc(
    name:               string,
    #any_int stride:    i32,
    #any_int size:      i32 = 0,
    usage:              Usage = .Default,
    data:               []u8 = nil,
    loc                 := #caller_location,
) -> (result: Resource_Handle, ok: bool) #optional_ok {
    base.log_debug("Creating buffer: %s", name)

    size := size

    if size == 0 && data != nil {
        size = i32(len(data))
    }

    assert(stride > 0)
    assert(size > 0)
    assert(stride >= 4)
    assert(stride % 4 == 0)
    assert(stride < 1024)
    assert(size < 1024 * 1024 * 256)
    assert((size % stride) == 0)

    if usage == .Immutable {
        assert(data != nil)
    }

    if usage == .Immutable {
        assert(len(data) > 0)
    }

    result = base.pool_find_free(_state.resources) or_return

    state: Resource_State
    state.kind = .Buffer
    state.size = {size, 1, 1}
    state.usage = usage
    state.loc = loc

    state.native = _create_buffer(
        name = name,
        size = size,
        stride = stride,
        usage = usage,
        data = data,
    ) or_return

    base.pool_insert(&_state.resources, result, state) or_else panic("Failed to insert")
    return result, true
}

// Must set size or data.
@(require_results)
create_index_buffer :: proc(
    name:           string,
    #any_int size:  i32 = 0,
    data:           []u8 = nil,
    usage:          Usage = .Default,
    loc             := #caller_location,
) -> (result: Resource_Handle, ok: bool) #optional_ok {
    size := size

    if size == 0 && data != nil {
        size = i32(len(data))
    }

    assert(size > 0)

    result = base.pool_find_free(_state.resources) or_return

    state: Resource_State
    state.kind = .Index_Buffer
    state.size = {i32(runtime.align_forward_int(int(size), 64)), 1, 1}
    state.usage = usage
    state.loc = loc

    state.native = _create_index_buffer(
        name = name,
        size = i32(state.size.x),
        data = data,
        usage = usage,
    ) or_return

    base.pool_insert(&_state.resources, result, state) or_else panic("Failed to insert")
    return result, true
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Destroy
//

destroy :: proc {
    destroy_shader,
    destroy_resource,
}

destroy_shader :: proc(handle: Shader_Handle) -> bool {
    state := base.pool_get(&_state.shaders, handle) or_return
    _destroy_shader(state^)
    return base.pool_remove(&_state.shaders, handle)
}

destroy_resource :: proc(handle: Resource_Handle) -> bool {
    state := base.pool_get(&_state.resources, handle) or_return
    _destroy_resource(state^)
    return base.pool_remove(&_state.resources, handle)
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Actions
//

@(deferred_none = end_pass)
scope_pass :: proc(name: string, desc: Pass_Desc) -> bool {
    begin_pass(name, desc)
    return true
}

begin_pass :: proc(name: string, desc: Pass_Desc) {
    assert(_state.curr_pass_desc == {}, "begin_pass/end_pass mismatch")
    assert(desc != {}, "Empty pass is not valid")
    validate_pass_desc(desc)
    _begin_pass(name, desc)
    _state.curr_pipeline = {}
    _state.curr_pipeline_desc = {}
    _state.curr_pass_desc = desc
}

end_pass :: proc() {
    assert(_state.curr_pass_desc != {})
    _end_pass()
    _state.curr_pipeline = {}
    _state.curr_pipeline_desc = {}
    _state.curr_pass_desc = {}
}

set_pipeline :: proc(handle: Pipeline_Handle) {
    if _state.curr_pipeline == handle {
        return
    }

    pip, pip_ok := _get_pipeline(handle)

    if !pip_ok {
        base.log_err("GPU: trying to begin invalid pipeline:", handle)
        return
    }

    pip_desc := _state.pipelines_desc[handle.index]

    validate_pipeline_desc(pip_desc)
    validate_pipeline_for_pass(pip_desc, _state.curr_pass_desc)

    prev_desc := _state.curr_pipeline_desc

    _state.curr_pipeline = handle
    _state.curr_pipeline_desc = _state.pipelines_desc[handle.index]

    // Needed for validation
    num_consts: i32
    for handle in _state.curr_pipeline_desc.constants {
        if handle == {} {
            break
        }
        num_consts += 1
    }
    _state.curr_num_pip_consts = num_consts

    _set_pipeline(
        curr_pip = pip^,
        curr = pip_desc,
        prev = prev_desc,
    )
}

@(deferred_none = end_compute_pass)
scope_compute_pass :: proc(name: string) -> bool {
    begin_compute_pass(name)
    return true
}

begin_compute_pass :: proc(name: string) {
    assert(_state.curr_compute_pass == {}, "begin_compute_pass/end_compute_pass mismatch")
    _begin_compute_pass(name)
    _state.curr_compute_pass = true
}

end_compute_pass :: proc() {
    assert(_state.curr_compute_pass != {})
    _end_compute_pass()
    _state.curr_compute_pass = {}
}

set_compute_pipeline :: proc(handle: Compute_Pipeline_Handle) {
    pip, pip_ok := _get_compute_pipeline(handle)

    if !pip_ok {
        base.log_err("GPU: trying to begin invalid compute pipeline:", handle)
        return
    }

    pip_desc := _state.compute_pipelines_desc[handle.index]

    validate_compute_pipeline_desc(pip_desc)

    prev_desc := _state.curr_compute_pipeline_desc

    _state.curr_compute_pipeline = handle
    _state.curr_compute_pipeline_desc = _state.compute_pipelines_desc[handle.index]

    _set_compute_pipeline(
        curr_pip = pip^,
        curr = pip_desc,
        prev = prev_desc,
    )
}

// WARNING: currently 'data' is not internally copied before use, make sure to keep it alive and valid for the whole pass.
update_constants :: proc(handle: Resource_Handle, data: []byte, loc := #caller_location) {
    assert(_state.curr_pass_desc == {}, "You must do all constant updates before rendering", loc = loc)

    res, res_ok := _get_resource(handle)
    if !res_ok {
        return
    }

    assert(res.kind == .Constants, loc = loc)
    assert(len(data) <= int(res.size.x) * int(res.size.y), loc = loc)
    assert(len(data) % int(res.size.x) == 0, loc = loc)
    assert(res.size.y >= 1, loc = loc)
    assert(res.size.z == 1, loc = loc)

    _update_constants(res, data)
}

// "buffers" can be multiple separate slices of CPU memory, written consecutively to the GPU memory.
// Written range is [offset : offset + sum_of_all_buffer_sizes].
// This way the backend can sometimes more efficiently copy the data to the native buffer,
// compared to always allocating a temp buffer to combine the writes.
update_buffer :: proc(handle: Resource_Handle, offset: int, buffers: ..[]byte, loc := #caller_location) {
    assert(_state.curr_pass_desc == {}, "You must do all buffer updates before rendering", loc = loc)

    if len(buffers) == 0 {
        return
    }

    res, res_ok := _get_resource(handle)
    assert(res_ok, loc = loc)
    if !res_ok {
        return
    }

    total_len := 0
    for buf in buffers {
        total_len += len(buf)
    }

    assert(res.kind == .Buffer || res.kind == .Index_Buffer, loc = loc)
    assert(total_len <= int(res.size.x), loc = loc)
    assert(res.size.y == 1 && res.size.z == 1, loc = loc)
    assert(res.usage != .Immutable, loc = loc)

    _update_buffer(res, offset, buffers)
}

update_texture_2d :: proc(handle: Resource_Handle, data: []byte, #any_int slice: i32 = 0) -> bool {
    assert(_state.curr_pass_desc == {}, "You must do all texture updates before rendering")

    res, res_ok := _get_resource(handle)
    if !res_ok {
        return false
    }

    assert(res.kind == .Texture2D)
    assert(slice < res.size.z)
    _update_texture_2d(res^, data = data, slice = slice)
    return true
}


draw_non_indexed :: proc(
    #any_int vertex_num:        u32,
    #any_int instance_num:      u32 = 1,
    const_offsets:              []u32 = nil,
) {
    assert(_state.curr_pipeline != {})
    assert(_state.curr_pipeline_desc.topo != .Invalid)
    assert(_state.curr_pipeline_desc.vs != {})
    assert(_state.curr_pipeline_desc.ps != {})
    assert(len(const_offsets) <= int(_state.curr_num_pip_consts))

    _draw_non_indexed(
        vertex_num = vertex_num,
        instance_num = instance_num,
        const_offsets = const_offsets,
    )
}

draw_indexed :: proc(
    #any_int index_num:         u32,
    #any_int instance_num:      u32 = 1,
    #any_int index_offset:      u32 = 0,
    const_offsets:              []u32 = nil,
) {
    assert(_state.curr_pipeline_desc.vs != {})
    assert(_state.curr_pipeline_desc.ps != {})
    assert(_state.curr_pipeline_desc.index.resource != {})
    assert(_state.curr_pipeline_desc.index.format != .Invalid)
    assert(len(const_offsets) <= int(_state.curr_num_pip_consts))

    _draw_indexed(
        index_num = index_num,
        instance_num = instance_num,
        index_offset = index_offset,
        const_offsets = const_offsets,
    )
}


dispatch_compute :: proc(size: [3]i32) {
    assert(size.x > 0 && size.x < MAX_DISPATCH_SIZE)
    assert(size.y > 0 && size.y < MAX_DISPATCH_SIZE)
    assert(size.z > 0 && size.z < MAX_DISPATCH_SIZE)

    _dispatch_compute(size)
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Validation
//

validate_pass_desc :: proc(desc: Pass_Desc) {
    num_colors := 0
    resolution: [2]i32

    for color in desc.colors {
        if color.resource == {} {
            break
        }
        num_colors += 1
    }

    for color, i in desc.colors {
        if i >= num_colors {
            assert(color == {})
            break
        }

        res, res_ok := _get_resource(color.resource)

        assert(res_ok)

        #partial switch res.kind {
        case .Texture2D, .Swapchain:
        case:
            assert(false)
        }

        if resolution == {} {
            resolution = res.size.xy
        } else {
            assert(res.size.xy == resolution)
        }
    }

    if desc.depth.resource != {} {
        res, res_ok := _get_resource(desc.depth.resource)
        assert(res_ok)
        assert(res.kind == .Texture2D)
        assert(res.size.xy == resolution)
    }

    if desc.depth == {} {
        assert(num_colors > 0)
    }
}

validate_pipeline_desc :: proc(desc: Pipeline_Desc) {
    assert(desc.topo != .Invalid)
    assert(desc.fill != .Invalid)
    assert(desc.cull != .Invalid)
    assert(desc.ps != {})
    assert(desc.vs != {})

    vs_res, vs_ok := _get_shader(desc.vs)
    ps_res, ps_ok := _get_shader(desc.ps)

    assert(vs_ok, "Vertex stage must have an assigned shader")
    assert(ps_ok, "Pixel stage must have an assigned shader")

    assert(vs_res.kind == .Vertex, "Shader bound to vertex stage must be a vertex shader")
    assert(ps_res.kind == .Pixel, "Shader bound to pixel stage must be a pixel shader")

    assert(desc.color_format != {} || desc.depth_format != {})

    depth_params_set := desc.depth_write != {} ||
        desc.depth_bias != {} ||
        desc.depth_comparison != {}

    if desc.depth_format == .Invalid {
        assert(!depth_params_set)
    }

    if depth_params_set {
        assert(desc.depth_format != .Invalid)
    }

    num_colors := 0
    for col in desc.color_format {
        if col == .Invalid {
            break
        }
        num_colors += 1
    }

    for col, i in desc.color_format {
        if i >= num_colors {
            assert(col == {})
        }
        assert(!texture_format_is_depth_stencil(col))
    }

    if desc.depth_format == .Invalid {
        assert(desc.depth_bias == 0)
        assert(desc.depth_comparison == {})
        assert(desc.depth_write == false)
    } else {
        assert(texture_format_is_depth_stencil(desc.depth_format))
    }

    if desc.index.format != .Invalid {
        _, index_ok := _get_resource(desc.index.resource)
        assert(index_ok)
    }

    for handle in desc.constants {
        if handle == {} {
            continue
        }
        res, res_ok := _get_resource(handle)
        assert(res_ok)
        assert(res.kind == .Constants)
    }

    for handle in desc.resources {
        if handle == {} {
            continue
        }
        res, res_ok := _get_resource(handle)
        assert(res_ok)
        #partial switch res.kind {
        case .Buffer, .Texture2D, .Texture3D:
        case:
            assert(false)
        }
    }
}

validate_pipeline_for_pass :: proc(pip: Pipeline_Desc, pass: Pass_Desc) {
    for col, i in pass.colors {
        _, res_ok := _get_resource(col.resource)
        // TODO: assert format

        if res_ok {
            assert(pip.color_format[i] != .Invalid)
        } else {
            assert(pip.color_format[i] == .Invalid)
        }
    }

    _, depth_ok := _get_resource(pass.depth.resource)
    if depth_ok {
        assert(pip.depth_format != .Invalid)
    } else {
        assert(pip.depth_format == .Invalid)
    }
}

validate_compute_pipeline_desc :: proc(desc: Compute_Pipeline_Desc, loc := #caller_location) {
    sh, sh_ok := _get_shader(desc.cs)
    assert(sh_ok)
    assert(sh.kind == .Compute)

    for handle in desc.constants {
        if handle == {} {
            continue
        }
        res, res_ok := _get_resource(handle)
        assert(res_ok)
        assert(res.kind == .Constants)
    }

    for handle in desc.resources {
        if handle == {} {
            continue
        }
        res, res_ok := _get_resource(handle)
        assert(res_ok)
        #partial switch res.kind {
        case .Buffer, .Texture2D, .Texture3D:
        case:
            assert(false)
        }
    }

    for handle in desc.rw_resources {
        if handle == {} {
            continue
        }
        res, res_ok := _get_resource(handle)
        assert(res_ok)
        #partial switch res.kind {
        case .Buffer, .Texture2D, .Texture3D:
        case:
            assert(false)
        }
    }

    for handle in desc.resources {
        if handle == {} {
            continue
        }
        for rw_handle in desc.rw_resources {
            assert(handle != rw_handle, "A resource cannot be bounds as read-only and read-write at the same time")
        }
    }
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Internal
//

@(require_results)
_get_pipeline :: proc(handle: Pipeline_Handle) -> (^Pipeline_State, bool) {
    return base.hash_pool_get(&_state.pipelines, handle)
}

@(require_results)
_get_compute_pipeline :: proc(handle: Compute_Pipeline_Handle) -> (^Compute_Pipeline_State, bool) {
    return base.hash_pool_get(&_state.compute_pipelines, handle)
}

@(require_results)
_get_resource :: proc(handle: Resource_Handle) -> (^Resource_State, bool) {
    return base.pool_get(&_state.resources, handle)
}

@(require_results)
_get_shader :: proc(handle: Shader_Handle) -> (^Shader_State, bool) {
    return base.pool_get(&_state.shaders, handle)
}

@(require_results)
get_pipeline_desc_bindings :: proc(desc: Pipeline_Desc) -> Pipeline_Bindings_Desc {
    return {
        samplers = desc.samplers,
        constants = desc.constants,
        resources = desc.resources,
        rw_resources = {},
    }
}

@(require_results)
_combine_buffer_writes_temp :: proc(buffers: [][]byte) -> (result: []byte) {
    if len(buffers) == 1 {
        return buffers[0]
    }

    sum_len := 0
    for buf in buffers {
        sum_len += len(buf)
    }

    result = runtime.make_aligned([]byte, sum_len, 4096, context.temp_allocator)

    write_ptr := uintptr(raw_data(result))
    for buf in buffers {
        runtime.mem_copy_non_overlapping(rawptr(write_ptr), raw_data(buf), len(buf))
        write_ptr += uintptr(len(buf))
    }

    return result
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Misc
//

@(require_results)
_table_find_slot :: proc(table_used: base.Bit_Pool($N)) -> (index: int, ok: bool) {
    return base.bit_pool_find_0(table_used)
}

@(require_results)
_table_insert :: proc(table_used: ^base.Bit_Pool($N), table_gen: [N]Handle_Gen, #any_int index: int) -> (result: Handle) {
    base.bit_pool_set_1(table_used, index)
    result = {
        index = Handle_Index(index),
        gen = table_gen[index],
    }
    return result
}

_table_destroy :: proc(table_used: ^base.Bit_Pool($N), table_gen: ^[N]Handle_Gen, handle: $H/Handle) {
    if table_gen[handle.index] != handle.gen {
        return
    }

    assert(base.bit_pool_is_1(table_used^, handle.index))

    base.bit_pool_set_0(table_used, handle.index)
    table_gen[handle.index] += 1
}

@(require_results)
_table_find_empty_hash :: proc(table: ^[$N]Hash, hash: u64) -> (result: int, prev: Hash, ok: bool) {
    start_index := int(hash) %% N

    for offs in 0..<MAX_HASH_PROBE_DIST {
        index := (start_index + offs) %% N
        if index == 0 {
            continue
        }

        h := table[index]

        if h == 0 || h == hash {
            return index, h, true
        }
    }

    return 0, 0, false
}


@(require_results)
_table_get :: proc(table: ^[$N]$T, table_gen: [N]Handle_Gen, handle: $H/Handle) -> (^T, bool) #no_bounds_check {
    if handle.index <= 0 || handle.index >= N {
        return nil, false
    }

    if handle.gen != table_gen[handle.index] {
        return nil, false
    }

    return &table[handle.index], true
}


_depth_enable :: proc(comp: Comparison_Op, write: bool) -> bool {
    return comp != .Always || write
}

@(require_results)
texture_format_is_depth_stencil :: proc(format: Texture_Format) -> bool {
    #partial switch format {
    case
        .D_F32,
        .D_U16_Norm,
        .D_U24_Norm_S_U8:
        return true
    }
    return false
}


@(require_results)
texture_format_channels :: proc(format: Texture_Format) -> i32 {
    switch format {
    case .Invalid:          return 0
    case .RGBA_F32:         return 4
    case .RGBA_U32:         return 4
    case .RGBA_S32:         return 4
    case .RGBA_F16:         return 4
    case .RGBA_U16:         return 4
    case .RGBA_S16:         return 4
    case .RGBA_U16_Norm:    return 4
    case .RGBA_S16_Norm:    return 4
    case .RG_F32:           return 2
    case .RG_U32:           return 2
    case .RG_S32:           return 2
    case .RG_U10_A_U2:      return 3
    case .RG_U10_A_U2_Norm: return 3
    case .RG_F11_B_F10:     return 3
    case .RGBA_U8:          return 4
    case .RGBA_S8:          return 4
    case .RGBA_U8_Norm:     return 4
    case .RGBA_S8_Norm:     return 4
    case .RG_F16:           return 2
    case .RG_U16:           return 2
    case .RG_S16:           return 2
    case .RG_U16_Norm:      return 2
    case .RG_S16_Norm:      return 2
    case .D_F32:            return 1
    case .R_F32:            return 1
    case .R_U32:            return 1
    case .R_S32:            return 1
    case .D_U24_Norm_S_U8:  return 2
    case .RG_U8:            return 2
    case .RG_S8:            return 2
    case .RG_U8_Norm:       return 2
    case .RG_S8_Norm:       return 2
    case .R_F16:            return 1
    case .R_U16:            return 1
    case .R_S16:            return 1
    case .D_U16_Norm:       return 1
    case .R_U16_Norm:       return 1
    case .R_S16_Norm:       return 1
    case .R_U8:             return 1
    case .R_S8:             return 1
    case .R_S8_Norm:        return 1
    case .R_U8_Norm:        return 1
    }
    assert(false)
    return 0
}


@(require_results)
texture_pixel_size :: proc(format: Texture_Format) -> i32 {
    switch format {
    case .Invalid:          return 0
    case .RGBA_F32:         return 4 * 4
    case .RGBA_U32:         return 4 * 4
    case .RGBA_S32:         return 4 * 4
    case .RGBA_F16:         return 4 * 2
    case .RGBA_U16:         return 4 * 2
    case .RGBA_S16:         return 4 * 2
    case .RGBA_U16_Norm:    return 4 * 2
    case .RGBA_S16_Norm:    return 4 * 2
    case .RG_F32:           return 2 * 4
    case .RG_U32:           return 2 * 4
    case .RG_S32:           return 2 * 4
    case .RG_U10_A_U2:      return 4
    case .RG_U10_A_U2_Norm: return 4
    case .RG_F11_B_F10:     return 4
    case .RGBA_U8:          return 4 * 1
    case .RGBA_S8:          return 4 * 1
    case .RGBA_U8_Norm:     return 4 * 1
    case .RGBA_S8_Norm:     return 4 * 1
    case .RG_F16:           return 2 * 2
    case .RG_U16:           return 2 * 2
    case .RG_S16:           return 2 * 2
    case .RG_U16_Norm:      return 2 * 2
    case .RG_S16_Norm:      return 2 * 2
    case .D_F32:            return 1 * 4
    case .R_F32:            return 1 * 4
    case .R_U32:            return 1 * 4
    case .R_S32:            return 1 * 4
    case .D_U24_Norm_S_U8:  return 4
    case .RG_U8:            return 2 * 1
    case .RG_S8:            return 2 * 1
    case .RG_U8_Norm:       return 2 * 1
    case .RG_S8_Norm:       return 2 * 1
    case .R_F16:            return 1 * 2
    case .R_U16:            return 1 * 2
    case .R_S16:            return 1 * 2
    case .D_U16_Norm:       return 1 * 2
    case .R_U16_Norm:       return 1 * 2
    case .R_S16_Norm:       return 1 * 2
    case .R_U8:             return 1
    case .R_S8:             return 1
    case .R_S8_Norm:        return 1
    case .R_U8_Norm:        return 1
    }
    assert(false)
    return 0
}
