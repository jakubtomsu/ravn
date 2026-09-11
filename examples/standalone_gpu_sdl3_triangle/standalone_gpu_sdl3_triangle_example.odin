package game

import "../../base"
import "../../gpu"
import "../../shader_compiler"
import sdl "vendor:sdl3"
import "core:math"

when gpu.BACKEND == gpu.BACKEND_WGPU {
    SHADER_TARGET :: shader_compiler.Target.WGSL
} else {
    SHADER_TARGET :: shader_compiler.Target.DXBC
}

MAX_INSTS :: 256

verts := []Vertex{
    {pos = {-0.5, -0.5, 0, 1}, col = {1, 0, 0, 1}},
    {pos = {0.5, -0.5, 0, 1}, col = {0, 1, 0, 1}},
    {pos = {0, 0.5, 0, 1}, col = {0, 0, 1, 1}},
}

main :: proc() {
    base.eprintfln("Hello")

    assert(sdl.Init({.VIDEO}))
    defer sdl.Quit()

    context.logger = base.make_logger()
    base.log_debug("Init")

    sdl.SetHintWithPriority(sdl.HINT_RENDER_DRIVER, "direct3d11", .OVERRIDE)
    window := sdl.CreateWindow("Ravn GPU SDL3 Triangle", 1280, 780, {.HIGH_PIXEL_DENSITY, .HIDDEN, .RESIZABLE})
    defer sdl.DestroyWindow(window)

    native_window := sdl.GetPointerProperty(sdl.GetWindowProperties(window), sdl.PROP_WINDOW_WIN32_HWND_POINTER, nil)

    size: [2]i32
    sdl.GetWindowSize(window, &size.x, &size.y)

    gpu_state := new(gpu.State)
    gpu.init(gpu_state, native_window)

    shc: shader_compiler.State
    if !shader_compiler.init(&shc, SHADER_TARGET) {
        panic("No shader compiler")
    }
    ps_blob := shader_compiler.compile(&shc, "triangle.hlsl", _shader_code, {stage = .Pixel}) or_else panic("ps_blob")
    vs_blob := shader_compiler.compile(&shc, "triangle.hlsl", _shader_code, {stage = .Vertex}) or_else panic("vs_blob")

    vbuf: gpu.Resource_Handle
    inst_buf: gpu.Resource_Handle
    layout: gpu.Bind_Layout_Handle
    binds: gpu.Bind_Group_Handle
    pip: gpu.Graphics_Pipeline_Handle
    ps: gpu.Shader_Handle
    vs: gpu.Shader_Handle
    tex: gpu.Resource_Handle

    gpu.create_buffer(&vbuf, .Vertex, size_of(Vertex), data = base.slice_bytes(verts)) or_else panic("buf")
    gpu.create_buffer(&inst_buf, .Vertex, size_of(Instance), size_of(Instance) * MAX_INSTS, usage = .Dynamic) or_else panic("buf")
    gpu.create_texture_2d(&tex, .RGBA_U8_Norm, 2, .Immutable, data = {
        0, 0, 0, 0, 255, 0, 0, 255,
        255, 255, 0, 255, 255, 255, 255, 255,
    }) or_else panic("tex")

    gpu.create_bind_layout(&layout, {slots = {
        {index=0, kind=.Resource_Texture_2D, stages={.Pixel}},
        {index=1, kind=.Sampler, stages={.Pixel}},
    }}) or_else panic("layout")

    // gpu.create_bind_group(&binds, {
    //     layout = layout,
    //     slots = {
    //         {index = 0, resource = vbuf},
    //     },
    // }) or_else panic("binds")

    gpu.create_shader(&ps, ps_blob, .Pixel) or_else panic("ps")
    gpu.create_shader(&vs, vs_blob, .Vertex) or_else panic("vs")

    gpu.create_graphics_pipeline(&pip, gpu.make_graphics_pipeline_desc(
        ps = ps,
        vs = vs,
        cull = .None,
        // layouts = {0 = layout},
        vertex_layouts = {
            0 = gpu.make_vertex_layout(Vertex),
            1 = gpu.make_vertex_layout(Instance, .Instance),
        },
        out_colors = {0 = .Swapchain},
    )) or_else panic("pip")

    sdl.ShowWindow(window)

    time: f32
    for quit := false; !quit; {
        for e: sdl.Event; sdl.PollEvent(&e); {
            #partial switch e.type {
            case .QUIT:
                quit = true
            case .KEY_DOWN:
                #partial switch e.key.scancode {
                case .ESCAPE:
                    quit = true
                }
            }
        }

        sdl.GetWindowSize(window, &size.x, &size.y)
        gpu.resize_swapchain(native_window, size)

        gpu.begin_frame()

        inst_data: [MAX_INSTS]Instance
        for &inst, i in inst_data {
            inst.pos = {(f32(i) / MAX_INSTS - 0.5) * 1.5, math.sin_f32(f32(i) * 20 / MAX_INSTS + time) * 0.2, f32(i) * 0.001, 0}
        }
        gpu.update_buffer(inst_buf, 0, base.slice_bytes(inst_data[:]))

        gpu.begin_graphics_pass("main", {
            colors = {0 = {resource = gpu.SWAPCHAIN_HANDLE, clear_mode = .Clear, clear_val = {0.01, 0.1, 0.2, 1}}},
        })

        // gpu.set_bind_group(0, binds)
        gpu.set_graphics_pipeline(pip)
        gpu.set_vertex_buffer(0, vbuf)
        gpu.set_vertex_buffer(1, inst_buf)
        gpu.draw_non_indexed(3, MAX_INSTS)

        gpu.end_graphics_pass()

        gpu.end_frame(sync = true)

        time += 0.02
    }
}

Vertex :: struct {
    pos:    [4]f32,
    col:    [4]f32,
}

Instance :: struct {
    pos: [4]f32,
}

@(rodata)
_shader_code := #load("../../data/ravn.hlsli", string) + `
struct Vertex {
    float4 pos : TEXCOORD0;
    float4 col : TEXCOORD1;
    float4 inst_pos : TEXCOORD2;
};

struct Vertex_Out {
    float4 pos : SV_Position;
    float4 col : COL;
};

Vertex_Out vs_main(Vertex vert, uint id : SV_InstanceID) {
    Vertex_Out output;
    output.pos = float4(vert.inst_pos.xyz + vert.pos.xyz * 0.2, 1.0);
    output.col = vert.col * float(id % 2 == 0 ? 1 : 0.8);
    return output;
}

float4 ps_main(Vertex_Out input) : SV_Target {
    return input.col;
}
`