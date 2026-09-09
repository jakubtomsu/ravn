package game

import "../../base"
import "../../gpu"
import "../../shader_compiler"
import sdl "vendor:sdl3"

when gpu.BACKEND == gpu.BACKEND_WGPU {
    SHADER_TARGET :: shader_compiler.Target.WGSL
} else {
    SHADER_TARGET :: shader_compiler.Target.DXBC
}

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
    window := sdl.CreateWindow("Ravn GPU SDL3 Triangle", 854, 480, {.HIGH_PIXEL_DENSITY, .HIDDEN, .RESIZABLE})
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
    layout: gpu.Bindings_Layout_Handle
    binds: gpu.Bindings_Handle
    pip: gpu.Graphics_Pipeline_Handle
    ps: gpu.Shader_Handle
    vs: gpu.Shader_Handle

    gpu.create_buffer(&vbuf, .Storage, size_of(Vertex), data = base.slice_bytes(verts)) or_else panic("buf")

    gpu.create_bindings_layout(&layout, {slots = {
        {index=0, kind=.Resource_Buffer, stages={.Vertex, .Pixel}},
    }}) or_else panic("layout")

    gpu.create_bindings(&binds, {
        layout = layout,
        slots = {
            {index = 0, resource = vbuf},
        },
    }) or_else panic("binds")

    gpu.create_shader(&ps, ps_blob, .Pixel) or_else panic("ps")
    gpu.create_shader(&vs, vs_blob, .Vertex) or_else panic("vs")

    gpu.create_graphics_pipeline(&pip, gpu.make_graphics_pipeline_desc(
        ps = ps,
        vs = vs,
        layout = layout,
        out_colors = {0 = .Swapchain},
    )) or_else panic("pip")

    sdl.ShowWindow(window)

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

        gpu.begin_graphics_pass("main", {
            colors = {0 = {resource = gpu.SWAPCHAIN_HANDLE, clear_mode = .Clear, clear_val = {0.01, 0.1, 0.2, 1}}},
        })

        gpu.set_bindings(binds)
        gpu.set_graphics_pipeline(pip)
        gpu.draw_non_indexed(3)

        gpu.end_graphics_pass()

        gpu.end_frame(sync = true)
    }
}

Vertex :: struct {
    pos:    [4]f32,
    col:    [4]f32,
}

@(rodata)
_shader_code := #load("../../data/ravn.hlsli", string) + `
struct Vertex {
    float4 pos;
    float4 col;
};

RV_RESOURCE_SLOT(0, StructuredBuffer<Vertex> verts);

struct Vertex_Out {
    float4 pos : SV_Position;
    float4 col : COL;
};

Vertex_Out vs_main(uint vid : SV_VertexID) {
    Vertex vert = verts[vid];
    Vertex_Out output;
    output.pos = vert.pos;
    output.col = vert.col;
    return output;
}

float4 ps_main(Vertex_Out input) : SV_Target {
    return input.col;
}
`