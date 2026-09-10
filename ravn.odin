#+vet explicit-allocators shadowing style
package ravn

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

RELEASE :: #config(RAVN_RELEASE, base.RELEASE)
VALIDATION :: #config(RAVN_VALIDATION, !RELEASE)
DEBUG_TRACE_ENABLED :: ODIN_DEBUG && #config(RAVN_DEBUG_TRACE, !RELEASE) // Debug symbols are required
SHADER_COMPILER_ENABLED :: #config(RAVN_SHADER_COMPILER, !RELEASE)

MAX_ARENAS                  :: #config(MAX_ARENAS, 64)
MAX_TEXTURES                :: #config(MAX_TEXTURES, 256) // Use texture pools if you hit this limit.
MAX_MESHES                  :: #config(MAX_MESHES, 1024)
MAX_OBJECTS                 :: #config(MAX_OBJECTS, 1024)
MAX_SPLINES                 :: #config(MAX_SPLINES, 1024)
MAX_DRAW_LAYERS             :: #config(MAX_DRAW_LAYERS, 16)
MAX_RENDER_TEXTURES         :: #config(MAX_RENDER_TEXTURES, 64)
MAX_TEXTURE_RESOURCES       :: #config(MAX_TEXTURE_RESOURCES, 64)
MAX_SHADERS                 :: #config(MAX_SHADERS, 64)
MAX_FILES                   :: #config(MAX_FILES, 1024)
MAX_SOUND_RESOURCES         :: #config(MAX_SOUND_RESOURCES, 1024)
MAX_TOTAL_SPRITE_INSTANCES  :: #config(MAX_TOTAL_SPRITE_INSTANCES, 1024) * 64
MAX_TOTAL_MESH_INSTANCES    :: #config(MAX_TOTAL_MESH_INSTANCES, 1024) * 64 // Shared between meshes, lines and triangles
MAX_TOTAL_DYNAMIC_VERTS     :: #config(MAX_TOTAL_DYNAMIC_VERTS, 1024) * 64 // Shared between triangles and lines
MAX_TEXTURE_POOLS           :: #config(MAX_TEXTURE_POOLS, 64)
MAX_TEXTURE_POOL_SLICES     :: #config(MAX_TEXTURE_POOL_SLICES, 64)
MAX_DRAW_STATE_DEPTH        :: #config(MAX_DRAW_STATE_DEPTH, 64)
MAX_TOTAL_DRAW_BATCHES      :: #config(MAX_TOTAL_DRAW_BATCHES, 4096)

DEFAULT_RENDER_TEXTURE :: Render_Texture_Handle{index = 1, gen = 0}
// This is the actual swapchain used for rendering directly to screen.

HASH_SEED :: #config(RAVN_HASH_SEED, 0xcbf29ce484222325)
HASH_ALG :: "fnv64a"

UV_EPS :: (1.0 / 2048.0)

LANES :: 8

HANDLE_INDEX_INVALID :: ~Handle_Index(0)

Handle_Index :: u16
Handle_Gen :: u8

Handle :: base.Handle

Arena_Handle :: distinct Handle
Object_Handle :: distinct Handle
Mesh_Handle :: distinct Handle
Texture_Handle :: distinct Handle
Texture_Resource_Handle :: distinct Handle
Texture_Pool_Handle :: distinct Handle
Spline_Handle :: distinct Handle
Render_Texture_Handle :: distinct Handle
Shader_Handle :: distinct Handle
File_Handle :: distinct Handle
Sound_Resource_Handle :: distinct Handle
Sound_Handle :: audio.Sound_Handle

// NOTE: This structure is passed between DLLs when hot-reloading.
App_Desc :: struct {
    name:               string,

    init:               App_Init_Proc,
    shutdown:           App_Shutdown_Proc,
    update:             App_Update_Proc,

    window_style:       platform.Window_Style,
    window_size:        [2]i32,
    window_high_dpi:    bool,
}

// Called after internal init is done to let the app initialize.
App_Init_Proc ::       #type proc()
// Called after request_shutdown() but before the engine cleans up.
App_Shutdown_Proc ::   #type proc()
// Called every frame.
// Usually, hot_ptr is nil. But after a hotreload, hot_ptr is the last returned data_ptr.
App_Update_Proc ::     #type proc(hot_ptr: rawptr) -> (data_ptr: rawptr)

Rect :: struct {
    min:    [2]f32,
    max:    [2]f32,
}

_state: ^State

