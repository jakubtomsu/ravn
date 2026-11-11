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
// TODO: split into transparent and opaque passes
State :: struct {
    allocator:              runtime.Allocator,
    state_allocator:        runtime.Allocator,
    uploaded_this_frame:    bool,

    target_color:           gpu.Resource_Handle,
    target_depth:           gpu.Resource_Handle,
    vert_buf:               gpu.Resource_Handle,
    shape_inst_buf:         gpu.Resource_Handle,
    shape_model_vbuf:       gpu.Resource_Handle,
    shape_offsets:          [Shape_Kind]u32,
    consts:                 gpu.Resource_Handle,

    ps:                     gpu.Shader_Handle,
    vert_vs:                gpu.Shader_Handle,
    shape_vs:               gpu.Shader_Handle,

    line_pip:               gpu.Graphics_Pipeline_Handle,
    tri_pip:                gpu.Graphics_Pipeline_Handle,
    line_shape_pip:         gpu.Graphics_Pipeline_Handle,
    tri_shape_pip:          gpu.Graphics_Pipeline_Handle,
    binds:                  gpu.Bind_Group_Handle,
    bind_layout:            gpu.Bind_Layout_Handle,

    line_buffer:            Buffer([2]Vertex),
    tri_buffer:             Buffer([3]Vertex),
    shape_buffers:          [Shape_Kind]Buffer(Shape_Instance),
}

Shape_Kind :: enum u8 {
    Line_Box,
    Line_Circle,
    Line_Sphere,
    Line_Hemisphere,
    Line_Cone,
    Line_Cylinder,
    Filled_Box,
    Filled_Circle,
    Filled_Sphere,
    Filled_Hemisphere,
    Filled_Cone,
    Filled_Cylinder,
}

SHAPE_BUFFER_LINE_KINDS :: bit_set[Shape_Kind]{
    .Line_Box,
    .Line_Circle,
    .Line_Sphere,
    .Line_Hemisphere,
    .Line_Cone,
    .Line_Cylinder,
}

@(init)
_check_shape_buffer_line_kinds :: proc "contextless" () {
    en := runtime.type_info_base(type_info_of(Shape_Kind)).variant.(^runtime.Type_Info_Enum)
    for name, i in en.names {
        if name[0] == 'L' {
            // Check if name is missing from SHAPE_BUFFER_LINE_KINDS
            assert_contextless(Shape_Kind(en.values[i]) in SHAPE_BUFFER_LINE_KINDS, name)
        }
    }
}

BUFFER_PERSISTENT_FILTER_PER_FRAME :: 1024

Buffer :: struct($T: typeid) {
    upload_elem_num:        u32,
    upload_elem_offset:     u32,

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

Shape_Instance :: struct #all_or_none {
    pos:    [3]f32,
    col:    [4]u8 `gpu:"U8x4_Norm"`,
    mat_x:  [4]f16,
    mat_y:  [4]f16,
    mat_z:  [4]f16,
    _:      [4]f16,
}

Shape_Vertex :: [4]f32

Vertex :: struct {
    pos:    [3]f32,
    col:    [4]u8 `gpu:"U8x4_Norm"`,
}

DEFAULT_SHAPE_BUFFER_CAPS :: [Shape_Kind]int{
    .Line_Box           = 1024 * 16,
    .Line_Circle        = 1024 * 8,
    .Line_Hemisphere    = 1024 * 8,
    .Line_Sphere        = 1024 * 16,
    .Line_Cone          = 1024 * 8,
    .Line_Cylinder      = 1024 * 8,
    .Filled_Box          = 1024 * 16,
    .Filled_Circle       = 1024 * 8,
    .Filled_Sphere       = 1024 * 16,
    .Filled_Hemisphere   = 1024 * 8,
    .Filled_Cone         = 1024 * 8,
    .Filled_Cylinder     = 1024 * 8,
}



// MARK: Core

