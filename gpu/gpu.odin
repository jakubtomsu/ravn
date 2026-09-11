#+vet explicit-allocators shadowing unused
package ravn_gpu

import "../base"
import "base:runtime"

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

// If you ever hit the pipeline limit it's probably a good idea to investigate
// *why* you have so many pipelines in the first place!
MAX_GRAPHICS_PIPELINES  :: #config(GPU_MAX_GRAPHICS_PIPELINES, 64)
MAX_COMPUTE_PIPELINES   :: #config(GPU_MAX_COMPUTE_PIPELINES, 64)
MAX_RESOURCES           :: #config(GPU_MAX_RESOURCES, 1024)
MAX_SHADERS             :: #config(GPU_MAX_SHADERS, 64)
MAX_CONSTANTS           :: #config(GPU_MAX_CONSTANTS, 64)
MAX_BIND_LAYOUTS        :: #config(GPU_MAX_BIND_LAYOUTS, 64)
MAX_BIND_GROUPS         :: #config(GPU_MAX_BIND_GROUPS, 64)

// Limits are based on the D3D11 resource limits, sometimes smaller to keep things in a reasonable range.
// https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-resources-limits

MAX_TEXTURE_2D_SIZE         :: 4096
MAX_TEXTURE_3D_SIZE         :: 1024
MAX_TEXTURE_ARRAY_DEPTH     :: 1024
MAX_CONSTANT_BUFFER_SIZE    :: 4096
MAX_DISPATCH_SIZE           :: 1024 * 16 // per dimension

MAX_VERTEX_LAYOUT_SLOTS   :: 16
MAX_BOUND_RENDER_TEXTURES :: 4

// Special handle to internal swapchain texture. Not an actual resource.
SWAPCHAIN_HANDLE :: Resource_Handle{index = max(base.Handle_Index), gen = 0}

Graphics_Pipeline_Handle :: distinct base.Handle
Compute_Pipeline_Handle :: distinct base.Handle
Shader_Handle :: distinct base.Handle
Resource_Handle :: distinct base.Handle
Bind_Layout_Handle :: distinct base.Handle
Bind_Group_Handle :: distinct base.Handle

// Holds all global state.
_state: ^State

State :: struct #align(4096) {
    using native:                   _State,
    in_frame:                       bool,
    init_context:                   runtime.Context,
    allocator:                      runtime.Allocator,
    // On WebGPU, the initialization is async.
    init_done:                      bool,
    swapchain_size:                 [2]i32,

    graphics_pipelines:             base.Pool(MAX_GRAPHICS_PIPELINES, Graphics_Pipeline_State, Graphics_Pipeline_Handle),
    compute_pipelines:              base.Pool(MAX_COMPUTE_PIPELINES, Compute_Pipeline_State, Compute_Pipeline_Handle),
    resources:                      base.Pool(MAX_RESOURCES, Resource_State, Resource_Handle),
    bind_layouts:                   base.Pool(MAX_BIND_LAYOUTS, Bind_Layout_State, Bind_Layout_Handle),
    bind_groups:                    base.Pool(MAX_BIND_GROUPS, Bind_Group_State, Bind_Group_Handle),
    shaders:                        base.Pool(MAX_SHADERS, Shader_State, Shader_Handle),

    encoder:                        Command_Encoder_State,
}

Command_Encoder_State :: struct {
    mode:                       Command_Encoder_Mode,
    id:                         base.Debug_ID,

    graphics_pass_desc:         Graphics_Pass_Desc,
    graphics_pipeline:          Graphics_Pipeline_Handle,
    graphics_pipeline_desc:     Graphics_Pipeline_Desc,
    graphics_index_format:      Index_Format,

    compute_pipeline:           Compute_Pipeline_Handle,
    compute_pipeline_desc:      Compute_Pipeline_Desc,
}

Command_Encoder_Mode :: enum u8 {
    None,
    Graphics,
    Compute,
}

Graphics_Pipeline_State :: struct #all_or_none {
    using native:   _Graphics_Pipeline_State,
    desc:           Graphics_Pipeline_Desc,
    id:             base.Debug_ID,
}

Compute_Pipeline_State :: struct #all_or_none {
    using native:   _Compute_Pipeline_State,
    desc:           Compute_Pipeline_Desc,
    id:             base.Debug_ID,
}

Shader_State :: struct #all_or_none {
    using native:   _Shader_State,
    kind:           Shader_Kind,
    id:             base.Debug_ID,
    data:           []byte, // Must be valid at pipeline creation time.
}

Resource_State :: struct #all_or_none {
    using native:   _Resource_State,
    kind:           Resource_Kind,
    tex_format:     Texture_Format,
    usage:          Usage,
    size:           [3]i32,
    id:             base.Debug_ID,
}

Bind_Layout_State :: struct #all_or_none {
    using native:   _Bind_Layout_State,
    desc:           Bind_Layout_Desc,
    id:             base.Debug_ID,
}

Bind_Group_State :: struct #all_or_none {
    using native:   _Bind_Group_State,
    consts:         [MAX_BIND_GROUP_CONSTANTS]Resource_Handle,
    consts_dyn:     bit_set[0..<MAX_BIND_GROUP_CONSTANTS],
    id:             base.Debug_ID,
}

Graphics_Pipeline_Desc :: struct #align(64) #all_or_none {
    topo:               Topology,
    cull:               Cull_Mode,
    fill:               Fill_Mode,
    depth_comparison:   Comparison_Op,
    depth_write:        bool,
    depth_bias:         i32,
    ps:                 Shader_Handle,
    vs:                 Shader_Handle,
    index_format:       Index_Format,
    blends:             [MAX_BOUND_RENDER_TEXTURES]Blend_Desc,
    color_format:       [MAX_BOUND_RENDER_TEXTURES]Texture_Format,
    depth_format:       Texture_Format,
    bind_layouts:       [MAX_PIPELINE_BIND_GROUPS]Bind_Layout_Handle,
    vertex_layouts:     [MAX_PIPELINE_VERTEX_LAYOUTS]Vertex_Layout_Desc,
}

// Layout of a single contiguous vertex data channel
Vertex_Layout_Desc :: struct {
    slots:  [MAX_VERTEX_LAYOUT_SLOTS]Vertex_Format,
    mode:   Vertex_Step_Mode,
}

Vertex_Step_Mode :: enum u8 {
    Vertex = 0,
    Instance,
}

Compute_Pipeline_Desc :: struct {
    cs:                 Shader_Handle,
    bind_layouts:       [MAX_PIPELINE_BIND_GROUPS]Bind_Layout_Handle,
}

Bind_Layout_Desc :: struct {
    slots:  [dynamic; NUM_TOTAL_BIND_GROUP_SLOTS]Bind_Layout_Slot_Desc,
}

Bind_Layout_Slot_Kind :: enum u8 {
    Sampler,
    Constants,
    Constants_Dynamic,
    Resource_Buffer,
    Resource_Texture_2D,
    Resource_Texture_2D_Array,
    Resource_Texture_3D,
    RW_Resource_Buffer,
    RW_Resource_Texture_2D,
    RW_Resource_Texture_2D_Array,
    RW_Resource_Texture_3D,
}

Bind_Layout_Slot_Desc :: struct {
    index:  i32,
    kind:   Bind_Layout_Slot_Kind,
    stages: bit_set[Shader_Kind],
    format: Texture_Format, // only needed for RW resources!
}

