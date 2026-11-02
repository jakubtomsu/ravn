#+vet explicit-allocators style unused shadowing
package ravn_debugdraw

import "core:mem"
import "core:slice"
import "core:log"
import "base:intrinsics"
import "base:runtime"
import "../gpu"

ENABLED :: #config(DEBUGDRAW_ENABLED, true)
LANES :: 32

_state: ^State

// Buffers share the actual GPU draw elem buffer and pipeline based on layout.
// Within one layout only offsets and extra bindings are necessary.
State :: struct {
    allocator:    runtime.Allocator,

    target_color:       gpu.Resource_Handle,
    target_depth:       gpu.Resource_Handle,
    vert_buf:           gpu.Resource_Handle,
    shape_inst_buf:     gpu.Resource_Handle,
    shape_model_vbuf:   gpu.Resource_Handle,
    shape_offsets:      [Shape_Buffer_Kind]u32,
    consts:             gpu.Resource_Handle,

    ps:                 gpu.Shader_Handle,
    vert_vs:            gpu.Shader_Handle,
    shape_vs:           gpu.Shader_Handle,

    line_pip:           gpu.Graphics_Pipeline_Handle,
    tri_pip:            gpu.Graphics_Pipeline_Handle,
    shape_pip:          gpu.Graphics_Pipeline_Handle,
    binds:              gpu.Bind_Group_Handle,
    bind_layout:        gpu.Bind_Layout_Handle,

    vert_buffers:       [Vertex_Buffer_Kind]Buffer(Vertex),
    shape_buffers:      [Shape_Buffer_Kind] Buffer(Shape_Instance),
}

Vertex_Buffer_Kind :: enum u8 {
    Line,
    Solid_Tri,
}

Shape_Buffer_Kind :: enum u8 {
    Line_Box,
    Line_Circle,
    Line_Half_Circle,
    Line_Sphere,
    Line_Cone,
    Line_Cylinder,
    Solid_Box,
    Solid_Circle,
    Solid_Sphere,
    Solid_Hemisphere,
    Solid_Cone,
    Solid_Cylinder,
}

BUFFER_PERSISTENT_FILTER_PER_FRAME :: 1024

Buffer :: struct($T: typeid) {
    upload_offset:          u32,

    immediate_exhausted:    bool, // Set to true if you try to push data over capacity.
    immediate_buf:          []T,
    immediate_offs:         u32,

    persistent_exhausted:   bool, // Set to true if you try to push data over capacity.
    persistent_buf:         []T,
    persistent_offs:        u32,
    persistent_timers:      []f16,
    persistent_filter_offs: u32,
}

Constants :: struct {
    proj:   matrix[4, 4]f32,
}

Shape_Instance :: struct {
    pos:    [3]f32,
    col:    [4]u8 `gpu:"U8x4_Norm"`,
    mat_x:  [4]f16,
    mat_y:  [4]f16,
    mat_z:  [4]f16,
    _pad:   [4]f16,
}

Shape_Vertex :: [4]f32

Vertex :: struct {
    pos:    [3]f32,
    col:    [4]u8 `gpu:"U8x4_Norm"`,
}

DEFAULT_VERTEX_BUFFER_CAPS :: [Vertex_Buffer_Kind]int{
    .Line       = 1024 * 16,
    .Solid_Tri  = 1024 * 16,
}

DEFAULT_SHAPE_BUFFER_CAPS :: [Shape_Buffer_Kind]int{
    .Line_Box           = 1024 * 16,
    .Line_Circle        = 1024 * 8,
    .Line_Half_Circle   = 1024 * 8,
    .Line_Sphere        = 1024 * 16,
    .Line_Cone          = 1024 * 8,
    .Line_Cylinder      = 1024 * 8,
    .Solid_Box          = 1024 * 16,
    .Solid_Circle       = 1024 * 8,
    .Solid_Sphere       = 1024 * 16,
    .Solid_Hemisphere   = 1024 * 8,
    .Solid_Cone         = 1024 * 8,
    .Solid_Cylinder     = 1024 * 8,
}



