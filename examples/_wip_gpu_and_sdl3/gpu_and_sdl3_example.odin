package raven_example_gpu_and_sdl3

// THIS EXAMPLE IS VERY OLD AND NEEDS UPDATING.

import "core:time"
import gpu "../../gpu"
import sdl "vendor:sdl3"
import glm "core:math/linalg/glsl"
import "core:log"
import "core:math/rand"

// https://github.com/odin-lang/examples/blob/master/directx/d3d11_minimal_sdl3/d3d11_in_odin.odin
// Based on https://gist.github.com/d7samurai/261c69490cce0620d0bfc93003cd1052


Constants :: struct #align(16) #min_field_align(16) {
    transform:    glm.mat4,
    projection:   glm.mat4,
    light_vector: glm.vec3,
}

Quad_Constants :: struct #align(16) #min_field_align(16) {
    transform: glm.mat4,
    time:   f32,
}

main :: proc() {
    assert(sdl.Init({.VIDEO}))
    defer sdl.Quit()

    context.logger = log.create_console_logger()
    log.debug("Init")

    sdl.SetHintWithPriority(sdl.HINT_RENDER_DRIVER, "direct3d11", .OVERRIDE)
    window := sdl.CreateWindow("GPU",
        854, 480,
        {.HIGH_PIXEL_DENSITY, .HIDDEN, .RESIZABLE},
    )
    defer sdl.DestroyWindow(window)

    native_window := sdl.GetPointerProperty(sdl.GetWindowProperties(window), sdl.PROP_WINDOW_WIN32_HWND_POINTER, nil)

    size: [2]i32
    sdl.GetWindowSize(window, &size.x, &size.y)

    log.info("Window size", size)

    gpu.init(native_window)
    defer gpu.shutdown()

    rt_final := gpu._update_swapchain(native_window, size)
    rt_color := gpu.create_texture_2d(.RG_F11_B_F10, size, render_texture = true)
    rt_depth := gpu.create_texture_2d(.D_F32, size, render_texture = true)

    quad_vs := gpu.create_shader(transmute([]u8)quad_hlsl, .Vertex)
    quad_ps := gpu.create_shader(transmute([]u8)quad_hlsl, .Pixel)
    post_vs := gpu.create_shader(transmute([]u8)post_hlsl, .Vertex)
    post_ps := gpu.create_shader(transmute([]u8)post_hlsl, .Pixel)
    vs := gpu.create_shader(transmute([]u8)shaders_hlsl, .Vertex)
    ps := gpu.create_shader(transmute([]u8)shaders_hlsl, .Pixel)
    cs := gpu.create_shader(transmute([]u8)life_hlsl, .Compute)

    consts := gpu.create_constants(size_of(Constants))
    quad_consts := gpu.create_constants(size_of(Quad_Constants))
    vbuf := gpu.create_buffer(size_of(Vertex), data = gpu.slice_bytes(vertex_data[:]))
    ibuf := gpu.create_index_buffer(data = gpu.slice_bytes(index_data[:]))
    quad_ibuf := gpu.create_index_buffer(data = gpu.slice_bytes([]u32{0, 1, 2, 1, 2, 3}))
    instbuf := gpu.create_buffer(size_of(Instance), data = gpu.slice_bytes(instance_data[:]), usage = .Dynamic)
    tex := gpu.create_texture_2d(.RGBA_U8_Norm, {TEXTURE_WIDTH, TEXTURE_HEIGHT}, .Immutable, data = gpu.slice_bytes(texture_data[:]))

    life_data := new([256 * 256]u8, context.temp_allocator)
    for &x in life_data {
        x = rand.float32() < 0.8 ? 255 : 0
    }

    lifetex: [2]gpu.Resource = {
        gpu.create_texture_2d(.R_U8_Norm, size = 256, data = gpu.slice_bytes(life_data[:]), rw_resource = true),
        gpu.create_texture_2d(.R_U8_Norm, size = 256, rw_resource = true),
    }

    defer {
        gpu.destroy(&rt_color)
        gpu.destroy(&rt_depth)
        gpu.destroy(&quad_vs)
        gpu.destroy(&quad_ps)
        gpu.destroy(&vs)
        gpu.destroy(&ps)
        gpu.destroy(&cs)
        gpu.destroy(&consts)
        gpu.destroy(&quad_consts)
        gpu.destroy(&vbuf)
        gpu.destroy(&ibuf)
        gpu.destroy(&quad_ibuf)
        gpu.destroy(&instbuf)
        gpu.destroy(&tex)
        gpu.destroy(&lifetex[0])
        gpu.destroy(&lifetex[1])
    }

    log.debug("Running")

    model_rotation    := glm.vec3{0.0, 0.0, 0.0}
    model_translation := glm.vec3{0.0, 0.0, 4.0}
    cull: gpu.Cull_Mode
    fill: gpu.Fill_Mode
    frame: int
    sync := true
    tick := time.tick_now()

    sdl.ShowWindow(window)
    for quit := false; !quit; {
        new_tick := time.tick_now()
        defer tick = new_tick

        for e: sdl.Event; sdl.PollEvent(&e); {
            #partial switch e.type {
            case .QUIT:
                quit = true
            case .KEY_DOWN:
                #partial switch e.key.scancode {
                case .ESCAPE:
                    quit = true

                case .C:
                    cull = gpu.Cull_Mode((int(cull) + 1) %% len(gpu.Cull_Mode))

                case .F:
                    fill = gpu.Fill_Mode((int(fill) + 1) %% len(gpu.Fill_Mode))

                case .S:
                    sync = !sync
                }
            }
        }

        prev_size := size
        sdl.GetWindowSize(window, &size.x, &size.y)
        if size != prev_size {
            rt_final = gpu._update_swapchain(native_window, size)
            gpu.destroy(&rt_depth)
            gpu.destroy(&rt_color)
            rt_color = gpu.create_texture_2d(.RG_F11_B_F10, size, render_texture = true)
            rt_depth = gpu.create_texture_2d(.D_F32, size, render_texture = true)
        }

        rotate_x := glm.mat4Rotate({1, 0, 0}, model_rotation.x)
        rotate_y := glm.mat4Rotate({0, 1, 0}, model_rotation.y)
        rotate_z := glm.mat4Rotate({0, 0, 1}, model_rotation.z)
        translate := glm.mat4Translate(model_translation)

        model_rotation.x += 0.005
        model_rotation.y += 0.009
        model_rotation.z += 0.001

        w := f32(size.x) / f32(size.y)
        h := f32(1)
        n := f32(1)
        f := f32(100)

        c: Constants = {
            transform = translate * rotate_z * rotate_y * rotate_x,
            light_vector = {+1, -1, +1},
            projection = {
                2 * n / w, 0,         0,           0,
                0,         2 * n / h, 0,           0,
                0,         0,         f / (f - n), n * f / (n - f),
                0,         0,         1,           0,
            },
        }

        for &inst in instance_data {
            inst.pos += glm.sin_f32(f32(frame) * 0.01) * 0.01
        }

        quad_c: Quad_Constants = {
            transform = glm.mat4Ortho3d(0, f32(size.x), 0, f32(size.y), -1, 1),
            time = f32(frame) / 60.0,
        }

        gpu.update_constants(consts, gpu.ptr_bytes(&c))
        gpu.update_constants(quad_consts, gpu.ptr_bytes(&quad_c))
        gpu.update_buffer(instbuf, 0, gpu.slice_bytes(instance_data[:]))

        gpu.set_shader(cs)
        gpu.set_resources({.Compute}, {
            0 = lifetex[0],
        })
        gpu.set_rw_resources({
            0 = lifetex[1],
        })
        gpu.dispatch({256 / 8, 256 / 8, 1})
        gpu.set_resources({.Compute}, {})
        gpu.set_rw_resources({})
        lifetex[0], lifetex[1] = lifetex[1], lifetex[0]

        gpu.set_render_textures({rt_color}, rt_depth)
        gpu.clear_render_texture(rt_color, {0.25, 0.5, 1.0, 1.0})
        gpu.clear_depth(rt_depth, 1)

        gpu.set_shader(vs)
        gpu.set_shader(ps)

        gpu.set_topology(.Triangles)
        gpu.set_blend({})
        gpu.set_rasterizer_desc({cull, fill, 0})
        gpu.set_depth_stencil_desc({.Less, .Write})
        gpu.set_index_buffer(ibuf, .U32)

        gpu.set_constants({.Vertex, .Pixel}, {
            0 = consts,
            1 = quad_consts,
        })

        gpu.set_samplers({.Vertex, .Pixel}, {
            0 = gpu.create_sampler(gpu.sampler_desc(.Unfiltered)),
        })

        gpu.set_resources({.Vertex, .Pixel}, {
            0 = tex,
            1 = vbuf,
            2 = instbuf,
            3 = lifetex[1],
        })

        gpu.draw_indexed(len(index_data), len(instance_data))

        gpu.set_render_textures({rt_final}, {})
        gpu.set_resources({.Vertex, .Pixel}, {
            0 = rt_color,
        })
        gpu.set_shader(post_vs)
        gpu.set_shader(post_ps)
        gpu.set_index_buffer(quad_ibuf, .U32)
        gpu.draw_indexed(6)

        gpu.set_shader(quad_vs)
        gpu.set_shader(quad_ps)
        gpu.set_index_buffer(quad_ibuf, .U32)
        gpu.draw_indexed(6)

        gpu.present_frame(sync)

        log.info("frame", frame, "duration", time.duration_milliseconds(time.tick_diff(tick, new_tick)))

        frame += 1
    }

    log.debug("Shutdown")
}

