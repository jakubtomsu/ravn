#+vet explicit-allocators shadowing unused style
package raven

import "base"
import "base/ufmt"
import "gpu"
import "platform"
import "rscn"
import "audio"
import "shader_compiler"

import "core:mem"
import "core:bytes"
import "base:intrinsics"
import "core:slice"
import "core:math/linalg"
import "core:math"
import "base:runtime"
import debug_trace "core:debug/trace"
import stbi "vendor:stb/image"

// TODO: go through all TODOs

// TODO: fix triangles with pooled textures
// TODO: actual 3d transform structure
// TODO: objects in scene data
// TODO: asset_load and reload
// TODO: consistent get_* and no get API!
// TODO: font state
// TODO: try core:image?
// TODO: separate hash table size from backing array size?
// TODO: abstract log_error and log_warn etc to comptime disable logging?
// TODO: compress vertex data more
// TODO: More "summary" info when app exist - min/max/avg cpu/gpu frame time, num draws, temp allocs, ..?
// TODO: uniform anchor values
// TODO: drawing real lines, not quads
// TODO: default module init/shutdown procs
// TODO: load_* vs create_*, insert_* naming convention, and resource management naming in general
// TODO: DXT texture compression
// TODO: triangle drawing with a dynamic mesh?
// TODO: figure out file flushing and custom file data loop
// TODO: all resources should return a handle if an identifier exists already

RELEASE :: #config(RAVEN_RELEASE, false)
VALIDATION :: #config(RAVEN_VALIDATION, !RELEASE)

// Enable internal logs. Mostly useful for debugging internals.
// TODO: tracing
LOG_INTERNAL :: #config(RAVEN_LOG_INTERNAL, false)

MAX_GROUPS :: 64
MAX_TEXTURES :: 256 // Use texture pools if you hit this limit.
MAX_MESHES :: 1024
MAX_OBJECTS :: 1024
MAX_SPLINES :: 1024

MAX_WATCHED_DIRS :: 8
MAX_DRAW_LAYERS :: 32
MAX_RENDER_TEXTURES :: 64
MAX_TEXTURE_RESOURCES :: 64
MAX_SHADERS :: 64
MAX_FILES :: 1024
MAX_SOUNDS :: 1024

MAX_TOTAL_SPRITE_INSTANCES :: 1024 * 32
MAX_TOTAL_MESH_INSTANCES :: 1024 * 64 // Shared between meshes, lines and triangles
MAX_TOTAL_DYNAMIC_VERTS :: 1024 * 8 // Shared between triangles and lines

MAX_TEXTURE_POOLS :: 8
MAX_TEXTURE_POOL_SLICES :: 64

MAX_BIND_STATE_DEPTH :: 64

MAX_TOTAL_DRAW_BATCHES :: 4096

// This is the actual swapchain used for rendering directly to screen.
DEFAULT_RENDER_TEXTURE :: Render_Texture_Handle{MAX_RENDER_TEXTURES - 1, 0}

HASH_SEED :: #config(RAVEN_HASH_SEED, 0xcbf29ce484222325)
MAX_PROBE_DIST :: #config(RAVEN_MAX_TABLE_PROBE_DIST, 16)

HASH_ALG :: "fnv64a"

UV_EPS :: (1.0 / 4096.0)

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
IVec2 :: [2]i32
IVec3 :: [3]i32
IVec4 :: [4]i32
Mat2 :: matrix[2, 2]f32
Mat3 :: matrix[3, 3]f32
Mat4 :: matrix[4, 4]f32
Quat :: quaternion128

Hash :: u64

HANDLE_INDEX_INVALID :: ~Handle_Index(0)

Handle_Index :: u16
Handle_Gen :: u8

Handle :: struct {
    index:  Handle_Index,
    gen:    Handle_Gen,
}

Group_Handle :: distinct Handle
Object_Handle :: distinct Handle
Mesh_Handle :: distinct Handle
Texture_Handle :: distinct Handle
Texture_Resource_Handle :: distinct Handle
Spline_Handle :: distinct Handle
Render_Texture_Handle :: distinct Handle
Vertex_Shader_Handle :: distinct Handle
Pixel_Shader_Handle :: distinct Handle
Sound_Resource_Handle :: audio.Resource_Handle
Sound_Handle :: audio.Sound_Handle

Module_Desc :: base.Module_Desc
Module_Init_Proc :: base.Module_Init_Proc
Module_Shutdown_Proc :: base.Module_Shutdown_Proc
Module_Update_Proc :: base.Module_Update_Proc


Rect :: struct {
    min:    Vec2,
    max:    Vec2,
}

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

Sprite_Scaling :: enum u8 {
    // Scale of 1 means each pixel is exactly one screen pixel.
    Pixel = 0,
    // No scaling, sprite scale is the final scale in pixels
    // Scale of 1 means the ENTIRE sprite is 1x1 pixels.
    Absolute,
}

_state: ^State

State :: struct #align(64) {
    initialized:                bool,
    start_time:                 u64,
    curr_time:                  u64,
    last_time:                  u64,
    frame_dur_ns:               u64,
    frame_index:                u64,
    screen_size:                [2]i32,
    screen_dirty:               bool,
    ended_frame:                bool,
    allocator:                  runtime.Allocator,
    window:                     platform.Window,
    dpi_scale:                  f32,
    module_desc:                Module_Desc,
    module_data:                rawptr,
    shutdown_requested:         bool,

    debug_trace_ctx:            debug_trace.Context,
    context_state:              Context_State,

    uploaded_gpu_draws:         bool,

    input:                      Input,

    bind_state:                 Bind_State,
    bind_states:                [MAX_BIND_STATE_DEPTH]Bind_State,
    bind_states_len:            i32,

    builtin_group:              Group_Handle,
    builtin_mesh:               [Builtin_Mesh]Mesh_Handle,
    builtin_texture:            [Builtin_Texture]Texture_Handle,
    builtin_pixel_shader:       [Builtin_Pixel_Shader]Pixel_Shader_Handle,
    builtin_vertex_shader:      [Builtin_Vertex_Shader]Vertex_Shader_Handle,

    sprite_inst_buf:            gpu.Resource_Handle,
    mesh_inst_buf:              gpu.Resource_Handle,
    dynamic_vert_buf:           gpu.Resource_Handle,
    quad_ibuf:                  gpu.Resource_Handle,

    global_consts:              gpu.Resource_Handle,
    draw_layers_consts:         gpu.Resource_Handle,
    draw_batch_consts:          gpu.Resource_Handle,

    counters:                   [Counter_Kind]Counter_State,

    watched_dirs_num:           i32,
    watched_dirs:               [MAX_WATCHED_DIRS]Watched_Dir,

    draw_layers:                [MAX_DRAW_LAYERS]Draw_Layer,

    groups_used:                bit_set[0..<MAX_GROUPS],
    groups_gen:                 [MAX_GROUPS]Handle_Gen,
    groups:                     [MAX_GROUPS]Group,

    render_textures_used:       bit_set[0..<MAX_RENDER_TEXTURES],
    render_textures_gen:        [MAX_RENDER_TEXTURES]Handle_Gen,
    render_textures:            [MAX_RENDER_TEXTURES]Render_Texture,

    objects_hash:               [MAX_OBJECTS]Hash,
    objects_gen:                [MAX_OBJECTS]Handle_Gen,
    objects:                    [MAX_OBJECTS]Object,

    meshes_hash:                [MAX_MESHES]Hash,
    meshes_gen:                 [MAX_MESHES]Handle_Gen,
    meshes:                     [MAX_MESHES]Mesh,

    splines_hash:               [MAX_SPLINES]Hash,
    splines_gen:                [MAX_SPLINES]Handle_Gen,
    splines:                    [MAX_SPLINES]Spline,

    textures_hash:              [MAX_TEXTURES]Hash,
    textures_gen:               [MAX_TEXTURES]Handle_Gen,
    textures:                   [MAX_TEXTURES]Texture,
    texture_pools:              [MAX_TEXTURE_POOLS]Texture_Pool,
    texture_pools_len:          i32,

    pixel_shaders_hash:         [MAX_SHADERS]Hash,
    pixel_shaders_gen:          [MAX_SHADERS]Handle_Gen,
    pixel_shaders:              [MAX_SHADERS]Pixel_Shader,

    vertex_shaders_hash:        [MAX_SHADERS]Hash,
    vertex_shaders_gen:         [MAX_SHADERS]Handle_Gen,
    vertex_shaders:             [MAX_SHADERS]Vertex_Shader,

    files_hash:                 [MAX_FILES]Hash,
    files:                      [MAX_FILES]File,

    // NOTE: currently, sound resource handles are direct handles into the audio package.
    // This means there is not necessarily an indirection, which simplifies things.
    // The name tracking is only important for hotreloads and name lookups.
    sound_resources_hash:       [MAX_SOUNDS]Hash,
    sound_resources:            [MAX_SOUNDS]Sound_Resource_Handle,

    platform_state:             platform.State,
    gpu_state:                  gpu.State,
    audio_state:                audio.State,
    shader_compiler_state:      shader_compiler.State,
}

Context_State :: struct {
    tracking:   mem.Tracking_Allocator,
}

// VFS file
File :: struct {
    flags:          bit_set[File_Flag],
    data:           []byte,
}

File_Flag :: enum u8 {
    Dirty,
    Changed, // Waiting to get loaded
    Dynamically_Allocated, // must use _state.allocator
}

Watched_Dir :: struct {
    path_len:   i32,
    path:       [256]byte,
    watcher:    platform.File_Watcher,
}

Pixel_Shader :: distinct gpu.Shader_Handle
Vertex_Shader :: distinct gpu.Shader_Handle


// Data Scope
// Collection of data with one lifetime.
Group :: struct {
    spline_vert_num:    i32,
    mesh_vert_num:      i32,
    mesh_index_num:     i32,
    object_child_num:   i32,

    object_buf:         []Object,
    object_child_buf:   []Object_Handle,
    spline_vert_buf:    []Spline_Vertex,

    vbuf:               gpu.Resource_Handle,
    ibuf:               gpu.Resource_Handle,
}

Object_Kind :: rscn.Object_Kind

// TODO: objects in general are totally unfinished
Object :: struct {
    kind:               Object_Kind,

    // TODO
    // Format like "Enemy:Foo0"?
    name_prefix:        Hash,
    name:               [16]u8,

    group:              Group_Handle,

    // Depends on 'kind' - either mesh or spline handle.
    data_handle:        Handle,
    texture:            Texture_Handle,

    parent:             Object_Handle,
    child_offset:       i32,
    child_num:          i32,

    param:              u64, // user param

    local_pos:          Vec3,
    local_rot:          Mat3,
    local_scale:        Vec3,
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
}

Spline :: struct {
    group:          Group_Handle,

    vert_num:       i32,
    vert_offs:      i32,

    param:          u64, // user param

    bounds_min:     Vec3,
    bounds_max:     Vec3,
}


Vertex_Index :: u16 // GPU Vertex Index
Spline_Vertex :: rscn.Spline_Vertex

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


Bind_State :: struct {
    draw_layer:             u8,
    blend:                  Blend_Mode,
    fill:                   Fill_Mode,
    depth_test:             bool,
    depth_write:            bool,
    texture_mode:           Bind_Texture_Mode,
    texture:                u8,
    texture_slice:          u8,
    texture_size:           [2]u16, // cached
    pixel_shader:           u8,
    vertex_shader:          u8,
}

Bind_Texture_Mode :: enum u8 {
    Non_Pooled,
    Pooled,
    Render_Texture,
}

Draw_Layer :: struct {
    camera:                 Camera,
    flags:                  bit_set[Draw_Layer_Flag],

    sprite_insts_base:      u32,
    mesh_insts_base:        u32,
    triangle_insts_base:    u32,
    line_insts_base:        u32,

    last_sprites_len:       i32,
    last_meshes_len:        i32,
    last_triangles_len:     i32,
    last_lines_len:         i32,
    last_dynamic_verts_len: i32,

    // NOTE: the dynamic arrays must be allocated with temp_allocator.
    // Beware of the default append() behavior.
    // TODO: binning, opaque and additive don't care.

    sprites:                #soa[dynamic]Sprite_Draw,
    meshes:                 #soa[dynamic]Mesh_Draw,
    triangles:              #soa[dynamic]Triangle_Draw,
    lines:                  #soa[dynamic]Line_Draw,

    dynamic_verts:          [dynamic]Vertex,

    sprite_batches:         [dynamic]Draw_Batch,
    mesh_batches:           [dynamic]Draw_Batch,
    triangle_batches:       [dynamic]Draw_Batch,
    line_batches:           [dynamic]Draw_Batch,
}

Draw_Layer_Flag :: enum u8 {
    // Disable frustum culling.
    No_Cull,
    // Disable all sorting.
    // NOTE: this doesn't affect just transparent objects, it's how batching optimization is done.
    No_Reorder,
    Flip_Y,
}

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


Render_Texture :: struct #all_or_none {
    size:   IVec2,
    color:  gpu.Resource_Handle,
    depth:  gpu.Resource_Handle,
}

// (CPU) Draw instance data

Sprite_Draw :: struct #all_or_none {
    key:    Draw_Sort_Key,
    inst:   Sprite_Inst,
}

Mesh_Draw :: struct #all_or_none {
    key:    Draw_Sort_Key,
    inst:   Mesh_Inst,
}

Triangle_Draw :: distinct Mesh_Draw
Line_Draw :: distinct Mesh_Draw

// CPU Data for a single draw call.
Draw_Batch :: struct #all_or_none {
    key:            Draw_Sort_Key,
    offset:         u32,
    num:            u16,
}

// GPU Instance data

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

#assert(MAX_TEXTURES <= 256)
#assert(MAX_SHADERS <= 64)
#assert(MAX_GROUPS <= 64)

DRAW_SORT_DIST_BITS :: 14
MAX_DRAW_SORT_KEY_DIST :: (1 << DRAW_SORT_DIST_BITS) - 1

// Must be an integer.
Draw_Sort_Key_Backing :: u64

// NOTE: the sort distance could be packed in fewer bits.
// Order of batches is defined bottom-up by these fields.
Draw_Sort_Key :: bit_field Draw_Sort_Key_Backing {
    texture:        u8                  | 8,
    texture_mode:   Bind_Texture_Mode   | 2,
    dist:           u16                 | DRAW_SORT_DIST_BITS,
    fill:           Fill_Mode           | 2,
    depth_write:    bool                | 1,
    depth_test:     bool                | 1,
    group:          u8                  | 6,
    ps:             u8                  | 6,
    vs:             u8                  | 6,
    // usage depends on the drawcall type, in mesh case it's the mesh index.
    asset_index:    u16                 | 16,
    blend:          Blend_Mode          | 2,
}

draw_sort_key_equal :: proc(key_a, key_b: Draw_Sort_Key) -> bool {
    a := key_a
    b := key_b
    a.dist = 0
    b.dist = 0
    return a == b
}

DEFAULT_SAMPLERS :: [2]gpu.Sampler_Desc{
    0 = {
        filter = .Unfiltered,
        bounds = {.Wrap, .Wrap, .Wrap},
        mip_max = 10,
    },
    // 1 = {
    //     filter = .Filtered,
    //     bounds = .Wrap,
    //     mip_max = 10,
    // },
}




/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Core
//

set_state_ptr :: proc "contextless" (state: ^State) {
    _state = state
    platform._state = &_state.platform_state
    gpu._state = &_state.gpu_state
    audio._state = &_state.audio_state
}

get_state_ptr :: proc "contextless" () -> (state: ^State) {
    return _state
}


when ODIN_OS == .JS {
    @(export) step :: proc(dt: f32) -> (keep_running: bool) {
        return __js_step(dt)
    }

} else when ODIN_BUILD_MODE == .Dynamic {
    @(export) _module_hot_step :: proc "contextless" (prev_state: ^State, desc: Module_Desc) -> ^State {
        return __module_hot_step(prev_state, desc)
    }
}


