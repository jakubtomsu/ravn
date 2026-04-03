// Dummy backend which doesn't produce any audio output.
package raven_audio

when BACKEND == BACKEND_NONE {
    _State :: struct {
        _:  byte,
    }

    @(require_results)
    _init :: proc() -> bool { return true }
    _shutdown :: proc() {}
    _render :: proc() {}
}