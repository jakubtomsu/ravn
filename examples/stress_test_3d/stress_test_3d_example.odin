package ravn_simple_3d_example

import "core:math/rand"
import "core:fmt"
import "core:math/linalg"
import "core:math"
import rv "../.."
import "../../platform"

state: ^State

State :: struct {
    cam_pos:    rv.Vec3,
    cam_ang:    rv.Vec3,

    death_sound: rv.Sound_Resource_Handle,
    berry_sound: rv.Sound_Resource_Handle,
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

    state.death_sound = rv.create_sound_resource_encoded("death", #load("../data/snake_death_sound.wav")) or_else panic("load")
    state.berry_sound = rv.create_sound_resource_encoded("berry", #load("../data/snake_powerup_sound.wav")) or_else panic("load")
}

_shutdown :: proc() {
    free(state)
}

_update :: proc(hot_state: rawptr) -> rawptr {
    if hot_state != nil {
        state = cast(^State)hot_state
    }

    if rv.get_key_pressed(.Escape) {
        rv.request_shutdown()
    }


    delta := rv.get_delta_time()

    // TODO: abstract basic flycam controls into a simple util?

    move: rv.Vec3
    if rv.get_key_down(.D) do move.x += 1
    if rv.get_key_down(.A) do move.x -= 1
    if rv.get_key_down(.W) do move.z += 1
    if rv.get_key_down(.S) do move.z -= 1
    if rv.get_key_down(.E) do move.y += 1
    if rv.get_key_down(.Q) do move.y -= 1

    state.cam_ang.xy += rv.get_mouse_delta().yx * 0.005
    state.cam_ang.x = clamp(state.cam_ang.x, -math.PI * 0.49, math.PI * 0.49)

    cam_rot := rv.euler_rot(state.cam_ang)
    mat := linalg.matrix3_from_quaternion_f32(cam_rot)

    speed: f32 = 5.0
    if rv.get_key_down(.Left_Shift) {
        speed *= 10
    } else if rv.get_key_down(.Left_Control) {
        speed *= 0.1
    }

    state.cam_pos += mat[0] * move.x * delta * speed
    state.cam_pos += mat[2] * move.z * delta * speed
    state.cam_pos.y += move.y * delta * speed

    rv.set_layer_params(0, rv.make_3d_perspective_camera(state.cam_pos, cam_rot))
    rv.set_layer_params(1, rv.make_screen_camera())

    rv.set_draw_depth(.Depth)

    if rv.scope_draw_state() {
        rv.set_draw_texture(rv.get_builtin_texture(.Default))
        rv.set_draw_layer(0)


        tex := [?]rv.Texture_Handle{
            rv.get_texture("default"),
            rv.get_texture("white"),
            rv.get_texture("error"),
            rv.get_texture("uv_tex"),
        }

        offs: rv.Vec3

        for blend in rv.Blend_Mode {
            rv.set_draw_blend(.Opaque)
            rv.set_draw_fill(.All)
            rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
            rv.draw_text(fmt.tprint(blend), offs + {-40, 0, 0}, scale = 0.15)

            rv.set_draw_blend(blend)

            defer {
                offs.x = 0
                offs.y -= 20
            }

            for fill in rv.Fill_Mode {
                rv.set_draw_fill(fill)
                for texh in tex {
                    rv.set_draw_texture(texh)

                    anim := rv.Vec3{0, rv.nsin(rv.get_time() + (offs.x + offs.y + offs.z) * 0.03), 0}


                    stress_draw(rv.get_builtin_mesh(.Cylinder), offs + anim)
                    offs += {5, 0, 0}

                    stress_draw(rv.get_builtin_mesh(.Icosphere), offs + anim)
                    offs += {5, 0, 0}
                }
            }
        }
    }

    rv.set_draw_layer(1)
    rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.set_draw_depth(.Depth)
    rv.draw_text("Use WASD and QE to move, mouse to look", {200, 14, 0.1}, scale = math.ceil(rv._state.dpi_scale)) // DPI HACK

    rv.draw_perf_scopes()

    rv.draw_perf_counter(.Frame_Time, {10, 500, 0.2}, scale = 2, col = rv.DARK_GREEN, show_text = false)
    rv.draw_perf_counter(.Frame_Work_Time, {10, 500, 0.1}, scale = 2, col = rv.GREEN)
    rv.draw_perf_counter(.Num_Draw_Calls, {10, 550, 0.1}, col = rv.ORANGE)
    // rv.draw_perf_counter(.Num_Total_Instances, {10, 600, 0.1}, scale = 0.001, col = rv.ORANGE)

    rv.submit_layers()

    rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE, rv.Vec3{0, 0, 0.1}, true)
    rv.render_layer(1, rv.DEFAULT_RENDER_TEXTURE, nil, false)

    return state
}

stress_draw :: proc(handle: rv.Mesh_Handle, pos: rv.Vec3, num: int = 256, col: rv.Vec4 = {1, 1, 1, 0.25}) {
    for i in 0..<num {
        rv.draw_mesh(handle,
            pos = pos + {0, 0, f32(i) * 3},
            col = col,
        )

        rv.draw_sprite(pos + {0, 0, f32(i) * 3}, scale = 0.01)
    }
}
