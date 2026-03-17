#+build js
package raven_audio

import "../base"

#assert(BACKEND == BACKEND_WEBAUDIO)

// NOTE: no backend guard,

_State :: struct {
    _:  byte,
}

@(require_results)
_init :: proc() -> bool {
    _init_js() // async
    return true
}

_shutdown :: proc() {
    _shutdown_js()
}

_render :: proc() {

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
    _get_num_queued_buffers :: proc "contextless" () -> i64 ---
}