@(rodata)
life_hlsl := `
Texture2D<float> src : register(t0);
RWTexture2D<float> dst : register(u0);

[numthreads(8, 8, 1)]
void cs_main(int3 did : SV_DispatchThreadID) {
    float curr = src[did.xy];
    int neighbors = 0;
    neighbors += src[did.xy + int2(-1, -1)];
    neighbors += src[did.xy + int2( 0, -1)];
    neighbors += src[did.xy + int2( 1, -1)];
    neighbors += src[did.xy + int2(-1,  0)];
    neighbors += src[did.xy + int2( 1,  0)];
    neighbors += src[did.xy + int2(-1,  1)];
    neighbors += src[did.xy + int2( 0,  1)];
    neighbors += src[did.xy + int2( 1,  1)];

    if (curr > 0.5) {
        if (neighbors < 2 || neighbors > 3) {
            curr = 0.0f;
        }
    } else {
        if (neighbors == 3) {
            curr = 1.0f;
        }
    }

    dst[did.xy] = curr; // float(neighbors) / 8.0f;
}
`

SHARED_HLSL :: `
struct VS_Out {
    float4 pos : SV_Position;
    float2 uv : TEX;
};

cbuffer constants : register(b1) {
    float4x4 transform;
    float time;
}
`

@(rodata)
post_hlsl := SHARED_HLSL + `
SamplerState smp : register(s0);
Texture2D tex : register(t0);

VS_Out vs_main(uint vid : SV_VertexID) {
    float2 pos = float2(float(vid & 1), float (vid >> 1));
    VS_Out output;
    output.pos = float4((pos * 2.0f - 1.0f) * float2(1, -1), 0.0f, 1.0f);
    output.uv = pos;
    return output;
}

float4 ps_main(VS_Out input) : SV_Target {
    // return float4(input.uv, 0, 1);
    float3 col = tex.Sample(smp, input.uv).rgb;

    col = 0.5f + 0.5f * cos(col * time + float3(0, 0.5, 1));

    return float4(col, 1);
}
`

