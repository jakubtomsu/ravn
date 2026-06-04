#+vet explicit-allocators shadowing style
package ravn_shader_compiler

import "../base"

import "base:runtime"

State :: struct {
    target:             Target,
    slang:              _Slang_State,
}

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
    stage:          Stage,
    defines:        [][2]string,
    release:        bool,

    include_proc:   Include_Proc,
    user:           rawptr,
}

Include_Proc :: #type proc (path: string, user: rawptr) -> (string, bool)

// If this returns false the shader compiler is not available. Do not call any other procedures.
@(require_results)
init :: proc(state: ^State, target: Target) -> bool {
    switch target {
    case .Invalid:
        return false

    case .DXBC:
        // Requires d3d11compiler DLL
        return ODIN_OS == .Windows

    case .WGSL:
        return _slang_init(&state.slang)
    }

    return false
}

compile :: proc(
    state:          ^State,
    name:           string,
    source:         string,
    opts:           Options,
    loc := #caller_location,
) -> (result: []byte, ok: bool) {
    assert(state != nil)
    assert(opts.stage != .Invalid, "You must specify the shader stage")

    switch state.target {
    case .Invalid:
        assert(false)

    case .DXBC:
        when ODIN_OS == .Windows {
            result, ok = _compile_dxbc(name, source, opts)
        } else {
            assert(false)
        }

    case .WGSL:
        result, ok = _compile_slang_wgsl(state, name, source, opts)
    }

    return result, ok
}

clone_to_cstring :: proc(s: string, allocator := context.allocator, loc := #caller_location) -> (res: cstring, err: runtime.Allocator_Error) #optional_allocator_error {
    c := make([]byte, len(s)+1, allocator, loc) or_return
    copy(c, s)
    c[len(s)] = 0
    return cstring(&c[0]), nil
}
