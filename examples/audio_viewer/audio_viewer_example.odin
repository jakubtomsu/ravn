package ravn_audio_viewer_example

import "core:math/rand"
import "core:math"
import rv "../.."
import "../../base"
import "../../base/ufmt"
import "../../audio"
import "../../audio/wav"

state: ^State

file_data := #load("../data/snake_death_sound.wav")

State :: struct {
    offset: f32,
    step:   f32,
    header: wav.Header,
    sound_res:  rv.Sound_Resource_Handle,
    sound_res2: rv.Sound_Resource_Handle,
    sound: rv.Sound_Handle,
    samples: []f32,
}

@export _app_desc := rv.App_Desc{
    update = _update,
    init = _init,
    shutdown = _shutdown,
}

main :: proc() {
    rv.run_main_loop(_app_desc)
}

_init :: proc() {
    state = new(State)
    state.offset = 0
    state.step = 4

    header, wav_data, ok := wav.decode_header(file_data)
    assert(ok)
    state.samples = wav.decode_samples(header.format, wav_data)
    assert(len(state.samples) > 0)

    state.sound_res = rv.create_sound_resource_encoded("wave", file_data) or_else panic("foo")
    state.header = header
}

_shutdown :: proc() {
    delete(state.samples)
    free(state)
}

pixel_to_sample :: proc(x: f32) -> f32 {
    return state.offset + (state.step * f32(state.header.format.num_channels) * x)
}

sample_to_pixel :: proc(x: f32) -> f32 {
    return (x - state.offset) / (state.step * f32(state.header.format.num_channels))
}

_update :: proc(_: rawptr) -> rawptr {
    if rv.get_key_pressed(.Escape) {
        rv.request_shutdown()
    }

    rv.update_draw_layer(0, rv.make_screen_camera(rv.get_screen_size()))

    rv.set_draw_texture(rv.get_builtin_texture(.White))

    scroll: int = 0
    if abs(rv.get_scroll_delta().y) > 0.1 {
        scroll = int(rv.get_scroll_delta().y)
    }

    if rv.get_mouse_down(.Left) && abs(rv.get_mouse_delta().x) > 0.1 {
        state.offset -= rv.get_mouse_delta().x * state.step
    }

    {
        if scroll > 0 {
            state.step /= 2
        } else if scroll < 0 {
            state.step *= 2
        }
        state.step = clamp(state.step, 0.1, 1024 * 1024)
    }

    state.offset = clamp(state.offset, -500 * state.step, f32(len(state.samples)) + 500 * state.step)

    for i in 0..<int(rv.get_screen_size().x) {
        index := int(pixel_to_sample(f32(i)))
        if index < 0 {
            continue
        }
        if index >= len(state.samples) {
            break
        }

        s := state.samples[index]
        rv.draw_sprite(
            {f32(i), rv.get_screen_size().y * 0.5, 0.5},
            scale = {1, s * 1000.0},
            scaling = .Absolute,
        )
    }

    if rv.get_key_pressed(.Space) {
        state.sound = rv.create_sound(state.sound_res,
            pitch = rand.float32_range(0.05, 2),
            volume = 2,
            pan = rand.float32_range(-1, 1),
        )
    }

    smp := audio.get_sound_time(state.sound, .Frames)

    rv.draw_sprite(
        {sample_to_pixel(smp), rv.get_screen_size().y * 0.5, 0.7},
        scale = {4, 1200.0},
        col = audio.get_sound_playing(state.sound) ? rv.GREEN : rv.DARK_GREEN,
        scaling = .Absolute,
    )

    rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.draw_text(
        ufmt.tprintf("%v", smp),
        {10, 10, 0}
    )

    rv.submit_layers()
    rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE, clear_color = rv.BLACK.rgb, clear_depth = true)

    return nil
}