// Default runner for a raven app.
//
// Calling this does nothing when compiling as a DLL, it's the responsibility
// of whoever loaded the DLL (e.g. hotreload runner) to call the app.
// NOTE: Things like reload never get called in this mode.
run_main_loop :: proc(desc: Module_Desc) {
    ensure(desc.update != nil)

    when ODIN_BUILD_MODE == .Dynamic {

        // Nothing.

    } else when ODIN_OS == .JS {

        init_state(context.allocator)
        _state.module_desc = desc

    } else when ODIN_OS == .Windows || ODIN_OS == .Linux || ODIN_OS == .Darwin {

        init_state(context.allocator)
        context = get_context()

        ensure(_state.gpu_state.init_done)

        if desc.init != nil {
            desc.init()
        }

        for {
            if !begin_frame() {
                break
            }

            _state.module_data = desc.update(nil)

            if !_state.ended_frame {
                end_frame()
            }
        }

        if desc.shutdown != nil {
            desc.shutdown()
        }

        shutdown_state()

    } else {
        panic("Cannot run module loop on this platform")
    }
}

__js_step :: proc(dt: f32) -> (keep_running: bool) {
    assert(_state != nil)
    assert(_state.module_desc.update != nil)

    context = get_context()

    if !_state.initialized {
        if gpu.is_init_done() {
            _post_gpu_init()
            if _state.module_desc.init != nil {
                _state.module_desc.init()
            }
        } else {
            return true
        }
    }

    if !begin_frame() {
        if _state.module_desc.shutdown != nil {
            _state.module_desc.shutdown()
        }
        return false
    }

    _state.module_data = _state.module_desc.update(nil)

    if !_state.ended_frame {
        end_frame()
    }

    return true
}

__module_hot_step :: proc "contextless" (prev_state: ^State, desc: Module_Desc) -> ^State {
    hotreloaded := false

    if prev_state == nil {
        // First init
        context = runtime.default_context()

        assert(_state == nil)

        init_state(context.allocator)
        context = get_context()
        ensure(_state != nil)
        assert(gpu.is_init_done())

        if desc.init != nil {
            desc.init()
        }

        return _state

    } else if _state == nil {
        hotreloaded = true
        set_state_ptr(prev_state)
        context = get_context()
    }

    context = get_context()

    assert(desc.update != nil)

    if !begin_frame() {
        if desc.shutdown != nil {
            desc.shutdown()
        }
        return nil
    }

    _state.module_data = desc.update(hotreloaded ? _state.module_data : nil)

    if !_state.ended_frame {
        end_frame()
    }

    return _state
}


get_context :: proc "contextless" () -> (result: runtime.Context) {
    result = runtime.default_context()

    result.assertion_failure_proc = _assertion_failure_proc

    result.allocator = {
        procedure = mem.tracking_allocator_proc,
        data = &_state.context_state.tracking,
    }

    result.logger = runtime.Logger{
        procedure = base._logger_proc,
        data = nil,
        lowest_level = .Debug,
        options = {.Level, .Time, .Short_File_Path, .Line, .Procedure, .Terminal_Color},
    }

    return result
}

init_context_state :: proc(ctx: ^Context_State) {
    mem.tracking_allocator_init(&_state.context_state.tracking, context.allocator, context.allocator)

    debug_trace.init(&_state.debug_trace_ctx)
}

// Create state, init context, init subsystems.
init_state :: proc(allocator := context.allocator) {
    ensure(_state == nil)

    state_err: runtime.Allocator_Error
    _state, state_err = new(State, allocator = allocator)

    if state_err != nil {
        panic("Failed to allocate Raven State")
    }

    _state.allocator = allocator

    init_context_state(&_state.context_state)

    context = get_context()

    base.log_info("Raven context initialized")

    base.log_info("Initializing platform...")

    platform.init(&_state.platform_state)

    platform.register_default_exception_handler()

    _state.start_time = platform.get_time_ns()
    platform.set_dpi_aware()

    base.log_info("Initializing audio...")

    if !audio.init(&_state.audio_state) {
        panic("Failed to initialize audio")
    }

    for &counter in _state.counters {
        counter.total_min = max(u64)
        counter.accum = max(u64)
    }

    base.log_info("Creating Window...")

    _state.window = platform.create_window("Raven App", style = .Regular)

    base.log_info("Initializing GPU...")

    if !gpu.init(&_state.gpu_state, platform.get_native_window_ptr(_state.window)) {
        panic("Failed to initialize GPU")
    }

    when !RELEASE {
        shader_compiler.init(&_state.shader_compiler_state)
    }

    if ODIN_OS != .JS {
        assert(gpu.is_init_done())
        _post_gpu_init()
    }
}

_post_gpu_init :: proc() {
    base.log_info("Finishing GPU Init...")

    assert(_state != nil)

    _state.screen_size = platform.get_window_frame_rect(_state.window).size
    _state.screen_dirty = true

    pool128_ok := create_texture_pool(128, 64)
    assert(pool128_ok)

    // Swapchain
    _state.render_textures_used += {int(DEFAULT_RENDER_TEXTURE.index)}
    _state.render_textures_gen[DEFAULT_RENDER_TEXTURE.index] = DEFAULT_RENDER_TEXTURE.gen
    _state.render_textures[DEFAULT_RENDER_TEXTURE.index] = Render_Texture{
        size = _state.screen_size,
        color = {},
        depth = gpu.create_texture_2d("rv-def-rentex-depth", .D_F32, _state.screen_size, render_texture = true) or_else panic("gpu"),
    }

    _state.sprite_inst_buf = gpu.create_buffer("rv-sprite-inst-buf",
        stride = size_of(Sprite_Inst),
        size = size_of(Sprite_Inst) * MAX_TOTAL_SPRITE_INSTANCES,
        usage = .Dynamic,
    ) or_else panic("gpu")

    _state.dynamic_vert_buf = gpu.create_buffer("rv-dynamic-vbuf",
        stride = size_of(Vertex),
        size = size_of(Vertex) * MAX_TOTAL_DYNAMIC_VERTS,
        usage = .Dynamic,
    ) or_else panic("gpu")

    _state.mesh_inst_buf = gpu.create_buffer("rv-mesh-inst-buf",
        stride = size_of(Mesh_Inst),
        size = size_of(Mesh_Inst) * MAX_TOTAL_MESH_INSTANCES,
        usage = .Dynamic,
    ) or_else panic("gpu")

    _state.global_consts = gpu.create_constants("rv-global-consts",
        size_of(Draw_Global_Constants),
    ) or_else panic("gpu")

    _state.draw_batch_consts = gpu.create_constants("rv-batch-consts",
        size_of(Draw_Batch_Constants),
        MAX_TOTAL_DRAW_BATCHES,
    ) or_else panic("gpu")

    _state.draw_layers_consts = gpu.create_constants("rv-layer-consts",
        size_of(Draw_Layer_Constants),
        MAX_DRAW_LAYERS,
    ) or_else panic("gpu")

    quad_indices := [6]u16{
        0, 1, 2,
        1, 3, 2,
    }

    _state.quad_ibuf = gpu.create_index_buffer("rv-quad-index-buf", data = gpu.slice_bytes(quad_indices[:])) or_else panic("gpu")

    _load_builtin_assets()

    base.log_info("Raven initialized successfully")

    _state.initialized = true
}

request_shutdown :: proc() {
    when ODIN_OS != .JS {
        _state.shutdown_requested = true
    }
}

// Called automatically at the right time when you call rv.request_shutdown()!
shutdown_state :: proc() {
    base.log_info("Shutting down Raven...")
    if _state == nil {
        return
    }

    if !_state.ended_frame {
        end_frame(false)
    }

    _print_stats_report()

    audio.shutdown()
    gpu.shutdown()
    platform.shutdown()

    free(_state, _state.allocator)
    _state = nil
}

_print_stats_report :: proc() {
    ufmt.eprintfln("Stats Report:")

    {
        c := _state.counters[.CPU_Frame_Ns]
        ufmt.eprintfln("CPU Frame time (ms):          avg %f, min %f, max %f",
            f64(c.total_sum) * 1e-6 / f64(c.total_num),
            f64(c.total_min) * 1e-6,
            f64(c.total_max) * 1e-6,
        )
    }

    {
        tot := _state.counters[.Num_Total_Instances]
        upl := _state.counters[.Num_Uploaded_Instances]
        ufmt.eprintfln("Per Frame Draw Instances:     avg total %f, avg uploaded %f",
            f64(tot.total_sum) / f64(tot.total_num),
            f64(upl.total_sum) / f64(upl.total_num),
        )
    }

    {
        c := _state.counters[.Num_Draw_Calls]
        ufmt.eprintfln("Draw Calls:                   avg %f, min %i, max %i",
            f64(c.total_sum) / f64(c.total_num),
            c.total_min,
            c.total_max,
        )
    }

    {
        tr := _state.context_state.tracking
        ufmt.eprintfln("Allocations:                  %i, %i freed, %i bytes total", tr.total_allocation_count, tr.total_free_count, tr.total_memory_allocated)

        if len(tr.allocation_map) > 0 {
            ufmt.eprintfln("Memory Leaks:")
            for _, it in tr.allocation_map {
                ufmt.eprintfln("\t%s(%i:%i) %s: Leaked %x of size %i bytes with alignment %i",
                    it.location.file_path,
                    it.location.line,
                    it.location.column,
                    it.location.procedure,
                    it.memory,
                    it.size,
                    it.alignment,
                )
            }
            ufmt.eprintfln("\tTotal Memory Leaks: %i", len(tr.allocation_map))
        }

        if len(tr.bad_free_array) > 0 {
            ufmt.eprintfln("Bad Frees:")
            for it in tr.bad_free_array {
                ufmt.eprintfln("\t%s(%i:%i) %s: Leaked %x",
                    it.location.file_path,
                    it.location.line,
                    it.location.column,
                    it.location.procedure,
                    it.memory,
                )
            }
            ufmt.eprintfln("\tTotal Bad Frees:", len(tr.bad_free_array))
        }

        peak_mem := tr.peak_memory_allocated + size_of(State)
        ufmt.eprintfln("Peak memory:                  %i bytes (%f MB) ", peak_mem, f64(peak_mem) / (1024 * 1024))
    }


}

begin_frame :: proc() -> (keep_running: bool) {
    assert(_state != nil)

    free_all(context.temp_allocator)
    // In case big file allocations happened...
    defer free_all(context.temp_allocator)

    if _state.frame_index == 0 {
        base.log_info("Time to first frame: %f ms", f32((platform.get_time_ns() - _state.start_time) / 1e3) * 1e-3)
    }

    keep_running = true

    _state.ended_frame = false

    prev_screen_size := _state.screen_size
    screen := platform.get_window_frame_rect(_state.window).size
    if screen.x > 0 && screen.y > 0 {
        _state.screen_size = screen
    }

    if prev_screen_size != _state.screen_size {
        _state.screen_dirty = true
    }

    if _state.screen_dirty {
        _state.screen_dirty = false
        assert(_state.render_textures_gen[DEFAULT_RENDER_TEXTURE.index] == DEFAULT_RENDER_TEXTURE.gen)
        rt := &_state.render_textures[DEFAULT_RENDER_TEXTURE.index]
        gpu.destroy_resource(rt.depth)
        rt.size = _state.screen_size
        rt.depth = gpu.create_texture_2d("rv-def-rentex-depth", .D_F32, _state.screen_size, render_texture = true) or_else panic("gpu")
        rt.color = gpu.update_swapchain(platform.get_native_window_ptr(_state.window), _state.screen_size) or_else panic("gpu")
    }

    assert(_state.render_textures[DEFAULT_RENDER_TEXTURE.index].color != {})

    for &counter in _state.counters {
        _counter_flush(&counter)
    }

    gpu_can_begin_frame := gpu.begin_frame()
    assert(gpu_can_begin_frame) // HACK

    audio.update()

    assert(_state.bind_states_len == 0, "Looks like you forgot pop_binds() somewhere")
    _state.frame_index += 1
    _state.uploaded_gpu_draws = false

    time_ns := platform.get_time_ns()
    _state.curr_time = time_ns

    _state.frame_dur_ns = time_ns - _state.last_time

    _state.last_time = time_ns

    if _state.frame_index > 10 {
        _counter_add(.CPU_Frame_Ns, _state.frame_dur_ns)
    } else {
        _counter_add(.CPU_Frame_Ns, max(u64))
    }

    _clear_draw_layers()

    _state.dpi_scale = platform.get_window_dpi_scale(_state.window)
    // base.log_info("DPI scale: ", _state.dpi_scale)

    _state.input.mouse_delta = 0
    _state.input.scroll_delta = 0

    delta := get_delta_time()
    _begin_input_digital_buffer_frame(&_state.input.keys, delta)
    _begin_input_digital_buffer_frame(&_state.input.mouse_buttons, delta)
    for &gp in _state.input.gamepads {
        _begin_input_digital_buffer_frame(&gp.buttons, delta)
        gp.axes = {}
    }

    for event in platform.poll_window_events(_state.window) {
        switch v in event {
        case platform.Event_Exit:
            keep_running = false

        case platform.Event_Key:
            if v.pressed {
                _input_digital_press(&_state.input.keys, v.key)
            } else {
                _input_digital_release(&_state.input.keys, v.key)
            }

        case platform.Event_Mouse_Button:
            if v.pressed {
                _input_digital_press(&_state.input.mouse_buttons, v.button)
            } else {
                _input_digital_release(&_state.input.mouse_buttons, v.button)
            }

        case platform.Event_Mouse:
            _state.input.mouse_delta.x += f32(v.move.x)
            _state.input.mouse_delta.y += f32(v.move.y)
            _state.input.mouse_pos.x = f32(v.pos.x)
            _state.input.mouse_pos.y = f32(v.pos.y)

        case platform.Event_Scroll:
            _state.input.scroll_delta += v.delta

        case platform.Event_Window_Size:
        }
    }

    for i in 0..<MAX_GAMEPADS {
        inp, inp_ok := platform.get_gamepad_state(i)
        if !inp_ok {
            _state.input.gamepads[i] = {}
            _state.input.gamepads_connected -= {i}
        }

        _state.input.gamepads_connected += {i}

        gpad := &_state.input.gamepads[i]

        for btn in Gamepad_Button {
            if btn in inp.buttons {
                _input_digital_press(&gpad.buttons, btn)
            } else {
                _input_digital_release(&gpad.buttons, btn)
            }
        }

        gpad.buttons.released = {}

        gpad.axes[.Left_Trigger] = inp.axes[.Left_Trigger] > 0.1 ? clamp(gpad.axes[.Left_Trigger], 0, 1) : 0
        gpad.axes[.Right_Trigger] = inp.axes[.Right_Trigger] > 0.1 ? clamp(gpad.axes[.Right_Trigger], 0, 1) : 0

        l_thumb := Vec2{
            gpad.axes[.Left_Thumb_X],
            gpad.axes[.Left_Thumb_Y],
        }

        r_thumb := Vec2{
            gpad.axes[.Right_Thumb_X],
            gpad.axes[.Right_Thumb_Y],
        }

        l_len := linalg.length(l_thumb)
        r_len := linalg.length(r_thumb)

        if l_len < 0.1 {
            l_thumb = 0
        } else if l_len > 1 {
            l_thumb = l_thumb / l_len
        }

        if r_len < 0.1 {
            r_thumb = 0
        } else if r_len > 1 {
            r_thumb = r_thumb / r_len
        }

        gpad.axes[.Left_Thumb_X] = l_thumb.x
        gpad.axes[.Left_Thumb_Y] = l_thumb.y
        gpad.axes[.Right_Thumb_X] = r_thumb.x
        gpad.axes[.Right_Thumb_Y] = r_thumb.y
    }

    if _state.frame_index < 5 {
        _state.input.mouse_delta = 0
    }

    changed_files := make([dynamic]string, 0, 64, context.temp_allocator)

    for i in 0..<_state.watched_dirs_num {
        dir := &_state.watched_dirs[i]

        path := string(dir.path[:dir.path_len])

        changes := platform.poll_file_watcher(&dir.watcher)

        for change in changes {
            base.log_info("changed file:", change)

            file_path := strings_join(path, platform.SEPARATOR, change, allocator = context.temp_allocator)

            data, ok := platform.read_file_by_path(file_path, allocator = _state.allocator)

            if !ok {
                log_internal("Failed to hotreload file {}", file_path)
                continue
            }

            if file, file_ok := get_internal_file_by_hash(hash_name(change)); file_ok {
                append(&changed_files, change)

                if .Dynamically_Allocated in file.flags {
                    delete(file.data, _state.allocator)
                }

                file.flags += {.Dirty, .Dynamically_Allocated}
                file.data = data
            } else {
                register_file_data(change, data, flags = {.Dynamically_Allocated})
            }
        }
    }

    for change in changed_files {
        load_asset(change, {})
    }

    _state.bind_states_len = 0
    _state.bind_state = {
        pixel_shader = int_cast(u8, _state.builtin_pixel_shader[.Default].index),
        vertex_shader = int_cast(u8, _state.builtin_vertex_shader[.Default].index),
        blend = .Opaque,
    }

    bind_pixel_shader_by_handle({})
    bind_vertex_shader_by_handle({})
    _bind_texture(_state.builtin_texture[.Default])

    if _state.shutdown_requested {
        keep_running = false
    }

    return keep_running
}

