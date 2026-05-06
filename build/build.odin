package raven_build

import "../shader_compiler"
import "../platform"
import "../base"
import "../base/ufmt"
import "core:strings"

init :: proc() {
    shader_compiler.init(new(shader_compiler.State))
}

compile_builtin_shaders :: proc() -> bool {
    targets := []shader_compiler.Target{
        .DXBC,
        .WGSL,
    }

    for target in targets {
        _compile_builtin_shader("data/default.vs.hlsl", target, .Vertex) or_return
        _compile_builtin_shader("data/default_sprite.vs.hlsl", target, .Vertex) or_return
        _compile_builtin_shader("data/default.ps.hlsl", target, .Pixel) or_return
    }

    return true
}

_compile_builtin_shader :: proc(
    $Path:  string,
    target: shader_compiler.Target,
    stage:  shader_compiler.Stage,
) -> bool {
    source := #load("../" + Path)

    bin, bin_ok := shader_compiler.compile(Path, string(source), {
        target = target,
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
    switch target {
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
    if path == "raven.hlsli" || path == "data/raven.hlsli" {
        return #load("../data/raven.hlsli"), true
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
