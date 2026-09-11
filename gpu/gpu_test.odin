#+test
#+vet shadowing unused
package ravn_gpu

import "core:testing"

@(test)
_vertex_layout_test :: proc(t: ^testing.T) {
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

    layout := make_vertex_layout(Vertex)
    expected := []Vertex_Format{.F32x3, .F32x2, .U10x3_U2_Norm, .U8x4_Norm, .I16x4_Norm, .F16x4, .U8x4_Norm, .U16x4, .F16x2, .I32x2, .U32, .F32}
    for format, i in expected {
        if format == {} {
            break
        }
        testing.expect(t, layout.slots[i] == format)
    }
}