end_frame :: proc(vsync := true) {
    validate(!_state.ended_frame)

    _state.ended_frame = true
    curr_time := platform.get_time_ns()

    frame_work_dur_ns := curr_time - _state.last_time

    if _state.frame_index > 10 {
        _counter_add(.CPU_Frame_Work_Ns, frame_work_dur_ns)
    } else {
        _counter_add(.CPU_Frame_Work_Ns, max(u64))
    }

    gpu.end_frame(sync = vsync)
}

_clear_draw_layers :: proc() {
    for &layer in _state.draw_layers {
        layer.last_sprites_len = i32(len(layer.sprites))
        layer.last_meshes_len = i32(len(layer.meshes))
        layer.last_triangles_len = i32(len(layer.triangles))
        layer.last_lines_len = i32(len(layer.lines))
        layer.last_dynamic_verts_len = i32(len(layer.dynamic_verts))

        layer.sprites = {}
        layer.meshes = {}
        layer.triangles = {}
        layer.lines = {}
        layer.dynamic_verts = {}

        layer.sprite_batches = {}
        layer.mesh_batches = {}
        layer.triangle_batches = {}
        layer.line_batches = {}
    }
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Builtins
//

Builtin_Texture :: enum u8 {
    Default = 0,
    Error,
    White,
    CGA8x8thick,
    CGA8x8thin,
}

Builtin_Mesh :: enum u8 {
    Icosphere,
    Cube,
    Plane,
    Disk,
    Cylinder,
}

Builtin_Vertex_Shader :: enum u8 {
    Default = 0,
    Default_Sprite,
}

Builtin_Pixel_Shader :: enum u8 {
    Default,
}


@(require_results)
get_builtin_texture :: proc(id: Builtin_Texture) -> Texture_Handle {
    return _state.builtin_texture[id]
}

@(require_results)
get_builtin_mesh :: proc(id: Builtin_Mesh) -> Mesh_Handle {
    return _state.builtin_mesh[id]
}

@(require_results)
get_builtin_vertex_shader :: proc(id: Builtin_Vertex_Shader) -> Vertex_Shader_Handle {
    return _state.builtin_vertex_shader[id]
}

@(require_results)
get_builtin_pixel_shader :: proc(id: Builtin_Pixel_Shader) -> Pixel_Shader_Handle {
    return _state.builtin_pixel_shader[id]
}

_load_builtin_assets :: proc() {
    register_const_directory(#load_directory("data"))

    for &tex, id in _state.builtin_texture {
        tex = load_texture(
            ufmt.tprintf("%s.png", enum_to_string(id)),
        ) or_else panic("Failed to load builtin texture")
    }

    default_sprite_vs: []byte
    default_vs: []byte
    default_ps: []byte

    when !RELEASE {
        default_sprite_vs = #load("data/default_sprite.vs.hlsl")
        default_vs = #load("data/default.vs.hlsl")
        default_ps = #load("data/default.ps.hlsl")
    } else when gpu.BACKEND ==  gpu.BACKEND_D3D11 {
        default_sprite_vs = #load("data/default_sprite.vs.hlsl.dxbc")
        default_vs = #load("data/default.vs.hlsl.dxbc")
        default_ps = #load("data/default.ps.hlsl.dxbc")

    } else when gpu.BACKEND == gpu.BACKEND_WGPU {
        default_sprite_vs = #load("data/default_sprite.vs.hlsl.wgsl")
        default_vs = #load("data/default.vs.hlsl.wgsl")
        default_ps = #load("data/default.ps.hlsl.wgsl")
    } else {
        #panic("GPU backend not supported")
    }


    _state.builtin_vertex_shader = {
        .Default = create_vertex_shader("default", default_vs) or_else panic("Failed to load default vertex shader"),
        .Default_Sprite = create_vertex_shader("default_sprite", default_sprite_vs) or_else panic("Failed to load default sprite vertex shader"),
    }

    _state.builtin_pixel_shader = {
        .Default = create_pixel_shader("default", default_ps) or_else panic("Failed to load default pixel shader"),
    }

    _state.builtin_group = load_scene_from_data(
        #load("data/default.rscn", string),
        #load("data/default.rscn.bin"),
        dst_group = {},
    ) or_else panic("Failed to load default scene")

    for &handle, id in _state.builtin_mesh {
        handle = get_mesh_by_name(enum_to_string(id)) or_else panic("Failed to get builtin mesh")
    }
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Util
//

// Last frame delta time
@(require_results)
get_delta_time :: proc() -> f32 {
    return f32(f64(_state.frame_dur_ns) * 1e-9)
}

@(require_results)
get_frame_index :: proc() -> u64 {
    return _state.frame_index
}

@(require_results)
get_time :: proc() -> f32 {
    return f32(f64(_state.curr_time - _state.start_time) * 1e-9)
}

@(require_results)
get_window :: proc() -> platform.Window {
    return _state.window
}

@(require_results)
atlas_cell :: proc(split: [2]i32, coord: [2]i32, scale: [2]f32 = 1.0) -> Rect {
    validate(split.x >= 1)
    validate(split.y >= 1)

    p := Vec2{
        linalg.fract(f32(coord.x) / f32(split.x)),
        linalg.fract(f32(coord.y) / f32(split.y)),
    }

    result := Rect{
        min = p,
        max = p + {
            scale.x / f32(split.x),
            scale.y / f32(split.y),
        },
    }

    result.min.y = 1.0 - result.min.y
    result.max.y = 1.0 - result.max.y

    return result
}

@(require_results)
atlas_slot :: proc(split: [2]i32, #any_int index: i32) -> Rect {
    validate(split.x >= 1)
    validate(split.y >= 1)

    coord := [2]i32{
        index % split.x,
        index / split.x,
    }

    return atlas_cell(split, coord)
}

FONT_SPLIT :: 16

@(require_results)
font_cell :: proc(coord: [2]i32) -> Rect {
    return atlas_cell(FONT_SPLIT, coord)
}

// Use rune_to_char to convert unicode symbols to the index.
@(require_results)
font_slot :: proc(#any_int index: i32) -> Rect {
    return font_cell([2]i32{
        index % FONT_SPLIT,
        index / FONT_SPLIT,
    })
}

@(require_results)
hash_name :: #force_inline proc "contextless" (name: string) -> Hash {
    hash := hash_fnv64a(transmute([]byte)name, seed = HASH_SEED)
    return Hash(hash == 0 ? 1 : hash)
}

@(require_results)
hash_const_name :: #force_inline proc "contextless" ($Name: string) -> Hash {
    hash: u64 = #hash(Name, HASH_ALG)
    return Hash(hash == 0 ? 1 : hash)
}

@(require_results)
get_screen_size :: proc() -> [2]f32 {
    return {f32(_state.screen_size.x), f32(_state.screen_size.y)}
}

@(require_results)
get_viewport :: proc() -> [3]f32 {
    return {f32(_state.screen_size.x), f32(_state.screen_size.y), 1.0}
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Scene
//

load_scene :: proc(name: string, dst_group: Group_Handle) -> (result_group: Group_Handle, ok: bool) {
    bin_name := strings_join(name, ".bin", allocator = context.temp_allocator)
    txt_data := get_file_data(name) or_return
    bin_data := get_file_data(bin_name) or_return

    return load_scene_from_data(string(txt_data), bin_data, dst_group)
}

load_scene_from_data :: proc(txt: string, bin: []byte, dst_group: Group_Handle) -> (Group_Handle, bool) {
    validate(len(txt) >= 5)
    validate(len(bin) >= 5)

    base.log_info("Loading Scene")

    parser := rscn.make_parser(txt)

    header, header_err := rscn.parse_header(&parser)
    if header_err != .OK {
        base.log_err("Failed to load scene: Header error")
        return {}, false
    }

    vert_buf := slice.reinterpret([]rscn.Mesh_Vertex, bin[header.mesh_vert_offs:])[:header.mesh_vert_num]
    index_buf := slice.reinterpret([]u16, bin[header.mesh_index_offs:])[:header.mesh_index_num]
    spline_vert_buf := slice.reinterpret([]rscn.Spline_Vertex, bin[header.spline_vert_offs:])[:header.spline_vert_num]

    group: ^Group
    group_handle: Group_Handle

    if dst_group != {} {
        ok: bool
        group, ok = get_internal_group(dst_group)
        group_handle = dst_group

        if !ok {
            base.log_err("Failed to load scene: Invalid target group handle")
            return {}, false
        }

        // APPEND TO GPU

    } else {
        verts := make([]Vertex, len(vert_buf), context.temp_allocator)
        for i in 0..<len(verts) {
            v := vert_buf[i]
            verts[i] = {
                pos = v.pos,
                uv = v.uv,
                normal = v.normal,
                col = {v.color.r, v.color.g, v.color.b, 255},
            }
        }

        ok: bool
        group_handle, ok = create_group(
            max_total_children  = i32(header.object_num),
            max_spline_verts    = i32(header.spline_vert_num),
            vertex_data         = verts,
            index_data          = index_buf,
        )

        if !ok {
            base.log_err("Failed to load scene: Couldn't create group")
            return {}, false
        }

        group, _ = get_internal_group(group_handle)

        assert(group != nil)
    }

    object_list := make([]Object_Handle, header.object_num, context.temp_allocator)
    mesh_list := make([]Mesh_Handle, header.object_num, context.temp_allocator)
    spline_list := make([]Spline_Handle, header.object_num, context.temp_allocator)

    object_counter := 0
    mesh_counter := 0
    spline_counter := 0

    parse_loop: for {
        elem, elem_err := rscn.parse_next_elem(&parser)
        switch elem_err {
        case .OK:

        case .End:
            break parse_loop

        case .Error:
            base.log_err("Failed to parse scene file")
            break parse_loop
        }

        switch v in elem {
        case rscn.Comment:

        case rscn.Image:
            _, ok := get_texture_by_name(v.path)
            if ok {
                // Ignore existing textures.
                // Watcher should handle the data updates.
                continue
            }

            if !load_asset(v.path, {}) {
                base.log_err("Failed to load scene texture")
            }

        case rscn.Mesh:
            base.log_debug("Loading Mesh: %s", v.name)

            index := mesh_counter
            mesh_counter += 1

            mesh: Mesh
            mesh.group = group_handle

            mesh.vert_num = i32(v.vert_num)
            mesh.index_num = i32(v.index_num)
            mesh.vert_offs = i32(v.vert_start) + group.mesh_vert_num
            mesh.index_offs = i32(v.index_start) + group.mesh_index_num

            verts := vert_buf[v.vert_start:][:v.vert_num]
            // indexes := index_buf[v.index_start:][:v.index_num]

            mesh.bounds_min = max(f32)
            mesh.bounds_max = min(f32)
            for vert in verts {
                mesh.bounds_min = linalg.min(mesh.bounds_min, vert.pos)
                mesh.bounds_max = linalg.max(mesh.bounds_max, vert.pos)
            }

            handle, handle_ok := insert_mesh_by_name(v.name, mesh)
            if !handle_ok {
                base.log_err("Failed to insert mesh, table is full")
                return {}, false
            }

            mesh_list[index] = handle

        case rscn.Spline:
            base.log_debug("Loading Spline: %s", v.name)

            index := spline_counter
            spline_counter += 1

            spline: Spline
            spline.group = group_handle

            spline.vert_num = i32(v.vert_num)
            spline.vert_offs = group.spline_vert_num + i32(v.vert_start)

            verts := spline_vert_buf[v.vert_start:][:v.vert_num]

            if v.vert_num > (len(group.spline_vert_buf) - int(group.spline_vert_num)) {
                base.log_err("Failed to create spline, spline vertex buffer can't fit the data")
                continue
            }

            // NOTE: consider vert radius?
            spline.bounds_min = max(f32)
            spline.bounds_max = min(f32)
            for vert, i in verts {
                spline.bounds_min = linalg.min(spline.bounds_min, vert.pos)
                spline.bounds_max = linalg.max(spline.bounds_max, vert.pos)

                group.spline_vert_buf[group.spline_vert_num + i32(i)] = vert
            }

            handle, handle_ok := insert_spline_by_name(v.name, spline)
            if !handle_ok {
                base.log_err("Failed to insert spline, table is full")
                return {}, false
            }

            group.spline_vert_num += i32(len(verts))

            spline_list[index] = handle

        case rscn.Object:
            base.log_debug("Loading Object: %s", v.name)

            index := object_counter
            object_counter += 1

            object: Object
            object.group = group_handle

            object.kind = v.kind
            object.parent.index = v.parent == -1 ? HANDLE_INDEX_INVALID : Handle_Index(v.parent) // TEMP

            switch v.kind {
            case .Empty:
                object.data_handle = {}

            case .Mesh:
                object.data_handle.index = v.mesh_index == -1 ? HANDLE_INDEX_INVALID : Handle_Index(v.mesh_index) // TEMP

            case .Spline:
                object.data_handle.index = v.spline_index == -1 ? HANDLE_INDEX_INVALID : Handle_Index(v.spline_index) // TEMP
            }

            handle, handle_ok := insert_object_by_name(v.name, object)
            if !handle_ok {
                base.log_err("Failed to insert object, table is full")
                return {}, false
            }

            object_list[index] = handle
        }
    }

    // Resolve indices -> handles

    // NOTE: the 2nd pass might be unnecessary if the data is ordered the right way? enforce it in rscn?
    for handle in object_list {
        obj := get_internal_object(handle) or_continue

        if obj.parent.index == HANDLE_INDEX_INVALID {
            continue
        }

        obj.parent = object_list[obj.parent.index]

        if parent, parent_ok := get_internal_object(obj.parent); parent_ok {
            parent.child_num += 1
        }

        switch obj.kind {
        case .Empty:

        case .Mesh:
            obj.data_handle = Handle(mesh_list[obj.data_handle.index])

        case .Spline:
            obj.data_handle = Handle(spline_list[obj.data_handle.index])
        }
    }


    // Reserve child array space
    child_offset := group.object_child_num
    for handle in object_list {
        obj := get_internal_object(handle) or_continue

        obj.child_offset = child_offset

        if child_offset + obj.child_num > i32(len(group.object_child_buf)) {
            base.log_err("Group child buffer is too small to contain all children")
            obj.child_num = 0
            continue
        }

        child_offset += obj.child_num
    }

    group.object_child_num = child_offset

    // Fill child array
    for handle in object_list {
        obj := get_internal_object(handle) or_continue

        parent := get_internal_object(obj.parent) or_continue

        group.object_child_buf[parent.child_offset] = handle
        parent.child_offset += 1
    }

    // Reset child offsets (this is a bit weird, be careful)
    for handle in object_list {
        obj := get_internal_object(handle) or_continue
        obj.child_offset -= obj.child_num
    }

    return group_handle, true
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Input
//

MAX_GAMEPADS :: platform.MAX_GAMEPADS

Key :: platform.Key
Mouse_Button :: platform.Mouse_Button
Gamepad_Button :: platform.Gamepad_Button
Gamepad_Axis :: platform.Gamepad_Axis

Input :: struct {
    mouse_delta:        [2]f32,
    mouse_pos:          [2]f32,
    scroll_delta:       [2]f32,

    keys:               Input_Digital_Buffer(Key),
    mouse_buttons:      Input_Digital_Buffer(Mouse_Button),

    gamepads:           [MAX_GAMEPADS]Input_Gamepad,
    gamepads_connected: bit_set[0..<MAX_GAMEPADS],
}

Input_Gamepad :: struct {
    buttons:    Input_Digital_Buffer(Gamepad_Button),
    axes:       [Gamepad_Axis]f32,
}

Input_Digital_Buffer :: struct($E: typeid) where intrinsics.type_is_enum(E) {
    down:       bit_set[E],
    pressed:    bit_set[E],
    released:   bit_set[E],
    repeated:   bit_set[E],
    buffered:   bit_set[E],
    timer:      [E]f32,
}

_begin_input_digital_buffer_frame :: proc(buf: ^Input_Digital_Buffer($T), delta: f32) {
    buf.pressed = {}
    buf.repeated = {}
    buf.released = {}
    for &t in buf.timer {
        t += delta
    }
}

_input_digital_press :: proc(buf: ^Input_Digital_Buffer($T), elem: T) {
    if elem not_in buf.down {
        buf.pressed += {elem}
        buf.buffered += {elem}
        buf.timer[elem] = 0
    } else {
        buf.repeated += {elem}
    }
    buf.down += {elem}
}

_input_digital_release :: proc(buf: ^Input_Digital_Buffer($T), elem: T) {
    buf.down -= {elem}
    buf.released += {elem}
}

// NOTE: [0, 0] is the bottom left corner.
mouse_pos :: proc() -> [2]f32 {
    return _state.input.mouse_pos
}

// Positive Y is up.
mouse_delta :: proc() -> [2]f32 {
    return _state.input.mouse_delta
}

scroll_delta :: proc() -> [2]f32 {
    return _state.input.scroll_delta
}


key_down :: proc(key: Key) -> bool {
    return key in _state.input.keys.down
}

// Down time is 0 on pressed.
key_down_time :: proc(key: Key) -> f32 {
    return _state.input.keys.timer[key]
}

key_pressed :: proc(key: Key, buf: f32 = 0) -> bool {
    if buf > 0.0001 &&
        key in _state.input.keys.buffered &&
        _state.input.keys.timer[key] <= buf
    {
        _state.input.keys.buffered -= {key}
        return true
    }

    if key in _state.input.keys.pressed {
        return true
    }

    return false
}

key_repeated :: proc(key: Key) -> bool {
    return key in _state.input.keys.repeated
}

key_released :: proc(key: Key) -> bool {
    return key in _state.input.keys.released
}


mouse_down :: proc(button: Mouse_Button) -> bool {
    return button in _state.input.mouse_buttons.down
}

// Down time is 0 on pressed.
mouse_down_time :: proc(button: Mouse_Button) -> f32 {
    return _state.input.mouse_buttons.timer[button]
}

mouse_pressed :: proc(button: Mouse_Button, buf: f32 = 0) -> bool {
    if buf > 0.0001 &&
        button in _state.input.mouse_buttons.buffered &&
        _state.input.mouse_buttons.timer[button] <= buf
    {
        _state.input.mouse_buttons.buffered -= {button}
        return true
    }

    if button in _state.input.mouse_buttons.pressed {
        return true
    }

    return false
}

mouse_repeated :: proc(button: Mouse_Button) -> bool {
    return button in _state.input.mouse_buttons.repeated
}

mouse_released :: proc(button: Mouse_Button) -> bool {
    return button in _state.input.mouse_buttons.released
}




/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Lookups
//

get_children :: proc(handle: Object_Handle, loc := #caller_location) -> ([]Object_Handle, bool) #optional_ok {
    obj, obj_ok := get_internal_object(handle)
    if !obj_ok {
        base.log_err("Failed to get object's children: invalid handle", loc = loc)
        return nil, false
    }

    group, group_ok := get_internal_group(obj.group)
    if !group_ok {
        base.log_err("Failed to get object's children: object's group handle is invalid")
        return nil, false
    }

    return group.object_child_buf[obj.child_offset:][:obj.child_num], true
}

get_child_by_name :: proc(handle: Object_Handle, name: string) -> (result: Object_Handle, ok: bool) #optional_ok {
    children := get_children(handle) or_return

    hash := hash_name(name)

    for ch in children {
        if _state.objects_hash[ch.index] != hash {
            continue
        }

        if _state.objects_gen[ch.index] != ch.gen {
            continue
        }

        return ch, true
    }

    return {}, false
}


@(require_results)
get_mesh :: proc($Name: string) -> (result: Mesh_Handle, ok: bool) #optional_ok {
    return get_mesh_by_hash(hash_const_name(Name))
}

@(require_results)
get_mesh_by_name :: proc(name: string) -> (result: Mesh_Handle, ok: bool) #optional_ok {
    return get_mesh_by_hash(hash_name(name))
}

