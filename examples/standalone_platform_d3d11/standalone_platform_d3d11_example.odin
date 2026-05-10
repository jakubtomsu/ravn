package ravn_example_platform_d3d11

// D3D11 code based on:
// https://gist.github.com/d7samurai/1e9a1f1a366740f7d8a3a20397fcfa6b

import "../../platform"
import "../../base"
import "base:runtime"
import "core:math"
import "core:fmt"
import "core:sys/windows"
import "vendor:directx/d3d11"
import "vendor:directx/dxgi"
import "vendor:directx/d3d_compiler"

Vertex :: struct {
    pos:    [2]f32,
    col:    [4]f32,
}

g_verts: [dynamic]Vertex
g_screen_size: [2]f32

state: platform.State

main :: proc() {
    context.logger = base.make_logger()

    platform.init(&state)
    defer platform.shutdown()

    window := platform.create_window("demo", .Regular)
    defer platform.destroy_window(window)

    swapchain: ^dxgi.ISwapChain
    device: ^d3d11.IDevice
    device_ctx: ^d3d11.IDeviceContext
    rendertarget: ^d3d11.ITexture2D
    rendertargetview: ^d3d11.IRenderTargetView
    vs_cso: ^d3d11.IBlob
    ps_cso: ^d3d11.IBlob
    vertexshader: ^d3d11.IVertexShader
    pixelshader: ^d3d11.IPixelShader

    swapchaindesc := dxgi.SWAP_CHAIN_DESC{
        { 0, 0, {}, .R8G8B8A8_UNORM, .UNSPECIFIED, .STRETCHED },
        { 1, 0 }, {.RENDER_TARGET_OUTPUT}, 2, windows.HWND(platform.get_native_window_ptr(window)), true,
        .FLIP_DISCARD,
        {},
    }
    check(d3d11.CreateDeviceAndSwapChain(nil, .HARDWARE, nil, {.DEBUG}, nil, 0, 7, &swapchaindesc, &swapchain, &device, nil, &device_ctx))

    check(swapchain->GetDesc(&swapchaindesc))
    check(swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, cast(^rawptr)&rendertarget))
    check(device->CreateRenderTargetView(rendertarget, nil, &rendertargetview))
    check(d3d_compiler.Compile(raw_data(SHADERS), len(SHADERS), nil, nil, nil, "vertex_shader", "vs_5_0", 0, 0, &vs_cso, nil))
    check(device->CreateVertexShader(vs_cso->GetBufferPointer(), vs_cso->GetBufferSize(), nil, &vertexshader))
    check(d3d_compiler.Compile(raw_data(SHADERS), len(SHADERS), nil, nil, nil, "pixel_shader", "ps_5_0", 0, 0, &ps_cso, nil))
    check(device->CreatePixelShader(ps_cso->GetBufferPointer(), ps_cso->GetBufferSize(), nil, &pixelshader))
    viewport := d3d11.VIEWPORT{ 0, 0, f32(swapchaindesc.BufferDesc.Width), f32(swapchaindesc.BufferDesc.Height), 0, 1 }

    vert_buf: ^d3d11.IBuffer
    check(device->CreateBuffer(&d3d11.BUFFER_DESC{
        Usage = .DYNAMIC,
        ByteWidth = size_of(Vertex) * 1024 * 8,
        BindFlags = {.VERTEX_BUFFER},
        CPUAccessFlags = {.WRITE},
    }, nil, &vert_buf))

    raster_state: ^d3d11.IRasterizerState
    check(device->CreateRasterizerState(&d3d11.RASTERIZER_DESC{
        FillMode = .SOLID,
        CullMode = .NONE,
        DepthClipEnable = false,
    }, &raster_state))

    blend_state: ^d3d11.IBlendState
    check(device->CreateBlendState(&d3d11.BLEND_DESC{
        RenderTarget = {
            0 = {
                BlendEnable = true,
                RenderTargetWriteMask = u8(d3d11.COLOR_WRITE_ENABLE_ALL),
                SrcBlend = .SRC_ALPHA,
                DestBlend = .INV_SRC_ALPHA,
                BlendOp = .ADD,
                SrcBlendAlpha = .ONE,
                DestBlendAlpha = .ZERO,
                BlendOpAlpha = .ADD,
            },
        },
    }, &blend_state))
    device_ctx->OMSetBlendState(blend_state, nil, 0xffffffff)

    layout := []d3d11.INPUT_ELEMENT_DESC{
        { "POSITION", 0, .R32G32_FLOAT, 0, 0, .VERTEX_DATA, 0 },
        { "COLOR", 0, .R32G32B32A32_FLOAT, 0, 8, .VERTEX_DATA, 0 },
    }

    input_layout: ^d3d11.IInputLayout
    device->CreateInputLayout(raw_data(layout), u32(len(layout)), vs_cso->GetBufferPointer(), vs_cso->GetBufferSize(), &input_layout)
    device_ctx->IASetInputLayout(input_layout)

    keys_down: bit_set[platform.Key]

    mouse: [2]f32

    drawable_size: [2]i32

    frame := 0
    main_loop: for {
        for event in platform.poll_window_events(window) {
            fmt.println("EVENT:", event)
            #partial switch v in event {
            case platform.Event_Exit:
                break main_loop

            case platform.Event_Key:
                pressed := false
                if v.pressed {
                    if v.key not_in keys_down {
                        pressed = true
                    }

                    keys_down += {v.key}
                } else {
                    keys_down -= {v.key}
                }

                if pressed {
                    #partial switch v.key {
                    case .Escape:
                        break main_loop

                    // case .M:
                        // platform.set_mouse_relative(window, !platform._state.mouse_relative)

                    case .Tab:
                        val := !platform._state.mouse_relative
                        platform.set_mouse_relative(window, val)
                        // platform.set_mouse_visible(!val)
                        monitor := platform.get_main_monitor_rect()

                        platform.set_window_style(window, val ? .Borderless : .Regular)
                        platform.set_window_size(window, val ? monitor.size : monitor.size / 2)
                        platform.set_window_pos(window, val ? monitor.min : (monitor.min + monitor.size / 4))
                    }
                }

            case platform.Event_Mouse:
                mouse = {f32(v.pos.x), f32(v.pos.y)}

            case platform.Event_Mouse_Button:

            case platform.Event_Scroll:
            }
        }

        clear(&g_verts)

        drawable := platform.get_window_rect(window)
        g_screen_size.x = f32(drawable.size.x)
        g_screen_size.y = f32(drawable.size.y)

        if drawable.size != drawable_size {
            drawable_size = drawable.size

            // check(swapchain->ResizeBuffers(
            //     0,              // buffer count (0 = preserve existing)
            //     0,       // new width
            //     0,      // new height
            //     .UNKNOWN, // keep old format
            //     {},               // flags
            // ))
        }

        {
            col := [4]f32{0.1, 1, 0.2, 1}
            if !platform.is_window_focused(window) || platform.is_window_minimized(window) {
                col = {1, 0.1, 0.1, 1}
            }

            draw_triangle(
                {{0, 0}, {0, 100}, {100, 0}},
                col * f32(frame % 60) / 60,
            )

            draw_triangle(
                {mouse, mouse + {20, 10}, mouse + {10, 20}},
                {1, {1, 1, 1, 0}, {1, 1, 1, 0}},
            )



            for i in 0..<platform.MAX_GAMEPADS {
                gp := platform.get_gamepad_state(i) or_continue
                fmt.println("GP", i, gp)

                draw_gamepad({200 + f32(i) * 200, 100}, gp)
            }

        }

        mapped_res: d3d11.MAPPED_SUBRESOURCE
        device_ctx->Map(vert_buf, 0, .WRITE_DISCARD, {}, &mapped_res)
        runtime.mem_copy_non_overlapping(mapped_res.pData, raw_data(g_verts), size_of(Vertex) * len(g_verts))
        device_ctx->Unmap(vert_buf, 0)

        // fmt.println("frame", frame)

        device_ctx->OMSetRenderTargets(1, &rendertargetview, nil)
        device_ctx->ClearRenderTargetView(rendertargetview, &[4]f32{0.01, 0.03, 0.03, 1.0})
        stride := u32(size_of(Vertex))
        offset: u32
        device_ctx->IASetVertexBuffers(0, 1, &vert_buf, &stride, &offset)
        device_ctx->IASetPrimitiveTopology(.TRIANGLELIST)
        device_ctx->VSSetShader(vertexshader, nil, 0)
        device_ctx->PSSetShader(pixelshader, nil, 0)
        device_ctx->RSSetViewports(1, &viewport)
        device_ctx->RSSetState(raster_state)
        device_ctx->Draw(u32(len(g_verts)), 0)
        check(swapchain->Present(1, {}))

        frame += 1
    }
}

