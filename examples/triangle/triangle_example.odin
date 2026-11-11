package ravn_triangle_example

import "core:log"
import "core:debug/trace"
import "core:slice"
import "../../glue"
import "../../gpu"
import "../../platform"
import "../../shaderc"

Vertex :: struct {
    pos:    [3]f32,
    col:    [4]f32,
}

Constants :: struct {
    col:    [4]f32,
}

main :: proc() {
    context.logger = log.create_console_logger()
    context.assertion_failure_proc = trace.assertion_failure_proc

    platform.init()
    defer platform.shutdown()

    window := platform.create_window("RAVN Triangle Example")

    gpu.init(window = platform.get_native_window_ptr(window))
    defer gpu.shutdown()

    if !shaderc.init() {
        return
    }

    vs_bin := shaderc.compile("main.vs.slang", VS, {target = glue.SHADER_TARGET, stage = .Vertex}) or_else panic("VS")
    ps_bin := shaderc.compile("main.ps.slang", PS, {target = glue.SHADER_TARGET, stage = .Pixel}) or_else panic("PS")
    ps: gpu.Shader_Handle; gpu.create_shader(&ps, ps_bin, .Pixel) or_else panic("shader")
    vs: gpu.Shader_Handle; gpu.create_shader(&vs, vs_bin, .Vertex) or_else panic("shader")

    pip: gpu.Graphics_Pipeline_Handle
    gpu.create_graphics_pipeline(&pip, gpu.make_graphics_pipeline_desc(
        vs = vs,
        ps = ps,
        vertex_layouts = { gpu.make_vertex_layout(Vertex, .Vertex) },
        color_formats = { .Swapchain },
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
    struct Vert_Out {
        float4 pos : SV_Position;
        float4 col : TEXCOORD0;
    };
"""

VS :: SHARED + """
    struct Vert_In {
        float3 pos : TEXCOORD0;
        float4 col : TEXCOORD1;
    };

    Vert_Out vs_main(Vert_In vert) {
        Vert_Out o;
        o.pos = float4(vert.pos, 1.0);
        o.col = vert.col;
        return o;
    }
    """

PS :: SHARED + """
    float4 ps_main(Vert_Out vert) : SV_Target {
        return vert.col;
    }
    """