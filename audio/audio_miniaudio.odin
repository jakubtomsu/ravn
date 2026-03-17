#+vet explicit-allocators shadowing unused
#+build !js
package raven_audio

import "base:runtime"
import "base:intrinsics"
import "../base"
// https://miniaud.io/docs/manual/index.html
import ma "vendor:miniaudio"

_ :: ma
_ :: base
_ :: runtime

when BACKEND == BACKEND_MINIAUDIO {
    _State :: struct {
        device:     ma.device,
    }

    @(require_results)
    _init :: proc() -> bool {
        config := ma.device_config_init(.playback)
        config.playback.format   = .f32
        config.playback.channels = 2
        config.sampleRate        = 0 // native
        config.dataCallback      = _miniaudio_data_callback

        if ma.device_init(nil, &config, &_state.device) != .SUCCESS {
            base.log_err("Failed to initialize miniaudio the device")
            return false
        }

        _state.frame_rate = _state.device.sampleRate

        if ma.device_start(&_state.device) != .SUCCESS {
            base.log_err("Failed to start miniaudio device")
            return false
        }

        return true
    }

    _shutdown :: proc() {
        ma.device_uninit(&_state.device)
    }

    _render :: proc() {
        // No single threaded support
    }

    _miniaudio_data_callback :: proc "c" (
        pDevice:    ^ma.device,
        pOutput:    rawptr,
        pInput:     rawptr, // const
        frameCount: u32,
    ) {
        // In playback mode copy data to pOutput. In capture mode read data from pInput. In full-duplex mode, both
        // pOutput and pInput will be valid and you can move data from pInput into pOutput. Never process more than
        // frameCount frames.

        context = _state.init_context

        assert(pDevice != nil)
        assert(pDevice.sampleRate == _state.frame_rate)
        assert(pOutput != nil)
        assert(frameCount > 0)

        frame_buf := (cast([^][2]f32)pOutput)[:frameCount]
        assert(0 == runtime.memory_compare_zero(pOutput, size_of(f32) * 2 * int(frameCount)))

        mixer_proc := intrinsics.atomic_load(&_state.master_mixer_proc)
        mixer_proc(frame_buf, frame_rate = int(_state.frame_rate))
    }

}