load_swapchain :: proc() {

}

draw_triangle :: proc(
    pos:    [3][2]f32,
    col:    [3][4]f32 = 1.0,
) {
    append_elems(&g_verts,
        Vertex{pos = ((pos[0] / g_screen_size) * 2.0 - 1.0) * {1, -1}, col = col[0]},
        Vertex{pos = ((pos[1] / g_screen_size) * 2.0 - 1.0) * {1, -1}, col = col[1]},
        Vertex{pos = ((pos[2] / g_screen_size) * 2.0 - 1.0) * {1, -1}, col = col[2]},
    )
}

draw_quad :: proc(
    pos:    [4][2]f32,
    col:    [4][4]f32 = 1.0,
) {
    draw_triangle(
        {pos[0], pos[1], pos[2]},
        {col[0], col[1], col[2]},
    )

    draw_triangle(
        {pos[1], pos[2], pos[3]},
        {col[1], col[2], col[3]},
    )
}

draw_box :: proc(
    pos:    [2]f32,
    size:   [2]f32,
    anchor: [2]f32 = 0.5,
    col:    [4][4]f32 = 1.0,
) {
    center := pos - size * anchor
    draw_quad(
        {
            center + {0, 0},
            center + {0, size.y},
            center + {size.x, 0},
            center + {size.x, size.y},
        },
        col,
    )
}