// MARK: Core

init :: proc(
    state:              ^State = nil,
    target_color:       gpu.Resource_Handle,
    target_depth:       gpu.Resource_Handle = {},
    vert_buffer_caps    := DEFAULT_VERTEX_BUFFER_CAPS,
    shape_buffer_caps   := DEFAULT_SHAPE_BUFFER_CAPS,
    allocator           := context.allocator,
) -> bool {
    state := state

    if _state != nil {
        return false
    }

    if gpu.get_resource_kind(target_color) != .Texture2D {
        log.error("Target color must be a valid color texture")
        return false
    }

    if format, format_ok := gpu.get_texture_format(target_depth); format_ok {
        if !gpu.is_texture_format_depth_stencil(format) {
            log.error("If depth texture is provided it must be depth format")
            return false
        }
    }

    if state == nil {
        state = new(State, allocator)
    }

    _state = state

    _state.allocator = allocator
    _state.target_color = target_color
    _state.target_depth = target_depth

    main_ps_bin: []byte
    vert_vs_bin: []byte
    shape_vs_bin: []byte

    when gpu.BACKEND == gpu.BACKEND_D3D11 {
        main_ps_bin     = #load("data/main.ps.dxbc")
        vert_vs_bin     = #load("data/vert.vs.dxbc")
        shape_vs_bin    = #load("data/shape.vs.dxbc")
    } else when gpu.BACKEND == gpu.BACKEND_WGPU {
        main_ps_bin     = #load("data/main.ps.wgsl")
        vert_vs_bin     = #load("data/vert.vs.wgsl")
        shape_vs_bin    = #load("data/shape.vs.wgsl")
    } else {
        panic("Shaders are missing for this GPU backend")
    }

    if !gpu.create_shader(&_state.ps, main_ps_bin, .Pixel) {
        log.error("Failed to create shader main_ps")
        return false
    }

    if !gpu.create_shader(&_state.vert_vs, vert_vs_bin, .Vertex) {
        log.error("Failed to create shader vert_vs")
        return false
    }

    if !gpu.create_shader(&_state.shape_vs, shape_vs_bin, .Vertex) {
        log.error("Failed to create shader shape_vs")
        return false
    }


    base_pip_desc := gpu.make_graphics_pipeline_desc(
        vs = {},
        ps = _state.ps,
        vertex_layouts = {},
        out_colors = {
            0 = gpu.get_texture_format(_state.target_color),
        },
        out_depth = gpu.get_texture_format(_state.target_depth) or_else .Invalid,
        blends = {
            0 = gpu.BLEND_ALPHA,
        },
        topo = .Invalid,
    )

    {
        pip_desc := base_pip_desc
        pip_desc.topo = .Lines
        pip_desc.vs = _state.vert_vs
        pip_desc.vertex_layouts = {
            0 = gpu.make_vertex_layout(Vertex, .Vertex),
        }

        if !gpu.create_graphics_pipeline(&_state.line_pip, pip_desc) {
            return false
        }
    }

    {
        pip_desc := base_pip_desc
        pip_desc.topo = .Triangles
        pip_desc.vs = _state.vert_vs
        pip_desc.vertex_layouts = {
            0 = gpu.make_vertex_layout(Vertex, .Vertex),
        }

        if !gpu.create_graphics_pipeline(&_state.tri_pip, pip_desc) {
            return false
        }
    }

    {
        pip_desc := base_pip_desc
        pip_desc.topo = .Triangles
        pip_desc.vs = _state.shape_vs
        pip_desc.cull = .Back
        pip_desc.vertex_layouts = {
            0 = gpu.make_vertex_layout(Shape_Vertex, .Vertex),
            1 = gpu.make_vertex_layout(Shape_Instance, .Instance),
        }

        if !gpu.create_graphics_pipeline(&_state.shape_pip, pip_desc) {
            return false
        }
    }

    total_vert_cap: int
    for cap in vert_buffer_caps {
        total_vert_cap += cap
    }

    total_shape_cap: int
    for cap in shape_buffer_caps {
        total_shape_cap += cap
    }

    if !gpu.create_buffer(&_state.shape_inst_buf,
        kind = .Vertex,
        stride = size_of(Shape_Instance),
        size = size_of(Shape_Instance) * int(total_shape_cap),
        usage = .Dynamic,
    ) {
        log.error("Failed to create shape buffer")
        return false
    }

    if !gpu.create_buffer(&_state.vert_buf,
        kind = .Vertex,
        stride = size_of(Shape_Instance),
        size = size_of(Shape_Instance) * int(total_vert_cap),
        usage = .Dynamic,
    ) {
        log.error("Failed to create vert buffer")
        return false
    }

    shape_verts: [dynamic]Shape_Vertex
    shape_verts.allocator = context.temp_allocator

    for buf, kind in _buffer_shape_verts {
        _state.shape_offsets[kind] = u32(len(shape_verts))
        append(&shape_verts, ..buf)
    }

    if !gpu.create_buffer(&_state.shape_model_vbuf,
        kind = .Vertex,
        stride = size_of(Shape_Vertex),
        data = slice.to_bytes(shape_verts[:]),
        usage = .Immutable,
    ) {
        return false
    }

    for &buf, kind in _state.vert_buffers {
        buffer_init(&buf, vert_buffer_caps[kind], allocator = allocator)
    }

    for &buf, kind in _state.shape_buffers {
        buffer_init(&buf, shape_buffer_caps[kind], allocator = allocator)
    }

    return true
}

