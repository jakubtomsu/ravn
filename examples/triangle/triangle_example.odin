package ravn_triangle_example

import "core:slice"
import "../../base"
import "../../glue"
import "../../gpu"
import "../../platform"
import "../../shader_compiler"

Vertex :: struct {
    pos:    [3]f32,
    col:    [4]f32,
}

Constants :: struct {
    col:    [4]f32,
}

main :: proc() {
    context.logger = base.make_logger()

    platform.init()
    defer platform.shutdown()

    window := platform.create_window("RAVN Triangle Example")

    gpu.init(window = platform.get_native_window_ptr(window))
    defer gpu.shutdown()

    if !shader_compiler.init(glue.SHADER_TARGET) {
        return
    }

    vs_bin := shader_compiler.compile_source(#file, VS, {stage = .Vertex}) or_else panic("VS")
    ps_bin := shader_compiler.compile_source(#file, PS, {stage = .Pixel}) or_else panic("PS")
    ps: gpu.Shader_Handle; gpu.create_shader(&ps, ps_bin, .Pixel) or_else panic("shader create")
    vs: gpu.Shader_Handle; gpu.create_shader(&vs, vs_bin, .Vertex) or_else panic("shader create")

    pip: gpu.Graphics_Pipeline_Handle
    gpu.create_graphics_pipeline(&pip, gpu.make_graphics_pipeline_desc(
        vs = vs,
        ps = ps,
        vertex_layouts = { 0 = gpu.make_vertex_layout(Vertex, .Vertex) },
        out_colors = { 0 = .Swapchain },
    )) or_else panic("pip")

    vbuf: gpu.Resource_Handle
    gpu.create_buffer(&vbuf, .Vertex, size_of(Vertex), data = slice.to_bytes([]Vertex{
        {{ 0.5, -0.5, 0}, {1, 0, 0, 1}},
        {{   0,  0.5, 0}, {0, 1, 0, 1}},
        {{-0.5, -0.5, 0}, {0, 0, 1, 1}},
    })) or_else panic("vbuf")

    running := true
    for running {
        for event in platform.poll_window_events(window) {
            #partial switch ev in event {
            case platform.Event_Exit:
                running = false
            case platform.Event_Button:
                if ev.button == .Escape {
                    running = false
                }
            }
        }

        gpu.resize_swapchain(platform.get_native_window_ptr(window), platform.get_window_rect(window).size)

        gpu.begin_frame()

        gpu.begin_graphics_pass("main", {
            colors = { 0 = { resource = gpu.SWAPCHAIN_HANDLE, clear_mode = .Clear, clear_val = {0.1, 0.2, 0.3, 1} }},
        })
        gpu.set_graphics_pipeline(pip)
        gpu.set_vertex_buffer(0, vbuf)
        gpu.draw_non_indexed(3)
        gpu.end_graphics_pass()

        gpu.end_frame(false)
    }
}

SHARED :: """
    struct VS_Out {
        float4 pos : SV_Position;
        float4 col : TEXCOORD0;
    };
"""

VS :: SHARED + """
    struct VS_In {
        float3 pos : TEXCOORD0;
        float4 col : TEXCOORD1;
    };

    VS_Out vs_main(VS_In vert) {
        VS_Out o;
        o.pos = float4(vert.pos, 1.0);
        o.col = vert.col;
        return o;
    }
    """

PS :: SHARED + """
    float4 ps_main(VS_Out vert) : SV_Target {
        return vert.col;
    }
    """