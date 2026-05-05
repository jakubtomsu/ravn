#+vet explicit-allocators shadowing style
package raven

import "base"
import "base/ufmt"
import "gpu"
import "platform"
import "rscn"
import "audio"
import "shader_compiler"
import "collision"
import "core:mem"
import "core:bytes"
import "base:intrinsics"
import "core:slice"
import "core:math/linalg"
import "core:math"
import "base:runtime"
import debug_trace "core:debug/trace"

// TODO: try odin's new [dynamic; N]T arrays
// TODO: fix triangles with pooled textures
// TODO: actual 3d transform structure
// TODO: objects in scene data
// TODO: asset_load and reload
// TODO: consistent get_* and no get API!
// TODO: font state
// TODO: try core:image?
// TODO: separate hash table size from backing array size?
// TODO: abstract log_error and log_warn etc to comptime disable logging?
// TODO: More "summary" info when app exist - min/max/avg cpu/gpu frame time, num draws, temp allocs, ..?
// TODO: default module init/shutdown procs
// TODO: load_* vs create_*, insert_* naming convention, and resource management naming in general
// TODO: DXT texture compression
// TODO: figure out file flushing and custom file data loop
// TODO: all resources should return a handle if an identifier exists already
// TODO: fix scene mesh normals
// TODO: draw_2D variants

RELEASE :: #config(RAVEN_RELEASE, base.RELEASE)
VALIDATION :: #config(RAVEN_VALIDATION, !RELEASE)

// Enable internal logs. Mostly useful for debugging internals.
// TODO: tracing
LOG_INTERNAL :: #config(RAVEN_LOG_INTERNAL, false)

MAX_ARENAS :: 64
MAX_TEXTURES :: 256 // Use texture pools if you hit this limit.
MAX_MESHES :: 1024
MAX_OBJECTS :: 1024
MAX_SPLINES :: 1024

MAX_WATCHED_DIRS :: 8
MAX_DRAW_LAYERS :: 16
MAX_RENDER_TEXTURES :: 64
MAX_TEXTURE_RESOURCES :: 64
MAX_SHADERS :: 64
MAX_FILES :: 1024
MAX_SOUNDS :: 1024

MAX_TOTAL_SPRITE_INSTANCES :: 1024 * 64
MAX_TOTAL_MESH_INSTANCES :: 1024 * 64 // Shared between meshes, lines and triangles
MAX_TOTAL_DYNAMIC_VERTS :: 1024 * 64 // Shared between triangles and lines

MAX_TEXTURE_POOLS :: 8
MAX_TEXTURE_POOL_SLICES :: 64

MAX_DRAW_STATE_DEPTH :: 64

MAX_TOTAL_DRAW_BATCHES :: 4096

// This is the actual swapchain used for rendering directly to screen.
DEFAULT_RENDER_TEXTURE :: Render_Texture_Handle{MAX_RENDER_TEXTURES - 1, 0}

HASH_SEED :: #config(RAVEN_HASH_SEED, 0xcbf29ce484222325)
MAX_PROBE_DIST :: #config(RAVEN_MAX_TABLE_PROBE_DIST, 16)

HASH_ALG :: "fnv64a"

UV_EPS :: (1.0 / 4096.0)

LANES :: 8

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

Arena_Handle :: distinct Handle
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

_state: ^State