shutdown :: proc() {
    if _state == nil {
        return
    }

    for &buf in _state.vert_buffers {
        buffer_destroy(&buf, allocator = _state.allocator)
    }

    for &buf in _state.shape_buffers {
        buffer_destroy(&buf, allocator = _state.allocator)
    }

    free(_state, _state.allocator)

    _state = nil
}



// MARK: Render

render_frame :: proc(camera_proj: matrix[4, 4]f32, delta: f32) {
    context.allocator = runtime.panic_allocator()

    upload_buffers(&_state.vert_buffers, _state.vert_buf)
    upload_buffers(&_state.shape_buffers, _state.shape_inst_buf)
    gpu.update_constants(_state.consts, mem.ptr_to_bytes(&Constants{
        proj = camera_proj,
    }))

    gpu.begin_graphics_pass("ravn_debugdraw", gpu.Graphics_Pass_Desc{
        colors = {
            0 = { resource = _state.target_color, clear_mode = .Keep },
        },
        depth = { resource = _state.target_depth, clear_mode = .Keep },
    })

    {
        gpu.set_graphics_pipeline(_state.line_pip)
        gpu.set_vertex_buffer(0, _state.vert_buf)
        draw_vert_buffer(_state.vert_buffers[.Line])
    }

    {
        gpu.set_graphics_pipeline(_state.tri_pip)
        gpu.set_vertex_buffer(0, _state.vert_buf)
        draw_vert_buffer(_state.vert_buffers[.Solid_Tri])
    }

    {
        gpu.set_graphics_pipeline(_state.shape_pip)
        gpu.set_vertex_buffer(0, _state.shape_model_vbuf)
        gpu.set_vertex_buffer(1, _state.shape_inst_buf)

        for buf, kind in _state.shape_buffers {
            draw_inst_buffer(buf, len(_buffer_shape_verts[kind]))
        }
    }

    gpu.end_graphics_pass()

    for &b in _state.vert_buffers {
        buffer_flush(&b, delta)
    }

    for &b in _state.shape_buffers {
        buffer_flush(&b, delta)
    }
}