@(rodata)
quad_hlsl := SHARED_HLSL + `
SamplerState mysampler : register(s0);
Texture2D<float> tex : register(t3);

VS_Out vs_main(uint vid : SV_VertexID) {
    float2 pos = float2(float(vid & 1), float (vid >> 1));
    VS_Out output;
    output.pos = mul(transform, float4(pos * 256 * 2, 0.0f, 1.0f));
    output.uv = pos;
    return output;
}

float4 ps_main(VS_Out input) : SV_Target {
    return tex.Sample(mysampler, input.uv);
}
`

@(rodata)
shaders_hlsl := `
cbuffer constants : register(b0) {
    float4x4 transform;
    float4x4 projection;
    float3 light_vector;
}

struct Vertex {
    float3 position;
    float3 normal;
    float2 texcoord;
    float3 color;
};

struct Instance {
    float3 pos;
};

struct VS_Out {
    float4 position : SV_Position;
    float2 texcoord : TEX;
    float4 color    : COL;
};

Texture2D mytexture : register(t0);
SamplerState mysampler : register(s0);
StructuredBuffer<Vertex> verts : register(t1);
StructuredBuffer<Instance> insts : register(t2);

VS_Out vs_main(uint vid : SV_VertexID, uint iid : SV_InstanceID) {
    Vertex vert = verts[vid];
    Instance inst = insts[iid];
    float light = clamp(dot(normalize(mul(transform, float4(vert.normal, 0.0f)).xyz), normalize(-light_vector)), 0.0f, 1.0f) * 0.8f + 0.2f;

    VS_Out output;
    float4 world_pos = float4(inst.pos, 0) + mul(transform, float4(vert.position, 1.0f));
    output.position = mul(projection, world_pos);
    output.texcoord = vert.texcoord;
    output.color    = float4(vert.color * light, 1.0f);
    return output;
}

float4 ps_main(VS_Out input) : SV_Target {
    return mytexture.Sample(mysampler, input.texcoord.xy) * input.color;
}
`