@(require_results)
get_mesh_by_hash :: proc(hash: Hash) -> (result: Mesh_Handle, ok: bool) #optional_ok {
    index := _table_lookup_hash(&_state.meshes_hash, hash) or_return
    return {
        index = Handle_Index(index),
        gen = _state.meshes_gen[index],
    }, true
}


@(require_results)
get_object :: proc($Name: string) -> (result: Object_Handle, ok: bool) #optional_ok {
    return get_object_by_hash(hash_const_name(Name))
}

@(require_results)
get_object_by_name :: proc(name: string) -> (result: Object_Handle, ok: bool) #optional_ok {
    return get_object_by_hash(hash_name(name))
}

@(require_results)
get_object_by_hash :: proc(hash: Hash) -> (result: Object_Handle, ok: bool) #optional_ok {
    index := _table_lookup_hash(&_state.objects_hash, hash) or_return
    return {
        index = Handle_Index(index),
        gen = _state.objects_gen[index],
    }, true
}



@(require_results)
get_texture :: proc($Name: string) -> (result: Texture_Handle, ok: bool) #optional_ok {
    return get_texture_by_hash(hash_const_name(Name))
}

@(require_results)
get_texture_by_name :: proc(name: string) -> (result: Texture_Handle, ok: bool) #optional_ok {
    return get_texture_by_hash(hash_name(name))
}

@(require_results)
get_texture_by_hash :: proc(hash: Hash) -> (result: Texture_Handle, ok: bool) #optional_ok {
    index := _table_lookup_hash(&_state.textures_hash, hash) or_return
    return {
        index = Handle_Index(index),
        gen = _state.textures_gen[index],
    }, true
}



@(require_results)
get_spline :: proc($Name: string) -> (result: Spline_Handle, ok: bool) #optional_ok {
    return get_spline_by_hash(hash_const_name(Name))
}

@(require_results)
get_spline_by_name :: proc(name: string) -> (result: Spline_Handle, ok: bool) #optional_ok {
    return get_spline_by_hash(hash_name(name))
}

@(require_results)
get_spline_by_hash :: proc(hash: Hash) -> (result: Spline_Handle, ok: bool) #optional_ok {
    index := _table_lookup_hash(&_state.splines_hash, hash) or_return
    return {
        index = Handle_Index(index),
        gen = _state.splines_gen[index],
    }, true
}



@(require_results)
get_vertex_shader :: proc($Name: string) -> (result: Vertex_Shader_Handle, ok: bool) #optional_ok {
    return get_vertex_shader_by_hash(hash_const_name(Name))
}

@(require_results)
get_vertex_shader_by_name :: proc(name: string) -> (result: Vertex_Shader_Handle, ok: bool) #optional_ok {
    return get_vertex_shader_by_hash(hash_name(name))
}

@(require_results)
get_vertex_shader_by_hash :: proc(hash: Hash) -> (result: Vertex_Shader_Handle, ok: bool) #optional_ok {
    index := _table_lookup_hash(&_state.vertex_shaders_hash, hash) or_return
    return {
        index = Handle_Index(index),
        gen = _state.vertex_shaders_gen[index],
    }, true
}


@(require_results)
get_pixel_shader :: proc($Name: string) -> (result: Pixel_Shader_Handle, ok: bool) #optional_ok {
    return get_pixel_shader_by_hash(hash_const_name(Name))
}

@(require_results)
get_pixel_shader_by_name :: proc(name: string) -> (result: Pixel_Shader_Handle, ok: bool) #optional_ok {
    return get_pixel_shader_by_hash(hash_name(name))
}

@(require_results)
get_pixel_shader_by_hash :: proc(hash: Hash) -> (result: Pixel_Shader_Handle, ok: bool) #optional_ok {
    index := _table_lookup_hash(&_state.pixel_shaders_hash, hash) or_return
    return {
        index = Handle_Index(index),
        gen = _state.pixel_shaders_gen[index],
    }, true
}




@(require_results)
get_internal_draw_layer :: proc(#any_int index: i32) -> (result: ^Draw_Layer, ok: bool) {
    if index < 0 || index >= MAX_DRAW_LAYERS {
        return nil, false
    }
    return &_state.draw_layers[index], true
}

@(require_results)
get_internal_mesh :: proc(handle: Mesh_Handle) -> (result: ^Mesh, ok: bool) {
    return _table_get(&_state.meshes, _state.meshes_gen, handle)
}

@(require_results)
get_internal_object :: proc(handle: Object_Handle) -> (result: ^Object, ok: bool) {
    return _table_get(&_state.objects, _state.objects_gen, handle)
}

@(require_results)
get_internal_spline :: proc(handle: Spline_Handle) -> (result: ^Spline, ok: bool) {
    return _table_get(&_state.splines, _state.splines_gen, handle)
}

@(require_results)
get_internal_vertex_shader :: proc(handle: Vertex_Shader_Handle) -> (result: ^Vertex_Shader, ok: bool) {
    return _table_get(&_state.vertex_shaders, _state.vertex_shaders_gen, handle)
}

@(require_results)
get_internal_pixel_shader :: proc(handle: Pixel_Shader_Handle) -> (result: ^Pixel_Shader, ok: bool) {
    return _table_get(&_state.pixel_shaders, _state.pixel_shaders_gen, handle)
}




@(require_results)
insert_mesh_by_name :: proc(name: string, mesh: Mesh) -> (result: Mesh_Handle, ok: bool) {
    return insert_mesh_by_hash(hash_name(name), mesh)
}

@(require_results)
insert_object_by_name :: proc(name: string, object: Object) -> (result: Object_Handle, ok: bool) {
    return insert_object_by_hash(hash_name(name), object)
}

@(require_results)
insert_spline_by_name :: proc(name: string, spline: Spline) -> (result: Spline_Handle, ok: bool) {
    return insert_spline_by_hash(hash_name(name), spline)
}

@(require_results)
insert_vertex_shader_by_name :: proc(name: string, shader: Vertex_Shader) -> (result: Vertex_Shader_Handle, ok: bool) {
    return insert_vertex_shader_by_hash(hash_name(name), shader)
}

@(require_results)
insert_pixel_shader_by_name :: proc(name: string, shader: Pixel_Shader) -> (result: Pixel_Shader_Handle, ok: bool) {
    return insert_pixel_shader_by_hash(hash_name(name), shader)
}


@(require_results)
insert_mesh_by_hash :: proc(hash: Hash, mesh: Mesh) -> (result: Mesh_Handle, ok: bool) {
    index, _ := _table_insert_hash(&_state.meshes_hash, hash) or_return

    _state.meshes[index] = mesh

    result = {
        index = Handle_Index(index),
        gen = _state.meshes_gen[index],
    }

    return result, true
}

@(require_results)
insert_object_by_hash :: proc(hash: Hash, object: Object) -> (result: Object_Handle, ok: bool) {
    index, _ := _table_insert_hash(&_state.objects_hash, hash) or_return

    _state.objects[index] = object

    result = {
        index = Handle_Index(index),
        gen = _state.objects_gen[index],
    }

    return result, true
}

@(require_results)
insert_spline_by_hash :: proc(hash: Hash, spline: Spline) -> (result: Spline_Handle, ok: bool) {
    index, _ := _table_insert_hash(&_state.splines_hash, hash) or_return

    _state.splines[index] = spline

    result = {
        index = Handle_Index(index),
        gen = _state.splines_gen[index],
    }

    return result, true
}

@(require_results)
insert_vertex_shader_by_hash :: proc(hash: Hash, shader: Vertex_Shader) -> (result: Vertex_Shader_Handle, ok: bool) {
    index, _ := _table_insert_hash(&_state.vertex_shaders_hash, hash) or_return

    _state.vertex_shaders[index] = shader

    result = {
        index = Handle_Index(index),
        gen = _state.vertex_shaders_gen[index],
    }

    return result, true
}


@(require_results)
insert_pixel_shader_by_hash :: proc(hash: Hash, shader: Pixel_Shader) -> (result: Pixel_Shader_Handle, ok: bool) {
    index, _ := _table_insert_hash(&_state.pixel_shaders_hash, hash) or_return

    _state.pixel_shaders[index] = shader

    result = {
        index = Handle_Index(index),
        gen = _state.pixel_shaders_gen[index],
    }

    return result, true
}



@(require_results)
_table_insert_hash :: proc(table: ^[$N]Hash, hash: u64) -> (result: int, prev: Hash, ok: bool) {
    start_index := int(hash) %% N

    for offs in 0..<MAX_PROBE_DIST {
        index := (start_index + offs) %% N
        if index == 0 {
            continue
        }

        h := table[index]

        if h == 0 || h == hash {
            table[index] = hash
            return index, h, true
        }
    }

    return 0, 0, false
}