// Describes a full set of resources accessible to a pipeline
Bind_Group_Desc :: struct {
    layout: Bind_Layout_Handle,
    slots:  [dynamic; NUM_TOTAL_BIND_GROUP_SLOTS]Bind_Group_Slot_Desc,
}

Bind_Group_Slot_Desc :: struct {
    index:      i32,
    resource:   Resource_Handle,
    sampler:    Sampler_Desc,
}

Graphics_Pass_Desc :: struct {
    colors: [MAX_BOUND_RENDER_TEXTURES]Graphics_Pass_Color_Desc,
    depth:  Graphics_Pass_Depth_Desc,
}

Graphics_Pass_Color_Desc :: struct {
    resource:   Resource_Handle,
    clear_mode: Clear_Mode,
    clear_val:  [4]f32,
}

Graphics_Pass_Depth_Desc :: struct {
    resource:   Resource_Handle,
    clear_mode: Clear_Mode,
    clear_val:  f32,
}

Clear_Mode :: enum u8 {
    Keep = 0,
    Clear,
}

Buffer_Kind :: enum u8 {
    Invalid = 0,
    Storage,
    Vertex,
    Index,
}

Sampler_Desc :: struct {
    filter:         bit_set[Filter],
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
    Buffer,
    Texture2D, // can be an array
    Texture3D,
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
    Wireframe, // NOTE: Not supported on WebGPU. The triangles will default to 'Solid'.
}

Cull_Mode :: enum u8 {
    Invalid,
    None,
    Front,
    Back,
}

