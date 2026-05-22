// FIXME: this example doesn't work yet
package raven_render_texture_example

import rv "../.."

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

    _state.tex = rv.create_render_texture({320, 180}) or_else panic("Failed to create render texture")
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

    rv.set_layer_params(0, rv.make_2d_camera())
    rv.set_layer_params(1, rv.make_screen_camera())

    { rv.scope_draw_state()
        rv.set_draw_layer(0)

        rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
        rv.draw_text_2d("Hello", 0)
        rv.draw_sprite_2d(0, scale = 100, col = rv.BLACK)
    }

    { rv.scope_draw_state()
        rv.set_draw_layer(1)
        rv.set_draw_render_texture(_state.tex)
        rv.draw_sprite_2d(0, scale = 10, scaling = .Absolute)

        rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
        rv.draw_text_2d("screenspace", 0, scale = 10)
    }

    rv.render_layer(0, _state.tex, rv.RED.rgb)
    rv.render_layer(1, clear_color = rv.DARK_CYAN.rgb)

    return _state
}