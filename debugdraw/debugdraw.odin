#+vet explicit-allocators style unused shadowing
package ravn_debugdraw

import "core:slice"
import "core:log"
import "base:intrinsics"
import "base:runtime"
import "../gpu"

ENABLED :: #config(DEBUGDRAW_ENABLED, true)
LANES :: 32

_state: ^State

State :: struct {
    state_allocator:    runtime.Allocator,

    target_color:       gpu.Resource_Handle,
    target_depth:       gpu.Resource_Handle,

    shape_vbuf:         gpu.Resource_Handle,
    shape_offsets:      [Buffer_Kind]u32,

    ps:                 gpu.Shader_Handle,
    layouts:            [Buffer_Layout_Kind]Buffer_Layout_Data,
    buffers:            [Buffer_Kind]Buffer_Data,
}

// Buffers share the actual GPU draw elem buffer and pipeline based on layout.
// Within one layout only offsets and extra bindings are necessary.
Buffer_Layout_Kind :: enum u8 {
    Vertex,
    Shape_Instance,
}

Buffer_Layout_Data :: struct {
    vs:         gpu.Shader_Handle,
    pip:        gpu.Graphics_Pipeline_Handle,
    layout:     gpu.Bind_Layout_Handle,
    res:        gpu.Resource_Handle,
}

Buffer_Kind :: enum u8 {
    Line,
    Line_Box,
    Line_Circle,
    Line_Half_Circle,
    Line_Sphere,
    Line_Cylinder,
    Solid_Tri,
    Solid_Box,
    Solid_Circle,
    Solid_Sphere,
    Solid_Hemisphere,
    Solid_Cylinder,
}

BUFFER_PERSIST_FILTER_PER_FRAME :: 1024

Buffer_Data :: struct {
    binds:                  gpu.Bind_Group_Handle,
    immediate_buf:          []byte,
    immediate_offs:         u32,
    persist_buf:            []byte,
    persist_offs:           u32,
    persist_timers:         []f16,
    persist_filter_offs:    u32,
}

Shape_Instance :: struct {
    pos:    [3]f32,
    col:    [4]u8,
    scale:  [3]f32,
    rot:    quaternion128,
}

Shape_Vertex :: [4]f32

Vertex :: struct {
    pos:    [3]f32,
    col:    [4]u8,
}

BUFFER_LAYOUT_IS_INSTANCED :: bit_set[Buffer_Layout_Kind]{
    .Shape_Instance,
}

@(rodata)
_buffer_layout_kind_sizes := [Buffer_Layout_Kind]int{
    .Vertex         = size_of(Vertex),
    .Shape_Instance = size_of(Shape_Instance),
}

@(rodata)
_buffer_layout_kinds := [Buffer_Kind]Buffer_Layout_Kind{
    .Line               = .Vertex,
    .Line_Box           = .Shape_Instance,
    .Line_Circle        = .Shape_Instance,
    .Line_Half_Circle   = .Shape_Instance,
    .Line_Sphere        = .Shape_Instance,
    .Line_Cylinder      = .Shape_Instance,
    .Solid_Tri          = .Vertex,
    .Solid_Box          = .Shape_Instance,
    .Solid_Circle       = .Shape_Instance,
    .Solid_Sphere       = .Shape_Instance,
    .Solid_Hemisphere   = .Shape_Instance,
    .Solid_Cylinder     = .Shape_Instance,
}

DEFAULT_BUFFER_CAPS :: [Buffer_Kind]int{
    .Line               = 1024 * 16,
    .Line_Box           = 1024 * 16,
    .Line_Circle        = 1024 * 16,
    .Line_Half_Circle   = 1024 * 16,
    .Line_Sphere        = 1024 * 16,
    .Line_Cylinder      = 1024 * 16,
    .Solid_Tri          = 1024 * 16,
    .Solid_Box          = 1024 * 16,
    .Solid_Circle       = 1024 * 16,
    .Solid_Sphere       = 1024 * 16,
    .Solid_Hemisphere   = 1024 * 16,
    .Solid_Cylinder     = 1024 * 16,
}

// MARK: Core

