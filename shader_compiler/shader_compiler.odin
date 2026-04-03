#+vet explicit-allocators shadowing style
package raven_shader_compiler

import "../base"

import "base:runtime"

SLANG_ENABLED :: #config(SHADER_COMPILER_SLANG_ENABLED, true)

Target :: enum u8 {
    Invalid = 0,
    DXBC,
    WGSL,
}

Stage :: enum u8 {
    Invalid = 0,
    Vertex,
    Pixel,
    Compute,
}

Options :: struct {
    target:         Target,
    stage:          Stage,
    defines:        [][2]string,
    release:        bool,

    include_proc:   Include_Proc,
    user:           rawptr,
}

Include_Proc :: #type proc (path: string, user: rawptr) -> (string, bool)

_state: ^State

State :: struct {
    using _slang: _Slang_State,
}

init :: proc(state: ^State) {
    _state = state
    _slang_init()
}

compile :: proc(
    name:           string,
    source:         string,
    opts:           Options,
    loc := #caller_location,
) -> (result: []byte, ok: bool) {
    assert(_state != nil, "You must first call init()")
    assert(opts.target != .Invalid, "You must specify the target output format")
    assert(opts.stage != .Invalid, "You must specify the shader stage")

    base.log_info("Compiling %s: %v, %v", name, opts.stage, opts.target, loc = loc)

    switch opts.target {
    case .Invalid:
        assert(false)

    case .DXBC:
        when ODIN_OS == .Windows {
            result, ok = _compile_dxbc(name, source, opts)
        } else {
            base.log_err("D3D11 shader compilation is not supported on non-windows platforms")
            assert(false)
        }

    case .WGSL:
        // TODO: Call slang/naga/dawn here...
        // base.log_err("WGSL transpilation is not supported yet.")
        // HACK: for now passthrough, assume WGPU input
        // return transmute([]byte)source, true

        result, ok = _compile_slang_wgsl(name, source, opts)
    }

    return result, ok
}

clone_to_cstring :: proc(s: string, allocator := context.allocator, loc := #caller_location) -> (res: cstring, err: runtime.Allocator_Error) #optional_allocator_error {
    c := make([]byte, len(s)+1, allocator, loc) or_return
    copy(c, s)
    c[len(s)] = 0
    return cstring(&c[0]), nil
}
