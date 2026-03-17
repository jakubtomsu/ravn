package raven_shader_compiler

_Slang_State :: struct {}

_slang_init :: proc() {
    panic("Slang is disabled in the raven shader compiler (SLANG_ENABLED=false)")
}

_compile_slang_wgsl :: proc(
    name:           string,
    source:         string,
    opts:           Options,
) -> (result: []byte, ok: bool) {
    panic("Slang is disabled in the raven shader compiler (SLANG_ENABLED=false)")
}
