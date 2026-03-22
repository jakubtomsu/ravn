#+vet explicit-allocators shadowing unused
#+build !js
package raven_audio

// https://github.com/libsdl-org/SDL/blob/main/examples/audio/02-simple-playback-callback/simple-playback-callback.c

import "../base"
import sdl "vendor:sdl3"
import "base:intrinsics"

_ :: base
_ :: sdl
_ :: intrinsics

when BACKEND == BACKEND_SDL3 {
    _SDL3_FRAME_RATE :: 48000

    _State :: struct {
        stream: ^sdl.AudioStream,
    }

    @(require_results)
    _init :: proc() -> bool {
        if !sdl.InitSubSystem({.AUDIO}) {
            base.log_err("Failed to init SDL Audio subsystem")
            return false
        }

        spec: sdl.AudioSpec = {
            channels = 2,
            format = .F32,
            freq = _SDL3_FRAME_RATE,
        }

        _state.frame_rate = _SDL3_FRAME_RATE

        _state.stream = sdl.OpenAudioDeviceStream(
            sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK,
            spec = &spec,
            callback = _sdl3_audio_stream_callback,
            userdata = nil,
        )

        if _state.stream == nil {
            base.log_err("Failed to open SDL Audio device stream")
            return false
        }

        if !sdl.ResumeAudioStreamDevice(_state.stream) {
            base.log_err("Failed to start SDL Audio device stream")
        }

        return true
    }

    _shutdown :: proc() {
        sdl.DestroyAudioStream(_state.stream)
    }

    _render :: proc() {
        // No single threaded support
    }

    _sdl3_audio_stream_callback :: proc "c" (
        userdata:           rawptr,
        stream:             ^sdl.AudioStream,
        additional_amount:  i32,
        total_amount:       i32,
    ) {
        context = _state.init_context

        assert(_state.stream != nil)

        frames_left := additional_amount / size_of([2]f32)
        for frames_left > 0 {
            frame_buf: [480][2]f32
            frame_num := min(frames_left, len(frame_buf))

            mixer_proc := intrinsics.atomic_load(&_state.master_mixer_proc)
            if mixer_proc != nil {
                mixer_proc(frame_buf[:frame_num], frame_rate = int(_state.frame_rate))
            }

            sdl.PutAudioStreamData(stream, &frame_buf, frame_num * size_of([2]f32))
            frames_left -= frame_num
        }
    }

}