State :: struct #align(4096) {
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
    init_allocator:             runtime.Allocator,
    allocator:                  runtime.Allocator,
    window:                     platform.Window,
    dpi_scale:                  f32,
    app_desc:                   App_Desc,
    app_data:                   rawptr,
    shutdown_requested:         bool,
    submitted_layers:           bool,

    context_state:              Context_State,

    input:                      Input,

    draw_state:                 Draw_State,
    draw_states:                [MAX_DRAW_STATE_DEPTH]Draw_State,
    draw_states_len:            i32,

    builtin_arena:              Arena_Handle,
    builtin_mesh:               [Builtin_Mesh]Mesh_Handle,
    builtin_texture:            [Builtin_Texture]Texture_Handle,
    builtin_shader:             [Builtin_Shader]Shader_Handle,

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

    draw_layers:                [MAX_DRAW_LAYERS]Draw_Layer,

    arenas:                     base.Pool(MAX_ARENAS, Arena, Arena_Handle),
    render_textures:            base.Pool(MAX_RENDER_TEXTURES, Render_Texture, Render_Texture_Handle),
    texture_pools:              base.Pool(MAX_TEXTURE_POOLS, Texture_Pool, Texture_Pool_Handle),

    meshes:                     base.Hash_Pool(MAX_MESHES, Mesh, Mesh_Handle),
    splines:                    base.Hash_Pool(MAX_SPLINES, Spline, Spline_Handle),
    textures:                   base.Hash_Pool(MAX_TEXTURES, Texture, Texture_Handle),
    shaders:                    base.Hash_Pool(MAX_SHADERS, Shader, Shader_Handle),
    files:                      base.Hash_Pool(MAX_FILES, File, File_Handle),
    sound_resources:            base.Hash_Pool(MAX_SOUND_RESOURCES, Sound_Resource_State, Sound_Resource_Handle),

    shader_compiler_state:      (shader_compiler.State when SHADER_COMPILER_ENABLED else struct {}),
    shader_compiler_target:     shader_compiler.Target,

    platform_state:             platform.State,
    gpu_state:                  gpu.State,
    audio_state:                audio.State,
    collision_state:            collision.State,
}

Context_State :: struct {
    tracking:   mem.Tracking_Allocator,
}

File :: struct #all_or_none {
    data:       []byte,
    flags:      bit_set[File_Flag],
}

File_Flag :: enum u8 {
    Temp,
}

Shader :: struct #all_or_none {
    shader:     gpu.Shader_Handle,
}

Sound_Resource_State :: struct #all_or_none {
    resource:   audio.Resource_Handle,
}

// Data Scope
// Collection of data with one lifetime.
Arena :: struct #all_or_none {
    usage:              Arena_Usage,

    spline_vert_num:    i32,
    object_child_num:   i32,

    spline_vert_buf:    []Spline_Vertex,

    collision_arena:    collision.Arena_Handle,

    // Static mode
    vert_upload_buf:    []Vertex,
    index_upload_buf:   []Vertex_Index,
    vert_upload_offs:   i32,
    index_upload_offs:  i32,
    dirty:              bool,

    vbuf:               gpu.Resource_Handle,
    ibuf:               gpu.Resource_Handle,
}

Arena_Usage :: enum u8 {
    // For dynamic (per-frame) geometry.
    Dynamic,
    // For scenes and long lived data.
    // All GPU buffers will be re-created on data flush.
    Static,
}

Mesh :: struct #all_or_none {
    arena:          Arena_Handle,

    vert_num:       i32,
    vert_offs:      i32,
    index_num:      i32,
    index_offs:     i32,

    bounds_min:     [3]f32,
    bounds_max:     [3]f32,
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

    bounds_min:     [3]f32,
    bounds_max:     [3]f32,
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Core
//

set_state_ptr :: proc "contextless" (state: ^State) {
    _state = state
    platform._state = &_state.platform_state
    gpu._state = &_state.gpu_state
    audio._state = &_state.audio_state
    collision._state = &_state.collision_state
}

get_state_ptr :: proc "contextless" () -> (state: ^State) {
    return _state
}


when ODIN_OS == .JS {
    @(export) step :: proc(dt: f32) -> (keep_running: bool) {
        return __js_step(dt)
    }

} else when ODIN_BUILD_MODE == .Dynamic {
    @(export) _app_hot_step :: proc "contextless" (prev_state: ^State, desc: ^App_Desc) -> ^State {
        return __app_hot_step(prev_state, desc^)
    }
}