init :: proc(
    state:          ^State = nil,
    target_color:   gpu.Resource_Handle,
    target_depth:   gpu.Resource_Handle = {},
    buffer_caps     := DEFAULT_BUFFER_CAPS,
    allocator       := context.allocator,
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

    _state.target_color = target_color
    _state.target_depth = target_depth

    if !gpu.create_graphics_pipeline(&_state.layouts[.Vertex].pip, gpu.make_graphics_pipeline_desc(
        vs = _state.layouts[.Vertex].vs,
        ps = _state.ps,
        vertex_layouts = {
            0 = gpu.make_vertex_layout(Vertex, .Vertex),
        },
        out_colors = {
            0 = gpu.get_texture_format(_state.target_color),
        },
        out_depth = gpu.get_texture_format(_state.target_depth) or_else .Invalid,
        blends = {
            0 = gpu.BLEND_ALPHA,
        },
        topo = .Lines,
    )) {
        return false
    }

    if !gpu.create_graphics_pipeline(&_state.layouts[.Shape_Instance].pip, gpu.make_graphics_pipeline_desc(
        vs = _state.layouts[.Shape_Instance].vs,
        ps = _state.ps,
        vertex_layouts = {
            0 = gpu.make_vertex_layout(Vertex, .Vertex),
            1 = gpu.make_vertex_layout(Shape_Instance, .Instance),
        },
        out_colors = {
            0 = gpu.get_texture_format(_state.target_color),
        },
        out_depth = gpu.get_texture_format(_state.target_depth) or_else .Invalid,
        blends = {
            0 = gpu.BLEND_ALPHA,
        },
        topo = .Triangles,
        cull = .Back,
    )) {
        return false
    }

    shape_verts: [dynamic]Shape_Vertex
    shape_verts.allocator = context.temp_allocator

    for buf, kind in _buffer_shape_verts {
        _state.shape_offsets[kind] = u32(len(shape_verts))
        append(&shape_verts, ..buf)
    }

    gpu.create_buffer(
        &_state.shape_vbuf,
        kind = .Vertex,
        stride = size_of(Shape_Vertex),
        data = slice.to_bytes(shape_verts[:]),
        usage = .Immutable,
    )

    layout_caps: [Buffer_Layout_Kind]int

    for &buf, kind in _state.buffers {
        layout_kind := _buffer_layout_kinds[kind]
        layout_caps[layout_kind] += buffer_caps[kind]

        elem_size := _buffer_layout_kind_sizes[layout_kind]
        buf.immediate_buf  = make([]byte,   buffer_caps[kind] * elem_size, allocator)
        buf.persist_buf    = make([]byte,   buffer_caps[kind] * elem_size)
        buf.persist_timers = make([]f16,    buffer_caps[kind], allocator)
    }
}

shutdown :: proc() {
    if _state == nil {
        return
    }

    free(_state, _state.state_allocator)

    _state = nil
}

// MARK: Render