init :: proc(
    state:              ^State = nil,
    target_color:       gpu.Resource_Handle = gpu.SWAPCHAIN_HANDLE,
    target_depth:       gpu.Resource_Handle = {},
    depth_comparison:   gpu.Comparison_Op = .Always,
    depth_write         := false,
    line_cap            := 1024 * 16,
    tri_cap             := 1024 * 16,
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
        state.state_allocator = allocator
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


    if !gpu.create_constants(&_state.consts, size_of(Constants)) {
        return false
    }

    if !gpu.create_bind_layout(&_state.bind_layout, gpu.Bind_Layout_Desc{
        {.Constants, {.Vertex}, {}},
    }) {
        return false
    }

    if !gpu.create_bind_group(&_state.binds, gpu.Bind_Group_Desc{
        layout = _state.bind_layout,
        slots = {{_state.consts, {}}},
    }) {
        return false
    }

    base_pip_desc := gpu.make_graphics_pipeline_desc(
        vs = {},
        ps = _state.ps,
        bind_layouts = { 0 = _state.bind_layout },
        vertex_layouts = {},
        color_formats = { gpu.get_texture_format(_state.target_color) },
        blends = { gpu.BLEND_ALPHA, },
        depth_format = gpu.get_texture_format(_state.target_depth) or_else .Invalid,
        topo = .Invalid,
        depth_comparison = depth_comparison,
        depth_write = depth_write,
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
        pip_desc.topo = .Lines
        pip_desc.vs = _state.shape_vs
        pip_desc.cull = .Back
        pip_desc.vertex_layouts = {
            0 = gpu.make_vertex_layout(Shape_Vertex, .Vertex),
            1 = gpu.make_vertex_layout(Shape_Instance, .Instance),
        }

        if !gpu.create_graphics_pipeline(&_state.line_shape_pip, pip_desc) {
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

        if !gpu.create_graphics_pipeline(&_state.tri_shape_pip, pip_desc) {
            return false
        }
    }

    total_vert_cap := tri_cap * 3 + line_cap * 2
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
        stride = size_of(Vertex),
        size = size_of(Vertex) * int(total_vert_cap),
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

    buffer_init(&_state.line_buffer, line_cap, allocator = allocator)
    buffer_init(&_state.tri_buffer, tri_cap, allocator = allocator)

    for &buf, kind in _state.shape_buffers {
        buffer_init(&buf, shape_buffer_caps[kind], allocator = allocator)
    }

    return true
}

shutdown :: proc() {
    if _state == nil {
        return
    }

    buffer_destroy(&_state.line_buffer, allocator = _state.allocator)
    buffer_destroy(&_state.tri_buffer, allocator = _state.allocator)

    for &buf in _state.shape_buffers {
        buffer_destroy(&buf, allocator = _state.allocator)
    }

    if _state.state_allocator != {} {
        free(_state, _state.state_allocator)
    }

    _state = nil
}



// MARK: Render

render_pass :: proc(
    camera_proj:        matrix[4, 4]f32,
    delta:              f32,
    color_clear_mode:   gpu.Clear_Mode = .Keep,
    color_clear_val:    [4]f32 = 0,
    depth_clear_mode:   gpu.Clear_Mode = .Keep,
    depth_clear_val:    f32 = 1,
) {
    context.allocator = runtime.panic_allocator()

    upload_frame(camera_proj = camera_proj, delta = delta)

    gpu.begin_graphics_pass("ravn_debugdraw", {
        colors = {
            0 = {
                resource = _state.target_color,
                clear_mode = color_clear_mode,
                clear_val = color_clear_val,
            },
        },
        depth = {
            resource = _state.target_depth,
            clear_mode = depth_clear_mode,
            clear_val = depth_clear_val,
        },
    })

    render_frame()

    gpu.end_graphics_pass()
}

upload_frame :: proc(camera_proj: matrix[4, 4]f32, delta: f32) {
    context.allocator = runtime.panic_allocator()

    assert(!_state.uploaded_this_frame)
    defer _state.uploaded_this_frame = true

    {
        buf := upload_buffers_make(context.temp_allocator)
        upload_buffers_push(&buf, &_state.line_buffer, elem_verts = 2)
        upload_buffers_push(&buf, &_state.tri_buffer, elem_verts = 3)
        gpu.update_buffer(_state.vert_buf, buffers = buf.bufs[:]) or_else panic("upload")
    }

    {
        buf := upload_buffers_make(context.temp_allocator)
        for &b in _state.shape_buffers {
            upload_buffers_push(&buf, &b)
        }
        gpu.update_buffer(_state.shape_inst_buf, buffers = buf.bufs[:]) or_else panic("upload")
    }

    gpu.update_constants(_state.consts, mem.ptr_to_bytes(&Constants{
        proj = camera_proj,
    }))

    buffer_flush(&_state.line_buffer, delta)
    buffer_flush(&_state.tri_buffer, delta)

    for &b in _state.shape_buffers {
        buffer_flush(&b, delta)
    }
}

render_frame :: proc() {
    context.allocator = runtime.panic_allocator()

    assert(_state.uploaded_this_frame)
    defer _state.uploaded_this_frame = false

    gpu.set_bind_group(0, _state.binds)

    {
        gpu.set_graphics_pipeline(_state.tri_pip)
        gpu.set_vertex_buffer(0, _state.vert_buf)
        draw_vert_buffer(_state.tri_buffer)
    }

    {
        gpu.set_graphics_pipeline(_state.tri_shape_pip)
        gpu.set_vertex_buffer(0, _state.shape_model_vbuf)
        gpu.set_vertex_buffer(1, _state.shape_inst_buf)

        for buf, kind in _state.shape_buffers {
            if kind not_in SHAPE_BUFFER_LINE_KINDS {
                draw_inst_buffer(buf, len(_buffer_shape_verts[kind]), vert_offset = int(_state.shape_offsets[kind]))
            }
        }
    }

    {
        gpu.set_graphics_pipeline(_state.line_pip)
        gpu.set_vertex_buffer(0, _state.vert_buf)
        draw_vert_buffer(_state.line_buffer)
    }

    {
        gpu.set_graphics_pipeline(_state.line_shape_pip)
        gpu.set_vertex_buffer(0, _state.shape_model_vbuf)
        gpu.set_vertex_buffer(1, _state.shape_inst_buf)

        for buf, kind in _state.shape_buffers {
            if kind in SHAPE_BUFFER_LINE_KINDS {
                draw_inst_buffer(buf, len(_buffer_shape_verts[kind]), vert_offset = int(_state.shape_offsets[kind]))
            }
        }
    }
}

draw_vert_buffer :: proc(buf: $T/Buffer($E)) {
    gpu.draw_non_indexed(
        vertex_num = int(buf.upload_elem_num),
        instance_num = 1,
        vertex_offset = int(buf.upload_elem_offset),
        instance_offset = 0,
    )
}

draw_inst_buffer :: proc(buf: $T/Buffer($E), vert_num: int, vert_offset: int) {
    gpu.draw_non_indexed(
        vertex_num = vert_num,
        instance_num = int(buf.upload_elem_num),
        vertex_offset = vert_offset,
        instance_offset = int(buf.upload_elem_offset),
    )
}



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

// MARK: Upload buffers

Upload_Buffers :: struct {
    offset: u32,
    bufs:   [dynamic][]byte,
}

@(require_results)
upload_buffers_make :: proc(allocator := context.temp_allocator) -> (result: Upload_Buffers) {
    result = {
        offset = 0,
    }
    result.bufs.allocator = allocator
    return result
}

upload_buffers_push :: proc(upload: ^Upload_Buffers, buf: ^$T/Buffer($E), elem_verts: u32 = 1) {
    assert(upload.bufs.allocator != {}, "Forgot to call init")
    buf.upload_elem_offset = upload.offset
    buf.upload_elem_num = u32(buf.immediate_offs + buf.persistent_offs) * elem_verts
    upload.offset += buf.upload_elem_num
    append(&upload.bufs, slice.to_bytes(buf.persistent_buf[:buf.persistent_offs]))
    append(&upload.bufs, slice.to_bytes(buf.immediate_buf[:buf.immediate_offs]))
}
