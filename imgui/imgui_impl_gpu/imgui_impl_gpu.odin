#+vet explicit-allocators shadowing unused
package ravn_imgui_impl_gpu

import "base:intrinsics"
import "core:mem"
import "core:slice"
import "core:log"
import "base:runtime"
import "../../base"
import "../../gpu"
import ".."

State :: struct {
    allocator:      runtime.Allocator,
    vbuf:           gpu.Resource_Handle,
    ibuf:           gpu.Resource_Handle,
    cbuf:           gpu.Resource_Handle,
    pip:            gpu.Graphics_Pipeline_Handle,
    bind_layout:    gpu.Bind_Layout_Handle,
    binds:          map[gpu.Resource_Handle]gpu.Bind_Group_Handle,
}

Constants :: struct {
    proj:   matrix[4, 4]f32,
}

Vertex :: struct {
	pos:    [2]f32,
	uv:     [2]f32,
	col:    u32 `gpu:"U8x4_Norm"`,
}

init :: proc(target_format: gpu.Texture_Format = .Swapchain, allocator := context.allocator) -> bool {
    assert(gpu._state != nil)

    imgui.CHECKVERSION()
    io := imgui.GetIO()
    assert(io.BackendRendererUserData == nil, "Already initialized a renderer backend")

    state := new(State, allocator)
    state.allocator = allocator

    io.BackendRendererUserData = state
    io.BackendRendererName = "imgui_impl_ravn_gpu"
    io.BackendFlags += {.RendererHasVtxOffset, .RendererHasTextures}

    plio := imgui.GetPlatformIO()
    plio.Renderer_TextureMaxWidth = gpu.MAX_TEXTURE_2D_SIZE
    plio.Renderer_TextureMaxHeight = gpu.MAX_TEXTURE_2D_SIZE

    if !gpu.create_bind_layout(&state.bind_layout, gpu.Bind_Layout_Desc{slots = {
        {0, .Constants, {.Vertex}, {}},
        {1, .Resource_Texture_2D, {.Pixel}, {}},
        {2, .Sampler, {.Pixel}, {}},
    }}) {
        log.error("Failed to create ImGui bind layout")
        return false
    }

    vs: gpu.Shader_Handle
    ps: gpu.Shader_Handle

    if !gpu.create_shader(&vs, #load("main.vs.dxbc"), .Vertex) {
        log.error("Failed to create vertex shader")
        return false
    }

    if !gpu.create_shader(&ps, #load("main.ps.dxbc"), .Pixel) {
        log.error("Failed to create pixel shader")
        return false
    }

    if !gpu.create_constants(&state.cbuf, size_of(Constants)) {
        log.error("Failed to create cbuffer")
        return false
    }

    if !gpu.create_graphics_pipeline(&state.pip, gpu.make_graphics_pipeline_desc(
        ps = ps,
        vs = vs,
        bind_layouts = {0 = state.bind_layout},
        vertex_layouts = {0 = gpu.make_vertex_layout(Vertex, .Vertex)},
        out_colors = {0 = target_format},
        blends = {gpu.BLEND_ALPHA},
        index_format = .U16,
    )) {
        log.error("Failed to create ImGui pipeline")
        return false
    }

    return true
}

shutdown :: proc() {
    assert(gpu._state != nil)

    io := imgui.GetIO()
    state := cast(^State)io.BackendRendererUserData
    assert(state != nil, "No renderer to shutdown, or already shutdown?")
}

new_frame :: proc() {
    assert(gpu._state != nil)

    io := imgui.GetIO()
    state := cast(^State)io.BackendRendererUserData
    assert(state != nil, "Backend not initialized")
}

// Call outside a draw pass
upload_draw_data :: proc(data: ^imgui.DrawData) {
    assert(gpu._state != nil)

    io := imgui.GetIO()
    state := cast(^State)io.BackendRendererUserData
    assert(state != nil, "Backend not initialized")

    if data.Textures != nil {
        for tex in data.Textures.Data[:data.Textures.Size] {
            if tex.Status == .OK {
                continue
            }
            _update_texture(tex)
        }
    }

    gpu.update_constants(state.cbuf, mem.ptr_to_bytes(&Constants{
        proj = _ortho_projection(data.DisplayPos, data.DisplaySize),
    }))

    if vbuf, ok := gpu._get_resource(state.vbuf); !ok || vbuf.size.x < data.TotalVtxCount*size_of(imgui.DrawVert) {
        if !gpu.create_buffer(&state.vbuf,
            .Vertex,
            size_of(imgui.DrawVert),
            size = max(4096, data.TotalVtxCount) * size_of(imgui.DrawVert),
            usage = .Dynamic,
        ) {
            log.error("Failed to create vertex buffer")
        }
    }

    if ibuf, ok := gpu._get_resource(state.ibuf); !ok || ibuf.size.x < data.TotalIdxCount*size_of(imgui.DrawIdx) {
        if !gpu.create_buffer(&state.ibuf,
            .Index,
            size_of(imgui.DrawIdx),
            size = max(4096, data.TotalIdxCount) * size_of(imgui.DrawIdx),
            usage = .Dynamic,
        ) {
            log.error("Failed to create index buffer")
        }
    }

    vdata := make([][]byte, data.CmdLists.Size, context.temp_allocator)
    idata := make([][]byte, data.CmdLists.Size, context.temp_allocator)
    for list, i in data.CmdLists.Data[:data.CmdLists.Size] {
        vdata[i] = slice.to_bytes(list.VtxBuffer.Data[:list.VtxBuffer.Size])
        idata[i] = slice.to_bytes(list.IdxBuffer.Data[:list.IdxBuffer.Size])
    }

    gpu.update_buffer(state.vbuf, offset = 0, buffers = vdata)
    gpu.update_buffer(state.ibuf, offset = 0, buffers = idata)
}

