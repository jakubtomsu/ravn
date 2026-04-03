package game

import "../../base"
import "../../gpu"
import "../../shader_compiler"
import sdl "vendor:sdl3"

main :: proc() {
    assert(sdl.Init({.VIDEO}))
    defer sdl.Quit()

    context.logger = base.make_logger()
    base.log_debug("Init")

    sdl.SetHintWithPriority(sdl.HINT_RENDER_DRIVER, "direct3d11", .OVERRIDE)
    window := sdl.CreateWindow("Raven GPU SDL3 Triangle", 854, 480, {.HIGH_PIXEL_DENSITY, .HIDDEN, .RESIZABLE})
    defer sdl.DestroyWindow(window)

    native_window := sdl.GetPointerProperty(sdl.GetWindowProperties(window), sdl.PROP_WINDOW_WIN32_HWND_POINTER, nil)

    size: [2]i32
    sdl.GetWindowSize(window, &size.x, &size.y)

    gpu_state := new(gpu.State)
    gpu.init(gpu_state, native_window)

    gpu.update_swapchain(native_window, size)

    shader_compiler.init(new(shader_compiler.State))
    ps_blob := shader_compiler.compile("triangle.hlsl", _shader_code, {stage = .Pixel, target = .DXBC}) or_else panic("ps_blob")
    vs_blob := shader_compiler.compile("triangle.hlsl", _shader_code, {stage = .Vertex, target = .DXBC}) or_else panic("vs_blob")

    pip := gpu.create_pipeline("triangle-pip", gpu.pipeline_desc(
        ps = gpu.create_shader("triangle-ps", ps_blob, .Pixel) or_else panic("ps"),
        vs = gpu.create_shader("triangle-vs", vs_blob, .Vertex) or_else panic("vs"),
        out_colors = {.RGBA_U8}, // TODO
        resources = {
            gpu.create_buffer("verts", size_of(Vertex), data = gpu.slice_bytes([]Vertex{
                {pos = {-0.5, -0.5, 0, 1}, col = {1, 0, 0, 1}},
                {pos = {0.5, -0.5, 0, 1}, col = {0, 1, 0, 1}},
                {pos = {0, 0.5, 0, 1}, col = {0, 0, 1, 1}},
            })) or_else panic("buf"),
        }
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

        prev_size := size
        sdl.GetWindowSize(window, &size.x, &size.y)
        if size != prev_size {
            base.log_debug("Resizing swapchain", size)
            gpu.update_swapchain(native_window, size)
        }

        gpu.begin_frame()

        gpu.begin_pass("main", {
            colors = {
                0 = {
                    resource = gpu.get_swapchain(),
                    clear_mode = .Clear,
                    clear_val = {0.01, 0.1, 0.2, 1},
                },
            },
        })

        gpu.bind_pipeline(pip)
        gpu.draw_non_indexed(3)

        gpu.end_pass()

        gpu.end_frame(sync = true)
    }
}

Vertex :: struct {
    pos:    [4]f32,
    col:    [4]f32,
}

@(rodata)
_shader_code := `
struct Vertex {
    float4 pos;
    float4 col;
};

StructuredBuffer<Vertex> verts : register(t0);

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