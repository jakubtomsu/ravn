package ravn_gui_example

import rv "../.."
import "../../gui"
import "../../gui_glue"

state: ^State

State :: struct {
}

@export _app_desc := rv.App_Desc {
    state_size = size_of(State),
    init = _init,
    shutdown = _shutdown,
    update = _update,
}

main :: proc() {
    rv.run_main_loop(_app_desc)
}

_init :: proc() {
    state = new(State)
    gui.init()
}

_shutdown :: proc() {
    gui.shutdown()
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

    gui.begin_frame(
        screen_size = rv.get_screen_size(),
        input = gui_glue.get_input(),
    )

    if gui.window("Foo", {100, 500}) {
        gui.label("Hello")
        gui.label("Hello2")

        gui.button("button")

        if gui.split(.Left, 0.5) {
            gui.box()
            gui.label("Left")
        }

        if gui.box() {
            gui.label("right")
        }
    }

    draws := gui.end_frame()

    rv.set_draw_blend(.Alpha)
    rv.set_draw_depth(.Depth)

    rv.set_draw_layer(0)

    rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.draw_text_2d(rv.tprintf("Hello World! %v", rv.get_mouse_delta()), {20, 20})
    rv.draw_rect_2d({rv.get_mouse_pos(), rv.get_mouse_pos() + 10}, col = rv.YELLOW)

    draw_gui(draws)

    rv.update_draw_layer(0, rv.make_screen_camera(rv.get_screen_size()))
    rv.render_layer(0, clear_color = [3]f32{0.25, 0.25, 0.25}, clear_depth = true)

    return state
}

draw_gui :: proc(draws: []gui.Draw) {
    rv.scope_draw_state()
    for draw in draws {
        if draw.text == "" {
            rv.set_draw_texture(rv.get_builtin_texture(.White))
            rv.draw_rect_2d(
                cast(rv.Rect)draw.rect,
                z = draw.z,
                col = draw.color,
            )
        } else {
            rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
            rv.draw_text(
                draw.text,
                {draw.rect.min.x, draw.rect.min.y, draw.z},
                col = draw.color,
                scale = draw.scale,
                spacing = draw.spacing,
            )
        }
    }
}