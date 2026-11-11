#+test
#+vet shadowing style
#+private file
package ravn_gpu

import "core:slice"
import "core:testing"

@(test)
_test_rtti_vertex_layout :: proc(t: ^testing.T) {
    U10x3_U2 :: bit_field u32 {
        x: u32 | 10,
        y: u32 | 10,
        z: u32 | 10,
        w: u32 |  2,
    }

    Rgba8 :: struct {
        r, g, b, a: u8,
    }

    Vertex :: struct {
        pos:       [3]f32,
        uv:        [2]f32,
        normal:    U10x3_U2 `gpu:"U10x3_U2_Norm"`,
        color:     Rgba8    `gpu:"U8x4_Norm"`,
        tangent:   [4]i16   `gpu:"I16x4_Norm"`,
        bitangent: [4]f16,
        weights:   [4]u8    `gpu:"U8x4_Norm"`,
        joints:    [4]u16,
        tex_uv2:   [2]f16,
        custom_i:  [2]i32,
        custom_u:  u32,
        height:    f32,
    }

    layout := make_vertex_layout(Vertex, .Vertex)
    expected := []Vertex_Format{.F32x3, .F32x2, .U10x3_U2_Norm, .U8x4_Norm, .I16x4_Norm, .F16x4, .U8x4_Norm, .U16x4, .F16x2, .I32x2, .U32, .F32}
    for format, i in expected {
        if format == {} {
            break
        }
        testing.expect(t, layout.slots[i] == format)
    }
}

// NOTE: this needs to be a single test due to the default test runner multithreading.
@(test)
_test_gpu :: proc(t: ^testing.T) {
    init(window = nil)
    defer shutdown()

    {
        res_buf_vtx, res_buf_idx, res_buf_storage: Resource_Handle
        res_tex_2d, res_tex_depth, res_tex_3d, res_uav: Resource_Handle
        res_cbuf, res_cbuf_dyn: Resource_Handle

        layout_std, layout_comp: Bind_Layout_Handle
        group_std, group_comp: Bind_Group_Handle

        // Resources
        testing.expect(t, create_buffer(&res_buf_vtx, .Vertex, 16, 64, .Default))
        testing.expect(t, create_buffer(&res_buf_idx, .Index, 2, 0, .Immutable, data = slice.to_bytes([]u16{0, 1, 2, 3})))
        testing.expect(t, create_buffer(&res_buf_storage, .Storage, 4, 1024, .Dynamic))

        testing.expect(t, create_texture_2d(&res_tex_2d, make_texture_desc(.RGBA_U8_Norm, {256, 256, 1}, .Default)))
        testing.expect(t, create_texture_2d(&res_tex_depth, make_texture_desc(.Depth_F32, {1920, 1080, 1}, .Default, flags = {.Render_Texture})))
        testing.expect(t, create_texture_2d(&res_uav, make_texture_desc(.R_U32, {64, 64, 1}, .Default, flags = {.RW_Resource}))) // Currently can fail due to WGPU bug?
        testing.expect(t, create_texture_3d(&res_tex_3d, make_texture_desc(.RG_S8_Norm, {32, 32, 32}, .Default)))

        testing.expect(t, create_constants(&res_cbuf, 64, 1))
        testing.expect(t, create_constants(&res_cbuf_dyn, 256, 4))

        testing.expect(t, create_bind_layout(&layout_std, {
            {kind = .Constants, stages = {.Vertex}},
            {kind = .Sampler, stages = {.Pixel}},
            {kind = .Resource_Texture_2D, stages = {.Pixel}},
            {kind = .Resource_Texture_3D, stages = {.Pixel}},
        }))

        testing.expect(t, create_bind_group(&group_std, {layout = layout_std, slots = {
            {resource = res_cbuf},
            {sampler = make_sampler_desc({.Min, .Mag, .Mip})},
            {resource = res_tex_2d},
            {resource = res_tex_3d},
        }}))

        testing.expect(t, create_bind_layout(&layout_comp, {
            {kind = .Constants_Dynamic, stages = {.Compute}},
            {kind = .Resource_Buffer, stages = {.Compute}},
            {kind = .RW_Resource_Texture_2D, stages = {.Compute}, format = .R_U32},
        }))

        testing.expect(t, create_bind_group(&group_comp, {layout = layout_comp, slots = {
            {resource = res_cbuf_dyn},
            {resource = res_buf_storage},
            {resource = res_uav},
        }}))

        testing.expect(t, destroy_bind_group(group_comp))
        testing.expect(t, destroy_bind_group(group_std))
        testing.expect(t, destroy_bind_layout(layout_comp))
        testing.expect(t, destroy_bind_layout(layout_std))

        testing.expect(t, destroy_resource(res_cbuf_dyn))
        testing.expect(t, destroy_resource(res_cbuf))
        testing.expect(t, destroy_resource(res_tex_3d))
        testing.expect(t, destroy_resource(res_uav))
        testing.expect(t, destroy_resource(res_tex_depth))
        testing.expect(t, destroy_resource(res_tex_2d))
        testing.expect(t, destroy_resource(res_buf_storage))
        testing.expect(t, destroy_resource(res_buf_idx))
        testing.expect(t, destroy_resource(res_buf_vtx))
    }

    tex: Resource_Handle
    create_texture_2d(&tex, make_texture_desc(.RGBA_U8_Norm, {512, 512, 1}, flags = {.Render_Texture})) or_else panic("tex")
    defer destroy_resource(tex)

    readback: Resource_Handle
    create_texture_2d(&readback, make_texture_desc(.RGBA_U8_Norm, {512, 512, 1}, .Staging)) or_else panic("tex")
    defer destroy_resource(readback)

    for i in 0..<20 {
        begin_frame()

        begin_graphics_pass("main", {
            colors = { 0 = { resource = tex, clear_mode = .Clear, clear_val = {0.1, f32(i) * 0.1, 0, 1} }},
        })

        end_graphics_pass()

        copy_texture(readback, tex) or_else panic("copy")

        end_frame()

        m, m_ok := map_texture(readback)

        testing.expect(t, m_ok)

        if m_ok {
            unmap_texture(readback)
        }
    }
}