upload_buffers :: proc(bufs: ^$Arr/[$K]Buffer($E), res: gpu.Resource_Handle) {
    upload_offset: u32
    upload_bufs: [dynamic][]byte
    upload_bufs.allocator = context.temp_allocator

    for &buf in bufs {
        buf.upload_offset = upload_offset
        upload_offset += buf.immediate_offs + buf.persistent_offs
        append(&upload_bufs, slice.to_bytes(buf.immediate_buf[:buf.immediate_offs]))
        append(&upload_bufs, slice.to_bytes(buf.persistent_buf[:buf.persistent_offs]))
    }

    gpu.update_buffer(res, offset = 0, buffers = upload_bufs[:]) or_else panic("upload")
}

draw_vert_buffer :: proc(buf: $T/Buffer($E)) {
    gpu.draw_non_indexed(
        vertex_num = int(buf.immediate_offs + buf.persistent_offs),
        instance_num = 1,
        vertex_offset = int(buf.upload_offset),
        instance_offset = 0,
    )
}

draw_inst_buffer :: proc(buf: $T/Buffer($E), vert_num: int) {
    gpu.draw_non_indexed(
        vertex_num = vert_num,
        instance_num = int(buf.immediate_offs + buf.persistent_offs),
        vertex_offset = 0,
        instance_offset = int(buf.upload_offset),
    )
}



// MARK: line drawing

line :: proc(
    pos0:   [3]f32,
    pos1:   [3]f32,
    col:    [2][4]f32 = 1,
    time:   f32 = 0,
) {
    #force_inline buffer_push(&_state.vert_buffers[.Line], Vertex{ pos = pos0, col = cast([4]u8)(col[0] * 255) }, time = time)
    #force_inline buffer_push(&_state.vert_buffers[.Line], Vertex{ pos = pos1, col = cast([4]u8)(col[1] * 255) }, time = time)
}

tri :: proc()
box :: proc()
circle :: proc()
half_circle :: proc()
sphere :: proc()
cylinder :: proc()

// MARK: triangle drawing

solid_tri :: proc()

solid_box :: proc(
    pos:    [3]f32,
    col:    [4]f32,
    time:   f32 = 0,
) {
    // buffer_push(&_state.shape_buffers[.Solid_Box], inst, time = time)
}

solid_circle :: proc()
solid_sphere :: proc()
solid_hemisphere :: proc()
solid_cylinder :: proc()

// MARK: Util

capsule :: proc()
aabb :: proc()



// MARK: Buffer


buffer_init :: proc(buf: ^$T/Buffer($E), cap: int, allocator := context.allocator) {
    buf.immediate_buf  = make([]E, cap, allocator)
    buf.persistent_buf    = make([]E, cap, allocator)
    buf.persistent_timers = make([]f16, cap, allocator)
}

buffer_destroy :: proc(buf: ^$T/Buffer($E), allocator := context.allocator) {
    delete(buf.immediate_buf, allocator = allocator)
    delete(buf.persistent_buf, allocator = allocator)
    delete(buf.persistent_timers, allocator = allocator)
    buf^ = {}
}

buffer_push :: proc(buf: ^$T/Buffer($E), data: E, time: f32) #no_bounds_check {
    if time > 0 {
        if buf.persistent_offs >= u32(len(buf.persistent_buf)) {
            buf.persistent_exhausted = true
            return
        }

        buf.persistent_buf[buf.persistent_offs] = data
        buf.persistent_timers[buf.persistent_offs] = f16(time)
        buf.persistent_offs += 1

    } else {
        if buf.immediate_offs >= u32(len(buf.immediate_buf)) {
            buf.immediate_exhausted = true
            return
        }

        buf.immediate_buf[buf.immediate_offs] = data
        buf.immediate_offs += 1
    }
}

buffer_flush :: proc(buf: ^$T/Buffer($E), delta: f32) {
    buf.immediate_exhausted = false
    buf.persistent_exhausted = false

    buf.immediate_offs = 0

    for &timer in buf.persistent_timers[:buf.persistent_offs] {
        timer -= f16(delta)
    }

    // Filter fixed amount of old persistent elems
    filter_num := min(buf.persistent_offs, BUFFER_PERSISTENT_FILTER_PER_FRAME)
    for _ in 0..<filter_num {
        if buf.persistent_filter_offs >= buf.persistent_offs {
            buf.persistent_filter_offs = 0
        }

        if buf.persistent_timers[buf.persistent_filter_offs] < 0 {
            buf.persistent_offs -= 1
            buf.persistent_buf[buf.persistent_filter_offs] = buf.persistent_buf[buf.persistent_offs]
            buf.persistent_timers[buf.persistent_filter_offs] = buf.persistent_timers[buf.persistent_offs]
        }

        buf.persistent_filter_offs += 1
    }
}