// Call inside a draw pass
render_draw_data :: proc(data: ^imgui.DrawData) {
    assert(gpu._state != nil)

    io := imgui.GetIO()
    state := cast(^State)io.BackendRendererUserData
    assert(state != nil, "Backend not initialized")

    gpu.set_graphics_pipeline(state.pip)
    gpu.set_index_buffer(state.ibuf, .U16)
    gpu.set_vertex_buffer(0, state.vbuf)

    global_index_offset := 0
    global_vertex_offset := 0

    // Render command lists
    for &list in data.CmdLists.Data[:data.CmdLists.Size] {
        for &cmd in list.CmdBuffer.Data[:list.CmdBuffer.Size] {
            if cmd.UserCallback != nil {
                cmd.UserCallback(list, &cmd)
                continue
            }

            // TODO: set scissor

            tex := _rawptr_as_handle(gpu.Resource_Handle, cast(rawptr)cast(uintptr)imgui.DrawCmd_GetTexID(&cmd))
            binds := _get_bind_group(state, tex)
            gpu.set_bind_group(0, binds)
            gpu.draw_indexed(
                index_num = cmd.ElemCount,
                instance_num = 1,
                index_offset = int(cmd.IdxOffset) + global_index_offset,
                vertex_offset = int(cmd.VtxOffset) + global_vertex_offset,
            )
        }

        global_index_offset += int(list.IdxBuffer.Size)
        global_vertex_offset += int(list.VtxBuffer.Size)
    }
}

_update_texture :: proc(tex: ^imgui.TextureData) {
    switch tex.Status {
    case .OK:
    case .Destroyed:

    case .WantCreate:
        handle: gpu.Resource_Handle
        if !gpu.create_texture_2d(&handle,
            format = .RGBA_U8_Norm,
            size = {tex.Width, tex.Height},
            data = tex.Pixels[:tex.Width*tex.Height*4],
        ) {
            log.error("Failed to create texture")
            break
        }
        tex.BackendUserData = _handle_as_rawptr(handle)
        imgui.TextureData_SetTexID(tex, cast(imgui.TextureID)transmute(u32)handle)
        imgui.TextureData_SetStatus(tex, .OK)

    case .WantUpdates:
        handle := _rawptr_as_handle(gpu.Resource_Handle, tex.BackendUserData)
        // TODO, Inefficient
        gpu.update_texture_2d(handle, tex.Pixels[:tex.Width*tex.Height*4])
        imgui.TextureData_SetStatus(tex, .OK)

    case .WantDestroy:
        if tex.UnusedFrames > 0 {
            handle := _rawptr_as_handle(gpu.Resource_Handle, tex.BackendUserData)
            gpu.destroy_resource(handle)
        }
    }
}

_handle_as_rawptr :: proc(handle: $H/base.Handle) -> rawptr {
    return cast(rawptr)cast(uintptr)transmute(u32)handle
}

_rawptr_as_handle :: proc($T: typeid/base.Handle, data: rawptr) -> T {
    return transmute(T)cast(u32)cast(uintptr)data
}

_get_bind_group :: proc(state: ^State, tex: gpu.Resource_Handle) -> gpu.Bind_Group_Handle {
    binds, binds_ok := state.binds[tex]
    if binds_ok {
        return binds
    }

    if !gpu.create_bind_group(&binds, gpu.Bind_Group_Desc{
        layout = state.bind_layout,
        slots = {
            {0, state.cbuf, {}},
            {1, tex, {}},
            {2, {}, gpu.make_sampler_desc({.Min, .Mag, .Mip})},
        },
    }) {
        log.error("Failed to create bind group for texture:", tex)
        return {}
    }

    state.binds[tex] = binds

    return binds
}

_ortho_projection :: proc(pos: [2]f32, size: [2]f32) -> matrix[4, 4]f32 {
    L := pos.x
    R := pos.x + size.x
    T := pos.y
    B := pos.y + size.y
    return intrinsics.transpose(matrix[4, 4]f32{
        2.0/(R-L),     0.0,           0.0, 0.0,
        0.0,           2.0/(T-B),     0.0, 0.0,
        0.0,           0.0,           0.5, 0.0,
        (R+L)/(L-R),  (T+B)/(B-T),    0.5, 1.0,
    })
}