@(require_results)
_table_lookup_hash :: proc(table: ^[$N]Hash, hash: u64) -> (int, bool) {
    start_index := int(hash) %% N

    for offs in 0..<MAX_PROBE_DIST {
        index := (start_index + offs) %% N
        if table[index] == hash {
            return index, true
        }
    }

    return {}, false
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
    for vert in vertices {
        mesh.bounds_min = linalg.min(mesh.bounds_min, vert.pos)
        mesh.bounds_max = linalg.max(mesh.bounds_max, vert.pos)
    }

    handle, handle_ok := insert_mesh_by_name(name, mesh)
    if !handle_ok {
        base.log_err("Failed to create mesh '%s', table is full", name)
        return {}, false
    }

    gpu.update_buffer(group.vbuf, gpu.slice_bytes(vertices), offset = int(mesh.vert_offs) * size_of(Vertex))
    gpu.update_buffer(group.ibuf, gpu.slice_bytes(indices), offset = int(mesh.index_offs) * size_of(Vertex_Index))

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
// MARK: VFS
// Virtual file system
//

get_file_data :: proc(name: string, flush := false) -> (data: []byte, ok: bool) {
    return get_file_data_by_hash(hash_name(name), flush = flush)
}

get_file_data_by_hash :: proc(hash: Hash, flush := false) -> (data: []byte, ok: bool) {
    index :=_table_lookup_hash(&_state.files_hash, hash) or_return

    file := &_state.files[index]

    if flush {
        if .Dirty in file.flags {
            file.flags -= {.Dirty}
            return file.data, true
        } else {
            return {}, false
        }
    }

    return file.data, true
}

load_asset :: proc(name: string, dst_group: Group_Handle) -> bool {
    if string_has_suffix(name, ".png") {
        data, data_ok := get_file_data(name)
        if !data_ok {
            base.log_err("Failed to load texture '%s', file not found", name)
            return false
        }
        _, ok := create_texture_from_encoded_data(name[:len(name) - 4], data)
        return ok
    } else if string_has_suffix(name, ".rscn") {
        _, ok := load_scene(name, dst_group = dst_group)
        return ok
    }
    // TODO
    // else if string_has_suffix(name, ".wav") {
    // } else if string_has_suffix(name, ".hlsl") {
    // }

    return true
}

register_file :: proc(path: string) -> bool {
    npath := normalize_path(path, context.temp_allocator)
    base.log_info("VFS registering file '%s'", npath)
    data, ok := platform.read_file_by_path(npath, _state.allocator)
    if !ok {
        base.log_err("VFS failed to register '%s', couldn't read file data", npath)
        return false
    }
    return register_file_data_by_hash(hash_name(npath), data, flags = {.Dynamically_Allocated})
}

register_file_data :: proc(path: string, data: []byte, flags: bit_set[File_Flag] = {}) -> bool {
    npath := normalize_path(path, context.temp_allocator)
    base.log_info("VFS registering file data '%s'", npath)
    return register_file_data_by_hash(hash_name(npath), data, flags = flags)
}

register_file_data_by_hash :: proc(hash: Hash, data: []byte, flags: bit_set[File_Flag]) -> bool {
    index, _, ok := _table_insert_hash(&_state.files_hash, hash)
    if !ok {
        return false
    }

    _state.files[index] = File{
        data = data,
        flags = flags + {.Dirty},
    }

    return true
}

register_const_directory :: proc(files: []runtime.Load_Directory_File) -> (ok: bool) {
    ok = true
    for file in files {
        if !register_file_data(file.name, file.data) {
            base.log_err("Failed to register file '%s' from a constant directory", file.name)
            ok = false
        }
    }
    return ok
}

// TODO: allow path patterns, just like platform dir iterator?
register_directory :: proc(path: string) {
    iter: platform.Directory_Iter

    if !platform.is_directory(path) {
        base.log_err("Cannot load data, '%s' is not a valid directory path", path)
    }

    pattern := strings_join(path, "\\*", allocator = context.temp_allocator)

    files := make([dynamic]string, 0, 64, context.temp_allocator)

    for name in platform.iter_directory(&iter, pattern, context.temp_allocator) {
        full := strings_join(path, platform.SEPARATOR, name, allocator = context.temp_allocator)

        if !platform.is_file(full) {
            continue
        }

        data, data_ok := platform.read_file_by_path(
            full,
            allocator = _state.allocator,
        )

        if !data_ok {
            base.log_err("VFS failed to register file '%s' from directory '%s', couldn't read file data", name, path)
            continue
        }

        register_file_data(name, data, flags = {.Dynamically_Allocated})

        append(&files, name)
    }
}

watch_asset_directory :: proc(path: string) -> bool {
    if _state.watched_dirs_num > MAX_WATCHED_DIRS {
        base.log_err("Failed to watch asset directory, too many watched directories")
        return false
    }

    index := _state.watched_dirs_num
    dir := &_state.watched_dirs[index]

    if !platform.init_file_watcher(&dir.watcher, path, recursive = false) {
        intrinsics.mem_zero(dir, size_of(Watched_Dir))
        return false
    }

    dir.path_len = i32(copy(dir.path[:], path))

    _state.watched_dirs_num += 1

    return true
}

get_internal_file_by_hash :: proc(hash: Hash) -> (file: ^File, ok: bool) {
    index := _table_lookup_hash(&_state.files_hash, hash) or_return
    return &_state.files[index], true
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
// MARK: Bind
//

@(deferred_none = pop_binds)
scope_binds :: proc() -> bool {
    push_binds()
    return true
}

push_binds :: proc() {
    if _state.bind_states_len >= MAX_BIND_STATE_DEPTH {
        base.log_err("Cannot set bind state, reached max depth")
        return
    }

    _state.bind_states[_state.bind_states_len] = _state.bind_state
    _state.bind_states_len += 1
}

pop_binds :: proc() {
    assert(_state.bind_states_len > 0)
    _state.bind_states_len -= 1
    _state.bind_state = _state.bind_states[_state.bind_states_len]
}

@(require_results)
get_binds :: proc() -> Bind_State {
    return _state.bind_state
}

// NOTE: be very careful when changing fields in Bind_State.
// This proc should be used mostly to revert state returned by 'get_binds'
set_binds :: proc(binds: Bind_State) {
    _state.bind_state = binds
}

bind_layer :: proc(#any_int layer: i32) {
    assert(layer >= 0 && layer <= MAX_DRAW_LAYERS)
    _state.bind_state.draw_layer = u8(layer)
}

bind_blend :: proc(blend: Blend_Mode) {
    _state.bind_state.blend = blend
}

bind_fill :: proc(fill: Fill_Mode) {
    _state.bind_state.fill = fill
}

bind_depth_write :: proc(write: bool) {
    _state.bind_state.depth_write = write
}

bind_depth_test :: proc(test: bool) {
    _state.bind_state.depth_test = test
}

bind_pixel_shader :: proc {
    bind_pixel_shader_by_name,
    bind_pixel_shader_by_handle,
}

bind_vertex_shader :: proc {
    bind_vertex_shader_by_name,
    bind_vertex_shader_by_handle,
}

bind_texture :: proc {
    bind_texture_by_const,
    bind_texture_by_name,
    bind_texture_by_handle,
    bind_render_texture_by_handle,
}


bind_pixel_shader_by_name :: proc(name: string) -> bool {
    bind_pixel_shader_by_handle(get_pixel_shader_by_name(name))
    return true
}

bind_vertex_shader_by_name :: proc(name: string) -> bool {
    bind_vertex_shader_by_handle(get_vertex_shader_by_name(name))
    return true
}

bind_texture_by_const :: proc($Name: string) -> bool {
    bind_texture_by_handle(get_texture_by_hash(hash_const_name(Name)))
    return true
}

bind_texture_by_name :: proc(name: string) -> bool {
    bind_texture_by_handle(get_texture_by_name(name))
    return true
}


bind_pixel_shader_by_handle :: proc(handle: Pixel_Shader_Handle) {
    if _, ok := get_internal_pixel_shader(handle); ok {
        _state.bind_state.pixel_shader = u8(handle.index)
    } else {
        _state.bind_state.pixel_shader = u8(_state.builtin_pixel_shader[.Default].index)
    }
}

bind_vertex_shader_by_handle :: proc(handle: Vertex_Shader_Handle) {
    if _, ok := get_internal_vertex_shader(handle); ok {
        _state.bind_state.vertex_shader = u8(handle.index)
    } else {
        _state.bind_state.vertex_shader = u8(_state.builtin_vertex_shader[.Default].index)
    }
}

bind_texture_by_handle :: proc(handle: Texture_Handle) {
    if !_bind_texture(handle) {
        _bind_texture(_state.builtin_texture[.Error])
    }
}

_bind_texture :: proc(handle: Texture_Handle) -> bool {
    tex := get_internal_texture(handle) or_return
    if tex.resource != {} {
        // Standalone tex
        _state.bind_state.texture_mode = .Non_Pooled
        _state.bind_state.texture = u8(handle.index)
        _state.bind_state.texture_slice = 0
        _state.bind_state.texture_size = tex.size
    } else {
        // Pool slice index
        pool := _state.texture_pools[tex.pool_index]
        assert(int(tex.slice) < int(pool.slices))
        assert(int(tex.slice) in pool.slices_used)

        _state.bind_state.texture_mode = .Pooled
        _state.bind_state.texture = u8(tex.pool_index)
        _state.bind_state.texture_slice = u8(tex.slice)
        _state.bind_state.texture_size = {
            u16(pool.size.x),
            u16(pool.size.y),
        }
    }
    return true
}

// Bind render texture for READING like a regular texture.
// In order to WRITE to a render texture, use layers.
bind_render_texture_by_handle :: proc(handle: Render_Texture_Handle) {
    assert(handle != DEFAULT_RENDER_TEXTURE)
    tex, tex_ok := get_internal_render_texture(handle)
    if !tex_ok {
        _bind_texture(_state.builtin_texture[.Error])
        return
    }
    assert(tex.color != {})

    _state.bind_state.texture_mode = .Render_Texture
    _state.bind_state.texture = u8(handle.index)
    _state.bind_state.texture_slice = 0
    _state.bind_state.texture_size = {
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

draw_sprite :: proc(
    pos:        Vec3,
    rect:       Rect = {0, 1},
    scale:      Vec2 = 1,
    col:        Vec4 = 1,
    rot:        Quat = 1,
    anchor:     Vec2 = 0,
    angle:      f32 = 0,
    add_col:    Vec4 = 0,
    scaling:    Sprite_Scaling = .Pixel,
    param:      u32 = 0,
) {
    validate_vec3(pos)
    validate_vec2(scale)
    validate_quat(rot)

    if col.a < 0.01 || abs(scale.x * scale.y) < 0.0001 {
        return
    }

    mat := linalg.matrix3_from_quaternion_f32(rot *
        linalg.quaternion_angle_axis_f32(angle, {0, 0, 1}))

    rect_size := rect_full_size(rect)

    size := Vec2{
        scale.x * 0.5,
        scale.y * 0.5,
    }

    layer := get_internal_draw_layer(_state.bind_state.draw_layer) or_else panic("Invalid layer")

    if .Flip_Y in layer.flags {
        size.y *= -1
    }

    switch scaling {
    case .Pixel:
        size *= {
            f32(_state.bind_state.texture_size.x) * rect_size.x,
            f32(_state.bind_state.texture_size.y) * rect_size.y,
        }

    case .Absolute:
        // No scaling
    }

    center := pos
    center += mat[0] * anchor.x * size.x
    center += mat[1] * anchor.y * size.y

    rect_size_sign := Vec2{
        math.sign_f32(rect_size.x),
        math.sign_f32(rect_size.y),
    }

    inst := pack_sprite_inst(
        pos = center,
        mat_x = mat[0] * size.x,
        mat_y = mat[1] * size.y,
        uv_min = rect.min + rect_size_sign * UV_EPS,
        uv_size = rect_size - rect_size_sign * UV_EPS * 2,
        col = col,
        add_col = add_col,
        tex_slice = _state.bind_state.texture_slice,
        param = param,
    )

    draw_sprite_inst(inst)
}

draw_sprite_inst :: proc(inst: Sprite_Inst) {
    draw: Sprite_Draw

    draw.inst = inst

    draw.key = Draw_Sort_Key{
        texture         = _state.bind_state.texture,
        texture_mode    = _state.bind_state.texture_mode,
        ps              = _state.bind_state.pixel_shader,
        vs              = u8(_state.builtin_vertex_shader[.Default_Sprite].index), // for now the VS is fixed
        blend           = _state.bind_state.blend,
        fill            = _state.bind_state.fill,
        depth_test      = _state.bind_state.depth_test,
        depth_write     = _state.bind_state.depth_write,
    }

    _push_sprite_draw(_state.bind_state.draw_layer, draw)
}

draw_rect :: proc(
    rect:       Rect,
    tex_rect:   Rect = {0, 1},
    z:          f32 = 0.0,
    col:        Vec4 = 1,
    add_col:    Vec4 = 0,
    param:      u32 = 0,
) {
    validate_rect(rect)
    validate_rect(tex_rect)
    validate_f32(z)

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
        tex_slice = _state.bind_state.texture_slice,
        param = param,
    )

    draw_sprite_inst(inst)
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
    char_size := IVec2{
        i32(_state.bind_state.texture_size.x) / 16,
        i32(_state.bind_state.texture_size.y) / 16,
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

    draw_layer := &_state.draw_layers[_state.bind_state.draw_layer]
    start_offs := len(draw_layer.sprites)

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

    return draw_layer.sprites.inst[:len(draw_layer.sprites)][start_offs:]
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
    validate_vec3(pos)
    validate_vec3(scale)
    validate_quat(rot)

    mesh, mesh_ok := get_internal_mesh(handle)
    if !mesh_ok {
        // TODO: draw "error mesh" instead
        base.log_err("Trying to draw a mesh with invalid handle")
        return
    }

    draw: Mesh_Draw

    mat := linalg.matrix3_from_quaternion_f32(rot)

    draw.key = {
        asset_index     = u16(handle.index),
        group           = u8(mesh.group.index),
        texture         = _state.bind_state.texture,
        texture_mode    = _state.bind_state.texture_mode,
        ps              = _state.bind_state.pixel_shader,
        vs              = _state.bind_state.vertex_shader,
        fill            = _state.bind_state.fill,
        blend           = _state.bind_state.blend,
        depth_test      = _state.bind_state.depth_test,
        depth_write     = _state.bind_state.depth_write,
    }

    if linalg.matrix3x3_determinant(mat) < 0 {
        switch draw.key.fill {
        case .All, .Wire: // no op
        case .Front: draw.key.fill = .Back
        case .Back: draw.key.fill = .Front
        }
    }

    draw.inst = pack_mesh_inst(
        pos = pos,
        mat_x = mat[0] * scale.x,
        mat_y = mat[1] * scale.y,
        mat_z = mat[2] * scale.z,
        tex_slice = _state.bind_state.texture_slice,
        vert_offs = u32(mesh.vert_offs),
        param = param,
        col = col,
        add_col = add_col,
    )

    _push_mesh_draw(_state.bind_state.draw_layer, draw)
}

draw_sprite_line :: proc(
    a:          Vec3,
    b:          Vec3,
    width:      f32,
    rect:       Rect = {0, 1},
    col:        Vec4 = 1,
    param:      u32 = 0,
) {
    draw_layer := &_state.draw_layers[_state.bind_state.draw_layer]

    mid := (a + b) * 0.5
    dir := linalg.normalize(b - a)
    // TODO: 2d and 3d might need a little different code path?
    // forw := linalg.normalize0(mid - draw_layer.camera.pos)
    forw := linalg.quaternion128_mul_vector3(draw_layer.camera.rot, Vec3{0, 0, 1})
    right := linalg.normalize0(linalg.cross(dir, forw))
    dist := linalg.distance(a, b)

    draw: Sprite_Draw

    // TODO: flip texture *data* instead of flipping sprites?

    draw.inst = pack_sprite_inst(
        pos = mid,
        mat_x = right * width,
        mat_y = dir * dist * 0.5,
        uv_min = rect.min.x + UV_EPS,
        uv_size = rect_full_size(rect) - UV_EPS * 2,
        col = col,
        add_col = 0,
        tex_slice = _state.bind_state.texture_slice,
        param = param,
    )

    draw.key = Draw_Sort_Key{
        texture         = _state.bind_state.texture,
        texture_mode    = _state.bind_state.texture_mode,
        ps              = _state.bind_state.pixel_shader,
        vs              = u8(_state.builtin_vertex_shader[.Default_Sprite].index), // for now the VS is fixed
        blend           = _state.bind_state.blend,
        fill            = _state.bind_state.fill,
        depth_test      = _state.bind_state.depth_test,
        depth_write     = _state.bind_state.depth_write,
    }

    _push_sprite_draw(_state.bind_state.draw_layer, draw)
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
    validate_vec3(pos)
    validate_quat(rot)
    validate_vec4(col)
    validate_vec4(add_col)
    validate(len(verts) % 3 == 0)

    if len(verts) == 0 {
        return
    }

    draw: Triangle_Draw

    draw_layer := &_state.draw_layers[_state.bind_state.draw_layer]
    offset := len(draw_layer.dynamic_verts)
    num := _push_draw_dynamic_verts(_state.bind_state.draw_layer, verts)

    draw.key = {
        group           = 0,
        texture         = _state.bind_state.texture,
        texture_mode    = _state.bind_state.texture_mode,
        ps              = _state.bind_state.pixel_shader,
        vs              = _state.bind_state.vertex_shader,
        fill            = _state.bind_state.fill,
        blend           = _state.bind_state.blend,
        depth_test      = _state.bind_state.depth_test,
        depth_write     = _state.bind_state.depth_write,
        asset_index     = int_cast(u16, num),
    }

    mat := linalg.matrix3_from_quaternion_f32(rot)

    draw.inst = pack_mesh_inst(
        pos = pos,
        mat_x = mat[0] * scale.x,
        mat_y = mat[1] * scale.y,
        mat_z = mat[2] * scale.z,
        tex_slice = _state.bind_state.texture_slice,
        vert_offs = u32(offset),
        param = param,
        col = col,
        add_col = add_col,
    )

    _push_triangle_draw(_state.bind_state.draw_layer, draw)
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
    validate(len(verts) % 2 == 0)
    validate_vec3(pos)
    validate_quat(rot)
    validate_vec4(col)
    validate_vec4(add_col)

    if len(verts) == 0 {
        return
    }

    draw: Line_Draw

    draw_layer := &_state.draw_layers[_state.bind_state.draw_layer]
    offset := len(draw_layer.dynamic_verts)
    num := _push_draw_dynamic_verts(_state.bind_state.draw_layer, verts)

    draw.key = {
        group           = 0,
        texture         = _state.bind_state.texture,
        texture_mode    = _state.bind_state.texture_mode,
        ps              = _state.bind_state.pixel_shader,
        vs              = _state.bind_state.vertex_shader,
        fill            = _state.bind_state.fill,
        blend           = _state.bind_state.blend,
        depth_test      = _state.bind_state.depth_test,
        depth_write     = _state.bind_state.depth_write,
        asset_index     = int_cast(u16, num),
    }

    mat := linalg.matrix3_from_quaternion_f32(rot)

    draw.inst = pack_mesh_inst(
        pos = pos,
        mat_x = mat[0] * scale.x,
        mat_y = mat[1] * scale.y,
        mat_z = mat[2] * scale.z,
        tex_slice = _state.bind_state.texture_slice,
        vert_offs = u32(offset),
        param = param,
        col = col,
        add_col = add_col,
    )

    _push_line_draw(_state.bind_state.draw_layer, draw)
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
    pos:        [2]Vec3,
    col:        [2]Vec4 = WHITE,
    uvs:        [2]Vec2 = {{0, 0.5}, {1, 0.5}},
    add_col:    Vec4 = BLACK,
    normals:    Maybe([2]Vec3) = nil,
) {
    validate_vec3(pos[0])
    validate_vec3(pos[1])

    norm, norm_ok := normals.?
    if !norm_ok {
        norm = Vec3{0, 1, 0}
    }

    verts: [2]Vertex
    for &v, i in verts {
        v = pack_vertex(
            pos = pos[i],
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

_push_sprite_draw :: proc(#any_int layer_index: int, draw: Sprite_Draw) {
    draw_layer := &_state.draw_layers[layer_index]
    _init_draw_array(&draw_layer.sprites, draw_layer.last_sprites_len)
    non_zero_append_soa_elem(&draw_layer.sprites, draw)
}

_push_mesh_draw :: proc(#any_int layer_index: int, draw: Mesh_Draw) {
    draw_layer := &_state.draw_layers[layer_index]
    _init_draw_array(&draw_layer.meshes, draw_layer.last_meshes_len)
    non_zero_append_soa_elem(&draw_layer.meshes, draw)
}

_push_triangle_draw :: proc(#any_int layer_index: int, draw: Triangle_Draw) {
    draw_layer := &_state.draw_layers[layer_index]
    _init_draw_array(&draw_layer.triangles, draw_layer.last_triangles_len)
    non_zero_append_soa_elem(&draw_layer.triangles, draw)
}

_push_line_draw :: proc(#any_int layer_index: int, draw: Line_Draw) {
    draw_layer := &_state.draw_layers[layer_index]
    _init_draw_array(&draw_layer.lines, draw_layer.last_lines_len)
    non_zero_append_soa_elem(&draw_layer.lines, draw)
}

_push_draw_dynamic_verts :: proc(#any_int layer_index: int, verts: []Vertex) -> int {
    draw_layer := &_state.draw_layers[layer_index]
    if len(draw_layer.dynamic_verts) == 0 {
        draw_layer.dynamic_verts = make_dynamic_array_len_cap(
            [dynamic]Vertex,
            0,
            256 + draw_layer.last_dynamic_verts_len,
            context.temp_allocator,
        )
    }
    assert(draw_layer.dynamic_verts.allocator == context.temp_allocator)
    return non_zero_append_elems(&draw_layer.dynamic_verts, ..verts) or_else 0
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
// MARK: GPU Data Upload
//

_upload_gpu_global_constants :: proc() {
    gpu.update_constants(_state.global_consts, gpu.ptr_bytes(&Draw_Global_Constants{
        time = get_time(),
        delta_time = get_delta_time(),
        frame = u32(get_frame_index()),
        resolution = _state.screen_size,
        rand_seed = 0,
        param = 0,
    }))
}

_draw_layer_no_instances :: proc(layer: Draw_Layer) -> bool {
    return \
        len(layer.sprites) == 0 &&
        len(layer.meshes) == 0 &&
        len(layer.triangles) == 0 &&
        len(layer.lines) == 0
}

_upload_gpu_layer_constants :: proc() {
    consts_buf: [MAX_DRAW_LAYERS]Draw_Layer_Constants

    for &layer, i in _state.draw_layers {
        if _draw_layer_no_instances(layer) {
            continue
        }

        const_data: Draw_Layer_Constants = {
            view_proj = calc_camera_world_to_clip_matrix(layer.camera),
            cam_pos = layer.camera.pos,
            layer_index = i32(i),
        }

        consts_buf[i] = const_data
    }

    gpu.update_constants(_state.draw_layers_consts, gpu.ptr_bytes(&consts_buf))
}

// This takes all the draw_* command data and uploads them to GPU buffers.
// Call render_gpu_layer(...) to actually draw.
// NOTE: until the start of the next frame, all draw_* commands after this call will be ignored.
@(optimization_mode="favor_size")
upload_gpu_layers :: proc() {
    assert(!_state.uploaded_gpu_draws)
    _state.uploaded_gpu_draws = true

    _upload_gpu_global_constants()

    _upload_gpu_layer_constants()

    Batcher_State :: struct {
        consts:         [MAX_TOTAL_DRAW_BATCHES]Draw_Batch_Constants,
        consts_num:     u32,
    }

    batcher: Batcher_State

    for layer in _state.draw_layers {
        _counter_add(.Num_Total_Instances, u64(
            len(layer.sprites) +
            len(layer.meshes) +
            len(layer.triangles) +
            len(layer.lines),
        ))
    }

    // Dynamic Verts
    {
        total_dynamic_verts := 0
        for layer in _state.draw_layers {
            total_dynamic_verts += len(layer.dynamic_verts)
        }

        vert_upload_buf := alloc_slice_non_zeroed(Vertex, total_dynamic_verts, alignment = 256, allocator = context.temp_allocator)
        vert_upload_offs := 0

        for layer in _state.draw_layers {
            if len(layer.dynamic_verts) == 0 {
                continue
            }

            runtime.mem_copy_non_overlapping(
                &vert_upload_buf[vert_upload_offs],
                raw_data(layer.dynamic_verts),
                size_of(Vertex) * len(layer.dynamic_verts),
            )

            vert_upload_offs += len(layer.dynamic_verts)
        }

        gpu.update_buffer(
            _state.dynamic_vert_buf,
            gpu.slice_bytes(vert_upload_buf[:vert_upload_offs]),
        )
    }


    // Prepare sprites
    {
        total_sprite_instances := 0

        for &layer, _ in _state.draw_layers {
            if len(layer.sprites) == 0 {
                continue
            }

            if .No_Cull not_in layer.flags {
                frustum := calc_camera_frustum(layer.camera)

                far_plane := frustum.planes[FRUSTUM_FAR_PLANE_INDEX]

                sprite_dist_factor := f32(MAX_DRAW_SORT_KEY_DIST) / far_plane.w

                forw := linalg.quaternion128_mul_vector3(layer.camera.rot, Vec3{0, 0, 1})

                for sprite_index := len(layer.sprites) - 1; sprite_index >= 0; sprite_index -= 1 {
                    inst := layer.sprites.inst[sprite_index]
                    key := &layer.sprites.key[sprite_index]

                    bounds_rad :=
                        linalg.abs(inst.mat_x) +
                        linalg.abs(inst.mat_y)

                    if key.blend != .Opaque {
                        dist := linalg.dot(forw, inst.pos - layer.camera.pos)
                        key.dist = ~u16(dist * sprite_dist_factor)
                    }

                    if !is_box_in_frustum(frustum, inst.pos, bounds_rad) {
                        unordered_remove_soa(&layer.sprites, sprite_index)
                    }
                }
            }

            instances := layer.sprites.inst[:len(layer.sprites)]

            if .No_Reorder not_in layer.flags {
                keys := layer.sprites.key[:len(layer.sprites)]

                indices := slice.sort_with_indices(transmute([]Draw_Sort_Key_Backing)keys, context.temp_allocator)
                slice.sort_from_permutation_indices(instances, indices)
            }

            total_sprite_instances += len(layer.sprites)
        }

        // GPU Upload sprites

        sprite_upload_buf, sprite_upload_err := runtime.mem_alloc_non_zeroed(size_of(Sprite_Inst) * total_sprite_instances, alignment = 256, allocator = context.temp_allocator)
        sprite_upload_offs := 0

        assert(sprite_upload_err == nil)

        for &layer, _ in _state.draw_layers {
            if len(layer.sprites) == 0 {
                continue
            }

            assert(sprite_upload_offs < len(sprite_upload_buf))

            instances := layer.sprites.inst[:len(layer.sprites)]

            uploaded_bytes := copy_slice(sprite_upload_buf[sprite_upload_offs:], gpu.slice_bytes(instances))
            total_bytes := size_of(Sprite_Inst) * len(layer.sprites)

            layer.sprite_insts_base = u32(sprite_upload_offs) / size_of(Sprite_Inst)

            assert(uploaded_bytes == total_bytes)
            sprite_upload_offs += uploaded_bytes
        }

        gpu.update_buffer(_state.sprite_inst_buf, sprite_upload_buf)
    }



    // Upload mesh-like data
    {
        total_mesh_instances := 0
        total_triangle_instances := 0
        total_line_instances := 0

        // NOTE: no culling for lines and tris
        for &layer in _state.draw_layers {
            total_triangle_instances += len(layer.triangles)
            total_line_instances += len(layer.lines)
        }

        for &layer, _ in _state.draw_layers {
            if len(layer.meshes) == 0 {
                continue
            }

            if .No_Cull not_in layer.flags {
                frustum := calc_camera_frustum(layer.camera)
                far_plane := frustum.planes[FRUSTUM_FAR_PLANE_INDEX]
                mesh_dist_factor := f32(MAX_DRAW_SORT_KEY_DIST) / far_plane.w
                forw := linalg.quaternion128_mul_vector3(layer.camera.rot, Vec3{0, 0, 1})

                for mesh_index := len(layer.meshes) - 1; mesh_index >= 0; mesh_index -= 1 {
                    inst := layer.meshes.inst[mesh_index]
                    key := &layer.meshes.key[mesh_index]

                    mesh := _state.meshes[key.asset_index]

                    box_rad :=
                        (linalg.abs(inst.mat_x) * max(abs(mesh.bounds_min.x), abs(mesh.bounds_max.x))) +
                        (linalg.abs(inst.mat_y) * max(abs(mesh.bounds_min.y), abs(mesh.bounds_max.y))) +
                        (linalg.abs(inst.mat_z) * max(abs(mesh.bounds_min.z), abs(mesh.bounds_max.z)))

                    if key.blend != .Opaque {
                        dist := linalg.dot(forw, inst.pos - layer.camera.pos)
                        // NOTE: should this get inverted for opaque meshes to minimize overdraw?
                        // What about Z prepass?
                        key.dist = ~u16(dist * mesh_dist_factor) // invert
                    }

                    if !is_box_in_frustum(frustum, inst.pos, box_rad) {
                        unordered_remove_soa(&layer.meshes, mesh_index)
                    }
                }
            }

            instances := layer.meshes.inst[:len(layer.meshes)]

            if .No_Reorder not_in layer.flags {
                keys := layer.meshes.key[:len(layer.meshes)]
                indices := slice.sort_with_indices(transmute([]Draw_Sort_Key_Backing)keys, context.temp_allocator)
                slice.sort_from_permutation_indices(instances, indices)
            }

            total_mesh_instances += len(layer.meshes)
        }

        mesh_upload_buf := alloc_slice_non_zeroed(Mesh_Inst,
            total_mesh_instances + total_triangle_instances + total_line_instances,
            alignment = 256,
            allocator = context.temp_allocator,
        )
        mesh_upload_offs := 0

        for &layer, _ in _state.draw_layers {
            if len(layer.meshes) == 0 {
                continue
            }
            assert(mesh_upload_offs < len(mesh_upload_buf))

            instances := layer.meshes.inst[:len(layer.meshes)]
            uploaded_num := copy_slice(mesh_upload_buf[mesh_upload_offs:], instances)
            assert(uploaded_num == len(layer.meshes))

            layer.mesh_insts_base = u32(mesh_upload_offs)

            mesh_upload_offs += uploaded_num
        }

        for &layer, _ in _state.draw_layers {
            if len(layer.triangles) == 0 {
                continue
            }
            assert(mesh_upload_offs < len(mesh_upload_buf))

            instances := layer.triangles.inst[:len(layer.triangles)]
            uploaded_num := copy_slice(mesh_upload_buf[mesh_upload_offs:], instances)
            assert(uploaded_num == len(layer.triangles))

            layer.triangle_insts_base = u32(mesh_upload_offs)

            mesh_upload_offs += uploaded_num
        }

        for &layer, _ in _state.draw_layers {
            if len(layer.lines) == 0 {
                continue
            }
            assert(mesh_upload_offs < len(mesh_upload_buf))

            instances := layer.lines.inst[:len(layer.lines)]
            uploaded_num := copy_slice(mesh_upload_buf[mesh_upload_offs:], instances)
            assert(uploaded_num == len(layer.lines))

            layer.line_insts_base = u32(mesh_upload_offs)

            mesh_upload_offs += uploaded_num
        }


        gpu.update_buffer(
            _state.mesh_inst_buf,
            gpu.slice_bytes(mesh_upload_buf[:mesh_upload_offs]),
        )
    }

    // Batch lists

    for &layer, _ in _state.draw_layers {
        _batcher_generate_draws(&batcher,
            &layer.sprite_batches,
            layer.sprites.key[:len(layer.sprites)],
            layer.sprite_insts_base,
        )
        if len(layer.sprites) > 0 {
            assert(len(layer.sprite_batches) > 0)
        }
    }

    for &layer, _ in _state.draw_layers {
        _batcher_generate_draws(&batcher,
            &layer.mesh_batches,
            layer.meshes.key[:len(layer.meshes)],
            layer.mesh_insts_base,
        )
        if len(layer.meshes) > 0 {
            assert(len(layer.mesh_batches) > 0)
        }
    }

    for &layer, _ in _state.draw_layers {
        _batcher_generate_draws(&batcher,
            &layer.triangle_batches,
            layer.triangles.key[:len(layer.triangles)],
            layer.triangle_insts_base,
        )
        if len(layer.triangles) > 0 {
            assert(len(layer.triangle_batches) > 0)
        }
    }

    for &layer, _ in _state.draw_layers {
        _batcher_generate_draws(&batcher,
            &layer.line_batches,
            layer.lines.key[:len(layer.lines)],
            layer.line_insts_base,
        )
        if len(layer.lines) > 0 {
            assert(len(layer.line_batches) > 0)
        }
    }


    // Upload actual batch consts for all draws

    gpu.update_constants(
        _state.draw_batch_consts,
        gpu.slice_bytes(batcher.consts[:batcher.consts_num]),
    )


    for layer in _state.draw_layers {
        _counter_add(.Num_Uploaded_Instances, u64(
            len(layer.sprites) +
            len(layer.meshes) +
            len(layer.triangles),
        ))
    }

    for &layer, _ in _state.draw_layers {
        for b in layer.sprite_batches {
            validate_draw_sort_key(b.key)
        }

        for b in layer.mesh_batches {
            validate_draw_sort_key(b.key)
        }

        for b in layer.triangle_batches {
            validate_draw_sort_key(b.key)
        }

        for b in layer.line_batches {
            validate_draw_sort_key(b.key)
        }
    }


    return

    _batcher_generate_draws :: proc(
        batcher:        ^Batcher_State,
        dst_batches:    ^[dynamic]Draw_Batch,
        keys:           []Draw_Sort_Key,
        inst_offs_base: u32,
    ) {
        if len(keys) == 0 {
            return
        }

        assert(dst_batches^ == nil)
        dst_batches^ = make([dynamic]Draw_Batch, 0, 256, context.temp_allocator)

        curr_key := keys[0]

        last := len(keys)

        instance_num: u32 = 0
        instance_offs: u32 = 0

        for i := 1; i <= last; i += 1 {
            instance_num += 1

            layer_key: Draw_Sort_Key
            if i != last {
                layer_key = keys[i]

                if draw_sort_key_equal(curr_key, layer_key) {
                    continue
                }
            }

            validate_draw_sort_key(curr_key)

            batch := Draw_Batch{
                key = curr_key,
                offset = u32(batcher.consts_num),
                num = int_cast(u16, instance_num),
            }

            append_elem(dst_batches, batch)

            assert(batcher.consts_num < len(batcher.consts))
            batcher.consts[batcher.consts_num] = {
                instance_offset = inst_offs_base + instance_offs,
            }
            batcher.consts_num += 1

            instance_offs += instance_num
            instance_num = 0
            curr_key = layer_key
        }
    }
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: GPU Drawing
//

// NOTE: the instance bind data only use a few of the available sots (consts/resources/blends/etc)
// We could possibly expose a direct way for the user to control this on per-layer basis.
// Custom pipeline and pass desc input?
@(optimization_mode="favor_size")
render_gpu_layer :: proc(
    #any_int index: i32,
    ren_tex_handle: Render_Texture_Handle = DEFAULT_RENDER_TEXTURE,
    clear_color:    Maybe(Vec3),
    clear_depth:    bool,
) {
    assert(ren_tex_handle != {})
    assert(_state.uploaded_gpu_draws, "You must call upload_gpu_layers() to submit draw data to VRAM before any actual rendering")

    layer := _state.draw_layers[index]

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
    }

    for smp, i in DEFAULT_SAMPLERS {
        pip_desc.samplers[i] = smp
    }


    //
    // Sprites
    //

    pip_desc.index = {
        resource = _state.quad_ibuf,
        format = .U16,
    }

    pip_desc.resources = {
        0 = _state.sprite_inst_buf,
    }

    for batch in layer.sprite_batches {
        // log_internal("Sprite batch drawcall with %i instances", batch.num)

        _gpu_pipeline_desc_apply_draw_key(&pip_desc, batch.key)

        pipeline, pipeline_ok := gpu.create_pipeline("sprite-pip", pip_desc)
        if !pipeline_ok {
            base.log_err("Failed to create GPU pipeline")
            continue
        }

        gpu.bind_pipeline(pipeline)

        _counter_add(.Num_Draw_Calls, 1)

        gpu.draw_indexed(
            index_num = 6,
            instance_num = batch.num,
            index_offset = 0,
            const_offsets = {
                0 = max(u32),
                1 = u32(index),
                2 = batch.offset,
            },
        )
    }


    //
    // Meshes
    //

    pip_desc.index = {
        resource = {},
        format = .U16,
    }

    pip_desc.resources = {
        0 = _state.mesh_inst_buf,
        1 = {},
    }

    for batch in layer.mesh_batches {
        _gpu_pipeline_desc_apply_draw_key(&pip_desc, batch.key)

        pip_desc.index.resource = _state.groups[batch.key.group].ibuf
        pip_desc.resources[1] = _state.groups[batch.key.group].vbuf

        pipeline, pipeline_ok := gpu.create_pipeline("mesh-pip", pip_desc)
        if !pipeline_ok {
            base.log_err("Failed to create GPU pipeline")
            continue
        }

        gpu.bind_pipeline(pipeline)

        _counter_add(.Num_Draw_Calls, 1)

        mesh := _state.meshes[batch.key.asset_index]

        gpu.draw_indexed(
            index_num = mesh.index_num,
            instance_num = batch.num,
            index_offset = mesh.index_offs,
            const_offsets = {
                0 = max(u32),
                1 = u32(index),
                2 = batch.offset,
            },
        )
    }


    //
    // Triangles
    //

    pip_desc.index = {
        resource = {},
        format = .U16,
    }

    pip_desc.index = {}
    pip_desc.resources = {
        0 = _state.mesh_inst_buf,
        1 = _state.dynamic_vert_buf,
    }

    for batch in layer.triangle_batches {
        _gpu_pipeline_desc_apply_draw_key(&pip_desc, batch.key)

        pipeline, pipeline_ok := gpu.create_pipeline("tri-pip", pip_desc)
        if !pipeline_ok {
            base.log_err("Failed to create GPU pipeline")
            continue
        }

        gpu.bind_pipeline(pipeline)

        _counter_add(.Num_Draw_Calls, 1)

        gpu.draw_non_indexed(
            vertex_num = batch.key.asset_index,
            instance_num = batch.num,
            const_offsets = {
                0 = max(u32),
                1 = u32(index),
                2 = batch.offset,
            },
        )
    }


    //
    // Lines
    //

    pip_desc.topo = .Lines
    pip_desc.index = {
        resource = {},
        format = .U16,
    }

    pip_desc.index = {}
    pip_desc.resources = {
        0 = _state.mesh_inst_buf,
        1 = _state.dynamic_vert_buf,
    }

    for batch in layer.line_batches {
        _gpu_pipeline_desc_apply_draw_key(&pip_desc, batch.key)

        pipeline, pipeline_ok := gpu.create_pipeline("line-pip", pip_desc)
        if !pipeline_ok {
            base.log_err("Failed to create GPU pipeline")
            continue
        }

        gpu.bind_pipeline(pipeline)

        _counter_add(.Num_Draw_Calls, 1)

        gpu.draw_non_indexed(
            vertex_num = batch.key.asset_index,
            instance_num = batch.num,
            const_offsets = {
                0 = max(u32),
                1 = u32(index),
                2 = batch.offset,
            },
        )
    }

    return
}

_gpu_pipeline_desc_apply_draw_key :: proc(pip_desc: ^gpu.Pipeline_Desc, key: Draw_Sort_Key, loc := #caller_location) {
    validate_draw_sort_key(key)

    pip_desc.blends[0] = _gpu_blend_mode_desc(key.blend)
    pip_desc.cull, pip_desc.fill = _gpu_fill_mode(key.fill)
    pip_desc.depth_comparison = key.depth_test ? .Greater_Equal : .Always
    pip_desc.depth_write = key.depth_write
    pip_desc.ps = gpu.Shader_Handle(_state.pixel_shaders[key.ps])
    pip_desc.vs = gpu.Shader_Handle(_state.vertex_shaders[key.vs])

    tex_res: gpu.Resource_Handle
    switch key.texture_mode {
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
    planes:     [6]Vec4, // xyz normal, w offset
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

    result.bounds_min = max(f32)
    result.bounds_max = min(f32)

    for p in result.corners {
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

    if pos.x < fru.bounds_min.x - rad.x - EPS ||
       pos.y < fru.bounds_min.y - rad.y - EPS ||
       pos.z < fru.bounds_min.z - rad.z - EPS ||
       pos.x > fru.bounds_max.x + rad.x + EPS ||
       pos.y > fru.bounds_max.y + rad.y + EPS ||
       pos.z > fru.bounds_max.z + rad.z + EPS
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


// world_to_screen :: proc(pos: Vec3, cam: Camera) -> Vec3 {
//     cam_mvp := calc_camera_world_to_clip_matrix(cam)

//     p := cam_mvp * Vec4{pos.x, pos.y, pos.z, 1.0}
//     p.xyz /= p.w

//     // p.x = (p.x / f32(get_screen_size().x)) * 2.0 - 1.0
//     // p.y = 1.0 - 2.0 * (p.y / f32(get_screen_size().y))

//     unimplemented()

//     // return p
// }


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



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Sounds
//

// play sound
create_sound :: audio.create_sound
destroy_sound :: audio.destroy_sound

load_sound_resource :: proc(path: string) -> (result: Sound_Resource_Handle, ok: bool) #optional_ok {
    name := strip_path_name(path)
    // TODO: register the resource internally for hot-reload
    data, data_ok := get_file_data(path)
    if !data_ok {
        base.log_err("Failed to load sound resource '%s' from '%s', VFS file not found", name, path)
    }

    return create_sound_resource_encoded(name, data)
}

create_sound_resource_encoded :: proc(name: string, data: []byte) -> (result: Sound_Resource_Handle, ok: bool) #optional_ok {
    base.log_info("Creating sound resource '%s' with size %i bytes", name, len(data))

    res := audio.create_resource(.WAV, data) or_return

    if !insert_sound_resource_by_hash(name, res) {
        // NOTE: currently this can continue running somewhat correctly, the result is valid.
        // But the resource won't be tracked properly internally.
        base.log_err("Failed to insert named sound resource '%s'")
    }

    return res, true
}

get_sound_resource :: proc(name: string) -> (result: Sound_Resource_Handle, ok: bool) #optional_ok {
    hash := hash_name(name)
    index := _table_lookup_hash(&_state.meshes_hash, hash) or_return
    return _state.sound_resources[index], true
}

@(require_results)
insert_sound_resource_by_hash :: proc(name: string, handle: Sound_Resource_Handle) -> bool {
    hash := hash_name(name)
    index, _ := _table_insert_hash(&_state.sound_resources_hash, hash) or_return
    _state.sound_resources[index] = handle
    return true
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Misc
//

@(require_results)
alloc_slice_non_zeroed :: proc($T: typeid, init_len: int, alignment: int = 2 * align_of(rawptr), allocator := context.allocator) -> []T {
    buf := runtime.mem_alloc_non_zeroed(size_of(T) * init_len, alignment = alignment, allocator = allocator) or_else panic("Failed to allocate")
    return ([^]T)(raw_data(buf))[:len(buf) / size_of(T)]
}

@(optimization_mode="favor_size")
hash_fnv64a :: proc "contextless" (data: []byte, seed: u64) -> u64 {
    h: u64 = seed
    for b in data {
        h = (h ~ u64(b)) * 0x100000001b3
    }
    return h
}

@(disabled=!LOG_INTERNAL)
log_internal :: proc(format: string, args: ..any, loc := #caller_location) {
    when LOG_INTERNAL {
        base.log_debug(format, args = args, location = loc)
    }
}

// Clean up a VFS path
normalize_path :: proc(path: string, allocator := context.temp_allocator) -> (result: string) {
    buf := make([]byte, len(path), allocator = allocator)
    read_offs := 0
    write_offs := 0

    for _ in 0..<len(path) {
        r, r_size := runtime.string_decode_rune(path[read_offs:])

        switch r {
        case:
            for j in 0..<r_size {
                buf[write_offs] = path[read_offs + j]
                write_offs += 1
            }

        case '\\':
            buf[write_offs] = '/'
            write_offs += 1

        case 'A'..='Z':
            buf[write_offs] = 'a' + u8(r) - 'A'
            write_offs += 1
        }

        read_offs += r_size
    }

    return string(buf[:write_offs])
}

// Convert VFS path to an asset name, for example:
// foo/bar/something.bin -> something
// foo.data.txt -> foo
strip_path_name :: proc "contextless" (str: string) -> (result: string) {
    back_index := bytes.last_index_byte(transmute([]byte)str,'\\')
    forw_index := bytes.last_index_byte(transmute([]byte)str,'/')
    result = str[max(back_index, forw_index) + 1:]
    dot_index := bytes.index_byte(transmute([]byte)result, '.')
    return result[:dot_index]
}

@(deferred_out = runtime.default_temp_allocator_temp_end)
temp_allocator_guard :: proc(loc := #caller_location) -> (temp: runtime.Arena_Temp, location: runtime.Source_Code_Location) {
    return runtime.default_temp_allocator_temp_begin(loc), loc
}

@(require_results)
string_has_suffix :: proc(s, suffix: string) -> bool {
    return len(s) >= len(suffix) && s[len(s)-len(suffix):] == suffix
}

@(require_results)
enum_to_string :: proc(val: $T) -> string where intrinsics.type_is_enum(T) {
    ti := runtime.type_info_base(type_info_of(T)).variant.(runtime.Type_Info_Enum)
    for v, i in ti.values {
        if v == runtime.Type_Info_Enum_Value(val) {
            return ti.names[i]
        }
    }
    return "INVALID"
}

@(require_results)
strings_join :: proc(a: ..string, allocator := context.temp_allocator, loc := #caller_location) -> (res: string, ok: bool) #optional_ok {
    if len(a) == 0 {
        return "", false
    }

    n := 0
    for s in a {
        n += len(s)
    }
    buf, buf_err := make([]byte, n, allocator, loc)
    if buf_err != nil {
        return
    }
    i := 0
    for s in a {
        i += copy(buf[i:], s)
    }
    return string(buf), true
}

_assertion_failure_proc :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
    // based on runtime.default_assertion_contextless_failure_proc

    runtime.print_string("\n")
    runtime.print_caller_location(loc)
    runtime.print_string(" ")
    runtime.print_string(loc.procedure)
    runtime.print_string(": ")
    runtime.print_string(prefix)
    if len(message) > 0 {
        runtime.print_string(": ")
        runtime.print_string(message)
    }
    runtime.print_byte('\n')

    when ODIN_DEBUG {
        ctx := &_state.debug_trace_ctx
        if _state != nil && !debug_trace.in_resolve(ctx) {
            buf: [64]debug_trace.Frame
            runtime.print_string("Debug Stack Trace:\n")

            frames := debug_trace.frames(ctx, skip = 1, frames_buffer = buf[:])
            for f, i in frames {
                fl := debug_trace.resolve(ctx, f, context.temp_allocator)
                if fl.loc.file_path == "" && fl.loc.line == 0 {
                    continue
                }
                runtime.print_int(i)
                runtime.print_string(" : ")
                runtime.print_caller_location(fl.loc)
                runtime.print_string(" ")
                runtime.print_string(fl.loc.procedure)
                runtime.print_byte('\n')
            }
        }
    } else {
        runtime.print_string("    compile with -debug to show stack trace\n")
    }

    runtime.print_string("\n")

    runtime.trap()
}


@(require_results)
pack_unorm8 :: proc "contextless" (val: [4]f32) -> [4]u8 {
    return {
        u8(clamp(val.x * 255, 0, 255)),
        u8(clamp(val.y * 255, 0, 255)),
        u8(clamp(val.z * 255, 0, 255)),
        u8(clamp(val.w * 255, 0, 255)),
    }
}

@(require_results)
unpack_unorm8 :: proc "contextless" (val: [4]u8) -> [4]f32 {
    return {
        f32(val.x) * (1.0 / 255.0),
        f32(val.y) * (1.0 / 255.0),
        f32(val.z) * (1.0 / 255.0),
        f32(val.w) * (1.0 / 255.0),
    }
}

@(require_results)
pack_unorm16 :: proc "contextless" (val: [2]f32) -> [2]u16 {
    return {
        u16(clamp(val.x * f32(max(u16)), 0, f32(max(u16)))),
        u16(clamp(val.y * f32(max(u16)), 0, f32(max(u16)))),
    }
}

@(require_results)
unpack_unorm16 :: proc "contextless" (val: [2]u16) -> [2]f32 {
    return {
        f32(val.x) * (1.0 / f32(max(u16))),
        f32(val.y) * (1.0 / f32(max(u16))),
    }
}


// Special packing to allow -2..2 range
@(require_results)
pack_signed_color_unorm8 :: proc "contextless" (val: [4]f32) -> [4]u8 {
    return pack_unorm8(val * 0.25 + 0.5)
}

@(require_results)
unpack_signed_color_unorm8 :: proc "contextless" (val: [4]u8) -> [4]f32 {
    return unpack_unorm8(val) * 4.0 - 2.0
}

// No UV precision loss up to 4096x4096 textures.
// 16 bits -> 65536 values.
// Input in range -8..8
@(require_results)
pack_uv_unorm16 :: proc "contextless" (val: [2]f32) -> [2]u16 {
    return pack_unorm16((val + 8.0) * (1.0 / 16.0))
}

@(require_results)
unpack_uv_unorm16 :: proc "contextless" (val: [2]u16) -> [2]f32 {
    return unpack_unorm16(val) * 16.0 - 8.0
}


@(require_results)
pack_sprite_inst :: proc(
    pos:        [3]f32,
    col:        [4]f32,
    mat_x:      [3]f32,
    uv_min:     [2]f32,
    mat_y:      [3]f32,
    uv_size:    [2]f32,
    add_col:    [4]f32,
    param:      u32,
    tex_slice:  u8,
) -> Sprite_Inst {
    return {
        pos         = pos,
        col         = pack_signed_color_unorm8(col),
        mat_x       = mat_x,
        uv_min      = pack_uv_unorm16(uv_min),
        mat_y       = mat_y,
        uv_size     = pack_uv_unorm16(uv_size),
        add_col     = pack_signed_color_unorm8(add_col),
        param       = param,
        tex_slice   = tex_slice,
    }
}

@(require_results)
pack_mesh_inst :: proc(
    pos:        [3]f32,
    col:        [4]f32,
    mat_x:      [3]f32,
    add_col:    [4]f32,
    mat_y:      [3]f32,
    tex_slice:  u8,
    vert_offs:  u32,
    mat_z:      [3]f32,
    param:      u32,
) -> Mesh_Inst {
    vert_offs := vert_offs
    assert(vert_offs < (1 << 24))
    return {
        pos         = pos,
        col         = pack_signed_color_unorm8(col),
        mat_x       = mat_x,
        add_col     = pack_signed_color_unorm8(add_col),
        mat_y       = mat_y,
        tex_slice   = tex_slice,
        vert_offs   = (cast(^[3]u8)&vert_offs)^,
        mat_z       = mat_z,
        param       = param,
    }
}

@(require_results)
pack_vertex :: proc(
    pos:    Vec3,
    uv:     Vec2 = 0,
    normal: Vec3 = {0, 1, 0},
    col:    Vec4 = 1,
) -> Vertex {
    return {
        pos = pos,
        uv = uv,
        normal = pack_unorm8(normal.xyzz * 0.5 + 0.5).xyz,
        col = pack_unorm8(col),
    }
}



//////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Counters
//
// A lightweight way to measure stats and report them to the outside world.
//

COUNTER_HISTORY :: 64

Counter_State :: struct {
    accum:      u64,
    vals:       [COUNTER_HISTORY]u64,
    total_num:  u64,
    total_min:  u64,
    total_max:  u64,
    total_sum:  u64,
}

Counter_Kind :: enum u8 {
    CPU_Frame_Ns,
    CPU_Frame_Work_Ns,
    Num_Draw_Calls,
    Num_Total_Instances,
    Num_Uploaded_Instances, // non-culled
    // TODO:
    // GPU_Frame_Ns
    // Upload_Ns,
    // Total_Draw_Layer_Ns,
    // Temp_Allocs,
    // Temp_Bytes,
}

_counter_add :: proc(kind: Counter_Kind, value: u64) {
    _state.counters[kind].accum = intrinsics.saturating_add(_state.counters[kind].accum, value)
}

_counter_flush :: proc(counter: ^Counter_State) {
    value := counter.accum
    counter.accum = 0
    if value == max(u64) {
        return
    }
    counter.total_num += 1
    counter.vals[counter.total_num % COUNTER_HISTORY] = value
    counter.total_min = min(counter.total_min, value)
    counter.total_max = max(counter.total_max, value)
    counter.total_sum += value
}

// Displays max of the recent history and a graph.
// Assumes screenspace camera.
// 'unit' is for converting e.g. nanoseconds into a reasonable range.
draw_counter :: proc(kind: Counter_Kind, pos: Vec3, scale: f32 = 1, unit: f32 = 1, col: Vec4 = 1, show_text := true) {
    scope_binds()
    bind_texture_by_handle(_state.builtin_texture[.CGA8x8thick])
    bind_blend(.Alpha)
    bind_depth_test(true)
    bind_depth_write(true)

    max_val: u64

    rect := Rect{
        min = {0, 1 - 1.0/128.0},
        max = {0 + 1.0/128.0, 1},
    }

    counter := _state.counters[kind]
    for i in 0..<COUNTER_HISTORY {
        index := (int(counter.total_num) - i) %% COUNTER_HISTORY
        val := counter.vals[index]

        height := -scale * unit * f32(val)

        draw_sprite(
            pos = pos + {COUNTER_HISTORY - f32(i), height * 0.5, 0},
            rect = rect,
            scale = {1, height},
            col = col,
        )

        draw_sprite(
            pos = pos + {COUNTER_HISTORY - f32(i), height * 0.5, 0.01},
            rect = rect,
            scale = {3, height + 2},
            col = BLACK,
        )

        max_val = max(val, max_val)
    }

    if show_text {
        // last := counter.vals[counter.total_num % COUNTER_HISTORY]
        text: string
        if unit == 1 {
            text = ufmt.tprintf("%i", max_val)
        } else {
            text = ufmt.tprintf("%f", f64(max_val) * f64(unit))
        }

        // draw_text(, pos + {64 + 12, 0, 0}, col = col)
        draw_text(text, pos + {64 + 16, 0, 0}, col = col, scale = math.ceil_f32(_state.dpi_scale), anchor = {-1, 1})
        draw_text(text, pos + {64 + 16 + 1, 1, 0.01}, col = BLACK, scale = math.ceil_f32(_state.dpi_scale), anchor = {-1, 1})
    }
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Validation
//
// Ensures the data user passed in is in somewhat reasonable state.
//

@(disabled=!VALIDATION)
validate :: proc(cond: bool, msg := #caller_expression(cond), loc := #caller_location) {
    if !cond {
        // NOTE(bill): This is wrapped in a procedure call
        // to improve performance to make the CPU not
        // execute speculatively, making it about an order of
        // magnitude faster
        @(cold)
        internal :: #force_no_inline proc(msg: string, loc: runtime.Source_Code_Location) {
            p := context.assertion_failure_proc
            if p == nil {
                p = runtime.default_assertion_failure_proc
            }

            p("Raven: Validation Failed", message = msg, loc = loc)
        }
        internal(msg, loc)
    }
}


@(disabled = !VALIDATION)
validate_f32 :: #force_inline proc(x: f32, loc := #caller_location) {
    validate(x == x && (x * 0.5 != x || x == 0), "Value is NaN or Inf", loc = loc)
}


@(disabled = !VALIDATION)
validate_vec2 :: proc(v: [2]f32, loc := #caller_location) {
    validate_f32(v.x, loc)
    validate_f32(v.y, loc)
}

@(disabled = !VALIDATION)
validate_vec3 :: proc(v: [3]f32, loc := #caller_location) {
    validate_f32(v.x, loc)
    validate_f32(v.y, loc)
    validate_f32(v.z, loc)
}

@(disabled = !VALIDATION)
validate_vec4 :: proc(v: [4]f32, loc := #caller_location) {
    validate_f32(v.x, loc)
    validate_f32(v.y, loc)
    validate_f32(v.z, loc)
    validate_f32(v.w, loc)
}

@(disabled = !VALIDATION)
validate_quat :: proc(q: quaternion128, loc := #caller_location) {
    validate_f32(q.x, loc)
    validate_f32(q.y, loc)
    validate_f32(q.z, loc)
    validate_f32(q.w, loc)
}

@(disabled = !VALIDATION)
validate_mat2 :: proc(m: Mat2, loc := #caller_location) {
    validate_vec2(m[0], loc)
    validate_vec2(m[1], loc)
}

@(disabled = !VALIDATION)
validate_mat3 :: proc(m: Mat3, loc := #caller_location) {
    validate_vec3(m[0], loc)
    validate_vec3(m[1], loc)
    validate_vec3(m[2], loc)
}

@(disabled = !VALIDATION)
validate_mat4 :: proc(m: Mat4, loc := #caller_location) {
    validate_vec4(m[0], loc)
    validate_vec4(m[1], loc)
    validate_vec4(m[2], loc)
    validate_vec4(m[3], loc)
}

@(disabled = !VALIDATION)
validate_rect :: proc(v: Rect, loc := #caller_location) {
    validate_vec2(v.min)
    validate_vec2(v.max)
}

@(disabled = !VALIDATION)
validate_draw_sort_key :: proc(key: Draw_Sort_Key) {
    validate(key.texture != {} || key.texture_mode != .Non_Pooled)
    validate(key.ps != {})
    validate(key.vs != {})
    // switch key.texture_mode {
    // case .Non_Pooled:
    // case .Pooled:
    // case .Render_Texture:
    // }
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: CP437 encoding
// Extended ASCII encoding, all 256 characters are valid visual glyphs.
//
// https://en.wikipedia.org/wiki/Code_page_437
//

// Unicode -> CP437. Use when iterating over a string.
rune_to_char :: proc(r: rune) -> u8 {
    switch r {
    // ASCII
    case ' '..='~': return u8(r)

    case: fallthrough

    case '�': return 0
    case '☺': return 1
    case '☻': return 2
    case '♥': return 3
    case '♦': return 4
    case '♣': return 5
    case '♠': return 6
    case '•': return 7
    case '◘': return 8
    case '○': return 9
    case '◙': return 10
    case '♂': return 11
    case '♀': return 12
    case '♪': return 13
    case '♫': return 14
    case '☼': return 15
    case '►': return 16
    case '◄': return 17
    case '↕': return 18
    case '‼': return 19
    case '¶': return 20
    case '§': return 21
    case '▬': return 22
    case '↨': return 23
    case '↑': return 24
    case '↓': return 25
    case '→': return 26
    case '←': return 27
    case '∟': return 28
    case '↔': return 29
    case '▲': return 30
    case '▼': return 31
    case '⌂': return 127
    case 'Ç': return 128
    case 'ü': return 129
    case 'é': return 130
    case 'â': return 131
    case 'ä': return 132
    case 'à': return 133
    case 'å': return 134
    case 'ç': return 135
    case 'ê': return 136
    case 'ë': return 137
    case 'è': return 138
    case 'ï': return 139
    case 'î': return 140
    case 'ì': return 141
    case 'Ä': return 142
    case 'Å': return 143
    case 'É': return 144
    case 'æ': return 145
    case 'Æ': return 146
    case 'ô': return 147
    case 'ö': return 148
    case 'ò': return 149
    case 'û': return 150
    case 'ù': return 151
    case 'ÿ': return 152
    case 'Ö': return 153
    case 'Ü': return 154
    case '¢': return 155
    case '£': return 156
    case '¥': return 157
    case '₧': return 158
    case 'ƒ': return 159
    case 'á': return 160
    case 'í': return 161
    case 'ó': return 162
    case 'ú': return 163
    case 'ñ': return 164
    case 'Ñ': return 165
    case 'ª': return 166
    case 'º': return 167
    case '¿': return 168
    case '⌐': return 169
    case '¬': return 170
    case '½': return 171
    case '¼': return 172
    case '¡': return 173
    case '«': return 174
    case '»': return 175
    case '░': return 176
    case '▒': return 177
    case '▓': return 178
    case '│': return 179
    case '┤': return 180
    case '╡': return 181
    case '╢': return 182
    case '╖': return 183
    case '╕': return 184
    case '╣': return 185
    case '║': return 186
    case '╗': return 187
    case '╝': return 188
    case '╜': return 189
    case '╛': return 190
    case '┐': return 191
    case '└': return 192
    case '┴': return 193
    case '┬': return 194
    case '├': return 195
    case '─': return 196
    case '┼': return 197
    case '╞': return 198
    case '╟': return 199
    case '╚': return 200
    case '╔': return 201
    case '╩': return 202
    case '╦': return 203
    case '╠': return 204
    case '═': return 205
    case '╬': return 206
    case '╧': return 207
    case '╨': return 208
    case '╤': return 209
    case '╥': return 210
    case '╙': return 211
    case '╘': return 212
    case '╒': return 213
    case '╓': return 214
    case '╫': return 215
    case '╪': return 216
    case '┘': return 217
    case '┌': return 218
    case '█': return 219
    case '▄': return 220
    case '▌': return 221
    case '▐': return 222
    case '▀': return 223
    case 'α': return 224
    case 'ß': return 225
    case 'Γ': return 226
    case 'π': return 227
    case 'Σ': return 228
    case 'σ': return 229
    case 'µ': return 230
    case 'τ': return 231
    case 'Φ': return 232
    case 'Θ': return 233
    case 'Ω': return 234
    case 'δ': return 235
    case '∞': return 236
    case 'φ': return 237
    case 'ε': return 238
    case '∩': return 239
    case '≡': return 240
    case '±': return 241
    case '≥': return 242
    case '≤': return 243
    case '⌠': return 244
    case '⌡': return 245
    case '÷': return 246
    case '≈': return 247
    case '°': return 248
    case '∙': return 249
    case '·': return 250
    case '√': return 251
    case 'ⁿ': return 252
    case '²': return 253
    case '■': return 254
    case 0x00A0: return 255 // non breaking space
    }
}

// CP437 -> Unicode. Use when iterating over encoded text to print it.
char_to_rune :: proc(ch: u8) -> rune {
    switch ch {
    // ASCII
    case '!'..='~':
        return rune(ch)

    case: fallthrough
    case 0: return '�'
    case 1: return '☺'
    case 2: return '☻'
    case 3: return '♥'
    case 4: return '♦'
    case 5: return '♣'
    case 6: return '♠'
    case 7: return '•'
    case 8: return '◘'
    case 9: return '○'
    case 10: return '◙'
    case 11: return '♂'
    case 12: return '♀'
    case 13: return '♪'
    case 14: return '♫'
    case 15: return '☼'
    case 16: return '►'
    case 17: return '◄'
    case 18: return '↕'
    case 19: return '‼'
    case 20: return '¶'
    case 21: return '§'
    case 22: return '▬'
    case 23: return '↨'
    case 24: return '↑'
    case 25: return '↓'
    case 26: return '→'
    case 27: return '←'
    case 28: return '∟'
    case 29: return '↔'
    case 30: return '▲'
    case 31: return '▼'
    case 127: return '⌂'
    case 128: return 'Ç'
    case 129: return 'ü'
    case 130: return 'é'
    case 131: return 'â'
    case 132: return 'ä'
    case 133: return 'à'
    case 134: return 'å'
    case 135: return 'ç'
    case 136: return 'ê'
    case 137: return 'ë'
    case 138: return 'è'
    case 139: return 'ï'
    case 140: return 'î'
    case 141: return 'ì'
    case 142: return 'Ä'
    case 143: return 'Å'
    case 144: return 'É'
    case 145: return 'æ'
    case 146: return 'Æ'
    case 147: return 'ô'
    case 148: return 'ö'
    case 149: return 'ò'
    case 150: return 'û'
    case 151: return 'ù'
    case 152: return 'ÿ'
    case 153: return 'Ö'
    case 154: return 'Ü'
    case 155: return '¢'
    case 156: return '£'
    case 157: return '¥'
    case 158: return '₧'
    case 159: return 'ƒ'
    case 160: return 'á'
    case 161: return 'í'
    case 162: return 'ó'
    case 163: return 'ú'
    case 164: return 'ñ'
    case 165: return 'Ñ'
    case 166: return 'ª'
    case 167: return 'º'
    case 168: return '¿'
    case 169: return '⌐'
    case 170: return '¬'
    case 171: return '½'
    case 172: return '¼'
    case 173: return '¡'
    case 174: return '«'
    case 175: return '»'
    case 176: return '░'
    case 177: return '▒'
    case 178: return '▓'
    case 179: return '│'
    case 180: return '┤'
    case 181: return '╡'
    case 182: return '╢'
    case 183: return '╖'
    case 184: return '╕'
    case 185: return '╣'
    case 186: return '║'
    case 187: return '╗'
    case 188: return '╝'
    case 189: return '╜'
    case 190: return '╛'
    case 191: return '┐'
    case 192: return '└'
    case 193: return '┴'
    case 194: return '┬'
    case 195: return '├'
    case 196: return '─'
    case 197: return '┼'
    case 198: return '╞'
    case 199: return '╟'
    case 200: return '╚'
    case 201: return '╔'
    case 202: return '╩'
    case 203: return '╦'
    case 204: return '╠'
    case 205: return '═'
    case 206: return '╬'
    case 207: return '╧'
    case 208: return '╨'
    case 209: return '╤'
    case 210: return '╥'
    case 211: return '╙'
    case 212: return '╘'
    case 213: return '╒'
    case 214: return '╓'
    case 215: return '╫'
    case 216: return '╪'
    case 217: return '┘'
    case 218: return '┌'
    case 219: return '█'
    case 220: return '▄'
    case 221: return '▌'
    case 222: return '▐'
    case 223: return '▀'
    case 224: return 'α'
    case 225: return 'ß'
    case 226: return 'Γ'
    case 227: return 'π'
    case 228: return 'Σ'
    case 229: return 'σ'
    case 230: return 'µ'
    case 231: return 'τ'
    case 232: return 'Φ'
    case 233: return 'Θ'
    case 234: return 'Ω'
    case 235: return 'δ'
    case 236: return '∞'
    case 237: return 'φ'
    case 238: return 'ε'
    case 239: return '∩'
    case 240: return '≡'
    case 241: return '±'
    case 242: return '≥'
    case 243: return '≤'
    case 244: return '⌠'
    case 245: return '⌡'
    case 246: return '÷'
    case 247: return '≈'
    case 248: return '°'
    case 249: return '∙'
    case 250: return '·'
    case 251: return '√'
    case 252: return 'ⁿ'
    case 253: return '²'
    case 254: return '■'
    case 255: return 0x00A0 // non breaking space
    }

}
