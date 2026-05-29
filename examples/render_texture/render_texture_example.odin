// FIXME: this example doesn't work yet
package raven_render_texture_example

import rv "../.."
import "core:math/linalg"

SIZE :: [2]i32{100, 100}

@export _module_desc := rv.Module_Desc{
    state_size = size_of(State),
    update = _update,
    init = _init,
    shutdown = _shutdown,
}

main :: proc() {
    rv.run_main_loop(_module_desc)
}

_state: ^State
State :: struct {
    tex:    rv.Render_Texture_Handle,
}

_init :: proc() {
    _state = new(State)

    _state.tex = rv.create_render_texture(SIZE) or_else panic("Failed to create render texture")
}

_shutdown :: proc() {
    free(_state)
    _state = nil
}

_update :: proc(hot: rawptr) -> rawptr {
    if hot != nil {
        _state = cast(^State)hot
    }

    if rv.get_key_pressed(.Escape) {
        rv.request_shutdown()
    }

    rv.update_draw_layer(0, rv.make_orthographic_3d_camera(cast([2]f32)SIZE, {0, 0, -1}, 1), flags = {.Flip_Y})
    rv.update_draw_layer(1, rv.make_perspective_3d_camera(
        rv.get_screen_size(),
        pos = [3]f32{0, 0.3, -1} * 5,
        rot = linalg.quaternion_angle_axis_f32(0.3, {1, 0, 0}),
        fov = rv.deg(20),
    ))

    { rv.scope_draw_state()
        rv.set_draw_layer(0)

        rv.set_draw_depth(.Depth)
        rv.set_draw_texture(rv.get_builtin_texture(.Default))

        rv.draw_mesh(rv.get_builtin_mesh(.Suzanne), pos = 0, scale = 0.6 * {1, -1, 1}, rot = linalg.quaternion_angle_axis(rv.get_time(), [3]f32{0, 1, 0}))
        rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
        rv.draw_text("Hello", {0, 1, 0}, 0.03, anchor = 0)
    }

    { rv.scope_draw_state()
        rv.set_draw_layer(1)
        rv.set_draw_render_texture(_state.tex)
        // rv.set_draw_texture(rv.get_builtin_texture(.Default))
        // rv.draw_sprite_2d(rv.get_screen_size() / 2, scaling = .Pixel)

        rv.set_draw_depth(.Depth)
        rv.draw_box(0, 0.5, linalg.quaternion_angle_axis_f32(rv.get_time() * 0.5, {0, 1, 0}))

        rv.set_draw_texture({})
        rv.draw_box({0, -0.6, 0}, {0.5, 0, 0.5}, linalg.quaternion_angle_axis_f32(rv.get_time() * 0.5, {0, 1, 0}), col = rv.BLACK)
    }

    rv.render_layer(0, _state.tex, rv.ORANGE.rgb)
    rv.render_layer(1, clear_color = [3]f32{0.05, 0.1, 0.2})

    return _state
}