// MARK: Data


@(rodata)
_buffer_shape_verts := [Shape_Buffer_Kind][]Shape_Vertex{
    .Line_Box = {
        {-1, -1, -1, 0}, { 1, -1, -1, 0},
        {-1, -1,  1, 0}, { 1, -1,  1, 0},
        {-1,  1, -1, 0}, { 1,  1, -1, 0},
        {-1,  1,  1, 0}, { 1,  1,  1, 0},

        {-1, -1, -1, 0}, {-1,  1, -1, 0},
        {-1, -1,  1, 0}, {-1,  1,  1, 0},
        { 1, -1, -1, 0}, { 1,  1, -1, 0},
        { 1, -1,  1, 0}, { 1,  1,  1, 0},

        {-1, -1, -1, 0}, {-1, -1,  1, 0},
        {-1,  1, -1, 0}, {-1,  1,  1, 0},
        { 1, -1, -1, 0}, { 1, -1,  1, 0},
        { 1,  1, -1, 0}, { 1,  1,  1, 0},
    },

    .Line_Circle = {
        {                       1,                        0, 0, 0}, {      0.9238795325112867,       0.3826834323650898, 0, 0},
        {      0.9238795325112867,       0.3826834323650898, 0, 0}, {      0.7071067811865476,       0.7071067811865476, 0, 0},
        {      0.7071067811865476,       0.7071067811865476, 0, 0}, {     0.38268343236508984,       0.9238795325112867, 0, 0},
        {     0.38268343236508984,       0.9238795325112867, 0, 0}, {   6.123233995736766e-17,                        1, 0, 0},
        {   6.123233995736766e-17,                        1, 0, 0}, {     -0.3826834323650897,       0.9238795325112867, 0, 0},
        {     -0.3826834323650897,       0.9238795325112867, 0, 0}, {     -0.7071067811865475,       0.7071067811865476, 0, 0},
        {     -0.7071067811865475,       0.7071067811865476, 0, 0}, {     -0.9238795325112867,       0.3826834323650899, 0, 0},
        {     -0.9238795325112867,       0.3826834323650899, 0, 0}, {                      -1,   1.2246467991473532e-16, 0, 0},
        {                      -1,   1.2246467991473532e-16, 0, 0}, {     -0.9238795325112868,     -0.38268343236508967, 0, 0},
        {     -0.9238795325112868,     -0.38268343236508967, 0, 0}, {     -0.7071067811865477,      -0.7071067811865475, 0, 0},
        {     -0.7071067811865477,      -0.7071067811865475, 0, 0}, {    -0.38268343236509034,      -0.9238795325112865, 0, 0},
        {    -0.38268343236509034,      -0.9238795325112865, 0, 0}, { -1.8369701987210297e-16,                       -1, 0, 0},
        { -1.8369701987210297e-16,                       -1, 0, 0}, {        0.38268343236509,      -0.9238795325112866, 0, 0},
        {        0.38268343236509,      -0.9238795325112866, 0, 0}, {      0.7071067811865474,      -0.7071067811865477, 0, 0},
        {      0.7071067811865474,      -0.7071067811865477, 0, 0}, {      0.9238795325112865,      -0.3826834323650904, 0, 0},
        {      0.9238795325112865,      -0.3826834323650904, 0, 0}, {                       1,                        0, 0, 0},
    },

    .Line_Half_Circle = {
        {                       1,                        0, 0, 0}, {      0.9238795325112867,       0.3826834323650898, 0, 0},
        {      0.9238795325112867,       0.3826834323650898, 0, 0}, {      0.7071067811865476,       0.7071067811865476, 0, 0},
        {      0.7071067811865476,       0.7071067811865476, 0, 0}, {     0.38268343236508984,       0.9238795325112867, 0, 0},
        {     0.38268343236508984,       0.9238795325112867, 0, 0}, {   6.123233995736766e-17,                        1, 0, 0},
        {   6.123233995736766e-17,                        1, 0, 0}, {     -0.3826834323650897,       0.9238795325112867, 0, 0},
        {     -0.3826834323650897,       0.9238795325112867, 0, 0}, {     -0.7071067811865475,       0.7071067811865476, 0, 0},
        {     -0.7071067811865475,       0.7071067811865476, 0, 0}, {     -0.9238795325112867,       0.3826834323650899, 0, 0},
        {     -0.9238795325112867,       0.3826834323650899, 0, 0}, {                      -1,   1.2246467991473532e-16, 0, 0},
    },

    .Line_Sphere = {
        {                       1,                        0, 0, 0}, {      0.9238795325112867,       0.3826834323650898, 0, 0},
        {      0.9238795325112867,       0.3826834323650898, 0, 0}, {      0.7071067811865476,       0.7071067811865476, 0, 0},
        {      0.7071067811865476,       0.7071067811865476, 0, 0}, {     0.38268343236508984,       0.9238795325112867, 0, 0},
        {     0.38268343236508984,       0.9238795325112867, 0, 0}, {   6.123233995736766e-17,                        1, 0, 0},
        {   6.123233995736766e-17,                        1, 0, 0}, {     -0.3826834323650897,       0.9238795325112867, 0, 0},
        {     -0.3826834323650897,       0.9238795325112867, 0, 0}, {     -0.7071067811865475,       0.7071067811865476, 0, 0},
        {     -0.7071067811865475,       0.7071067811865476, 0, 0}, {     -0.9238795325112867,       0.3826834323650899, 0, 0},
        {     -0.9238795325112867,       0.3826834323650899, 0, 0}, {                      -1,   1.2246467991473532e-16, 0, 0},
        {                      -1,   1.2246467991473532e-16, 0, 0}, {     -0.9238795325112868,     -0.38268343236508967, 0, 0},
        {     -0.9238795325112868,     -0.38268343236508967, 0, 0}, {     -0.7071067811865477,      -0.7071067811865475, 0, 0},
        {     -0.7071067811865477,      -0.7071067811865475, 0, 0}, {    -0.38268343236509034,      -0.9238795325112865, 0, 0},
        {    -0.38268343236509034,      -0.9238795325112865, 0, 0}, { -1.8369701987210297e-16,                       -1, 0, 0},
        { -1.8369701987210297e-16,                       -1, 0, 0}, {        0.38268343236509,      -0.9238795325112866, 0, 0},
        {        0.38268343236509,      -0.9238795325112866, 0, 0}, {      0.7071067811865474,      -0.7071067811865477, 0, 0},
        {      0.7071067811865474,      -0.7071067811865477, 0, 0}, {      0.9238795325112865,      -0.3826834323650904, 0, 0},
        {      0.9238795325112865,      -0.3826834323650904, 0, 0}, {                       1,                        0, 0, 0},

        {                       1, 0,                       0, 0}, {      0.9238795325112867, 0,       0.3826834323650898, 0},
        {      0.9238795325112867, 0,      0.3826834323650898, 0}, {      0.7071067811865476, 0,       0.7071067811865476, 0},
        {      0.7071067811865476, 0,      0.7071067811865476, 0}, {     0.38268343236508984, 0,       0.9238795325112867, 0},
        {     0.38268343236508984, 0,      0.9238795325112867, 0}, {   6.123233995736766e-17, 0,                        1, 0},
        {   6.123233995736766e-17, 0,                       1, 0}, {     -0.3826834323650897, 0,       0.9238795325112867, 0},
        {     -0.3826834323650897, 0,      0.9238795325112867, 0}, {     -0.7071067811865475, 0,       0.7071067811865476, 0},
        {     -0.7071067811865475, 0,      0.7071067811865476, 0}, {     -0.9238795325112867, 0,       0.3826834323650899, 0},
        {     -0.9238795325112867, 0,      0.3826834323650899, 0}, {                      -1, 0,   1.2246467991473532e-16, 0},
        {                      -1, 0,  1.2246467991473532e-16, 0}, {     -0.9238795325112868, 0,     -0.38268343236508967, 0},
        {     -0.9238795325112868, 0,    -0.38268343236508967, 0}, {     -0.7071067811865477, 0,      -0.7071067811865475, 0},
        {     -0.7071067811865477, 0,     -0.7071067811865475, 0}, {    -0.38268343236509034, 0,      -0.9238795325112865, 0},
        {    -0.38268343236509034, 0,     -0.9238795325112865, 0}, { -1.8369701987210297e-16, 0,                       -1, 0},
        { -1.8369701987210297e-16, 0,                      -1, 0}, {        0.38268343236509, 0,      -0.9238795325112866, 0},
        {        0.38268343236509, 0,     -0.9238795325112866, 0}, {      0.7071067811865474, 0,      -0.7071067811865477, 0},
        {      0.7071067811865474, 0,     -0.7071067811865477, 0}, {      0.9238795325112865, 0,      -0.3826834323650904, 0},
        {      0.9238795325112865, 0,     -0.3826834323650904, 0}, {                       1, 0,                        0, 0},

        {0,                       1,                        0, 0}, {0,       0.9238795325112867,       0.3826834323650898, 0},
        {0,      0.9238795325112867,       0.3826834323650898, 0}, {0,       0.7071067811865476,       0.7071067811865476, 0},
        {0,      0.7071067811865476,       0.7071067811865476, 0}, {0,      0.38268343236508984,       0.9238795325112867, 0},
        {0,     0.38268343236508984,       0.9238795325112867, 0}, {0,    6.123233995736766e-17,                        1, 0},
        {0,   6.123233995736766e-17,                        1, 0}, {0,      -0.3826834323650897,       0.9238795325112867, 0},
        {0,     -0.3826834323650897,       0.9238795325112867, 0}, {0,      -0.7071067811865475,       0.7071067811865476, 0},
        {0,     -0.7071067811865475,       0.7071067811865476, 0}, {0,      -0.9238795325112867,       0.3826834323650899, 0},
        {0,     -0.9238795325112867,       0.3826834323650899, 0}, {0,                       -1,   1.2246467991473532e-16, 0},
        {0,                      -1,   1.2246467991473532e-16, 0}, {0,      -0.9238795325112868,     -0.38268343236508967, 0},
        {0,     -0.9238795325112868,     -0.38268343236508967, 0}, {0,      -0.7071067811865477,      -0.7071067811865475, 0},
        {0,     -0.7071067811865477,      -0.7071067811865475, 0}, {0,     -0.38268343236509034,      -0.9238795325112865, 0},
        {0,    -0.38268343236509034,      -0.9238795325112865, 0}, {0,  -1.8369701987210297e-16,                       -1, 0},
        {0, -1.8369701987210297e-16,                       -1, 0}, {0,         0.38268343236509,      -0.9238795325112866, 0},
        {0,        0.38268343236509,      -0.9238795325112866, 0}, {0,       0.7071067811865474,      -0.7071067811865477, 0},
        {0,      0.7071067811865474,      -0.7071067811865477, 0}, {0,       0.9238795325112865,      -0.3826834323650904, 0},
        {0,      0.9238795325112865,      -0.3826834323650904, 0}, {0,                        1,                        0, 0},
    },

    .Line_Cone = {

    },

    .Line_Cylinder = {

    },

    .Solid_Box = {

    },

    .Solid_Circle = {

    },
    .Solid_Sphere = {

    },
    .Solid_Hemisphere = {

    },
    .Solid_Cone = {

    },
    .Solid_Cylinder = {

    },
}