render_frame :: proc(delta: f32) {
    context.allocator = runtime.panic_allocator()

    // Upload

    upload_offsets: [Buffer_Layout_Kind]u32
    upload_starts:  [Buffer_Kind]u32
    upload_bufs:    [Buffer_Layout_Kind][dynamic][]byte
    for &b in upload_bufs {
        b.allocator = context.temp_allocator
    }

    for buf, kind in _state.buffers {
        layout_kind := _buffer_layout_kinds[kind]

        upload_starts[kind] = upload_offsets[layout_kind]
        upload_offsets[layout_kind] += buf.immediate_offs + buf.persist_offs

        append(&upload_bufs[layout_kind], buf.immediate_buf[:buf.immediate_offs])
        append(&upload_bufs[layout_kind], buf.persist_buf[:buf.persist_offs])
    }

    for layout_kind in Buffer_Layout_Kind {
        gpu.update_buffer(_state.layouts[layout_kind].res, offset = 0, buffers = upload_bufs[layout_kind][:])
    }

    // Draw

    gpu.begin_graphics_pass("ravn_debugdraw", gpu.Graphics_Pass_Desc{
        colors = {
            0 = {
                resource = _state.target_color,
                clear_mode = .Keep,
            },
        },
        depth = {
            resource = _state.target_depth,
            clear_mode = .Keep,
        },
    })

    for layout, layout_kind in _state.layouts {
        gpu.set_graphics_pipeline(layout.pip)
        gpu.set_vertex_buffer(0, layout.res)

        for buf, kind in _state.buffers {
            if _buffer_layout_kinds[kind] != layout_kind {
                continue
            }

            gpu.set_bind_group(0, buf.binds)
            elem_num := int(buf.immediate_offs + buf.persist_offs)
            elem_offset := int(upload_starts[kind] * u32(_buffer_layout_kind_sizes[layout_kind]))
            if layout_kind in BUFFER_LAYOUT_IS_INSTANCED {
                gpu.draw_non_indexed(
                    vertex_num = len(_buffer_shape_verts[kind]),
                    instance_num = elem_num,
                    vertex_offset = 0,
                    instance_offset = elem_offset,
                )
            } else {
                gpu.draw_non_indexed(
                    vertex_num = elem_num,
                    instance_num = 1,
                    vertex_offset = elem_offset,
                    instance_offset = 0,
                )
            }
        }        
    }

    // Clear and filter

    for &buf, kind in _state.buffers {
        buf.immediate_offs = 0

        for &timer in buf.persist_timers[:buf.persist_offs] {
            timer -= f16(delta)
        }

        elem_size := _buffer_layout_kind_sizes[_buffer_layout_kinds[kind]]

        // Filter fixed amount of old persistent elems
        filter_num := min(buf.persist_offs, BUFFER_PERSIST_FILTER_PER_FRAME)
        for _ in 0..<filter_num {
            if buf.persist_filter_offs >= buf.persist_offs {
                buf.persist_filter_offs = 0
            }

            if buf.persist_timers[buf.persist_filter_offs] < 0 {
                intrinsics.mem_copy(
                    &buf.persist_buf[buf.persist_filter_offs],
                    &buf.persist_buf[buf.persist_offs],
                    elem_size,
                )
                buf.persist_timers[buf.persist_filter_offs] = buf.persist_timers[buf.persist_offs]
                buf.persist_offs -= 1
            }

            buf.persist_filter_offs += 1
        }
    }

}

// MARK: line drawing

line :: proc(
    pos0:   [3]f32,
    pos1:   [3]f32,
    col:    [2][4]f32 = 1,
    time:   f32 = 0,
) {
    verts := [2]Vertex{
        { pos = v0, col = col[0] },
        { pos = v1, col = col[1] },
    }

    
}

tri :: proc()
box :: proc()
circle :: proc()
half_circle :: proc()
sphere :: proc()
cylinder :: proc()

// MARK: triangle drawing

solid_tri :: proc()
solid_line :: proc()
solid_box :: proc()
solid_circle :: proc()
solid_sphere :: proc()
solid_hemisphere :: proc()
solid_cylinder :: proc()

// MARK: Util

capsule :: proc()
aabb :: proc()

// MARK: Data


@(rodata)
_buffer_shape_verts := [Buffer_Kind][]Shape_Vertex{
    .Line               = {},

    .Line_Box           = {
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

    .Line_Circle        = {
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

    .Line_Half_Circle   = {
        {                       1,                        0, 0, 0}, {      0.9238795325112867,       0.3826834323650898, 0, 0},
        {      0.9238795325112867,       0.3826834323650898, 0, 0}, {      0.7071067811865476,       0.7071067811865476, 0, 0},
        {      0.7071067811865476,       0.7071067811865476, 0, 0}, {     0.38268343236508984,       0.9238795325112867, 0, 0},
        {     0.38268343236508984,       0.9238795325112867, 0, 0}, {   6.123233995736766e-17,                        1, 0, 0},
        {   6.123233995736766e-17,                        1, 0, 0}, {     -0.3826834323650897,       0.9238795325112867, 0, 0},
        {     -0.3826834323650897,       0.9238795325112867, 0, 0}, {     -0.7071067811865475,       0.7071067811865476, 0, 0},
        {     -0.7071067811865475,       0.7071067811865476, 0, 0}, {     -0.9238795325112867,       0.3826834323650899, 0, 0},
        {     -0.9238795325112867,       0.3826834323650899, 0, 0}, {                      -1,   1.2246467991473532e-16, 0, 0},
    },

    .Line_Sphere        = {
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

    .Line_Cylinder      = {

    },

    .Solid_Tri          = {},

    .Solid_Box          = {

    },

    .Solid_Circle       = {

    },
    .Solid_Sphere       = {

    },
    .Solid_Hemisphere   = {

    },
    .Solid_Cylinder     = {

    },
}
