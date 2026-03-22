package raven_audio_viewer_example

import "core:math/rand"
import "core:math"
import rv "../.."
import "../../base"
import "../../base/ufmt"
import "../../audio"
import "../../audio/wav"
import "../../audio/qoa"

state: ^State

file_data := #load("../data/snake_death_sound.wav")
// file_data := #load("../data/162493__tasmanianpower__vinyl-rewind.wav")

State :: struct {
    offset: f32,
    step:   f32,
    header: wav.Header,
    sound_res:  rv.Sound_Resource_Handle,
    sound_res2: rv.Sound_Resource_Handle,
    sound: rv.Sound_Handle,
    samples: []f32,
}

@export _module_desc := rv.Module_Desc{
    update = _update,
    init = _init,
    shutdown = _shutdown,
}

main :: proc() {
    rv.run_main_loop(_module_desc)
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

    sin_samples := make([]f32, 480)
    for &smp, i in sin_samples {
        smp = f32(i) / 1000
    }

    state.sound_res2 = audio.create_resource_mono_f32(sin_samples, frame_rate = audio._state.frame_rate) or_else panic("kdjfslksdf")
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
    if rv.key_pressed(.Escape) {
        rv.request_shutdown()
    }

    rv.set_layer_params(0, rv.make_screen_camera())

    rv.bind_texture(rv.get_builtin_texture(.White))

    scroll: int = 0
    if abs(rv.scroll_delta().y) > 0.1 {
        scroll = int(rv.scroll_delta().y)
    }

    if rv.mouse_down(.Left) && abs(rv.mouse_delta().x) > 0.1 {
        state.offset -= rv.mouse_delta().x * state.step
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

    if rv.key_pressed(.Space) {
        state.sound = rv.create_sound(state.sound_res2,
            // pitch = rand.float32_range(0.01, 2),
            // volume = 2,
            flags = {.Loop},
            // pan = rand.float32_range(-1, 1),
        )
    }

    smp := audio.get_sound_time(state.sound, .Frames)

    rv.draw_sprite(
        {sample_to_pixel(smp), rv.get_screen_size().y * 0.5, 0.7},
        scale = {4, 1200.0},
        col = audio.get_sound_playing(state.sound) ? rv.GREEN : rv.DARK_GREEN,
        scaling = .Absolute,
    )

    rv.bind_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.draw_text(
        ufmt.tprintf("%v", smp),
        {10, 10, 0}
    )

    rv.upload_gpu_layers()
    rv.render_gpu_layer(0, rv.DEFAULT_RENDER_TEXTURE, clear_color = rv.BLACK.rgb, clear_depth = true)

    return nil
}