State :: struct #align(64) {
    initialized:                bool,
    start_time:                 u64,
    curr_time:                  u64,
    last_time:                  u64,
    last_cycle:                 i64,
    frame_dur_ns:               u64,
    frame_dur_cycles:           i64,
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
    submitted_layers:           bool,

    debug_trace_ctx:            debug_trace.Context,
    context_state:              Context_State,

    input:                      Input,

    draw_state:                 Draw_State,
    draw_states:                [MAX_DRAW_STATE_DEPTH]Draw_State,
    draw_states_len:            i32,

    builtin_arena:              Arena_Handle,
    builtin_mesh:               [Builtin_Mesh]Mesh_Handle,
    builtin_texture:            [Builtin_Texture]Texture_Handle,
    builtin_pixel_shader:       [Builtin_Pixel_Shader]Pixel_Shader_Handle,
    builtin_vertex_shader:      [Builtin_Vertex_Shader]Vertex_Shader_Handle,

    quad_ibuf:                  gpu.Resource_Handle,

    sprite_inst_buf:            gpu.Resource_Handle,
    mesh_inst_buf:              gpu.Resource_Handle,
    dynamic_vert_buf:           gpu.Resource_Handle,

    dynamic_vert_upload_buf:    []Vertex,
    dynamic_vert_upload_offs:   u32,

    global_consts:              gpu.Resource_Handle,
    draw_layers_consts:         gpu.Resource_Handle,
    draw_batch_consts:          gpu.Resource_Handle,

    perf_counters:              [Perf_Counter_Kind]Perf_Counter_State,

    watched_dirs_num:           i32,
    watched_dirs:               [MAX_WATCHED_DIRS]Watched_Dir,

    draw_layers:                [MAX_DRAW_LAYERS]Draw_Layer,

    arenas_used:                bit_set[0..<MAX_ARENAS],
    arenas_gen:                 [MAX_ARENAS]Handle_Gen,
    arenas:                     [MAX_ARENAS]Arena,

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
Arena :: struct {
    spline_vert_num:    i32,
    mesh_vert_num:      i32,
    mesh_index_num:     i32,
    object_child_num:   i32,

    object_buf:         []Object,
    object_child_buf:   []Object_Handle,
    spline_vert_buf:    []Spline_Vertex,

    collision_arena:    collision.Arena_Handle,

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

    arena:              Arena_Handle,

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
    arena:          Arena_Handle,

    vert_num:       i32,
    vert_offs:      i32,
    index_num:      i32,
    index_offs:     i32,

    param:          u64, // user param

    bounds_min:     Vec3,
    bounds_max:     Vec3,
    bounds_rad:     f32, // Centered sphere

    verts:          []Vertex,
    indices:        []Vertex_Index,
    collision_mesh: collision.Mesh_Handle,
}

