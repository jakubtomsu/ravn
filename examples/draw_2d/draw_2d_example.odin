package draw_2d_example

import rv "../.."

state: ^State

State :: struct {
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

    rv.update_draw_layer(0, rv.make_2d_camera(0, 1))
    rv.update_draw_layer(1, rv.make_screen_camera(0))

    rv.set_draw_blend(.Alpha)
    rv.set_draw_depth(.Depth)

    rv.set_draw_layer(0)

    // rv.draw_sprite(0, scale = 100, scaling = .Absolute)
    rv.draw_line_2d(0, {100, 0}, rv.RED)
    rv.draw_line_2d(0, {0, 100}, rv.GREEN)
    rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.draw_text_2d("Hello World!\n(worldspace text)", {20, 20})

    rv.set_draw_layer(1)

    rv.draw_text_2d("Hello Screen!\n(screenspace text)", {10, 10})

    rv.submit_layers()
    rv.render_layer(0, clear_color = [3]f32{0, 0, 0.1}, clear_depth = true)
    rv.render_layer(1, clear_color = nil, clear_depth = false)

    return state
}