// Default runner for a ravn app.
// Calling this does nothing when compiling as a DLL, it's the responsibility
// of whoever loaded the DLL (e.g. hotreload runner) to call the app.
// NOTE: Things like reload never get called in this mode.
run_main_loop :: proc(desc: App_Desc) {
    ensure(desc.update != nil)

    when ODIN_BUILD_MODE == .Dynamic {

        // Nothing.

    } else when ODIN_OS == .JS {

        init_state(context.allocator, desc)

    } else when ODIN_OS == .Windows || ODIN_OS == .Linux || ODIN_OS == .Darwin {

        init_state(context.allocator, desc)
        context = get_context()

        ensure(_state.gpu_state.init_done)

        if desc.init != nil {
            desc.init()
        }

        for {
            if !_app_update_frame(desc) {
                break
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

_app_update_frame :: proc(desc: App_Desc, hot_ptr: rawptr = nil) -> bool {
    if !begin_frame() {
        return false
    }

    _state.app_data = desc.update(hot_ptr)

    if !_state.ended_frame {
        end_frame()
    }

    return true
}

__js_step :: proc(dt: f32) -> (keep_running: bool) {
    assert(_state != nil)
    assert(_state.app_desc.update != nil)

    context = get_context()

    if !_state.initialized {
        if gpu.is_init_done() {
            _post_gpu_init()
            if _state.app_desc.init != nil {
                _state.app_desc.init()
            }
        } else {
            return true
        }
    }

    if !_app_update_frame(_state.app_desc) {
        if _state.app_desc.shutdown != nil {
            _state.app_desc.shutdown()
        }
        return false
    }

    return true
}

__app_hot_step :: proc "contextless" (prev_state: ^State, desc: App_Desc) -> ^State {
    hotreloaded := false

    if prev_state == nil {
        // First init
        context = runtime.default_context()

        assert(_state == nil)

        init_state(context.allocator, desc)
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

    if !_app_update_frame(desc, hot_ptr = hotreloaded ? _state.app_data : nil) {
        if desc.shutdown != nil {
            desc.shutdown()
        }
        return nil
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
}

// Create state, init context, init subsystems.
init_state :: proc(allocator: runtime.Allocator, desc: App_Desc) {
    ensure(_state == nil)

    state_err: runtime.Allocator_Error
    _state, state_err = new(State, allocator = allocator)

    if state_err != nil {
        panic("Failed to allocate Ravn State")
    }

    _state.app_desc = desc
    _state.init_allocator = allocator

    init_context_state(&_state.context_state, allocator)
    context = get_context()

    _state.allocator = context.allocator

    base.log_info("Ravn context initialized")

    base.pool_clear(&_state.arenas)
    base.pool_clear(&_state.render_textures)
    base.pool_clear(&_state.texture_pools)

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

    window_title := desc.name == "" ? "RAVN App" : desc.name
    rect: platform.Rect
    if desc.window_size != 0 {
        monitor := platform.get_main_monitor_rect()
        size := [2]i32{
            min(monitor.size.x, desc.window_size.x),
            min(monitor.size.y, desc.window_size.y),
        }
        rect = {
            min  = monitor.min + monitor.size / 2 - size / 2,
            size = size,
        }
    }

    _state.window = platform.create_window(window_title, style = desc.window_style, rect = rect, high_dpi = desc.window_high_dpi)

    base.log_info("Initializing GPU...")
    if !gpu.init(&_state.gpu_state, platform.get_native_window_ptr(_state.window)) {
        panic("Failed to initialize GPU")
    }

    when SHADER_COMPILER_ENABLED {
        if shader_compiler.init(&_state.shader_compiler_state, target = SHADER_TARGET) {
            _state.shader_compiler_target = SHADER_TARGET
        } else {
            _state.shader_compiler_target = .Invalid
            base.log_err("Failed to load shader compiler, likely a missing dynamic library. Compiling shaders from source won't be available.")
        }
    }

    collision.init(&_state.collision_state, _state.allocator)

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

    // Swapchain
    default_rtex_handle, default_rtex_ok := base.pool_find_free(_state.render_textures)
    assert(default_rtex_ok)
    assert(default_rtex_handle == DEFAULT_RENDER_TEXTURE)
    default_rtex_ok = base.pool_insert(&_state.render_textures, DEFAULT_RENDER_TEXTURE, Render_Texture{
        size = _state.screen_size,
        color = {},
        depth = gpu.create_texture_2d("rv-def-rentex-depth", .D_F32, _state.screen_size, render_texture = true) or_else panic("Failed to create a depth buffer"),
        loc = #location(),
    })
    assert(default_rtex_ok)

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

    base.log_info("Ravn initialized successfully")

    _state.initialized = true
}

request_shutdown :: proc() {
    when ODIN_OS != .JS {
        _state.shutdown_requested = true
    }
}

// Called automatically at the right time when you call rv.request_shutdown()!
shutdown_state :: proc() {
    base.log_info("Shutting down Ravn...")
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
    for iter := base.pool_iter(&_state.arenas); handle, arena in base.pool_next(&iter) {
        _delete_arena_buffers(arena)
    }

    collision.shutdown()
    audio.shutdown()
    gpu.shutdown()
    platform.shutdown()

    _print_stats_report()

    free(_state, _state.init_allocator)
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
        base.log_info("Init time: %f ms", f32((platform.get_time_ns() - _state.start_time) / 1e3) * 1e-3)
    }

    free_all(context.temp_allocator)
    _state.frame_index += 1
    evict_all_temp_files()

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

    default_rt, default_rt_ok := base.pool_get(&_state.render_textures, DEFAULT_RENDER_TEXTURE)
    assert(default_rt_ok)

    if _state.screen_dirty {
        _state.screen_dirty = false
        gpu.destroy_resource(default_rt.depth)
        default_rt.size = _state.screen_size
        default_rt.depth = gpu.create_texture_2d("rv-def-rentex-depth", .D_F32, _state.screen_size, render_texture = true) or_else panic("gpu")
        default_rt.color = gpu.update_swapchain(platform.get_native_window_ptr(_state.window), _state.screen_size) or_else panic("gpu")
    }

    assert(default_rt.color != {})

    for &counter in _state.perf_counters {
        _perf_counter_flush(&counter)
    }

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
    collision.begin_step(get_delta_time())

    _perf_counter_add(.Frame_Time, _state.frame_dur_ns)

    _state.dynamic_vert_upload_offs = 0

    _state.dpi_scale = platform.get_window_dpi_scale(_state.window)

    _input_clear_temp_state(&_state.input, get_delta_time())

    for event in platform.poll_window_events(_state.window) {
        switch v in event {
        case platform.Event_Exit:
            keep_running = false

        case platform.Event_Window_Size:

        case platform.Event_Key, platform.Event_Mouse_Button, platform.Event_Mouse, platform.Event_Scroll:
            _input_apply_event(&_state.input, event)
        }
    }

    for i in 0..<MAX_GAMEPADS {
        state, state_ok := platform.get_gamepad_state(i)
        _input_apply_gamepad_state(&_state.input, i, state = state, state_ok = state_ok)
    }

    // HACK
    if _state.frame_index < 5 {
        _state.input.mouse_delta = 0
    }

    _clear_draw_layers()

    for i in 0..<MAX_ARENAS {
        handle := Arena_Handle{index = Handle_Index(i), gen = _state.arenas.gen[i]}
        arena := base.pool_get(&_state.arenas, handle) or_continue
        flush_arena_gpu_buffers(handle)
    }

    _state.draw_states_len = 0
    _state.draw_state = get_default_draw_state()

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

    collision.end_step()

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

@(require_results)
read_file :: proc(path: string, temp := true) -> ([]byte, bool) {
    hash := hash_name(normalize_path(path, context.temp_allocator))
    handle, existing, existing_ok := base.hash_pool_find(&_state.files, hash)

    if existing_ok {
        if existing.data != nil {
            return existing.data, true
        }
    }

    when ODIN_OS == .JS {
        return nil, false
    } else {
        data, data_ok := platform.read_file_by_path(path, temp ? context.temp_allocator : _state.allocator)
        if !data_ok {
            return nil, false
        }

        flags: bit_set[File_Flag]
        if temp {
            flags += {.Temp}
        }

        file: File = {
            flags = flags,
            data = data,
        }

        if !_register_file(hash, file) {
            base.log_err("Failed to register file: %s", path)
        }

        return data, true
    }
}

register_file_data :: proc(path: string, data: []byte, flags: bit_set[File_Flag] = {}) -> bool {
    hash := hash_name(normalize_path(path, context.temp_allocator))
    file := File{
        data = data,
        flags = flags,
    }
    return _register_file(hash, file)
}

_register_file :: proc(hash: u64, file: File) -> bool {
    handle, exists := base.hash_pool_find_free(_state.files, hash) or_return
    if exists {
        return false
    }
    base.hash_pool_insert(&_state.files, hash, handle, file) or_return
    return true
}

evict_all_temp_files :: proc() {
    for iter := base.hash_pool_iter(&_state.files); handle, file in base.hash_pool_next(&iter) {
        if .Temp in file.flags {
            file.data = {}
        }
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
    UV_Sphere_0,
    UV_Sphere_1,
    Cone_0,
    Cone_1,
    Cube,
    Plane,
    Disk_0,
    Disk_1,
    Cylinder_0,
    Cylinder_1,
    Utah_Teapot,
    Suzanne,
}

Builtin_Shader :: enum u8 {
    Default_VS,
    Default_VS_Sprite,

    Default_PS,
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
get_builtin_shader :: proc(id: Builtin_Shader) -> Shader_Handle {
    return _state.builtin_shader[id]
}

_load_builtin_assets :: proc() {
    register_file_data("CGA8x8thick.png",    #load("data/CGA8x8thick.png"))
    register_file_data("CGA8x8thin.png",     #load("data/CGA8x8thin.png"))
    register_file_data("default.png",        #load("data/default.png"))
    register_file_data("error.png",          #load("data/error.png"))
    register_file_data("white.png",          #load("data/white.png"))

    default_pool, default_pool_ok := create_texture_pool(128, 64)
    assert(default_pool_ok)
    assert(default_pool != {})
    _h, _ok := base.pool_get(&_state.texture_pools, default_pool)
    log_dump(default_pool)
    log_dump(base.pool_has(_state.texture_pools, default_pool))
    log_dump(_h)
    assert(_h != {})
    assert(_ok)

    for &tex, id in _state.builtin_texture {
        tex = load_texture(ufmt.tprintf("%s.png", enum_to_string(id)), pool_handle = default_pool) or_else panic("Failed to load builtin texture")
    }

    default_sprite_vs: []byte
    default_vs: []byte
    default_ps: []byte

    when gpu.BACKEND ==  gpu.BACKEND_D3D11 {
        default_sprite_vs = #load("data/default_sprite.vs.hlsl.dxbc")
        default_vs = #load("data/default.vs.hlsl.dxbc")
        default_ps = #load("data/default.ps.hlsl.dxbc")
    } else when gpu.BACKEND == gpu.BACKEND_WGPU {
        default_sprite_vs = #load("data/default_sprite.vs.hlsl.wgsl")
        default_vs = #load("data/default.vs.hlsl.wgsl")
        default_ps = #load("data/default.ps.hlsl.wgsl")
    }

    _state.builtin_shader = {
        .Default_VS = create_shader_from_bin("default.vs.hlsl", default_vs) or_else panic("Failed to load default vertex shader"),
        .Default_VS_Sprite = create_shader_from_bin("default_sprite.vs.hlsl", default_sprite_vs) or_else panic("Failed to load default sprite vertex shader"),
        .Default_PS = create_shader_from_bin("default.ps.hlsl", default_ps) or_else panic("Failed to load default pixel shader"),
    }

    _state.builtin_arena = load_scene_from_data(
        #load("data/default.rscn", string),
        #load("data/default.rscn.bin"),
        arena_handle = {},
    ) or_else panic("Failed to load default scene")

    for &handle, id in _state.builtin_mesh {
        handle = find_mesh_by_name(enum_to_string(id)) or_else panic("Failed to get builtin mesh")
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

    p := [2]f32{
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
hash_name :: #force_inline proc "contextless" (name: string) -> u64 {
    hash := base.hash_fnv64a(transmute([]byte)name, seed = HASH_SEED)
    return hash == 0 ? 1 : hash
}

@(require_results)
hash_const_name :: #force_inline proc "contextless" ($Name: string) -> u64 {
    hash: u64 = #hash(Name, HASH_ALG)
    return u64(hash == 0 ? 1 : hash)
}

@(require_results)
get_screen_size :: proc() -> [2]f32 {
    return {f32(_state.screen_size.x), f32(_state.screen_size.y)}
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Arena
//

@(require_results)
_get_arena :: proc(handle: Arena_Handle) -> (result: ^Arena, ok: bool) {
    return base.pool_get(&_state.arenas, handle)
}

@(require_results)
create_arena :: proc(
    usage:                          Arena_Usage,
    #any_int max_mesh_verts:        i32 = 1024 * 1024,
    #any_int max_mesh_indices:      i32 = 1024 * 1024,
    #any_int max_spline_verts:      i32 = 1024 * 8,
    #any_int collision_arena_size:  u64 = 1024 * 1024,
) -> (result: Arena_Handle, ok: bool) #optional_ok {
    handle := base.pool_find_free(_state.arenas) or_return

    arena := Arena{
        usage = usage,
        spline_vert_buf     = runtime.make_aligned([]Spline_Vertex, max_spline_verts, 4096, _state.allocator),
        vert_upload_buf     = runtime.make_aligned([]Vertex, max_mesh_verts, 4096, _state.allocator),
        index_upload_buf    = runtime.make_aligned([]Vertex_Index, max_mesh_indices, 4096, _state.allocator),
        collision_arena     = collision.create_arena(collision_arena_size, _state.allocator),
        spline_vert_num     = 0,
        object_child_num    = 0,
        ibuf                = {},
        vbuf                = {},
        vert_upload_offs    = 0,
        index_upload_offs   = 0,
        dirty               = false,
    }

    switch usage {
    case .Dynamic:
        arena.vbuf, ok = gpu.create_buffer("rv-arena-vert-buf",
            stride  = size_of(Vertex),
            size    = size_of(Vertex) * max_mesh_verts,
            usage   = .Default,
        )

        assert(ok)
        assert(arena.vbuf != {})

        arena.ibuf, ok = gpu.create_index_buffer("rv-arena-index-buf",
            size = size_of(Vertex_Index) * max_mesh_indices,
            usage = .Default,
        )

        assert(ok)
        assert(arena.ibuf != {})

    case .Static:
        // GPU buffers will be created later
    }

    base.pool_insert(&_state.arenas, handle, arena) or_else panic("Failed to insert arena")
    return handle, true
}

clear_arena :: proc(handle: Arena_Handle) {
    arena, arena_ok := _get_arena(handle)
    if !arena_ok {
        return
    }

    assert(arena.usage == .Dynamic)
    if arena.usage != .Dynamic {
        return
    }

    free_all(collision.arena_allocator(arena.collision_arena))

    arena.spline_vert_num = 0
    arena.object_child_num = 0
    arena.vert_upload_offs = 0
    arena.index_upload_offs = 0
}

// NOTE: doesn't clear!
flush_arena_gpu_buffers :: proc(handle: Arena_Handle) {
    arena, arena_ok := _get_arena(handle)
    if !arena_ok || !arena.dirty {
        return
    }

    arena.dirty = false

    base.log_info("Flushing arena GPU buffers")

    switch arena.usage {
    case .Dynamic:
        gpu.update_buffer(arena.vbuf, offset = 0, buffers = {
            gpu.slice_bytes(arena.vert_upload_buf),
        })

        gpu.update_buffer(arena.ibuf, offset = 0, buffers = {
            gpu.slice_bytes(arena.index_upload_buf),
        })

    case .Static:
        gpu.destroy_resource(arena.vbuf)
        gpu.destroy_resource(arena.ibuf)

        ok: bool

        assert(arena.vert_upload_offs > 0)
        assert(arena.index_upload_offs > 0)

        arena.vbuf, ok = gpu.create_buffer("rv-arena-vert-buf",
            stride  = size_of(Vertex),
            usage   = .Immutable,
            data = gpu.slice_bytes(arena.vert_upload_buf[:arena.vert_upload_offs]),
        )
        assert(ok)

        arena.ibuf, ok = gpu.create_index_buffer("rv-arena-index-buf",
            usage = .Immutable,
            data = gpu.slice_bytes(arena.index_upload_buf[:arena.index_upload_offs]),
        )
        assert(ok)

    case:
        assert(false)
    }

    assert(arena.vbuf != {})
    assert(arena.ibuf != {})
}

destroy_arena :: proc(handle: Arena_Handle) -> bool {
    arena := _get_arena(handle) or_return

    gpu.destroy_resource(arena.vbuf) or_return
    gpu.destroy_resource(arena.ibuf) or_return

    // for i in 0..<MAX_MESHES {
    //     mesh := &_state.meshes[i]
    //     if mesh.arena != handle {
    //         continue
    //     }

    //     mesh^ = {}
    //     _state.meshes_hash[i] = 0
    //     _state.meshes_gen[i] += 1
    // }

    // for i in 0..<MAX_SPLINES {
    //     spline := &_state.splines[i]
    //     if spline.arena != handle {
    //         continue
    //     }

    //     spline^ = {}
    //     _state.splines_hash[i] = 0
    //     _state.splines_gen[i] += 1
    // }

    _delete_arena_buffers(arena)
    base.pool_remove(&_state.arenas, handle) or_return
    return true
}

_delete_arena_buffers :: proc(arena: ^Arena) {
    delete(arena.spline_vert_buf, _state.allocator)
    delete(arena.vert_upload_buf, _state.allocator)
    delete(arena.index_upload_buf, _state.allocator)
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Scene
//

load_scene :: proc(path: string, arena_handle: Arena_Handle = {}) -> (result_arena: Arena_Handle, ok: bool) {
    bin_path := strings_join(path, ".bin", allocator = context.temp_allocator)
    txt_data, txt_ok := read_file(path)
    bin_data, bin_ok := read_file(bin_path)

    if !txt_ok {
        base.log_err("Failed to load scene, '%s' is missing", path)
        return {}, false
    }

    if !bin_ok {
        base.log_err("Failed to load scene, '%s' is missing", bin_path)
        return {}, false
    }

    return load_scene_from_data(string(txt_data), bin_data, arena_handle = arena_handle)
}

load_scene_from_data :: proc(txt: string, bin: []byte, arena_handle: Arena_Handle) -> (result_arena: Arena_Handle, ok: bool) {
    arena_handle := arena_handle
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

    if arena_handle == {} {
        arena_handle = create_arena(
            usage = .Static,
            max_mesh_verts = len(vert_buf),
            max_mesh_indices = len(index_buf),
            max_spline_verts = len(spline_vert_buf),
        )
    }

    vertices := make([]Vertex, len(vert_buf), _state.allocator)
    for i in 0..<len(vertices) {
        v := vert_buf[i]

        col: [4]f32
        col.rgb = cast([3]f32)v.color * (1.0 / 255.0)
        col.a = 1

        vertices[i] = pack_vertex(
            pos = v.pos,
            uv = v.uv,
            normal = unpack_unorm8(v.normal.xyzz).xyz * 2.0 - 1.0,
            col = col,
        )
    }

    arena: ^Arena
    arena, ok = _get_arena(arena_handle)

    if !ok {
        base.log_err("Failed to load scene: Invalid target arena handle")
        return {}, false
    }

    mesh_list := make([]Mesh_Handle, header.object_num, context.temp_allocator)
    spline_list := make([]Spline_Handle, header.object_num, context.temp_allocator)

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
            _, ok = find_texture_by_name(v.path)
            if !ok {
                continue
            }
            load_texture(v.path)

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
            )

        case rscn.Spline:
            base.log_debug("Skipping Spline: %s", v.name)

        case rscn.Object:
            // Not supported yet
            base.log_debug("Skipping Object: %s", v.name)
        }
    }

    return arena_handle, true
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Lookups
//

@(require_results)
find_mesh_by_name :: proc(name: string) -> (result: Mesh_Handle, ok: bool) #optional_ok {
    return find_mesh_by_hash(hash_name(name))
}

@(require_results)
find_mesh_by_hash :: proc(hash: u64) -> (result: Mesh_Handle, ok: bool) #optional_ok {
    result, _, ok = base.hash_pool_find(&_state.meshes, hash)
    return
}

@(require_results)
find_texture_by_name :: proc(name: string) -> (result: Texture_Handle, ok: bool) #optional_ok {
    return find_texture_by_hash(hash_name(name))
}

@(require_results)
find_texture_by_hash :: proc(hash: u64) -> (result: Texture_Handle, ok: bool) #optional_ok {
    result, _, ok = base.hash_pool_find(&_state.textures, hash)
    return
}

@(require_results)
find_spline_by_name :: proc(name: string) -> (result: Spline_Handle, ok: bool) #optional_ok {
    return find_spline_by_hash(hash_name(name))
}

@(require_results)
find_spline_by_hash :: proc(hash: u64) -> (result: Spline_Handle, ok: bool) #optional_ok {
    result, _, ok = base.hash_pool_find(&_state.splines, hash)
    return
}

@(require_results)
find_shader_by_name :: proc(name: string) -> (result: Shader_Handle, ok: bool) #optional_ok {
    return find_shader_by_hash(hash_name(name))
}

@(require_results)
find_shader_by_hash :: proc(hash: u64) -> (result: Shader_Handle, ok: bool) #optional_ok {
    result, _, ok = base.hash_pool_find(&_state.shaders, hash)
    return
}

@(require_results)
_get_draw_layer :: proc(#any_int index: i32) -> (result: ^Draw_Layer, ok: bool) {
    if index < 0 || index >= MAX_DRAW_LAYERS {
        return nil, false
    }
    return &_state.draw_layers[index], true
}

@(require_results)
_get_mesh :: proc(handle: Mesh_Handle) -> (result: ^Mesh, ok: bool) {
    return base.hash_pool_get(&_state.meshes, handle)
}

@(require_results)
_get_spline :: proc(handle: Spline_Handle) -> (result: ^Spline, ok: bool) {
    return base.hash_pool_get(&_state.splines, handle)
}

@(require_results)
_get_shader :: proc(handle: Shader_Handle) -> (result: ^Shader, ok: bool) {
    return base.hash_pool_get(&_state.shaders, handle)
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Collision
//

invalidate_collision_mesh :: proc(mesh_handle: Mesh_Handle) {
    mesh, mesh_ok := _get_mesh(mesh_handle)
    if !mesh_ok {
        base.log_err("Failed to create collision mesh, invalid mesh handle")
        return
    }
    mesh.collision_mesh = {}
}

get_or_create_collision_mesh :: proc(mesh_handle: Mesh_Handle) -> (result: collision.Mesh_Handle, ok: bool) #optional_ok {
    #assert(size_of(Vertex_Index) == size_of(u16))

    mesh, mesh_ok := _get_mesh(mesh_handle)
    if !mesh_ok {
        base.log_err("Failed to create collision mesh, invalid mesh handle")
        return {}, false
    }

    if mesh.collision_mesh != {} {
        return mesh.collision_mesh, true
    }

    arena, arena_ok := _get_arena(mesh.arena)
    assert(arena_ok)
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

    return result, true
}





/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Sounds
//

get_sound_resource :: proc(handle: Sound_Resource_Handle) -> (result: audio.Resource_Handle, ok: bool) #optional_ok {
    res := base.hash_pool_get(&_state.sound_resources, handle) or_return
    return res.resource, true
}

load_sound_resource :: proc(path: string) -> (result: Sound_Resource_Handle, ok: bool) #optional_ok {
    name := asset_name_from_path(path)
    data, data_ok := read_file(path)
    if !data_ok {
        base.log_err("Failed to load sound resource '%s' from '%s', VFS file not found", name, path)
        return {}, false
    }
    return create_sound_resource_encoded(name, data)
}

create_sound_resource_encoded :: proc(name: string, data: []byte) -> (result: Sound_Resource_Handle, ok: bool) #optional_ok {
    base.log_info("Creating sound resource '%s' with size %i bytes", name, len(data))

    hash := hash_name(name)
    handle, exists := base.hash_pool_find_free(_state.sound_resources, hash) or_return
    assert(!exists)

    res := audio.create_resource(.WAV, data) or_return

    state := Sound_Resource_State {
        resource = res,
    }

    base.hash_pool_insert(&_state.sound_resources, hash, handle, state) or_return
    return handle, true
}

destroy_sound_resource :: proc(handle: Sound_Resource_Handle) -> bool {
    res := get_sound_resource(handle) or_return
    audio.destroy_resource(res) or_return
    base.hash_pool_remove(&_state.sound_resources, handle) or_return
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

// Convert VFS path to an asset name by stripping the directory and the last extension, for example:
// foo/bar/something.bin -> something
// foo.ps.hlsl -> foo.ps
@(require_results)
asset_name_from_path :: proc "contextless" (str: string) -> (result: string) {
    file_name := file_name_from_path(str)
    dot_index := bytes.last_index_byte(transmute([]byte)file_name, '.')
    return file_name[:dot_index]
}

@(require_results)
file_name_from_path :: proc "contextless" (str: string) -> string {
    back_index := bytes.last_index_byte(transmute([]byte)str,'\\')
    forw_index := bytes.last_index_byte(transmute([]byte)str,'/')
    return str[max(back_index, forw_index) + 1:]
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

    when DEBUG_TRACE_ENABLED {
        if _state != nil {
            runtime.print_string("Debug Stack Trace:\n")

            cap := debug_trace.capture(skip = 1)
            locs, err := debug_trace.resolve(cap, context.temp_allocator, context.temp_allocator)

            if err != .None {
                runtime.print_string("Error resolving stack trace:")
                switch err {
                case .None: runtime.print_string("None")
                case .Allocator_Error: runtime.print_string("Allocator_Error")
                case .Parse_Address_Failed: runtime.print_string("Parse_Address_Failed")
                case .Resolve_Aborted: runtime.print_string("Resolve_Aborted")
                }
                runtime.print_string("\n")
            } else {
                for l, i in locs {
                    if l.file_path == "" && l.line == 0 {
                        continue
                    }
                    runtime.print_int(i)
                    runtime.print_string(" : ")
                    runtime.print_caller_location(l)
                    runtime.print_string(" ")
                    runtime.print_string(l.procedure)
                    runtime.print_byte('\n')
                }
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

// No UV precision loss up to 2048x2048 textures.
// Input in range -16..16
@(require_results)
pack_uv_unorm16 :: proc "contextless" (val: [2]f32) -> [2]u16 {
    return #force_inline pack_unorm16((val + 16.0) * (1.0 / 32.0))
}

@(require_results)
unpack_uv_unorm16 :: proc "contextless" (val: [2]u16) -> [2]f32 {
    return #force_inline unpack_unorm16(val) * 32.0 - 16.0
}

@(require_results)
pack_normal_octahedral_unorm8 :: proc "contextless" (val: [3]f32) -> [2]u8 {
    return pack_unorm8(encode_octahedral(val).xyyy).xy
}

@(require_results)
unpack_normal_octahedral_unorm8 :: proc "contextless" (val: [2]u8) -> [3]f32 {
    return decode_octahedral(unpack_unorm8(val.xyyy).xy)
}

@(require_results)
_wrap_octahedral :: proc "contextless" (v: [2]f32) -> [2]f32 {
    f: [2]f32
    f.x = v.x >= 0 ? 1 : -1
    f.y = v.y >= 0 ? 1 : -1
    return (1.0 - linalg.abs(v.yx)) * f
}

// Input is vector from a sphere.
// Output is in range 0..1
@(require_results)
encode_octahedral :: proc "contextless" (n: [3]f32) -> [2]f32 {
    n := n
    n /= (abs(n.x) + abs(n.y) + abs(n.z))
    n.xy = n.z >= 0.0 ? n.xy : cast([2]f32)_wrap_octahedral(n.xy)
    return n.xy * 0.5 + 0.5
}

// Result is normalized vector on a sphere
@(require_results)
decode_octahedral :: proc "contextless" (f: [2]f32) -> [3]f32 {
    f := f
    f = f * 2.0 - 1.0
    // https://twitter.com/Stubbesaurus/status/937994790553227264
    n := [3]f32{f.x, f.y, 1.0 - abs(f.x) - abs(f.y)}
    t: f32 = clamp(-n.z, 0, 1)
    n.x += n.x >= 0 ? -t : t
    n.y += n.y >= 0 ? -t : t
    return linalg.normalize(n)
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
    pos:        [3]f32,
    uv:         [2]f32 = 0,
    normal:     [3]f32 = {0, 1, 0},
    col:        [4]f32 = 1,
    joints:     [4]u8 = 0,
    weights:    [4]f32 = {1, 0, 0, 0},
) -> Vertex {
    return {
        pos = pos,
        uv = pack_uv_unorm16(uv),
        normal = pack_normal_octahedral_unorm8(normal.xyz),
        col = pack_unorm8(col),
        joints = joints,
        weights = pack_unorm8(weights),
    }
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
draw_perf_counter :: proc(kind: Perf_Counter_Kind, pos: [3]f32, scale: f32 = 1, col: [4]f32 = 1, show_text := true) {
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

draw_perf_scopes :: proc(pos: [3]f32 = {10, 40, 0.1}, scale: f32 = 1) {
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
        shadow_offs := max(1, math.round(scale))

        for scope, i in scopes {
            p := pos + [3]f32{0, f32(i) * 16 * scale, 0}

            ms := f32(f64(scope.cycles) * cycles_to_ms)
            width := max(1, clamp(ms, 0, 16) * 10) * scale

            text := base.tprintf("%s: %f ms", scope.name, ms)
            draw_text(text, p, scale = {scale, scale})
            draw_text(text, p + {shadow_offs, shadow_offs, 0.001}, col = BLACK, scale = {scale, scale})
            draw_sprite(p + {-5 * scale, 5 * scale, 0.01}, rect, {width, 16 * scale}, anchor = {-1, 0},
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
    case 32: return ' '
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
