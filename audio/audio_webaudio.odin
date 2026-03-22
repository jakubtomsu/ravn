#+build js
package raven_audio

import "../base"

// NOTE: no backend guard, this must be active on JS
#assert(BACKEND == BACKEND_WEBAUDIO)

_WEBAUDIO_BUFFER_FRAMES :: 480
_WEBAUDIO_FRAME_RATE :: 48000
_WEBAUDIO_TARGET_LATENCY_MS :: 50
// like 3-10 buffers should be good
_WEBAUDIO_TARGET_QUEUED_BUFFERS ::
    _WEBAUDIO_FRAME_RATE * _WEBAUDIO_TARGET_LATENCY_MS / _WEBAUDIO_BUFFER_FRAMES / 1000 // buffers per ms

#assert(_WEBAUDIO_TARGET_QUEUED_BUFFERS > 0)
#assert(_WEBAUDIO_TARGET_QUEUED_BUFFERS <= 20)

_State :: struct {
    _:  byte,
}

@(require_results)
_init :: proc() -> bool {
    base.log_info("Webaudio init")
    _state.frame_rate = _WEBAUDIO_FRAME_RATE
    _init_js() // async
    return true
}

_shutdown :: proc() {
    _shutdown_js()
}

_render :: proc() {
    num_queued := _get_num_queued_buffers()

    target_queued_buffer: i32 = _WEBAUDIO_TARGET_QUEUED_BUFFERS

    for ;num_queued < target_queued_buffer; num_queued += 1 {
        buffer: [_WEBAUDIO_BUFFER_FRAMES][2]f32

        mixer_proc := _state.master_mixer_proc
        if mixer_proc != nil {
            mixer_proc(buffer[:], frame_rate = int(_state.frame_rate))
        }

        // de-interleave in WASM land

        transposed: [2][_WEBAUDIO_BUFFER_FRAMES]f32
        for frame, i in buffer {
            transposed[0][i] = frame[0]
            transposed[1][i] = frame[1]
        }

        _push_buffer(&transposed[0][0])
    }
}

@(export)
foreign import raven_audio "raven_audio"

@(default_calling_convention="c")
foreign raven_audio {
    @(link_name = "init")
    _init_js :: proc "contextless" () ---

    @(link_name = "shutdown")
    _shutdown_js :: proc "contextless" () ---

    @(link_name = "push_buffer")
    _push_buffer :: proc "contextless" (data_ptr: [^]f32) ---

    @(link_name = "get_num_queued_buffers", require_results)
    _get_num_queued_buffers :: proc "contextless" () -> i32 ---
}
