package ravn_shader_compiler

_Slang_State :: struct {}

_slang_init :: proc(state: ^_Slang_State) -> bool {
    return false
}

_compile_slang_wgsl :: proc(
    state:          ^State,
    name:           string,
    source:         string,
    opts:           Options,
) -> (result: []byte, ok: bool) {
    return nil, false
}
