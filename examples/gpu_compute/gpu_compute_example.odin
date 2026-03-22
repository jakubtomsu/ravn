package raven_gpu_compute_example

import "core:math"
import "core:math/rand"
import "core:math/linalg"
import rv "../.."
import "../../gpu"
import "../../base"
import "../../base/ufmt"
import "../../shader_compiler"

SIZE :: 256

state: ^State

State :: struct {
    cam_pos:    rv.Vec3,
    tex_index:  i32,
    tex_len:    i32,
    fill:       f32,
    tex:        [64]rv.Texture_Handle,
    cs:         gpu.Shader_Handle,
}

@export _module_desc := rv.Module_Desc {
    state_size = size_of(State),
    init = _init,
    shutdown = _shutdown,
    update = _update,
}

main :: proc() {
    rv.run_main_loop(_module_desc)
}

_init :: proc() {
    state = new(State)

    life_hlsl := #load("gpu_compute_life.hlsl", string)

    cs_bin := shader_compiler.compile("life.hlsl", life_hlsl, {target = .DXBC, stage = .Compute}) or_else panic("Shader compile")
    state.cs = gpu.create_shader("life", cs_bin, .Compute) or_else panic("Shader")

    pixels := make([][4]u8, SIZE * SIZE, context.temp_allocator)
    state.fill = 0.5
    for &pixel in pixels {
        pixel = rand.float32() > state.fill ? 255 : 0
    }

    for &t, i in state.tex {
        // t = rv.create_texture_from_data("grid", data) or_else panic("tex")
        name := ufmt.tprintf("grid%i", i)
        res := gpu.create_texture_2d(name, .RGBA_U8_Norm, SIZE, rw_resource = true, data = gpu.slice_bytes(pixels)) or_else panic("tex")
        t = rv.create_texture_from_resource(name, res) or_else panic("tex")
    }
}

_shutdown :: proc() {
    free(state)
}

_update :: proc(hot_state: rawptr) -> rawptr {
    if hot_state != nil {
        state = cast(^State)hot_state
    }

    if rv.key_pressed(.Escape) {
        rv.request_shutdown()
    }

    delta := rv.get_delta_time()

    cam_pos := rv.Vec3{-1, 1, -1} * 10
    mouse := rv.mouse_pos() / rv.get_screen_size() - 0.5
    cam_pos += rv.Vec3{1, 0, -1} * mouse.x * 10
    cam_pos += rv.Vec3{-1, 0, -1} * mouse.y * 10

    state.cam_pos = rv.lexp(state.cam_pos, cam_pos, delta * 4)

    cam := rv.make_3d_orthographic_camera(
        pos = state.cam_pos,
        rot = linalg.quaternion_from_forward_and_up_f32(-{1, -1, 1}, {0, 1, 0}),
        fov = 5,
    )

    if rv.key_pressed(.Space) {
        state.tex_index = 0
        state.tex_len = 0

        pixels := make([][4]u8, SIZE * SIZE, context.temp_allocator)
        state.fill = rand.float32_range(0.05, 0.95)
        for &pixel in pixels {
            pixel = rand.float32() > state.fill ? 255 : 0
        }

        gpu.update_texture_2d(rv.get_internal_texture(state.tex[0]).resource, gpu.slice_bytes(pixels))
    }

    {
        gpu.scope_compute_pass("life")

        next := (state.tex_index + 1) %% len(state.tex)

        desc := gpu.compute_pipeline_desc(
            state.cs,
            resources = {
                rv.get_internal_texture(state.tex[state.tex_index]).resource,
            },
            rw_resources = {
                rv.get_internal_texture(state.tex[next]).resource,
            },
        )

        pip := gpu.create_compute_pipeline("life", desc) or_else panic("cs pipeline")

        gpu.bind_compute_pipeline(pip)

        gpu.dispatch_compute({SIZE / 8, SIZE / 8, 1})

        state.tex_index = next
        state.tex_len = min(state.tex_len + 1, len(state.tex))
    }

    rv.set_layer_params(0, cam)
    rv.set_layer_params(1, rv.make_screen_camera())

    rv.bind_depth_test(true)
    rv.bind_depth_write(true)

    // rv.draw_mesh(
    //     rv.get_builtin_mesh(.Cylinder),
    //     pos = 0,
    // )

    for i in 0..<i32(state.tex_len-1) {
        rv.bind_texture(state.tex[(state.tex_index - i) %% len(state.tex)])
        t := f32(i) / f32(len(state.tex))

        // brute force thickness
        THICK :: 6
        for j in 0..<i32(THICK) {
            rv.draw_sprite(
                {0, -f32(i * THICK + j) * 0.005, 0},
                rot = linalg.quaternion_angle_axis_f32(math.PI * 0.5, {1, 0, 0}),
                scale = 16,
                col = i + j == 0 ? rv.LIGHT_PINK + 0.2 : rv.oklerp(rv.LIGHT_PINK, rv.DARK_BLUE * 0.5, t),
                scaling = .Absolute,
            )
        }
    }

    rv.draw_line_mat3(0, 1)

    rv.bind_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.bind_layer(1)
    rv.draw_text(ufmt.tprintf("press space to restart\ntex: %v\nfill: %v", state.tex_index, state.fill), {10, 10, 0})

    rv.draw_counter(.CPU_Frame_Ns, {20, 200, 0.1}, scale = 2, unit = 1e-6, col = rv.GREEN)

    rv.submit_layers()
    rv.render_layer(0, clear_color = rv.DARK_BLUE.rgb * 0.5, clear_depth = true)
    rv.render_layer(1, clear_color = nil, clear_depth = true)

    return state
}