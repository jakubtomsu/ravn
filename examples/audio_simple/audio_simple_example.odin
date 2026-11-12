package ravn_audio_simple_example

import "core:log"
import "core:time"
import "core:fmt"
import "../../audio"
import "../../base"

state: audio.State

main :: proc() {
    context.logger = log.create_console_logger()

    audio_ok := audio.init(&state)
    assert(audio_ok)
    defer audio.shutdown()

    res0, res0_ok := audio.create_resource(.WAV, #load("../data/snake_death_sound.wav"))
    res1, res1_ok := audio.create_resource(.WAV, #load("../data/snake_powerup_sound.wav"))
    assert(res0_ok)
    assert(res1_ok)

    audio.set_listener(
        pos = 0,
        vel = 0,
        forw = {0, 0, 1},
        right = {1, 0, 0},
    )

    for i in 0..<10 {
        audio.update()

        sound, sound_ok := audio.create_sound(i % 2 == 0 ? res0 : res1)
        assert(sound_ok)
        fmt.eprintfln("Iter %i : %v", i, sound)
        // audio.set_sound_playing(sound, true)
        // audio.set_sound_pitch(sound, 0.5 + f32(i) * 0.2)

        for _ in 0..<100 {
            audio.update()
            time.sleep(time.Millisecond * 10)
        }
    }
}