package ravn_build

import "../shader_compiler"
import "../platform"
import "../base"
import "../base/ufmt"
import "core:strings"

compile_builtin_shaders :: proc() -> bool {
    targets := []shader_compiler.Target{
        .DXBC,
        .WGSL,
    }

    for target in targets {
        state: shader_compiler.State
        if !shader_compiler.init(&state, target) {
            base.log_err("Failed to initialize shader compiler for target '{}'", target)
        }

        _compile_builtin_shader(&state, "data/default.vs.hlsl", .Vertex) or_return
        _compile_builtin_shader(&state, "data/default_sprite.vs.hlsl", .Vertex) or_return
        _compile_builtin_shader(&state, "data/default.ps.hlsl", .Pixel) or_return
    }

    return true
}

_compile_builtin_shader :: proc(
    state:  ^shader_compiler.State,
    $Path:  string,
    stage:  shader_compiler.Stage,
) -> bool {
    source := #load("../" + Path)

    bin, bin_ok := shader_compiler.compile(state, Path, string(source), {
        stage = stage,
        release = true,
        defines = {
            {"RELEASE", "1"},
        },
        include_proc = _shader_include_bultin,
    })

    if !bin_ok {
        base.log_err("Failed to compile builtin shader '%s'", Path)
        return false
    }

    ext: string
    switch state.target {
    case .Invalid:
        panic("Invalid target")

    case .DXBC:
        ext = "dxbc"

    case.WGSL:
        ext = "wgsl"
    }

    dst_path := ufmt.tprintf(Path + ".%s", ext)
    write_ok := platform.write_file_by_path(dst_path, bin)

    if !write_ok {
        base.log_err("Failed to write compiled builtin shader (%s) to disk", dst_path)
        return false
    }

    return true
}

_shader_include_bultin :: proc (path: string, user: rawptr) -> (string, bool) {
    base.log_info("Including '%s'", path)
    // HACK
    if path == "ravn.hlsli" || path == "data/ravn.hlsli" {
        return #load("../data/ravn.hlsli"), true
    }
    return "", false
}


find_last_slash :: proc(str: string) -> int {
    a := strings.last_index_byte(str,'\\')
    b := strings.last_index_byte(str,'/')
    return max(a, b)
}

remove_all :: proc(pattern: string) {
    iter: platform.Directory_Iter
    for path in platform.iter_directory(&iter, pattern, context.temp_allocator) {
        base.log_info("removing '%s'", path)
        platform.delete_file(path)
    }
}
