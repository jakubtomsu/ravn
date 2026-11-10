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
    target:             Target,
    slang:              _Slang_State,
    allocator:          runtime.Allocator,
}

Target :: enum u8 {
    Invalid = 0,
    DXBC,
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
    stage:          Stage,
    defines:        [][2]string,
    release:        bool,
    include_proc:   Include_Proc,
    include_dirs:   [dynamic; 32]string,
    user:           rawptr,
}

Blob :: struct {
    _dxbc:  _DXBC_Blob,
    _slang: _Slang_Blob,
    data:   []byte,
}

Include_Proc :: #type proc (path: string, opts: Options) -> (string, bool)

DEFAULT_OPTIONS :: Options{
    include_proc = file_system_include_proc,
    include_dirs = {
        ".",
    },
}

// If this returns false the shader compiler is not available. Do not call any other procedures.
@(require_results)
init :: proc(target: Target, state_ptr: ^State = nil, allocator := context.allocator) -> bool {
    if state_ptr == nil {
        _state = new(State, allocator)
        _state.allocator = allocator
    } else {
        _state = state_ptr
    }

    _state.target = target

    switch target {
    case .Invalid:
        return false

    case .DXBC:
        // Requires d3d11compiler DLL
        return ODIN_OS == .Windows

    case .WGSL, .SPIRV:
        return _slang_init(&_state.slang)
    }

    return false
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
    case .SPIRV:    return "spv"
    }
    assert(false)
    return "none"
}

compile :: proc {
    compile_from_path,
    compile_from_source,
}

compile_from_path :: proc(path: string, opts: Options = DEFAULT_OPTIONS, loc := #caller_location) -> (result: Blob, ok: bool) {
    data, err := os.read_entire_file_from_path(path, context.temp_allocator)
    if err != nil {
        log.error("Failed to read shader file:", err)
        return {}, false
    }
    return compile_from_source(path, string(data), opts)
}

compile_from_source :: proc(
    name:           string,
    source:         string,
    opts:           Options = DEFAULT_OPTIONS,
    loc := #caller_location,
) -> (result: Blob, ok: bool) {
    opts := opts

    assert(_state != nil)

    if opts.stage == .Invalid {
        if strings.contains(name, ".vs") {
            opts.stage = .Vertex
        } else if strings.contains(name, ".ps") {
            opts.stage = .Pixel
        } else if strings.contains(name, ".cs") {
            opts.stage = .Compute
        }
    }

    assert(opts.stage != .Invalid, "You must specify shader stage")

    switch _state.target {
    case .Invalid:
        assert(false)

    case .DXBC:
        when ODIN_OS == .Windows {
            result, ok = _compile_dxbc(name, source, opts)
        } else {
            assert(false)
        }

    case .WGSL, .SPIRV:
        result, ok = _compile_slang(_state, name, source, opts)
    }

    return result, ok
}

destroy_blob :: proc(blob: ^Blob) {
    assert(blob != nil)
    _dxbc_blob_destroy(&blob._dxbc)
    _slang_blob_destroy(&blob._slang)
    blob^ = {}
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
