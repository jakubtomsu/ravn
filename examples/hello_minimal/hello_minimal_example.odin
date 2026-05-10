package ravn_example_hello_minimal

import "core:math"
import rv "../.."

main :: proc() {
    rv.init_state(context.allocator)

    context = rv.get_context()

    defer rv.shutdown_state()

    for rv.begin_frame() {
        if rv.get_key_pressed(.Escape) {
            break
        }

        rv.set_layer_params(0, rv.make_screen_camera())

        rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
        rv.draw_text_2d("Hello World!",
            rv.get_screen_size() * 0.5 + {0, math.sin_f32(rv.get_time()) * 100},
            anchor = 0.5,
            scale = 4,
        )

        rv.submit_layers()

        rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE,
            clear_color = rv.Vec3{0, 0, 0.5},
            clear_depth = true,
        )

        rv.end_frame()
    }
}