Filter :: enum u8 {
    Min,
    Mag,
    Mip,
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

Texture_Format :: enum u8 {
    Invalid = 0,
    Swapchain,
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
    R_F32,
    R_U32,
    R_S32,
    RG_U8,
    RG_S8,
    RG_U8_Norm,
    RG_S8_Norm,
    R_F16,
    R_U16,
    R_S16,
    R_U16_Norm,
    R_S16_Norm,
    R_U8,
    R_S8,
    R_S8_Norm,
    R_U8_Norm,
    Depth_F32,
    Depth_U24_Norm_S_U8,
    Depth_U16_Norm,
}

Vertex_Format :: enum u8 {
    Invalid = 0,
    U8,
    U8x2,
    U8x4,
    I8,
    I8x2,
    I8x4,
    U8_Norm,
    U8x2_Norm,
    U8x4_Norm,
    I8_Norm,
    I8x2_Norm,
    I8x4_Norm,
    U16,
    U16x2,
    U16x4,
    I16,
    I16x2,
    I16x4,
    U16_Norm,
    U16x2_Norm,
    U16x4_Norm,
    I16_Norm,
    I16x2_Norm,
    I16x4_Norm,
    F16,
    F16x2,
    F16x4,
    F32,
    F32x2,
    F32x3,
    F32x4,
    U32,
    U32x2,
    U32x3,
    U32x4,
    I32,
    I32x2,
    I32x3,
    I32x4,
    U10x3_U2_Norm,
}


// Alpha blending is default
make_blend_desc :: proc(
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

make_sampler_desc :: proc(
    filter:         bit_set[Filter],
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

init :: proc(state: ^State, native_window: rawptr) -> bool {
    if _state != nil {
        return true
    }
    _state = state
    _state.init_context = context

    base.pool_clear(&_state.graphics_pipelines)
    base.pool_clear(&_state.compute_pipelines)
    base.pool_clear(&_state.resources)
    base.pool_clear(&_state.bind_layouts)
    base.pool_clear(&_state.bind_groups)
    base.pool_clear(&_state.shaders)

    return _init(native_window)
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
    assert(_state.init_done)
    assert(_state.encoder == {})
    _state.encoder = {}
    _state.in_frame = true
    return _begin_frame()
}

end_frame :: proc(sync: bool = true, loc := #caller_location) {
    assert(_state != nil)
    assert(_state.in_frame)
    assert(_state.encoder == {})
    _end_frame(sync)
    _state.in_frame = false
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Create
//

@(require_results)
make_graphics_pipeline_desc :: proc(
    ps:                 Shader_Handle,
    vs:                 Shader_Handle,
    layouts:            [MAX_PIPELINE_BIND_GROUPS]Bind_Layout_Handle = {},
    vertex_layouts:     [MAX_PIPELINE_VERTEX_LAYOUTS]Vertex_Layout_Desc,
    out_colors:         []Texture_Format,
    out_depth:          Texture_Format = .Invalid,
    blends:             []Blend_Desc = {},
    index_format:       Index_Format = .Invalid,
    topo:               Topology = .Triangles,
    cull:               Cull_Mode = .None,
    fill:               Fill_Mode = .Solid,
    depth_comparison:   Comparison_Op = .Always,
    depth_write:        bool = false,
    depth_bias:         i32 = 0,
) -> (result: Graphics_Pipeline_Desc) {
    assert(len(result.color_format) >= len(out_colors))
    assert(len(result.blends) >= len(blends))

    result = {
        ps = ps,
        vs = vs,
        index_format = index_format,
        topo = topo,
        cull = cull,
        fill = fill,
        depth_comparison = depth_comparison,
        depth_write = depth_write,
        depth_bias = depth_bias,
        depth_format = out_depth,
        bind_layouts = layouts,
        vertex_layouts = vertex_layouts,
        color_format = {},
        blends = {},
    }

    copy(result.color_format[:], out_colors)
    copy(result.blends[:], blends)

    return result
}


@(require_results)
make_compute_pipeline_desc :: proc(
    cs:         Shader_Handle,
    layouts:    [MAX_PIPELINE_BIND_GROUPS]Bind_Layout_Handle,
) -> (result: Compute_Pipeline_Desc) {
    assert(cs != {})
    result = {
        cs = cs,
        bind_layouts = layouts,
    }
    return result
}

// Make vertex layout from a struct type using RTTI.
// Every field must be 4-byte aligned.
// Example:
//  Vertex :: struct {
//      pos:   [3]f32,
//      uv:    [2]f32,
//      color: [4]u8 `gpu:"U8x4_Norm"`,
//  }
make_vertex_layout :: proc($T: typeid, mode: Vertex_Step_Mode = .Vertex, loc := #caller_location) -> (result: Vertex_Layout_Desc) {
    st, is_struct := runtime.type_info_base(type_info_of(T)).variant.(runtime.Type_Info_Struct)
    if !is_struct {
        base.log_err("'%v' is not a struct", typeid_of(T), loc = loc)
        panic("type must be a struct", loc)
    }

    if int(st.field_count) > MAX_VERTEX_LAYOUT_SLOTS {
        base.log_err("'%v' has %i fields, max is %i", typeid_of(T), st.field_count, MAX_VERTEX_LAYOUT_SLOTS, loc = loc)
        panic("too many vertex fields", loc)
    }

    for field_index in 0 ..< st.field_count {
        name := st.names[field_index]
        offset := st.offsets[field_index]

        if offset % 4 != 0 {
            base.log_err("field '%v.%s' at offset %i is not 4-byte aligned", typeid_of(T), name, offset, loc = loc)
            panic("field is not 4-byte aligned", loc)
        }

        ok: bool
        if tag_val, has_tag := _struct_tag_lookup(st.tags[field_index], "gpu"); has_tag {
            result.slots[field_index], ok = _vertex_format_from_name(tag_val, T, name, loc)
            if !ok {
                base.log_err("field '%v.%s' maps to '%s', which is not a valid Vertex_Format", typeid_of(T), name, tag_val, loc = loc)
                panic("no matching Vertex_Format", loc)
            }
            continue
        }

        field_ti := runtime.type_info_core(st.types[field_index])
        elem_ti := field_ti
        num_components := 1
        if arr, is_arr := field_ti.variant.(runtime.Type_Info_Array); is_arr {
            num_components = arr.count
            elem_ti = runtime.type_info_core(arr.elem)
        }

        prefix: string
        #partial switch v in elem_ti.variant {
        case runtime.Type_Info_Float:   prefix = "F"
        case runtime.Type_Info_Integer: prefix = v.signed ? "I" : "U"
        case:
            base.log_err("field '%v.%s' has unsupported type '%v'", typeid_of(T), name, st.types[field_index].id, loc = loc)
            panic("unsupported field type", loc)
        }

        format_name := base.tprintf("%s%i", prefix, elem_ti.size * 8)
        if num_components > 1 {
            format_name = base.tprintf("%sx%i", format_name, num_components)
        }

        result.slots[field_index], ok = _vertex_format_from_name(format_name, T, name, loc)
        if !ok {
            base.log_err("field '%v.%s' maps to '%s', which is not a valid Vertex_Format", typeid_of(T), name, format_name, loc = loc)
            panic("no matching Vertex_Format", loc)
        }
    }

    result.mode = mode
    return result
}

_vertex_format_from_name :: proc(name: string, $T: typeid, field: string, loc: runtime.Source_Code_Location) -> (Vertex_Format, bool) {
    enum_ti := runtime.type_info_base(type_info_of(Vertex_Format)).variant.(runtime.Type_Info_Enum)
    for n, i in enum_ti.names {
        format := Vertex_Format(i64(enum_ti.values[i]))
        if n == name && format != .Invalid {
            return format, true
        }
    }
    return .Invalid, false
}

// Based on core:reflect.struct_tag_lookup
@(require_results)
_struct_tag_lookup :: proc(tag: string, key: string) -> (value: string, ok: bool) {
    for t := tag; t != ""; /**/ {
        i := 0
        for i < len(t) && t[i] == ' ' { // Skip whitespace
            i += 1
        }
        t = t[i:]
        if len(t) == 0 {
            break
        }

        i = 0
        loop: for i < len(t) {
            switch t[i] {
            case ':', '"':
                break loop
            case 0x00 ..< ' ', 0x7f ..= 0x9f: // break if control character is found
                break loop
            }
            i += 1
        }

        if i == 0 {
            break
        }
        if i+1 >= len(t) {
            break
        }

        if t[i] != ':' || t[i+1] != '"' {
            break
        }
        name := string(t[:i])
        t = t[i+1:]

        i = 1
        for i < len(t) && t[i] != '"' { // find closing quote
            if t[i] == '\\' {
                i += 1 // Skip escaped characters
            }
            i += 1
        }

        if i >= len(t) {
            break
        }

        val := string(t[:i+1])
        t = t[i+1:]

        if key == name {
            return val[1:i], true
        }
    }
    return
}

@(require_results)
_find_free_or_destroy_existing :: proc(
    id:             base.Debug_ID,
    pool:           ^$T/base.Pool($N, $D, $H),
    handle:         ^H,
    destroy_state:  proc(^D),
    loc             := #caller_location,
) -> (ok: bool) {
    assert(handle != nil)

    if handle^ == {} {
        handle^, ok = base.pool_find_free(pool^)
        if !ok {
            base.log_err("GPU: Failed to find an available %v: %s",
                typeid_of(H), base.format_debug_id(id, context.temp_allocator), loc = loc)
            return false
        }
        return true
    }

    old, old_ok := base.pool_get(pool, handle^)
    if !old_ok {
        base.log_err("Failed to re-create invalid %v: %s",
            typeid_of(H), base.format_debug_id(id, context.temp_allocator), loc = loc)
        return false
    }
    destroy_state(old)
    return true
}

@(require_results)
create_bind_layout :: proc(
    handle:     ^Bind_Layout_Handle,
    desc:       Bind_Layout_Desc,
    name        := #caller_expression(handle),
    loc         := #caller_location,
) -> (ok: bool) {
    desc := desc
    base.log_debug("Creating bind_group layout '%s'", name)
    id := base.create_debug_id(name, loc, context.allocator)
    defer if !ok do base.destroy_debug_id(&id)

    for &slot in desc.slots {
        if slot.stages == {} {
            if _is_bind_layout_slot_rw(slot.kind) {
                slot.stages = {.Compute}
            } else {
                slot.stages = {.Vertex, .Pixel, .Compute}
            }
        }
    }

    validate_bind_layout_desc(id, desc, loc = loc)

    _find_free_or_destroy_existing(id, &_state.bind_layouts, handle, _destroy_bind_layout_state) or_return

    state := Bind_Layout_State{
        native = {},
        desc = desc,
        id = id,
    }

    state.native, ok = _create_bind_layout(id, desc)
    if !ok {
        base.log_err("Failed to create native bind_group layout: '%s'", name)
        return false
    }

    base.pool_set(&_state.bind_layouts, handle^, state) or_else base.panic_id(id, "Invalid state")
    return true
}

@(require_results)
create_bind_group :: proc(
    handle: ^Bind_Group_Handle,
    desc:   Bind_Group_Desc,
    name    := #caller_expression(handle),
    loc     := #caller_location,
) -> (ok: bool) {
    base.log_debug("Creating bind_group '%s'", name)
    id := base.create_debug_id(name, loc, context.allocator)
    defer if !ok do base.destroy_debug_id(&id)

    validate_bind_group_desc(id, desc, loc = loc)
    _find_free_or_destroy_existing(id, &_state.bind_groups, handle, _destroy_bind_group_state) or_return

    state := Bind_Group_State{
        native = {},
        consts = {},
        consts_dyn = {},
        id = id,
    }

    state.native, ok = _create_bind_group(id, desc)
    if !ok {
        base.log_err("Failed to create native bind_group: '%s'", name)
        return false
    }

    for slot in desc.slots {
        res := _get_resource(slot.resource) or_continue
        if res.kind == .Constants {
            state.consts[slot.index] = slot.resource
            if res.size.y > 1 {
                state.consts_dyn += {int(slot.index)}
            }
        }
    }

    base.pool_set(&_state.bind_groups, handle^, state) or_else base.panic_id(id, "Invalid state")
    return true
}

@(require_results)
create_graphics_pipeline :: proc(
    handle: ^Graphics_Pipeline_Handle,
    desc:   Graphics_Pipeline_Desc,
    name    := #caller_expression(handle),
    loc     := #caller_location,
) -> (ok: bool) {
    base.log_debug("Creating graphics pipeline '%s'", name)
    id := base.create_debug_id(name, loc, context.allocator)
    defer if !ok do base.destroy_debug_id(&id)

    validate_graphics_pipeline_desc(id, desc)
    _find_free_or_destroy_existing(id, &_state.graphics_pipelines, handle, _destroy_graphics_pipeline_state) or_return

    state := Graphics_Pipeline_State{
        native = {},
        desc = desc,
        id = id,
    }

    state.native, ok = _create_graphics_pipeline(id, desc)
    if !ok {
        base.log_err("Failed to create native graphics pipeline: '%s'", name)
        return false
    }

    base.pool_set(&_state.graphics_pipelines, handle^, state) or_else base.panic_id(id, "Invalid state")
    return true
}

@(require_results)
create_compute_pipeline :: proc(
    handle: ^Compute_Pipeline_Handle,
    desc:   Compute_Pipeline_Desc,
    name    := #caller_expression(handle),
    loc     := #caller_location,
) -> (ok: bool) {
    base.log_debug("Creating compute pipeline '%s'", name)
    id := base.create_debug_id(name, loc, context.allocator)
    defer if !ok do base.destroy_debug_id(&id)

    validate_compute_pipeline_desc(id, desc, loc = loc)
    _find_free_or_destroy_existing(id, &_state.compute_pipelines, handle, _destroy_compute_pipeline_state) or_return

    state := Compute_Pipeline_State{
        native = {},
        id = id,
        desc = desc,
    }

    state.native, ok = _create_compute_pipeline(id, desc)
    if !ok {
        base.log_err("Failed to create native compute pipeline: '%s'", name)
        return false
    }

    base.pool_set(&_state.compute_pipelines, handle^, state) or_else base.panic_id(id, "Invalid state")
    return true
}

// Set 'item_num' above 1 or more to enable multi const buffers with dynamic offsets.

@(require_results)
create_constants :: proc(
    handle:     ^Resource_Handle,
    item_size:  i32,
    item_num:   i32 = 1,
    name        := #caller_expression(handle),
    loc         := #caller_location,
) -> (ok: bool) {
    id := base.create_debug_id(name, loc, context.allocator)
    defer if !ok do base.destroy_debug_id(&id)

    base.assert_id(id, item_size > 0)
    base.assert_id(id, item_num >= 1)
    base.assert_id(id, item_size < MAX_CONSTANT_BUFFER_SIZE)
    base.assert_id(id, item_size % 16 == 0)

    if item_num > 1 {
        base.assert_id(id, item_size % 256 == 0, "Dynamic constant buffers must be aligned to 256 bytes due to hardware")
    }

    _find_free_or_destroy_existing(id, &_state.resources, handle, _destroy_resource_state) or_return

    state := Resource_State{
        size = {item_size, item_num, 1},
        kind = .Constants,
        usage = .Dynamic,
        id = id,
        tex_format = .Invalid,
        native = {},
    }

    state.native, ok = _create_constants(id, item_size = item_size, item_num = item_num)
    if !ok {
        base.log_err("GPU: Failed to create native constants")
        return false
    }

    base.pool_set(&_state.resources, handle^, state) or_else base.panic_id(id, "Invalid state")
    return true
}

@(require_results)
create_shader :: proc(
    handle: ^Shader_Handle,
    data:   []byte,
    kind:   Shader_Kind,
    name    := #caller_expression(handle),
    loc     := #caller_location,
) -> (ok: bool) {
    id := base.create_debug_id(name, loc, context.allocator)
    defer if !ok do base.destroy_debug_id(&id)

    base.assert_id(id, kind != .Invalid)
    base.assert_id(id, len(data) > 0)

    _find_free_or_destroy_existing(id, &_state.shaders, handle, _destroy_shader_state) or_return

    state := Shader_State{
        kind = kind,
        id = id,
        native = {},
        data = data, // Warning, keeping user-allocated data
    }

    state.native, ok = _create_shader(id, data = data, kind = kind)
    if !ok {
        base.log_err("GPU: failed to create a native shader")
        return false
    }

    base.pool_set(&_state.shaders, handle^, state) or_else base.panic_id(id, "Invalid state")
    return true
}

// Resources

resize_swapchain :: proc(window: rawptr, size: [2]i32) -> (ok: bool) {
    assert(size.x > 0, "Swapchain must be non-zero width")
    assert(size.y > 0, "Swapchain must be non-zero height")
    if size == _state.swapchain_size {
        return true
    }
    _state.swapchain_size = size
    return _resize_swapchain(window, size)
}

// TODO: Mips to zero to gen?

@(require_results)
create_texture_2d :: proc(
    handle:             ^Resource_Handle,
    format:             Texture_Format,
    size:               [2]i32,
    usage:              Usage = .Default,
    mips:               i32 = 1,
    array_depth:        i32 = 1,
    render_texture:     bool = false,
    rw_resource:        bool = false,
    data:               []byte = nil,
    name                := #caller_expression(handle),
    loc                 := #caller_location,
) -> (ok: bool) {
    base.log_debug("Creating texture: %s", name)
    id := base.create_debug_id(name, loc, context.allocator)
    defer if !ok do base.destroy_debug_id(&id)

    base.assert_id(id, format != .Invalid)
    base.assert_id(id, size.x > 0)
    base.assert_id(id, size.x <= MAX_TEXTURE_2D_SIZE)
    base.assert_id(id, size.y > 0)
    base.assert_id(id, size.y <= MAX_TEXTURE_2D_SIZE)
    base.assert_id(id, array_depth < MAX_TEXTURE_ARRAY_DEPTH)

    if render_texture {
        base.assert_id(id, array_depth == 1)
        base.assert_id(id, usage == .Default)
        base.assert_id(id, data == nil)
    }

    if usage == .Immutable {
        base.assert_id(id, data != nil)
    }

    if is_texture_format_depth_stencil(format) {
        base.assert_id(id, render_texture)
    }

    if data != nil {
        base.assert_id(id, mips == 1)
        base.assert_id(id, array_depth == 1)
        base.assert_id(id, len(data) == (int(size.x * size.y) * int(get_texture_format_pixel_size(format))))
    }

    _find_free_or_destroy_existing(id, &_state.resources, handle, _destroy_resource_state) or_return

    state := Resource_State{
        kind = .Texture2D,
        size = {size.x, size.y, array_depth},
        usage = usage,
        tex_format = format,
        id = id,
        native = {},
    }

    state.native, ok = _create_texture_2d(id,
        format = format,
        usage = usage,
        size = size,
        mips = mips,
        array_depth = array_depth,
        render_texture = render_texture,
        rw_resource = rw_resource,
        data = data,
    )

    base.pool_set(&_state.resources, handle^, state) or_else base.panic_id(id, "Invalid state")
    return true
}

// Must set size or data.
@(require_results)
create_buffer :: proc(
    handle:             ^Resource_Handle,
    kind:               Buffer_Kind,
    #any_int stride:    i32,
    #any_int size:      i32 = 0,
    usage:              Usage = .Default,
    data:               []u8 = nil,
    name                := #caller_expression(handle),
    loc                 := #caller_location,
) -> (ok: bool) {
    base.log_debug("Creating buffer: %s", name)
    id := base.create_debug_id(name, loc, context.allocator)
    defer if !ok do base.destroy_debug_id(&id)

    size := size

    if size == 0 && data != nil {
        size = i32(len(data))
    }

    base.assert_id(id, stride > 0)
    base.assert_id(id, size > 0)
    base.assert_id(id, stride >= 4)
    base.assert_id(id, stride % 4 == 0)
    base.assert_id(id, stride < 1024)
    base.assert_id(id, size < 1024 * 1024 * 256)
    base.assert_id(id, (size % stride) == 0)

    if usage == .Immutable {
        base.assert_id(id, data != nil)
        base.assert_id(id, len(data) > 0)
    }

    _find_free_or_destroy_existing(id, &_state.resources, handle, _destroy_resource_state) or_return

    state := Resource_State{
        kind = .Buffer,
        size = {i32(runtime.align_forward_int(int(size), 64)), stride, 1},
        usage = usage,
        id = id,
        tex_format = {},
        native = {},
    }

    state.native, ok = _create_buffer(id,
        kind = kind,
        size = state.size.x,
        stride = stride,
        usage = usage,
        data = data,
    )

    base.pool_set(&_state.resources, handle^, state) or_else base.panic_id(id, "Invalid state")
    return true
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Destroy
//

destroy :: proc {
    destroy_shader,
    destroy_resource,
    destroy_bind_group,
    destroy_bind_layout,
    destroy_graphics_pipeline,
    destroy_compute_pipeline,
}

destroy_shader :: proc(handle: Shader_Handle) -> bool {
    state := base.pool_get(&_state.shaders, handle) or_return
    _destroy_shader_state(state)
    return base.pool_remove(&_state.shaders, handle)
}

destroy_resource :: proc(handle: Resource_Handle) -> bool {
    state := base.pool_get(&_state.resources, handle) or_return
    _destroy_resource_state(state)
    return base.pool_remove(&_state.resources, handle)
}

destroy_bind_group :: proc(handle: Bind_Group_Handle) -> bool {
    state := base.pool_get(&_state.bind_groups, handle) or_return
    _destroy_bind_group_state(state)
    return base.pool_remove(&_state.bind_groups, handle)
}

destroy_bind_layout :: proc(handle: Bind_Layout_Handle) -> bool {
    state := base.pool_get(&_state.bind_layouts, handle) or_return
    _destroy_bind_layout_state(state)
    return base.pool_remove(&_state.bind_layouts, handle)
}

destroy_graphics_pipeline :: proc(handle: Graphics_Pipeline_Handle) -> bool {
    state := base.pool_get(&_state.graphics_pipelines, handle) or_return
    _destroy_graphics_pipeline_state(state)
    return base.pool_remove(&_state.graphics_pipelines, handle)
}

destroy_compute_pipeline :: proc(handle: Compute_Pipeline_Handle) -> bool {
    state := base.pool_get(&_state.compute_pipelines, handle) or_return
    _destroy_compute_pipeline_state(state)
    return base.pool_remove(&_state.compute_pipelines, handle)
}

_destroy_shader_state :: proc(state: ^Shader_State) {
    _destroy_shader(state^)
    base.destroy_debug_id(&state.id)
}

_destroy_resource_state :: proc(state: ^Resource_State) {
    _destroy_resource(state^)
    base.destroy_debug_id(&state.id)
}

_destroy_bind_group_state :: proc(state: ^Bind_Group_State) {
    _destroy_bind_group(state^)
    base.destroy_debug_id(&state.id)
}

_destroy_bind_layout_state :: proc(state: ^Bind_Layout_State) {
    _destroy_bind_layout(state^)
    base.destroy_debug_id(&state.id)
}

_destroy_graphics_pipeline_state :: proc(state: ^Graphics_Pipeline_State) {
    _destroy_graphics_pipeline(state^)
    base.destroy_debug_id(&state.id)
}

_destroy_compute_pipeline_state :: proc(state: ^Compute_Pipeline_State) {
    _destroy_compute_pipeline(state^)
    base.destroy_debug_id(&state.id)
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Actions
//

@(deferred_none = end_graphics_pass)
scope_graphics_pass :: proc(name: string, desc: Graphics_Pass_Desc) -> bool {
    begin_graphics_pass(name, desc)
    return true
}

begin_graphics_pass :: proc(name: string, desc: Graphics_Pass_Desc, loc := #caller_location) {
    base.assert_id(_state.encoder.id, _state.encoder.mode == .None, "begin_pass/end_pass mismatch")
    id := base.create_debug_id(name, loc, context.temp_allocator)
    validate_pass_desc(id, desc)
    _begin_graphics_pass(id, desc)
    _state.encoder = {
        mode = .Graphics,
        id = id,
        graphics_pipeline = {},
        graphics_pipeline_desc = {},
        graphics_pass_desc = desc,
    }
}

end_graphics_pass :: proc() {
    base.assert_id(_state.encoder.id, _state.encoder.mode == .Graphics)
    _end_graphics_pass()
    _state.encoder = {}
}

set_bind_group :: proc(#any_int slot: int, handle: Bind_Group_Handle, offsets: []u32 = nil) {
    assert(_state.encoder.mode != .None)
    assert(handle != {})
    assert(slot >= 0)
    assert(slot < MAX_PIPELINE_BIND_GROUPS)
    bind_group, bind_group_ok := _get_bind_group(handle)
    assert(bind_group_ok)
    _set_bind_group(slot, bind_group, offsets)
}

set_vertex_buffer :: proc(slot: int, handle: Resource_Handle, #any_int offset: int = 0) {
    assert(_state.encoder.mode == .Graphics)
    assert(handle != {})
    buf, buf_ok := _get_resource(handle)
    assert(buf_ok)
    base.assert_id(buf.id, buf.kind == .Buffer)
    _set_vertex_buffer(slot, buf, offset)
}

set_index_buffer :: proc(handle: Resource_Handle, format: Index_Format, #any_int offset: int = 0) {
    assert(_state.encoder.mode == .Graphics)
    assert(handle != {})
    assert(format != .Invalid)
    buf, buf_ok := _get_resource(handle)
    assert(buf_ok)
    base.assert_id(buf.id, buf.kind == .Buffer)
    _state.encoder.graphics_index_format = format
    _set_index_buffer(buf, format, offset)
}

set_graphics_pipeline :: proc(handle: Graphics_Pipeline_Handle) {
    assert(_state.encoder.mode == .Graphics)
    if _state.encoder.graphics_pipeline == handle {
        return
    }

    pip, pip_ok := _get_graphics_pipeline(handle)

    if !pip_ok {
        base.log_err("GPU: trying to set invalid pipeline:", handle)
        return
    }

    validate_graphics_pipeline_desc(pip.id, pip.desc)
    validate_graphics_pipeline_for_pass(pip.id, pip.desc, _state.encoder.graphics_pass_desc)

    _state.encoder.graphics_pipeline = handle
    _state.encoder.graphics_pipeline_desc = pip.desc
    _set_graphics_pipeline(pip)
}

@(deferred_none = end_compute_pass)
scope_compute_pass :: proc(name: string) -> bool {
    begin_compute_pass(name)
    return true
}

begin_compute_pass :: proc(name: string, loc := #caller_location) {
    assert(_state.encoder.mode == .None, "begin_compute_pass/end_compute_pass mismatch")
    id := base.create_debug_id(name, loc, context.temp_allocator)
    _begin_compute_pass(id)
    _state.encoder = {
        mode = .Compute,
        id = id,
    }
}

end_compute_pass :: proc() {
    base.assert_id(_state.encoder.id, _state.encoder.mode == .Compute)
    _end_compute_pass()
    _state.encoder = {}
}

set_compute_pipeline :: proc(handle: Compute_Pipeline_Handle) {
    pip, pip_ok := _get_compute_pipeline(handle)

    if !pip_ok {
        base.log_err("GPU: trying to begin invalid compute pipeline:", handle)
        return
    }

    validate_compute_pipeline_desc(pip.id, pip.desc)

    _state.encoder.compute_pipeline = handle
    _state.encoder.compute_pipeline_desc = pip.desc
    _set_compute_pipeline(pip)
}

update_constants :: proc(handle: Resource_Handle, data: []byte, loc := #caller_location) {
    assert(_state.encoder.mode == .None, "You must do all constant updates before rendering", loc = loc)

    res, res_ok := _get_resource(handle)
    if !res_ok {
        return
    }

    assert(res.kind == .Constants, loc = loc)
    assert(len(data) <= int(res.size.x) * int(res.size.y), loc = loc)
    assert(len(data) % int(res.size.x) == 0, loc = loc)
    assert(res.size.y >= 1, loc = loc)
    assert(res.size.z == 1, loc = loc)

    data_clone := make([]byte, len(data), context.temp_allocator)
    copy(data_clone, data)

    _update_constants(res, data_clone)
}

// "buffers" can be multiple separate slices of CPU memory, written consecutively to the GPU memory.
// Written range is [offset : offset + sum_of_all_buffer_sizes].
// This way the backend can sometimes more efficiently copy the data to the native buffer,
// compared to always allocating a temp buffer to combine the writes.
update_buffer :: proc(handle: Resource_Handle, offset: int, buffers: ..[]byte, loc := #caller_location) {
    assert(_state.encoder.mode == .None, "You must do all buffer updates outside passes", loc = loc)

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

    assert(res.kind == .Buffer, loc = loc)
    assert(total_len <= int(res.size.x), loc = loc)
    assert(res.usage != .Immutable, loc = loc)

    _update_buffer(res, offset, buffers)
}

update_texture_2d :: proc(handle: Resource_Handle, data: []byte, #any_int slice: i32 = 0) -> bool {
    assert(_state.encoder.mode == .None, "You must do all texture updates before rendering")

    res, res_ok := _get_resource(handle)
    if !res_ok {
        return false
    }

    assert(res.kind == .Texture2D)
    assert(slice < res.size.z)
    _update_texture_2d(res, data = data, slice = slice)
    return true
}


draw_non_indexed :: proc(#any_int vertex_num: u32, #any_int instance_num: u32 = 1) {
    assert(_state.encoder.mode == .Graphics)
    assert(_state.encoder.graphics_pipeline != {})
    assert(_state.encoder.graphics_pipeline_desc.topo != .Invalid)
    assert(_state.encoder.graphics_pipeline_desc.vs != {})
    assert(_state.encoder.graphics_pipeline_desc.ps != {})
    _draw_non_indexed(vertex_num = vertex_num, instance_num = instance_num)
}

draw_indexed :: proc(#any_int index_num: u32, #any_int instance_num: u32 = 1, #any_int index_offset: u32 = 0) {
    assert(_state.encoder.mode == .Graphics)
    assert(_state.encoder.graphics_pipeline_desc.vs != {})
    assert(_state.encoder.graphics_pipeline_desc.ps != {})
    assert(_state.encoder.graphics_index_format != .Invalid)
    _draw_indexed(index_num = index_num, instance_num = instance_num, index_offset = index_offset)
}

dispatch_compute :: proc(size: [3]i32) {
    assert(_state.encoder.mode == .Compute)
    assert(size.x > 0 && size.x < MAX_DISPATCH_SIZE)
    assert(size.y > 0 && size.y < MAX_DISPATCH_SIZE)
    assert(size.z > 0 && size.z < MAX_DISPATCH_SIZE)
    _dispatch_compute(size)
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Validation
//

validate_pass_desc :: proc(id: base.Debug_ID, desc: Graphics_Pass_Desc, loc := #caller_location) {
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
            base.assert_id(id, color == {}, loc = loc)
            continue
        }

        if color.resource == SWAPCHAIN_HANDLE {
            resolution = _state.swapchain_size
            continue
        }

        res, res_ok := _get_resource(color.resource)
        base.assert_id(id, res_ok, loc = loc)

        #partial switch res.kind {
        case .Texture2D:
        case:
            base.assert_id(id, false, loc = loc)
        }

        if resolution == {} {
            resolution = res.size.xy
        } else {
            base.assert_id(id, res.size.xy == resolution, loc = loc)
        }
    }

    if desc.depth.resource != {} {
        res, res_ok := _get_resource(desc.depth.resource)
        base.assert_id(id, res_ok, loc = loc)
        base.assert_id(id, res.kind == .Texture2D, loc = loc)
        base.assert_id(id, res.size.xy == resolution, loc = loc)
    }

    if desc.depth == {} {
        base.assert_id(id, num_colors > 0, loc = loc)
    }
}

validate_bind_layout_desc :: proc(id: base.Debug_ID, desc: Bind_Layout_Desc, loc := #caller_location) {
    base.assert_id(id, len(desc.slots) > 0, "Bind_Group layout must have at least one slot", loc = loc)

    used: bit_set[0..<NUM_TOTAL_BIND_GROUP_SLOTS]
    for slot in desc.slots {
        base.assert_id(id, slot.index >= 0 && slot.index < _bind_layout_slot_kind_num(slot.kind),
            "Bind_Group layout slot index out of range for its kind", loc = loc)

        base.assert_id(id, int(slot.index) not_in used, "Duplicate bind_group layout slot index", loc = loc)
        used += {int(slot.index)}

        base.assert_id(id, .Invalid not_in slot.stages, "Bind_Group layout slot has an invalid shader stage", loc = loc)

        if _is_bind_layout_slot_rw(slot.kind) {
            base.assert_id(id, slot.stages != {}, "RW bind_group layout slot must specify its shader stages explicitly", loc = loc)
            base.assert_id(id, .Vertex not_in slot.stages, "RW bind_group layout slot cannot be visible to the vertex stage", loc = loc)
        }

        if _bind_layout_slot_requires_layout(slot.kind) {
            base.assert_id(id, slot.format != .Invalid, "RW texture bind_group layout slot requires a format", loc = loc)
            base.assert_id(id, !is_texture_format_depth_stencil(slot.format), "RW texture bind_group layout slot cannot use a depth format", loc = loc)
        } else {
            base.assert_id(id, slot.format == .Invalid, "Only RW texture bind_group layout slots may set a format", loc = loc)
        }
    }
}

validate_bind_group_desc :: proc(id: base.Debug_ID, desc: Bind_Group_Desc, loc := #caller_location) {
    layout, layout_ok := _get_bind_layout(desc.layout)
    base.assert_id(id, layout_ok, "Bind_Group reference an invalid layout", loc = loc)

    // A bind group must fill exactly the slots declared by its layout, no more, no less.
    base.assert_id(id, len(desc.slots) == len(layout.desc.slots), "Bind_Group must fill exactly the layout's slots", loc = loc)

    used: [NUM_TOTAL_BIND_GROUP_SLOTS]bool
    for slot in desc.slots {
        layout_slot, layout_slot_ok := _find_bind_layout_slot(layout.desc, slot.index)
        base.assert_id(id, layout_slot_ok, "Bind_Group slot index not present in the layout", loc = loc)

        base.assert_id(id, !used[slot.index], "Duplicate bind_group slot index", loc = loc)
        used[slot.index] = true

        if layout_slot.kind == .Sampler {
            base.assert_id(id, slot.resource == {}, "A sampler slot must not bind a resource", loc = loc)
            continue
        }

        base.assert_id(id, slot.resource != {}, "A resource slot must bind a resource", loc = loc)

        res, res_ok := _get_resource(slot.resource)
        base.assert_id(id, res_ok, "Bind_Group slot references an invalid resource", loc = loc)
        base.assert_id(id, res.kind == _bind_layout_slot_resource_kind(layout_slot.kind), "Bound resource kind does not match the layout slot", loc = loc)

        if layout_slot.kind == .Constants_Dynamic {
            base.assert_id(id, res.size.y > 1, "A Constants_Dynamic slot expects a multi-item constant buffer", loc = loc)
        }
    }
}


validate_graphics_pipeline_desc :: proc(id: base.Debug_ID, desc: Graphics_Pipeline_Desc, loc := #caller_location) {
    base.assert_id(id, desc.topo != .Invalid, loc = loc)
    base.assert_id(id, desc.fill != .Invalid, loc = loc)
    base.assert_id(id, desc.cull != .Invalid, loc = loc)
    base.assert_id(id, desc.ps != {}, loc = loc)
    base.assert_id(id, desc.vs != {}, loc = loc)

    vs_res, vs_ok := _get_shader(desc.vs)
    ps_res, ps_ok := _get_shader(desc.ps)

    base.assert_id(id, vs_ok, "Vertex stage must have an assigned shader", loc = loc)
    base.assert_id(id, ps_ok, "Pixel stage must have an assigned shader", loc = loc)

    base.assert_id(id, vs_res.kind == .Vertex, "Shader bound to vertex stage must be a vertex shader", loc = loc)
    base.assert_id(id, ps_res.kind == .Pixel, "Shader bound to pixel stage must be a pixel shader", loc = loc)

    base.assert_id(id, desc.color_format != {} || desc.depth_format != {}, loc = loc)

    depth_params_set := desc.depth_write != {} ||
        desc.depth_bias != {} ||
        desc.depth_comparison != {}

    if desc.depth_format == .Invalid {
        base.assert_id(id, !depth_params_set, loc = loc)
    }

    if depth_params_set {
        base.assert_id(id, desc.depth_format != .Invalid, loc = loc)
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
            base.assert_id(id, col == {}, loc = loc)
        }
        base.assert_id(id, !is_texture_format_depth_stencil(col), loc = loc)
    }

    if desc.depth_format == .Invalid {
        base.assert_id(id, desc.depth_bias == 0, loc = loc)
        base.assert_id(id, desc.depth_comparison == {}, loc = loc)
        base.assert_id(id, desc.depth_write == false, loc = loc)
    } else {
        base.assert_id(id, is_texture_format_depth_stencil(desc.depth_format), loc = loc)
    }
}

validate_graphics_pipeline_for_pass :: proc(id: base.Debug_ID, pip: Graphics_Pipeline_Desc, pass: Graphics_Pass_Desc, loc := #caller_location) {
    for col, i in pass.colors {
        if col.resource == SWAPCHAIN_HANDLE {
            base.assert_id(id, pip.color_format[i] == .Swapchain, loc = loc)
        } else {
            _, res_ok := _get_resource(col.resource)
            if res_ok {
                base.assert_id(id, pip.color_format[i] != .Invalid, loc = loc)
            } else {
                base.assert_id(id, pip.color_format[i] == .Invalid, loc = loc)
            }
        }
    }

    _, depth_ok := _get_resource(pass.depth.resource)
    if depth_ok {
        base.assert_id(id, is_texture_format_depth_stencil(pip.depth_format), loc = loc)
    } else {
        base.assert_id(id, pip.depth_format == .Invalid, loc = loc)
    }
}

validate_compute_pipeline_desc :: proc(id: base.Debug_ID, desc: Compute_Pipeline_Desc, loc := #caller_location) {
    sh, sh_ok := _get_shader(desc.cs)
    base.assert_id(id, sh_ok, loc = loc)
    base.assert_id(id, sh.kind == .Compute, loc = loc)
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Internal
//

@(require_results)
_get_graphics_pipeline :: proc(handle: Graphics_Pipeline_Handle) -> (^Graphics_Pipeline_State, bool) {
    return base.pool_get(&_state.graphics_pipelines, handle)
}

@(require_results)
_get_compute_pipeline :: proc(handle: Compute_Pipeline_Handle) -> (^Compute_Pipeline_State, bool) {
    return base.pool_get(&_state.compute_pipelines, handle)
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
_get_bind_layout :: proc(handle: Bind_Layout_Handle) -> (^Bind_Layout_State, bool) {
    return base.pool_get(&_state.bind_layouts, handle)
}

@(require_results)
_get_bind_group :: proc(handle: Bind_Group_Handle) -> (^Bind_Group_State, bool) {
    return base.pool_get(&_state.bind_groups, handle)
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
_depth_enable :: proc(comp: Comparison_Op, write: bool) -> bool {
    return comp != .Always || write
}

@(require_results)
_is_bind_layout_slot_rw :: proc(kind: Bind_Layout_Slot_Kind) -> bool {
    #partial switch kind {
    case .RW_Resource_Buffer,
        .RW_Resource_Texture_2D,
        .RW_Resource_Texture_2D_Array,
        .RW_Resource_Texture_3D:
        return true
    }
    return false
}

@(require_results)
_bind_layout_slot_requires_layout :: proc(kind: Bind_Layout_Slot_Kind) -> bool {
    #partial switch kind {
    case .RW_Resource_Texture_2D,
        .RW_Resource_Texture_2D_Array,
        .RW_Resource_Texture_3D:
        return true
    }
    return false
}

@(require_results)
_bind_layout_slot_kind_num :: proc(kind: Bind_Layout_Slot_Kind) -> i32 {
    switch kind {
    case .Sampler:
        return MAX_BIND_GROUP_SAMPLERS

    case .Constants, .Constants_Dynamic:
        return MAX_BIND_GROUP_CONSTANTS

    case .Resource_Buffer,
        .Resource_Texture_2D,
        .Resource_Texture_2D_Array,
        .Resource_Texture_3D:
        return MAX_BIND_GROUP_RESOURCES

    case .RW_Resource_Buffer,
        .RW_Resource_Texture_2D,
        .RW_Resource_Texture_2D_Array,
        .RW_Resource_Texture_3D:
        return MAX_BIND_GROUP_RW_RESOURCES
    }
    return 0
}

@(require_results)
_bind_layout_slot_kind_shift :: proc(kind: Bind_Layout_Slot_Kind) -> i32 {
    switch kind {
    case .Sampler:
        return BIND_GROUP_SAMPLER_SLOT_SHIFT

    case .Constants, .Constants_Dynamic:
        return BIND_GROUP_CONSTANTS_SLOT_SHIFT

    case .Resource_Buffer,
        .Resource_Texture_2D,
        .Resource_Texture_2D_Array,
        .Resource_Texture_3D:
        return BIND_GROUP_RESOURCE_SLOT_SHIFT

    case .RW_Resource_Buffer,
        .RW_Resource_Texture_2D,
        .RW_Resource_Texture_2D_Array,
        .RW_Resource_Texture_3D:
        return BIND_GROUP_RW_RESOURCE_SLOT_SHIFT
    }
    return 0
}

@(require_results)
_bind_layout_slot_resource_kind :: proc(kind: Bind_Layout_Slot_Kind) -> Resource_Kind {
    switch kind {
    case .Sampler:
        return .Invalid

    case .Constants, .Constants_Dynamic:
        return .Constants

    case .Resource_Buffer, .RW_Resource_Buffer:
        return .Buffer

    case .Resource_Texture_2D,
        .Resource_Texture_2D_Array,
        .RW_Resource_Texture_2D,
        .RW_Resource_Texture_2D_Array:
        return .Texture2D

    case .Resource_Texture_3D, .RW_Resource_Texture_3D:
        return .Texture3D
    }
    return .Invalid
}

@(require_results)
_find_bind_layout_slot :: proc(desc: Bind_Layout_Desc, index: i32) -> (Bind_Layout_Slot_Desc, bool) {
    for slot in desc.slots {
        if slot.index == index {
            return slot, true
        }
    }
    return {}, false
}

@(require_results)
is_texture_format_depth_stencil :: proc(format: Texture_Format) -> bool {
    #partial switch format {
    case
        .Depth_F32,
        .Depth_U16_Norm,
        .Depth_U24_Norm_S_U8:
        return true
    }
    return false
}

@(require_results)
get_texture_format_num_channels :: proc(format: Texture_Format) -> int {
    switch format {
    case .Invalid:              return 0
    case .Swapchain:            return 4
    case .RGBA_F32:             return 4
    case .RGBA_U32:             return 4
    case .RGBA_S32:             return 4
    case .RGBA_F16:             return 4
    case .RGBA_U16:             return 4
    case .RGBA_S16:             return 4
    case .RGBA_U16_Norm:        return 4
    case .RGBA_S16_Norm:        return 4
    case .RG_F32:               return 2
    case .RG_U32:               return 2
    case .RG_S32:               return 2
    case .RG_U10_A_U2:          return 3
    case .RG_U10_A_U2_Norm:     return 3
    case .RG_F11_B_F10:         return 3
    case .RGBA_U8:              return 4
    case .RGBA_S8:              return 4
    case .RGBA_U8_Norm:         return 4
    case .RGBA_S8_Norm:         return 4
    case .RG_F16:               return 2
    case .RG_U16:               return 2
    case .RG_S16:               return 2
    case .RG_U16_Norm:          return 2
    case .RG_S16_Norm:          return 2
    case .R_F32:                return 1
    case .R_U32:                return 1
    case .R_S32:                return 1
    case .RG_U8:                return 2
    case .RG_S8:                return 2
    case .RG_U8_Norm:           return 2
    case .RG_S8_Norm:           return 2
    case .R_F16:                return 1
    case .R_U16:                return 1
    case .R_S16:                return 1
    case .R_U16_Norm:           return 1
    case .R_S16_Norm:           return 1
    case .R_U8:                 return 1
    case .R_S8:                 return 1
    case .R_S8_Norm:            return 1
    case .R_U8_Norm:            return 1
    case .Depth_F32:            return 1
    case .Depth_U24_Norm_S_U8:  return 2
    case .Depth_U16_Norm:       return 1
    }
    assert(false)
    return 0
}

@(require_results)
get_texture_format_pixel_size :: proc(format: Texture_Format) -> int {
    switch format {
    case .Invalid:              return 0
    case .Swapchain:            return 0
    case .RGBA_F32:             return 4 * 4
    case .RGBA_U32:             return 4 * 4
    case .RGBA_S32:             return 4 * 4
    case .RGBA_F16:             return 4 * 2
    case .RGBA_U16:             return 4 * 2
    case .RGBA_S16:             return 4 * 2
    case .RGBA_U16_Norm:        return 4 * 2
    case .RGBA_S16_Norm:        return 4 * 2
    case .RG_F32:               return 2 * 4
    case .RG_U32:               return 2 * 4
    case .RG_S32:               return 2 * 4
    case .RG_U10_A_U2:          return 4
    case .RG_U10_A_U2_Norm:     return 4
    case .RG_F11_B_F10:         return 4
    case .RGBA_U8:              return 4 * 1
    case .RGBA_S8:              return 4 * 1
    case .RGBA_U8_Norm:         return 4 * 1
    case .RGBA_S8_Norm:         return 4 * 1
    case .RG_F16:               return 2 * 2
    case .RG_U16:               return 2 * 2
    case .RG_S16:               return 2 * 2
    case .RG_U16_Norm:          return 2 * 2
    case .RG_S16_Norm:          return 2 * 2
    case .R_F32:                return 1 * 4
    case .R_U32:                return 1 * 4
    case .R_S32:                return 1 * 4
    case .RG_U8:                return 2 * 1
    case .RG_S8:                return 2 * 1
    case .RG_U8_Norm:           return 2 * 1
    case .RG_S8_Norm:           return 2 * 1
    case .R_F16:                return 1 * 2
    case .R_U16:                return 1 * 2
    case .R_S16:                return 1 * 2
    case .R_U16_Norm:           return 1 * 2
    case .R_S16_Norm:           return 1 * 2
    case .R_U8:                 return 1
    case .R_S8:                 return 1
    case .R_S8_Norm:            return 1
    case .R_U8_Norm:            return 1
    case .Depth_F32:            return 1 * 4
    case .Depth_U24_Norm_S_U8:  return 4
    case .Depth_U16_Norm:       return 1 * 2
    }
    assert(false)
    return 0
}

get_vertex_format_size :: proc(format: Vertex_Format) -> int {
    switch format {
    case .Invalid:
        assert(false)
    case .U8:            return size_of(u8)
    case .U8x2:          return size_of(u8) * 2
    case .U8x4:          return size_of(u8) * 4
    case .I8:            return size_of(i8)
    case .I8x2:          return size_of(i8) * 2
    case .I8x4:          return size_of(i8) * 4
    case .U8_Norm:       return size_of(u8)
    case .U8x2_Norm:     return size_of(u8) * 2
    case .U8x4_Norm:     return size_of(u8) * 4
    case .I8_Norm:       return size_of(i8)
    case .I8x2_Norm:     return size_of(i8) * 2
    case .I8x4_Norm:     return size_of(i8) * 4
    case .U16:           return size_of(u16)
    case .U16x2:         return size_of(u16) * 2
    case .U16x4:         return size_of(u16) * 4
    case .I16:           return size_of(i16)
    case .I16x2:         return size_of(i16) * 2
    case .I16x4:         return size_of(i16) * 4
    case .U16_Norm:      return size_of(u16)
    case .U16x2_Norm:    return size_of(u16) * 2
    case .U16x4_Norm:    return size_of(u16) * 4
    case .I16_Norm:      return size_of(i16)
    case .I16x2_Norm:    return size_of(i16) * 2
    case .I16x4_Norm:    return size_of(i16) * 4
    case .F16:           return size_of(f16)
    case .F16x2:         return size_of(f16) * 2
    case .F16x4:         return size_of(f16) * 4
    case .F32:           return size_of(f32)
    case .F32x2:         return size_of(f32) * 2
    case .F32x3:         return size_of(f32) * 3
    case .F32x4:         return size_of(f32) * 4
    case .U32:           return size_of(u32)
    case .U32x2:         return size_of(u32) * 2
    case .U32x3:         return size_of(u32) * 3
    case .U32x4:         return size_of(u32) * 4
    case .I32:           return size_of(i32)
    case .I32x2:         return size_of(i32) * 2
    case .I32x3:         return size_of(i32) * 3
    case .I32x4:         return size_of(i32) * 4
    case .U10x3_U2_Norm: return 4
    }
    assert(false)
    return 0
}