draw_circle :: proc(
    pos:    [2]f32,
    scale:  [2]f32,
    col:    [2][4]f32 = 1,
    res:    i32 = 16,
) {
    prev: [2]f32
    for i in 0..=res {
        t := math.TAU * (f32(i) / f32(res))

        p := pos + scale * [2]f32{math.cos(t), math.sin(t)}

        if i > 0 {
            draw_triangle(
                {pos, prev, p},
                {col[0], col[1], col[1]},
            )
        }

        prev = p
    }
}

draw_gamepad :: proc(
    pos:    [2]f32,
    gp:     platform.Gamepad_State,
) {
    draw_quad(
        {
            pos + {-100,-80},
            pos + {-150, 80},
            pos + { 100,-80},
            pos + {150, 80},
        },
        [4]f32{1, 1, 1, 0.1},
    )

    draw_circle(pos, 5, {0.5, 0.1})

    draw_circle(pos + {+50, 20}, 25, {0, 0.5})
    draw_circle(pos + {+50, 20} + {
        gp.axes[.Right_Thumb_X],
        gp.axes[.Right_Thumb_Y],
        } * 15 * {1, -1}, 15, {0.8, 1})
    draw_circle(pos + {-70,-10}, 25, {0, 0.5})
    draw_circle(pos + {-70,-10} + {
        gp.axes[.Left_Thumb_X],
        gp.axes[.Left_Thumb_Y],
        } * 15 * {1, -1}, 15, {0.8, 1})

    draw_circle(pos + { 75, -80}, {10, 10 + 10 * gp.axes[.Right_Trigger]}, col = {0.8 * gp.axes[.Right_Trigger], 1})
    draw_circle(pos + {-75, -80}, {10, 10 + 10 * gp.axes[.Left_Trigger]}, col = {0.8 * gp.axes[.Left_Trigger], 1})

    draw_circle(pos + { 75, -50}, {20, 10}, col = .Right_Shoulder in gp.buttons ? 1 : 0.6)
    draw_circle(pos + {-75, -50}, {20, 10}, col = .Left_Shoulder in gp.buttons ? 1 : 0.6)

    draw_circle(pos + { 15, -5}, 5, col = .Start in gp.buttons ? 1 : 0.6)
    draw_circle(pos + {-15, -5}, 5, col = .Back in gp.buttons ? 1 : 0.6)
}

check :: proc(res: d3d11.HRESULT, loc := #caller_location, expr := #caller_expression(res)) {
    assert(res == windows.S_OK, message = expr, loc = loc)
}

SHADERS: string: `
struct VS_INPUT {
    float4 pos : POSITION;
    float4 col : COLOR;
};

struct PS_INPUT {
    float4 pos : SV_POSITION;
    float4 col : COLOR;
};

PS_INPUT vertex_shader(VS_INPUT input) {
    PS_INPUT output;
    output.pos = float4(input.pos.x, input.pos.y, 0.0, 1.0);
    output.col = input.col;
    return output;
}

float4 pixel_shader(PS_INPUT input) : SV_TARGET {
    return input.col;
}
`