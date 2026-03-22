package raven_simple_3d_example

import "core:fmt"
import "core:math/linalg"
import "core:math"
import rv "../.."
import "../../platform"

state: ^State

State :: struct {
    cam_pos:    rv.Vec3,
    cam_ang:    rv.Vec3,
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

    // TODO: FIXME: relative and non-relative mouse have inverted delta
    platform.set_mouse_relative(rv.get_window(), true)
    platform.set_mouse_visible(false)

    state.cam_pos = {25, 5, -25}
    state.cam_ang = {0.5, 0, 0}
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

    // TODO: abstract basic flycam controls into a simple util?

    move: rv.Vec3
    if rv.key_down(.D) do move.x += 1
    if rv.key_down(.A) do move.x -= 1
    if rv.key_down(.W) do move.z += 1
    if rv.key_down(.S) do move.z -= 1
    if rv.key_down(.E) do move.y += 1
    if rv.key_down(.Q) do move.y -= 1

    state.cam_ang.xy += rv.mouse_delta().yx * 0.005
    state.cam_ang.x = clamp(state.cam_ang.x, -math.PI * 0.49, math.PI * 0.49)

    cam_rot := rv.euler_rot(state.cam_ang)
    mat := linalg.matrix3_from_quaternion_f32(cam_rot)

    speed: f32 = 5.0
    if rv.key_down(.Left_Shift) {
        speed *= 10
    } else if rv.key_down(.Left_Control) {
        speed *= 0.1
    }

    state.cam_pos += mat[0] * move.x * delta * speed
    state.cam_pos += mat[2] * move.z * delta * speed
    state.cam_pos.y += move.y * delta * speed

    rv.set_layer_params(0, rv.make_3d_perspective_camera(state.cam_pos, cam_rot))
    rv.set_layer_params(1, rv.make_screen_camera())

    rv.bind_depth_test(true)
    rv.bind_depth_write(true)

    if rv.scope_binds() {
        rv.bind_texture("default")
        rv.bind_layer(0)


        tex := [?]rv.Texture_Handle{
            rv.get_texture("default"),
            rv.get_texture("white"),
            rv.get_texture("error"),
            rv.get_texture("uv_tex"),
        }

        depth := [4][2]bool{
            {false, false},
            {true, false},
            {false, true},
            {true, true},
        }

        offs: rv.Vec3

        for blend in rv.Blend_Mode {
            rv.bind_blend(.Opaque)
            rv.bind_fill(.All)
            rv.bind_texture(rv.get_builtin_texture(.CGA8x8thick))
            rv.draw_text(fmt.tprint(blend), offs + {-40, 0, 0}, scale = 0.15)

            rv.bind_blend(blend)

            defer {
                offs.x = 0
                offs.y -= 20
            }

            for fill in rv.Fill_Mode {
                rv.bind_fill(fill)
                for texh in tex {
                    rv.bind_texture(texh)

                    // stress_draw(rv.get_mesh("Circle"), offs)
                    // offs += {5, 0, 0}

                    stress_draw(rv.get_builtin_mesh(.Cylinder), offs)
                    offs += {5, 0, 0}

                    // stress_draw(rv.get_mesh("Icosphere"), offs)
                    // offs += {5, 0, 0}
                }
            }
        }
    }

    rv.bind_layer(1)
    rv.bind_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.bind_depth_test(true)
    rv.bind_depth_write(true)
    rv.draw_text("Use WASD and QE to move, mouse to look", {200, 14, 0.1}, scale = math.ceil(rv._state.dpi_scale)) // DPI HACK

    rv.draw_counter(.CPU_Frame_Ns, {10, 50, 0.2}, scale = 2, unit = 1e-6, col = rv.DARK_GREEN)
    rv.draw_counter(.CPU_Frame_Work_Ns, {10, 50, 0.1}, scale = 2, unit = 1e-6, col = rv.GREEN, show_text = false)
    rv.draw_counter(.Num_Draw_Calls, {10, 100, 0.1}, col = rv.ORANGE)

    rv.upload_gpu_layers()

    rv.render_gpu_layer(0, rv.DEFAULT_RENDER_TEXTURE, rv.Vec3{0, 0, 0.1}, true)
    rv.render_gpu_layer(1, rv.DEFAULT_RENDER_TEXTURE, nil, false)

    return state
}

stress_draw :: proc(handle: rv.Mesh_Handle, pos: rv.Vec3, num: int = 256, col: rv.Vec4 = {1, 1, 1, 0.25}) {
    for i in 0..<num {
        rv.draw_mesh(handle,
            pos = pos + {0, 0, f32(i) * 3},
            rot = rv.quat_angle_axis(f32(i) * 0.1 + rv.get_time(), {0, 0, 1}),
            col = col,
        )
    }
}
