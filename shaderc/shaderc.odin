#+vet explicit-allocators shadowing style
package ravn_shaderc

import "core:log"
import "core:strings"
import "core:os"
import "base:runtime"

when ODIN_OS == .Windows {
    DEFAULT_TARGET :: Target.DXBC
} else {
    DEFAULT_TARGET :: Target.WGSL
}

_state: ^State

State :: struct {
    slang:              _Slang_State,
    allocator:          runtime.Allocator,
}

Target :: enum u8 {
    Invalid = 0,
    DXBC,
    HLSL,
    WGSL,
    SPIRV,
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
    include_dirs:   [dynamic; 32]string,
    user:           rawptr,
}

Include_Proc :: #type proc (path: string, opts: Options) -> (string, bool)

DEFAULT_OPTIONS :: Options{
    target = DEFAULT_TARGET,
    include_proc = file_system_include_proc,
    include_dirs = {
        ".",
    },
}

@(require_results)
init :: proc(state_ptr: ^State = nil, allocator := context.allocator) -> bool {
    if state_ptr == nil {
        _state = new(State, allocator)
        _state.allocator = allocator
    } else {
        _state = state_ptr
    }

    if !_slang_init(&_state.slang) {
        return false
    }

    return true
}

shutdown :: proc() {
    assert(_state != nil)
    if _state.allocator != {} {
        free(_state, _state.allocator)
    }
    _state = nil
}

get_target_file_ext :: proc(target: Target) -> string {
    switch target {
    case .Invalid:  return "invalid"
    case .DXBC:     return "dxbc"
    case .WGSL:     return "wgsl"
    case .HLSL:     return "hlsl"
    case .SPIRV:    return "spv"
    }
    assert(false)
    return "none"
}

compile :: proc {
    compile_from_path,
    compile_from_source,
}

compile_from_path :: proc(
    path:       string,
    opts:       Options = DEFAULT_OPTIONS,
    allocator   := context.allocator,
    loc         := #caller_location,
) -> (result: []byte, ok: bool) {
    data, err := os.read_entire_file_from_path(path, context.temp_allocator)
    if err != nil {
        log.error("Failed to read shader file:", err)
        return {}, false
    }
    return compile_from_source(path, string(data), opts, allocator = allocator)
}

compile_from_source :: proc(
    name:       string,
    source:     string,
    opts:       Options = DEFAULT_OPTIONS,
    allocator   := context.allocator,
    loc         := #caller_location,
) -> (result: []byte, ok: bool) {
    opts := opts

    assert(_state != nil)
    assert(opts.target != .Invalid)

    if opts.target == .Invalid {
        log.error("Invalid target")
        return nil, false
    }

    if opts.stage == .Invalid {
        if strings.contains(name, ".vs.") {
            opts.stage = .Vertex
        } else if strings.contains(name, ".ps.") {
            opts.stage = .Pixel
        } else if strings.contains(name, ".cs.") {
            opts.stage = .Compute
        }
    }

    assert(opts.stage != .Invalid, "You must specify shader stage")

    switch opts.target {
    case .Invalid:
        assert(false)
        return nil, false

    case .DXBC:
        when ODIN_OS == .Windows {
            slang_opts := opts
            slang_opts.target = .HLSL
            hlsl, hlsl_ok := _slang_compile(name, source, slang_opts, allocator = allocator)
            if !hlsl_ok {
                log.error("Failed to compile to HLSL")
                return nil, false
            }

            d3d_opts := opts
            d3d_opts.include_proc = nil
            result, ok = _d3dcompiler_compile_hlsl_to_dxbc(name, string(hlsl), d3d_opts, allocator = allocator)
        } else {
            log.error("Cannot compile to DXBC, d3dcompiler not available on this platform")
            return nil, false
        }

    case .WGSL, .SPIRV, .HLSL:
        result, ok = _slang_compile(name, source, opts, allocator = allocator)
    }

    if !ok {
        log.error("Failed to compile")
        return nil, false
    }

    return result, true
}

file_system_include_proc : Include_Proc : proc(path: string, opts: Options) -> (string, bool) {
    for dir in opts.include_dirs {
        actual_path := os.join_path({dir, path}, context.temp_allocator) or_continue
        // log.debug(actual_path, path)
        data, err := os.read_entire_file_from_path(actual_path, allocator = context.temp_allocator)
        if err == nil {
            return string(data), true
        }
    }
    return "", false
}