Instance :: struct {
    pos: [3]f32
}

instance_data := []Instance{
    {{0, 0, 0}},
    {{3, 0, 0}},
    {{0, 3, 0}},
    {{3, 3, 0}},
    {{0, 0, 3}},
    {{3, 0, 3}},
    {{0, 3, 3}},
    {{3, 3, 3}},
}

TEXTURE_WIDTH  :: 2
TEXTURE_HEIGHT :: 2

@(rodata)
texture_data := [TEXTURE_WIDTH*TEXTURE_HEIGHT]u32{
    0xffffffff, 0xff7f7f7f,
    0xff7f7f7f, 0xffffffff,
}

Vertex :: struct {
    pos:        [3]f32,
    normal:     [3]f32,
    texcoord:   [2]f32,
    color:      [3]f32,
}

@(rodata)
vertex_data := [?]f32{
    -1.0,  1.0, -1.0,  0.0,  0.0, -1.0,  0.0,  0.0,  0.973,  0.480,  0.002,
    -0.6,  1.0, -1.0,  0.0,  0.0, -1.0,  2.0,  0.0,  0.973,  0.480,  0.002,
     0.6,  1.0, -1.0,  0.0,  0.0, -1.0,  8.0,  0.0,  0.973,  0.480,  0.002,
     1.0,  1.0, -1.0,  0.0,  0.0, -1.0, 10.0,  0.0,  0.973,  0.480,  0.002,
    -0.6,  0.6, -1.0,  0.0,  0.0, -1.0,  2.0,  2.0,  0.973,  0.480,  0.002,
     0.6,  0.6, -1.0,  0.0,  0.0, -1.0,  8.0,  2.0,  0.973,  0.480,  0.002,
    -0.6, -0.6, -1.0,  0.0,  0.0, -1.0,  2.0,  8.0,  0.973,  0.480,  0.002,
     0.6, -0.6, -1.0,  0.0,  0.0, -1.0,  8.0,  8.0,  0.973,  0.480,  0.002,
    -1.0, -1.0, -1.0,  0.0,  0.0, -1.0,  0.0, 10.0,  0.973,  0.480,  0.002,
    -0.6, -1.0, -1.0,  0.0,  0.0, -1.0,  2.0, 10.0,  0.973,  0.480,  0.002,
     0.6, -1.0, -1.0,  0.0,  0.0, -1.0,  8.0, 10.0,  0.973,  0.480,  0.002,
     1.0, -1.0, -1.0,  0.0,  0.0, -1.0, 10.0, 10.0,  0.973,  0.480,  0.002,
     1.0,  1.0, -1.0,  1.0,  0.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     1.0,  1.0, -0.6,  1.0,  0.0,  0.0,  2.0,  0.0,  0.897,  0.163,  0.011,
     1.0,  1.0,  0.6,  1.0,  0.0,  0.0,  8.0,  0.0,  0.897,  0.163,  0.011,
     1.0,  1.0,  1.0,  1.0,  0.0,  0.0, 10.0,  0.0,  0.897,  0.163,  0.011,
     1.0,  0.6, -0.6,  1.0,  0.0,  0.0,  2.0,  2.0,  0.897,  0.163,  0.011,
     1.0,  0.6,  0.6,  1.0,  0.0,  0.0,  8.0,  2.0,  0.897,  0.163,  0.011,
     1.0, -0.6, -0.6,  1.0,  0.0,  0.0,  2.0,  8.0,  0.897,  0.163,  0.011,
     1.0, -0.6,  0.6,  1.0,  0.0,  0.0,  8.0,  8.0,  0.897,  0.163,  0.011,
     1.0, -1.0, -1.0,  1.0,  0.0,  0.0,  0.0, 10.0,  0.897,  0.163,  0.011,
     1.0, -1.0, -0.6,  1.0,  0.0,  0.0,  2.0, 10.0,  0.897,  0.163,  0.011,
     1.0, -1.0,  0.6,  1.0,  0.0,  0.0,  8.0, 10.0,  0.897,  0.163,  0.011,
     1.0, -1.0,  1.0,  1.0,  0.0,  0.0, 10.0, 10.0,  0.897,  0.163,  0.011,
     1.0,  1.0,  1.0,  0.0,  0.0,  1.0,  0.0,  0.0,  0.612,  0.000,  0.069,
     0.6,  1.0,  1.0,  0.0,  0.0,  1.0,  2.0,  0.0,  0.612,  0.000,  0.069,
    -0.6,  1.0,  1.0,  0.0,  0.0,  1.0,  8.0,  0.0,  0.612,  0.000,  0.069,
    -1.0,  1.0,  1.0,  0.0,  0.0,  1.0, 10.0,  0.0,  0.612,  0.000,  0.069,
     0.6,  0.6,  1.0,  0.0,  0.0,  1.0,  2.0,  2.0,  0.612,  0.000,  0.069,
    -0.6,  0.6,  1.0,  0.0,  0.0,  1.0,  8.0,  2.0,  0.612,  0.000,  0.069,
     0.6, -0.6,  1.0,  0.0,  0.0,  1.0,  2.0,  8.0,  0.612,  0.000,  0.069,
    -0.6, -0.6,  1.0,  0.0,  0.0,  1.0,  8.0,  8.0,  0.612,  0.000,  0.069,
     1.0, -1.0,  1.0,  0.0,  0.0,  1.0,  0.0, 10.0,  0.612,  0.000,  0.069,
     0.6, -1.0,  1.0,  0.0,  0.0,  1.0,  2.0, 10.0,  0.612,  0.000,  0.069,
    -0.6, -1.0,  1.0,  0.0,  0.0,  1.0,  8.0, 10.0,  0.612,  0.000,  0.069,
    -1.0, -1.0,  1.0,  0.0,  0.0,  1.0, 10.0, 10.0,  0.612,  0.000,  0.069,
    -1.0,  1.0,  1.0, -1.0,  0.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -1.0,  1.0,  0.6, -1.0,  0.0,  0.0,  2.0,  0.0,  0.127,  0.116,  0.408,
    -1.0,  1.0, -0.6, -1.0,  0.0,  0.0,  8.0,  0.0,  0.127,  0.116,  0.408,
    -1.0,  1.0, -1.0, -1.0,  0.0,  0.0, 10.0,  0.0,  0.127,  0.116,  0.408,
    -1.0,  0.6,  0.6, -1.0,  0.0,  0.0,  2.0,  2.0,  0.127,  0.116,  0.408,
    -1.0,  0.6, -0.6, -1.0,  0.0,  0.0,  8.0,  2.0,  0.127,  0.116,  0.408,
    -1.0, -0.6,  0.6, -1.0,  0.0,  0.0,  2.0,  8.0,  0.127,  0.116,  0.408,
    -1.0, -0.6, -0.6, -1.0,  0.0,  0.0,  8.0,  8.0,  0.127,  0.116,  0.408,
    -1.0, -1.0,  1.0, -1.0,  0.0,  0.0,  0.0, 10.0,  0.127,  0.116,  0.408,
    -1.0, -1.0,  0.6, -1.0,  0.0,  0.0,  2.0, 10.0,  0.127,  0.116,  0.408,
    -1.0, -1.0, -0.6, -1.0,  0.0,  0.0,  8.0, 10.0,  0.127,  0.116,  0.408,
    -1.0, -1.0, -1.0, -1.0,  0.0,  0.0, 10.0, 10.0,  0.127,  0.116,  0.408,
    -1.0,  1.0,  1.0,  0.0,  1.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
    -0.6,  1.0,  1.0,  0.0,  1.0,  0.0,  2.0,  0.0,  0.000,  0.254,  0.637,
     0.6,  1.0,  1.0,  0.0,  1.0,  0.0,  8.0,  0.0,  0.000,  0.254,  0.637,
     1.0,  1.0,  1.0,  0.0,  1.0,  0.0, 10.0,  0.0,  0.000,  0.254,  0.637,
    -0.6,  1.0,  0.6,  0.0,  1.0,  0.0,  2.0,  2.0,  0.000,  0.254,  0.637,
     0.6,  1.0,  0.6,  0.0,  1.0,  0.0,  8.0,  2.0,  0.000,  0.254,  0.637,
    -0.6,  1.0, -0.6,  0.0,  1.0,  0.0,  2.0,  8.0,  0.000,  0.254,  0.637,
     0.6,  1.0, -0.6,  0.0,  1.0,  0.0,  8.0,  8.0,  0.000,  0.254,  0.637,
    -1.0,  1.0, -1.0,  0.0,  1.0,  0.0,  0.0, 10.0,  0.000,  0.254,  0.637,
    -0.6,  1.0, -1.0,  0.0,  1.0,  0.0,  2.0, 10.0,  0.000,  0.254,  0.637,
     0.6,  1.0, -1.0,  0.0,  1.0,  0.0,  8.0, 10.0,  0.000,  0.254,  0.637,
     1.0,  1.0, -1.0,  0.0,  1.0,  0.0, 10.0, 10.0,  0.000,  0.254,  0.637,
    -1.0, -1.0, -1.0,  0.0, -1.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
    -0.6, -1.0, -1.0,  0.0, -1.0,  0.0,  2.0,  0.0,  0.001,  0.447,  0.067,
     0.6, -1.0, -1.0,  0.0, -1.0,  0.0,  8.0,  0.0,  0.001,  0.447,  0.067,
     1.0, -1.0, -1.0,  0.0, -1.0,  0.0, 10.0,  0.0,  0.001,  0.447,  0.067,
    -0.6, -1.0, -0.6,  0.0, -1.0,  0.0,  2.0,  2.0,  0.001,  0.447,  0.067,
     0.6, -1.0, -0.6,  0.0, -1.0,  0.0,  8.0,  2.0,  0.001,  0.447,  0.067,
    -0.6, -1.0,  0.6,  0.0, -1.0,  0.0,  2.0,  8.0,  0.001,  0.447,  0.067,
     0.6, -1.0,  0.6,  0.0, -1.0,  0.0,  8.0,  8.0,  0.001,  0.447,  0.067,
    -1.0, -1.0,  1.0,  0.0, -1.0,  0.0,  0.0, 10.0,  0.001,  0.447,  0.067,
    -0.6, -1.0,  1.0,  0.0, -1.0,  0.0,  2.0, 10.0,  0.001,  0.447,  0.067,
     0.6, -1.0,  1.0,  0.0, -1.0,  0.0,  8.0, 10.0,  0.001,  0.447,  0.067,
     1.0, -1.0,  1.0,  0.0, -1.0,  0.0, 10.0, 10.0,  0.001,  0.447,  0.067,
    -0.6,  0.6, -1.0,  1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
    -0.6,  0.6, -0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
    -0.6, -0.6, -0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
    -0.6, -0.6, -1.0,  1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
     0.6,  0.6, -0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
     0.6,  0.6, -1.0, -1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
     0.6, -0.6, -1.0, -1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
     0.6, -0.6, -0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
    -0.6, -0.6, -1.0,  0.0,  1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
    -0.6, -0.6, -0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
     0.6, -0.6, -0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
     0.6, -0.6, -1.0,  0.0,  1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
    -0.6,  0.6, -0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
    -0.6,  0.6, -1.0,  0.0, -1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
     0.6,  0.6, -1.0,  0.0, -1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
     0.6,  0.6, -0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
     1.0,  0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     0.6,  0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     0.6, -0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     1.0, -0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     0.6,  0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     1.0,  0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     1.0, -0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     0.6, -0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     1.0,  0.6,  0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     0.6,  0.6,  0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     0.6,  0.6, -0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     1.0,  0.6, -0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     0.6, -0.6,  0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     1.0, -0.6,  0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     1.0, -0.6, -0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     0.6, -0.6, -0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
     0.6,  0.6,  1.0, -1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
     0.6,  0.6,  0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
     0.6, -0.6,  0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
     0.6, -0.6,  1.0, -1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
    -0.6,  0.6,  0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
    -0.6,  0.6,  1.0,  1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
    -0.6, -0.6,  1.0,  1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
    -0.6, -0.6,  0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
     0.6, -0.6,  1.0,  0.0,  1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
     0.6, -0.6,  0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
    -0.6, -0.6,  0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
    -0.6, -0.6,  1.0,  0.0,  1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
     0.6,  0.6,  0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
     0.6,  0.6,  1.0,  0.0, -1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
    -0.6,  0.6,  1.0,  0.0, -1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
    -0.6,  0.6,  0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
    -1.0,  0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -0.6,  0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -0.6, -0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -1.0, -0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -0.6,  0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -1.0,  0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -1.0, -0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -0.6, -0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -1.0, -0.6,  0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -0.6, -0.6,  0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -0.6, -0.6, -0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -1.0, -0.6, -0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -0.6,  0.6,  0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -1.0,  0.6,  0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -1.0,  0.6, -0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -0.6,  0.6, -0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
    -0.6,  1.0,  0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
    -0.6,  0.6,  0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
    -0.6,  0.6, -0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
    -0.6,  1.0, -0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
     0.6,  0.6,  0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
     0.6,  1.0,  0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
     0.6,  1.0, -0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
     0.6,  0.6, -0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
    -0.6,  1.0, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
    -0.6,  0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
     0.6,  0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
     0.6,  1.0, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
    -0.6,  0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
    -0.6,  1.0,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
     0.6,  1.0,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
     0.6,  0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
    -0.6, -0.6,  0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
    -0.6, -1.0,  0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
    -0.6, -1.0, -0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
    -0.6, -0.6, -0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
     0.6, -1.0,  0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
     0.6, -0.6,  0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
     0.6, -0.6, -0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
     0.6, -1.0, -0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
    -0.6, -0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
    -0.6, -1.0, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
     0.6, -1.0, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
     0.6, -0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
    -0.6, -1.0,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
    -0.6, -0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
     0.6, -0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
     0.6, -1.0,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
}

