package raven_example_hello

// This would look like 'import rv "raven"' in your own projects.
import rv "../.."

// Module_Desc structure let's Raven know which procedures to call to init, update frame etc.
// The '@export' qualifier makes sure it's visible when running in hot-reload mode.
// The state_size is optional for error checking during hotreload.
@export _module_desc := rv.Module_Desc{
    update = _update,
}

// The main procedure is your app's entry point.
// But to support multiple platforms, Raven handles the frame update loop, only calling your module.
main :: proc() {
    // If you really want you can write your own main loop directly,
    // but you have to handle the platform differences manually.
    rv.run_main_loop(_module_desc)
}

// The update procedure executes every frame.
// Raven has a internal frame loop, which looks like this:
//
// while not app_requested_shutdown:
//      1. read input and prepare frame
//      2. module.update() <--- we're here
//      3. submit GPU commands wait for new frame (vsync)
//
// NOTE: see simple_3d or other examples to learn how a full app with state does hotreload.
_update :: proc(_: rawptr) -> rawptr {
    if rv.key_pressed(.Escape) {
        rv.request_shutdown()
    }

    // Raven renders into "draw layers".
    // Layer 0 is the default one, so let's set up a regular screenspace view for it.
    rv.set_layer_params(0, rv.make_screen_camera())

    // To configure draw state like blending, textures, shaders, current layer, etc, call 'rv.bind_*'
    // You can also call push_binds/pop_binds to save and restore the bind state.
    rv.bind_texture(rv.get_builtin_texture(.CGA8x8thick))

    rv.draw_sprite({100, 100, 0}, rv.font_slot(0), scale = 1, col = rv.PURPLE)

    // Odin strings are UTF-8 encoded, but fonts are currently CP437 16x16 atlases.
    // Unicode fonts might get supported later.
    rv.draw_text("Hello World! ☺", {100, 100, 0}, scale = 4, spacing = 1)

    // Draw the full font atlas texture, with color based on space key input.
    col := rv.key_down(.Space) ? rv.GREEN : rv.WHITE
    rv.draw_sprite({rv.get_screen_size().x * 0.5, rv.get_screen_size().y * 0.5, 0.1}, scale = 2, col = col)

    // The 'rv.draw_*' commands only record what geometry you want to render each frame.
    // To actually display it on the screen you must first upload it to the GPU, and then
    // explicily render each layer into a particular render texture.
    rv.submit_layers()
    rv.render_layer(0, clear_color = rv.DARK_BLUE.rgb, clear_depth = true)

    return nil
}