Spline :: struct {
    arena:          Arena_Handle,

    vert_num:       i32,
    vert_offs:      i32,

    param:          u64, // user param

    bounds_min:     Vec3,
    bounds_max:     Vec3,
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Core
//

set_state_ptr :: proc "contextless" (state: ^State) {
    _state = state
    platform._state = &_state.platform_state
    gpu._state = &_state.gpu_state
    audio._state = &_state.audio_state
    shader_compiler._state = &_state.shader_compiler_state
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

init_context_state :: proc(ctx: ^Context_State, allocator: runtime.Allocator) {
    mem.tracking_allocator_init(&_state.context_state.tracking, allocator, allocator)

    debug_trace.init(&_state.debug_trace_ctx)
}

// Create state, init context, init subsystems.
init_state :: proc(allocator: runtime.Allocator) {
    ensure(_state == nil)

    state_err: runtime.Allocator_Error
    _state, state_err = new(State, allocator = allocator)

    if state_err != nil {
        panic("Failed to allocate Raven State")
    }

    _state.allocator = allocator

    init_context_state(&_state.context_state, allocator)

    context = get_context()

    base.log_info("Raven context initialized")

    base.log_info("Initializing platform...")

    platform.init(&_state.platform_state)

    platform.register_default_exception_handler()

    _state.start_time = platform.get_time_ns()

    base.log_info("Initializing audio...")

    if !audio.init(&_state.audio_state) {
        panic("Failed to initialize audio")
    }

    for &counter in _state.perf_counters {
        counter.total_min = max(u64)
        counter.total_num = -20 // warmup period
    }

    base.log_info("Creating Window...")

    _state.window = platform.create_window("Raven App", style = .Regular, high_dpi = true)

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

    _state.screen_size = platform.get_window_rect(_state.window).size
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

    _state.dynamic_vert_upload_buf = make([]Vertex, MAX_TOTAL_DYNAMIC_VERTS, _state.allocator)

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

    when PERF_SCOPES_ENABLED {
        delete(_perf_scopes)
    }

    delete(_state.dynamic_vert_upload_buf, _state.allocator)

    _print_stats_report()

    audio.shutdown()
    gpu.shutdown()
    platform.shutdown()

    free(_state, _state.allocator)
    _state = nil
}

_print_stats_report :: proc() {
    ufmt.eprintfln("\nStats Report:\n")

    {
        offs := 0
        offs += ufmt.eprintf("Perf Counter")

        _align(&offs, 30)
        offs += ufmt.eprintf("Average")

        _align(&offs, 60)
        offs += ufmt.eprintf("Min")

        _align(&offs, 90)
        offs += ufmt.eprintf("Max")

        ufmt.eprintfln("")
    }

    for c, kind in _state.perf_counters {
        name := ufmt.tprintf("%v", kind)
        for &b in transmute([]byte)name {
            if b == '_' {
                b = ' '
            }
        }

        unit := _perf_counter_display_scale[kind]

        offs := 0
        offs += ufmt.eprintf("%s:", name)

        _align(&offs, 30)
        offs += ufmt.eprintf("%v", f64(c.total_sum) * unit / f64(c.total_num))

        _align(&offs, 60)
        offs += ufmt.eprintf("%v", f64(c.total_min) * unit)

        _align(&offs, 90)
        offs += ufmt.eprintf("%v", f64(c.total_max) * unit)

        ufmt.eprintfln("")
    }

    ufmt.eprintfln("")

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

    _align :: proc(offs: ^int, col: int) {
        val := offs^
        for ; val < col; val += 1 {
            ufmt.eprintf(" ")
        }
        offs^ = val
    }
}

begin_frame :: proc() -> (keep_running: bool) {
    perf_scope()

    assert(_state != nil)
    assert(_state.draw_states_len == 0, "Looks like you forgot pop_binds() somewhere")

    if _state.frame_index == 0 {
        base.log_info("Time to first frame: %f ms", f32((platform.get_time_ns() - _state.start_time) / 1e3) * 1e-3)
    }

    free_all(context.temp_allocator)

    keep_running = true

    _state.ended_frame = false

    prev_screen_size := _state.screen_size
    screen := platform.get_window_rect(_state.window).size
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

    for &counter in _state.perf_counters {
        _perf_counter_flush(&counter)
    }

    _state.frame_index += 1
    _state.submitted_layers = false

    time_ns := platform.get_time_ns()
    time_cycles := intrinsics.read_cycle_counter()
    _state.curr_time = time_ns
    _state.frame_dur_ns = time_ns - _state.last_time
    _state.frame_dur_cycles = time_cycles - _state.last_cycle
    _state.last_time = time_ns
    _state.last_cycle = time_cycles

    gpu_can_begin_frame := gpu.begin_frame()
    assert(gpu_can_begin_frame) // HACK

    audio.update()

    _perf_counter_add(.Frame_Time, _state.frame_dur_ns)

    _clear_draw_layers()

    _state.dynamic_vert_upload_offs = 0

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

    _state.draw_states_len = 0
    _state.draw_state = {
        ps = int_cast(u8, _state.builtin_pixel_shader[.Default].index),
        vs = int_cast(u8, _state.builtin_vertex_shader[.Default].index),
        blend_mode = .Opaque,
    }

    set_draw_pixel_shader({})
    set_draw_vertex_shader({})
    _set_draw_texture(_state.builtin_texture[.Default])

    if _state.shutdown_requested {
        keep_running = false
    }

    return keep_running
}

end_frame :: proc(vsync := true) {
    perf_scope()

    assert(!_state.ended_frame)

    _state.ended_frame = true
    curr_time := platform.get_time_ns()

    _perf_counter_add(.Frame_Work_Time, curr_time - _state.last_time)

    gpu.end_frame(sync = vsync)
}

_clear_draw_layers :: proc() {
    for &layer in _state.draw_layers {
        _draw_batch_table_init(&layer.sprites)
        _draw_batch_table_init(&layer.meshes)
        _draw_batch_table_init(&layer.triangles)
        _draw_batch_table_init(&layer.lines)
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
    Icosphere_0,
    Icosphere_1,
    Icosphere = Icosphere_1,
    UV_Sphere_0,
    UV_Sphere_1,
    UV_Sphere = UV_Sphere_1,
    Cube,
    Plane,
    Disk_0,
    Disk_1,
    Disk = Disk_1,
    Cylinder_0,
    Cylinder_1,
    Cylinder = Cylinder_1,
    Utah_Teapot,
    Suzanne,
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

    // TODO: if slang dll is not present and is required, can we use precompiled WGSL?
    // The reason is prototyping.

    _state.builtin_vertex_shader = {
        .Default = create_vertex_shader("default", default_vs) or_else panic("Failed to load default vertex shader"),
        .Default_Sprite = create_vertex_shader("default_sprite", default_sprite_vs) or_else panic("Failed to load default sprite vertex shader"),
    }

    _state.builtin_pixel_shader = {
        .Default = create_pixel_shader("default", default_ps) or_else panic("Failed to load default pixel shader"),
    }

    _state.builtin_arena = load_scene_from_data(
        #load("data/default.rscn", string),
        #load("data/default.rscn.bin"),
        dst_arena = {},
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
    assert(split.x >= 1)
    assert(split.y >= 1)

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
    assert(split.x >= 1)
    assert(split.y >= 1)

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



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Arena
//

@(require_results)
get_internal_arena :: proc(handle: Arena_Handle) -> (result: ^Arena, ok: bool) {
    return _table_get(&_state.arenas, _state.arenas_gen, handle)
}

@(require_results)
create_arena :: proc(
    max_mesh_verts:     i32 = 1024 * 16,
    max_mesh_indices:   i32 = 1024 * 32,
    max_spline_verts:   i32 = 1024,
    max_total_children: i32 = 1024,
    vertex_data:        []Vertex = {},
    index_data:         []Vertex_Index = {},
) -> (result: Arena_Handle, ok: bool) #optional_ok {
    used_set := (transmute(u64)_state.arenas_used) | 1
    index := intrinsics.count_trailing_zeros(~used_set)
    if index == 64 {
        base.log_err("Failed to create arena: There is already max number of arenas")
        return {}, false
    }

    arena := &_state.arenas[index]

    _state.arenas_used += {int(index)}

    arena^ = Arena{
        object_child_buf    = make([]Object_Handle, max_total_children, _state.allocator),
        spline_vert_buf     = make([]Spline_Vertex, max_spline_verts, _state.allocator),
    }

    // TODO: allow creating mutable arenas with default data..?
    if vertex_data != nil {
        arena.vbuf, ok = gpu.create_buffer("rv-arena-vert-buf",
            stride  = size_of(Vertex),
            // size    = size_of(Vertex) * len(vertex_data),
            usage   = .Immutable,
            data    = gpu.slice_bytes(vertex_data),
        )
    } else {
        arena.vbuf, ok = gpu.create_buffer("rv-arena-vert-buf",
            stride  = size_of(Vertex),
            size    = size_of(Vertex) * max_mesh_verts,
            usage   = .Default,
        )
    }

    assert(ok)

    if index_data != nil {
        arena.ibuf, ok = gpu.create_index_buffer("rv-arena-index-buf",
            // size = size_of(Vertex_Index) * len(index_data),
            data = gpu.slice_bytes(index_data),
            usage = .Immutable,
        )
    } else {
        arena.ibuf, ok = gpu.create_index_buffer("rv-arena-index-buf",
            size = size_of(Vertex_Index) * max_mesh_indices,
            usage = .Default,
        )
    }

    assert(ok)

    handle := Arena_Handle{
        index = Handle_Index(index),
        gen = _state.arenas_gen[index],
    }

    return handle, true
}

clear_arena :: proc(handle: Arena_Handle) {
    arena, arena_ok := get_internal_arena(handle)
    if !arena_ok {
        return
    }

    arena.spline_vert_num = 0
    arena.mesh_vert_num = 0
    arena.mesh_index_num = 0
    arena.object_child_num = 0
}

destroy_arena :: proc(handle: Arena_Handle) {
    arena, arena_ok := get_internal_arena(handle)
    if !arena_ok {
        return
    }

    gpu.destroy_resource(arena.vbuf)
    gpu.destroy_resource(arena.ibuf)

    for i in 0..<MAX_MESHES {
        mesh := &_state.meshes[i]
        if mesh.arena != handle {
            continue
        }

        mesh^ = {}
        _state.meshes_hash[i] = 0
        _state.meshes_gen[i] += 1
    }


    for i in 0..<MAX_OBJECTS {
        object := &_state.objects[i]
        if object.arena != handle {
            continue
        }

        object^ = {}
        _state.objects_hash[i] = 0
        _state.objects_gen[i] += 1
    }

    for i in 0..<MAX_SPLINES {
        spline := &_state.splines[i]
        if spline.arena != handle {
            continue
        }

        spline^ = {}
        _state.splines_hash[i] = 0
        _state.splines_gen[i] += 1
    }

    delete(arena.spline_vert_buf, _state.allocator)
    delete(arena.object_child_buf, _state.allocator)

    _state.arenas[handle.index] = {}
    _state.arenas_gen[handle.index] += 1
    _state.arenas_used -= {int(handle.index)}
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Scene
//

load_scene :: proc(name: string, dst_arena: Arena_Handle = {}) -> (result_arena: Arena_Handle, ok: bool) {
    bin_name := strings_join(name, ".bin", allocator = context.temp_allocator)
    txt_data := get_file_data(name) or_return
    bin_data := get_file_data(bin_name) or_return

    return load_scene_from_data(string(txt_data), bin_data, dst_arena)
}

load_scene_from_data :: proc(txt: string, bin: []byte, dst_arena: Arena_Handle) -> (Arena_Handle, bool) {
    assert(len(txt) >= 5)
    assert(len(bin) >= 5)

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

    arena: ^Arena
    arena_handle: Arena_Handle

    vertices := make([]Vertex, len(vert_buf), context.temp_allocator)
    for i in 0..<len(vertices) {
        v := vert_buf[i]
        vertices[i] = {
            pos = v.pos,
            uv = v.uv,
            normal = v.normal,
            col = {v.color.r, v.color.g, v.color.b, 255},
        }
    }

    if dst_arena != {} {
        ok: bool
        arena, ok = get_internal_arena(dst_arena)
        arena_handle = dst_arena

        if !ok {
            base.log_err("Failed to load scene: Invalid target arena handle")
            return {}, false
        }

        // APPEND TO GPU
        unimplemented()

    } else {
        ok: bool
        arena_handle, ok = create_arena(
            max_total_children  = i32(header.object_num),
            max_spline_verts    = i32(header.spline_vert_num),
            vertex_data         = vertices,
            index_data          = index_buf,
        )

        if !ok {
            base.log_err("Failed to load scene: Couldn't create arena")
            return {}, false
        }

        arena, _ = get_internal_arena(arena_handle)

        assert(arena != nil)
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

            index := mesh_counter
            mesh_counter += 1

            verts := vertices[v.vert_start:][:v.vert_num]
            indices := index_buf[v.index_start:][:v.index_num]

            mesh_list[index] = create_mesh_from_data(
                name = v.name,
                arena_handle = arena_handle,
                verts = verts,
                indices = indices,
                update_gpu_buffers = false,
            )

        case rscn.Spline:
            base.log_debug("Loading Spline: %s", v.name)

            index := spline_counter
            spline_counter += 1

            spline: Spline
            spline.arena = arena_handle

            spline.vert_num = i32(v.vert_num)
            spline.vert_offs = arena.spline_vert_num + i32(v.vert_start)

            verts := spline_vert_buf[v.vert_start:][:v.vert_num]

            if v.vert_num > (len(arena.spline_vert_buf) - int(arena.spline_vert_num)) {
                base.log_err("Failed to create spline, spline vertex buffer can't fit the data")
                continue
            }

            // NOTE: consider vert radius?
            spline.bounds_min = max(f32)
            spline.bounds_max = min(f32)
            for vert, i in verts {
                spline.bounds_min = linalg.min(spline.bounds_min, vert.pos)
                spline.bounds_max = linalg.max(spline.bounds_max, vert.pos)

                arena.spline_vert_buf[arena.spline_vert_num + i32(i)] = vert
            }

            handle, handle_ok := insert_spline_by_name(v.name, spline)
            if !handle_ok {
                base.log_err("Failed to insert spline, table is full")
                return {}, false
            }

            arena.spline_vert_num += i32(len(verts))

            spline_list[index] = handle

        case rscn.Object:
            base.log_debug("Loading Object: %s", v.name)

            index := object_counter
            object_counter += 1

            object: Object
            object.arena = arena_handle

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
    child_offset := arena.object_child_num
    for handle in object_list {
        obj := get_internal_object(handle) or_continue

        obj.child_offset = child_offset

        if child_offset + obj.child_num > i32(len(arena.object_child_buf)) {
            base.log_err("Arena child buffer is too small to contain all children")
            obj.child_num = 0
            continue
        }

        child_offset += obj.child_num
    }

    arena.object_child_num = child_offset

    // Fill child array
    for handle in object_list {
        obj := get_internal_object(handle) or_continue

        parent := get_internal_object(obj.parent) or_continue

        arena.object_child_buf[parent.child_offset] = handle
        parent.child_offset += 1
    }

    // Reset child offsets (this is a bit weird, be careful)
    for handle in object_list {
        obj := get_internal_object(handle) or_continue
        obj.child_offset -= obj.child_num
    }

    return arena_handle, true
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


// Keys

get_key_down :: proc(key: Key) -> bool {
    return key in _state.input.keys.down
}

// Down time is 0 on pressed.
get_key_down_time :: proc(key: Key) -> f32 {
    return _state.input.keys.timer[key]
}

get_key_repeated :: proc(key: Key) -> bool {
    return key in _state.input.keys.repeated
}

get_key_released :: proc(key: Key) -> bool {
    return key in _state.input.keys.released
}

// buf: buffering window duration in seconds
get_key_pressed :: proc(key: Key, buf: f32 = 0) -> bool {
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


// Mouse

// NOTE: [0, 0] is the bottom left corner.
get_mouse_pos :: proc() -> [2]f32 {
    return _state.input.mouse_pos
}

// Positive Y is up.
get_mouse_delta :: proc() -> [2]f32 {
    return _state.input.mouse_delta
}

get_scroll_delta :: proc() -> [2]f32 {
    return _state.input.scroll_delta
}

get_mouse_down :: proc(button: Mouse_Button) -> bool {
    return button in _state.input.mouse_buttons.down
}

// Down time is 0 on pressed.
get_mouse_down_time :: proc(button: Mouse_Button) -> f32 {
    return _state.input.mouse_buttons.timer[button]
}

get_mouse_repeated :: proc(button: Mouse_Button) -> bool {
    return button in _state.input.mouse_buttons.repeated
}

get_mouse_released :: proc(button: Mouse_Button) -> bool {
    return button in _state.input.mouse_buttons.released
}

// buf: buffering window duration in seconds
get_mouse_pressed :: proc(button: Mouse_Button, buf: f32 = 0) -> bool {
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


// Gamepads

get_gamepad_axis :: proc(gamepad_index: int, axis: Gamepad_Axis, deadzone: f32 = 0.01) -> f32 {
    gamepad := _state.input.gamepads[gamepad_index]
    val := gamepad.axes[axis]
    return abs(val) < deadzone ? 0 : val
}

get_gamepad_down :: proc(gamepad_index: int, button: Gamepad_Button) -> bool {
    gamepad := _state.input.gamepads[gamepad_index]
    return button in gamepad.buttons.down
}

// Down time is 0 on pressed
get_gamepad_down_time :: proc(gamepad_index: int, button: Gamepad_Button) -> f32 {
    gamepad := _state.input.gamepads[gamepad_index]
    return gamepad.buttons.timer[button]
}

get_gamepad_repeated :: proc(gamepad_index: int, button: Gamepad_Button) -> bool {
    gamepad := _state.input.gamepads[gamepad_index]
    return button in gamepad.buttons.repeated
}

get_gamepad_released :: proc(gamepad_index: int, button: Gamepad_Button) -> bool {
    gamepad := _state.input.gamepads[gamepad_index]
    return button in gamepad.buttons.released
}

// buf: buffering window duration in seconds
get_gamepad_pressed :: proc(gamepad_index: int, button: Gamepad_Button, buf: f32 = 0) -> bool {
    gamepad := _state.input.gamepads[gamepad_index]

    if buf > 0.0001 &&
        button in gamepad.buttons.buffered &&
        gamepad.buttons.timer[button] <= buf
    {
        gamepad.buttons.buffered -= {button}
        return true
    }

    if button in gamepad.buttons.pressed {
        return true
    }

    return false
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

    arena, arena_ok := get_internal_arena(obj.arena)
    if !arena_ok {
        base.log_err("Failed to get object's children: object's arena handle is invalid")
        return nil, false
    }

    return arena.object_child_buf[obj.child_offset:][:obj.child_num], true
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

load_asset :: proc(name: string, dst_arena: Arena_Handle) -> bool {
    if string_has_suffix(name, ".png") {
        data, data_ok := get_file_data(name)
        if !data_ok {
            base.log_err("Failed to load texture '%s', file not found", name)
            return false
        }
        _, ok := create_texture_from_encoded_data(name[:len(name) - 4], data)
        return ok
    } else if string_has_suffix(name, ".rscn") {
        _, ok := load_scene(name, dst_arena = dst_arena)
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
// MARK: Collision
//

create_collision_mesh :: proc(mesh: Mesh_Handle) -> (result: collision.Mesh_Handle, ok: bool) #optional_ok {
    #assert(size_of(Vertex_Index) == size_of(u16))

    mesh := get_internal_mesh(mesh) or_return

    if mesh.collision_mesh != {} {
        return mesh.collision_mesh, true
    }

    arena := get_internal_arena(mesh.arena) or_return
    allocator := collision.arena_allocator(arena.collision_arena)

    verts := make([][3]f32, len(mesh.verts), allocator)
    for &v, i in verts {
        v = mesh.verts[i].pos
    }

    result = collision.create_mesh(
        arena.collision_arena,
        verts,
        slice.reinterpret([][3]u16, mesh.indices),
    ) or_return

    mesh.collision_mesh = result

    return result, ok
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
alloc_slice_non_zeroed :: proc($T: typeid, init_len: int, alignment: int = 2 * align_of(rawptr), allocator: runtime.Allocator) -> []T {
    buf := runtime.mem_alloc_non_zeroed(size_of(T) * init_len, alignment = alignment, allocator = allocator) or_else panic("Failed to allocate")
    return ([^]T)(raw_data(buf))[:len(buf) / size_of(T)]
}

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
    v := transmute(#simd[4]f32)val
    v = intrinsics.simd_clamp(v * 255, 0, 255)
    return transmute([4]u8)cast(#simd[4]u8)v
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
    v := transmute(#simd[4]f32)val
    v = v * 0.25 * 255.0 + 0.5 * 255.0
    v = intrinsics.simd_clamp(v, 0, 255)
    return transmute([4]u8)cast(#simd[4]u8)v
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
    return #force_inline pack_unorm16((val + 8.0) * (1.0 / 16.0))
}

@(require_results)
unpack_uv_unorm16 :: proc "contextless" (val: [2]u16) -> [2]f32 {
    return #force_inline unpack_unorm16(val) * 16.0 - 8.0
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
    param:      u32 = 0,
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

// https://nullprogram.com/blog/2018/07/31/

@(require_results)
hash_murmurhash32_mix32 :: proc "contextless" (x: u32) -> u32 {
    x := x
    x ~= x >> 16
    x *= 0x85ebca6b
    x ~= x >> 13
    x *= 0xc2b2ae35
    x ~= x >> 16
    return x
}

@(require_results)
hash_splittable64 :: proc "contextless" (x: u64) -> u64 {
    x := x
    x ~= x >> 30
    x *= 0xbf58476d1ce4e5b9
    x ~= x >> 27
    x *= 0x94d049bb133111eb
    x ~= x >> 31
    return x
}

align_up :: proc(x: u32, align: u32) -> u32 {
    return (x + align - 1) & ~(align - 1)
}


// Order independent blend modes are a lot simpler on the renderer CPU side.
is_blend_mode_order_dependent :: proc(mode: Blend_Mode) -> bool {
    switch mode {
    case .Opaque, .Add:
        return false
    case .Premultiplied_Alpha, .Alpha:
        return true
    }
    return false
}


//////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Perf
//
// A lightweight way to measure stats and report them to the outside world.
//

PERF_COUNTER_HISTORY :: 64

Perf_Counter_State :: struct {
    accum:      u64,
    vals:       [PERF_COUNTER_HISTORY]u64,
    total_num:  i64,
    total_min:  u64,
    total_max:  u64,
    total_sum:  u64,
}

Perf_Counter_Kind :: enum u8 {
    Num_Draw_Calls,

    Frame_Time,
    Frame_Work_Time,

    // TODO:
    // Temp_Allocs,
    // Temp_Bytes,
}

@(rodata)
_perf_counter_display_scale := [Perf_Counter_Kind]f64{
    .Num_Draw_Calls = 1,
    .Frame_Time = 1e-6,
    .Frame_Work_Time = 1e-6,
}

_perf_counter_add :: proc(kind: Perf_Counter_Kind, #any_int value: u64 = 1) {
    _state.perf_counters[kind].accum += value
}

_perf_counter_flush :: proc(perf_counter: ^Perf_Counter_State) {
    perf_counter.total_num += 1
    value := perf_counter.accum
    perf_counter.accum = 0
    if perf_counter.total_num <= 0 {
        return
    }
    perf_counter.vals[perf_counter.total_num % PERF_COUNTER_HISTORY] = value
    perf_counter.total_min = min(perf_counter.total_min, value)
    perf_counter.total_max = max(perf_counter.total_max, value)
    perf_counter.total_sum += value
}

// Displays max of the recent history and a graph.
// Maximum makes more sense than the average, because temporal spikes are important.
//
// Assumes screenspace camera.
// 'unit' is for converting e.g. nanoseconds into a reasonable range.
draw_perf_counter :: proc(kind: Perf_Counter_Kind, pos: Vec3, scale: f32 = 1, col: Vec4 = 1, show_text := true) {
    scope_draw_state()
    set_draw_texture(_state.builtin_texture[.CGA8x8thick])
    set_draw_blend(.Alpha)
    set_draw_depth(.Depth)

    max_val: u64

    rect := Rect{
        min = {0, 1 - 1.0/128.0},
        max = {0 + 1.0/128.0, 1},
    }

    unit := f32(_perf_counter_display_scale[kind])

    perf_counter := _state.perf_counters[kind]
    for i in 0..<PERF_COUNTER_HISTORY {
        index := (int(perf_counter.total_num) - i) %% PERF_COUNTER_HISTORY
        val := perf_counter.vals[index]

        height := -1 * scale * unit * f32(val)

        draw_sprite(
            pos = pos + {PERF_COUNTER_HISTORY - f32(i), height * 0.5, 0},
            rect = rect,
            scale = {1, height},
            col = col,
        )

        draw_sprite(
            pos = pos + {PERF_COUNTER_HISTORY - f32(i), height * 0.5, 0.01},
            rect = rect,
            scale = {3, height + 2},
            col = BLACK,
        )

        max_val = max(val, max_val)
    }

    if show_text {
        // last := perf_counter.vals[perf_counter.total_num % PERF_COUNTER_HISTORY]
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

// Lives for only the current frame. Measures sum nanoseconds.

PERF_SCOPES_ENABLED :: #config(PERF_SCOPES_ENABLED, !RELEASE)

when PERF_SCOPES_ENABLED {
    _perf_scopes: map[string]i64
}

@(deferred_in_out = _perf_scope_add)
perf_scope :: proc(name: string = "", loc := #caller_location) -> i64 {
    when PERF_SCOPES_ENABLED {
        return intrinsics.read_cycle_counter()
    } else {
        return 0
    }
}

@(disabled = !PERF_SCOPES_ENABLED,)
_perf_scope_add :: proc(name: string, loc := #caller_location, start: i64) {
    when PERF_SCOPES_ENABLED {
        str := name == "" ? loc.procedure : name
        prev := _perf_scopes[str]
        _perf_scopes[str] = prev + (intrinsics.read_cycle_counter() - start)
    }
}

draw_perf_scopes :: proc(pos: Vec3 = {10, 40, 0.1}, scale: f32 = 1) {
    when PERF_SCOPES_ENABLED {
        scope_draw_state()
        set_draw_texture(get_builtin_texture(.CGA8x8thick))
        set_draw_depth(.Depth)

        Scope :: struct {
            name:   string,
            cycles: i64,
        }

        scopes := make([]Scope, len(_perf_scopes), context.temp_allocator)
        _scope_counter := 0
        for name, scope in _perf_scopes {
            scopes[_scope_counter] = {name, scope}
            _scope_counter += 1
        }

        slice.sort_by(scopes, proc(a, b: Scope) -> bool {
            return a.name > b.name
        })

        rect := Rect{
            min = {0, 1 - 1.0/128.0},
            max = {0 + 1.0/128.0, 1},
        }

        FRAME_TIME :: 1.0 / 60.0

        cycles_to_ms := f64(_state.frame_dur_ns) / (f64(_state.frame_dur_cycles) * 1e6)

        for scope, i in scopes {
            p := pos + Vec3{0, f32(i) * 16, 0}

            ms := f32(f64(scope.cycles) * cycles_to_ms)
            width := max(1, clamp(ms, 0, 16) * 10)

            text := base.tprintf("%s: %f ms", scope.name, ms)
            draw_text(text, p)
            draw_text(text, p + {1, 1, 0.001}, col = BLACK)
            draw_sprite(p + {-5, 5, 0.01}, rect, {width, 16}, anchor = {-1, 0},
                col = ms > 16.1 ? RED : (ms < 1 ? GREEN : ORANGE),
            )
        }

        // Flush
        if _perf_scopes != nil {
            clear(&_perf_scopes)
        }
    }
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