index_data := [?]u32{
      0,   1,   9,   9,   8,   0,   1,   2,   5,   5,   4,   1,   6,   7,  10,  10,   9,   6,   2,   3,  11,  11,  10,   2,
     12,  13,  21,  21,  20,  12,  13,  14,  17,  17,  16,  13,  18,  19,  22,  22,  21,  18,  14,  15,  23,  23,  22,  14,
     24,  25,  33,  33,  32,  24,  25,  26,  29,  29,  28,  25,  30,  31,  34,  34,  33,  30,  26,  27,  35,  35,  34,  26,
     36,  37,  45,  45,  44,  36,  37,  38,  41,  41,  40,  37,  42,  43,  46,  46,  45,  42,  38,  39,  47,  47,  46,  38,
     48,  49,  57,  57,  56,  48,  49,  50,  53,  53,  52,  49,  54,  55,  58,  58,  57,  54,  50,  51,  59,  59,  58,  50,
     60,  61,  69,  69,  68,  60,  61,  62,  65,  65,  64,  61,  66,  67,  70,  70,  69,  66,  62,  63,  71,  71,  70,  62,
     72,  73,  74,  74,  75,  72,  76,  77,  78,  78,  79,  76,  80,  81,  82,  82,  83,  80,  84,  85,  86,  86,  87,  84,
     88,  89,  90,  90,  91,  88,  92,  93,  94,  94,  95,  92,  96,  97,  98,  98,  99,  96, 100, 101, 102, 102, 103, 100,
    104, 105, 106, 106, 107, 104, 108, 109, 110, 110, 111, 108, 112, 113, 114, 114, 115, 112, 116, 117, 118, 118, 119, 116,
    120, 121, 122, 122, 123, 120, 124, 125, 126, 126, 127, 124, 128, 129, 130, 130, 131, 128, 132, 133, 134, 134, 135, 132,
    136, 137, 138, 138, 139, 136, 140, 141, 142, 142, 143, 140, 144, 145, 146, 146, 147, 144, 148, 149, 150, 150, 151, 148,
    152, 153, 154, 154, 155, 152, 156, 157, 158, 158, 159, 156, 160, 161, 162, 162, 163, 160, 164, 165, 166, 166, 167, 164,
}