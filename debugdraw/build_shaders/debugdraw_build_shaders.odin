package ravn_debugdraw_build_shaders

import "core:strings"
import "core:fmt"
import "core:os"
import "core:debug/trace"
import "../../shader_compiler"
import "../../base"

main :: proc() {
    context.logger = base.make_logger()
    context.assertion_failure_proc = trace.assertion_failure_proc

    os.remove("debugdraw/data/main.ps.dxbc")
    os.remove("debugdraw/data/vert.vs.dxbc")
    os.remove("debugdraw/data/shape.vs.dxbc")
    os.remove("debugdraw/data/main.ps.wgsl")
    os.remove("debugdraw/data/vert.vs.wgsl")
    os.remove("debugdraw/data/shape.vs.wgsl")

    if shader_compiler.init(.DXBC) {
        defer shader_compiler.shutdown()
        compile_all("dxbc")
    }

    if shader_compiler.init(.WGSL) {
        defer shader_compiler.shutdown()
        compile_all("wgsl")
    }
}

compile_all :: proc(ext: string) {
    compile(fmt.tprintf("debugdraw/data/main.ps.%s", ext),  "debugdraw/shaders/main.ps.hlsl")
    compile(fmt.tprintf("debugdraw/data/vert.vs.%s", ext),  "debugdraw/shaders/vert.vs.hlsl")
    compile(fmt.tprintf("debugdraw/data/shape.vs.%s", ext), "debugdraw/shaders/shape.vs.hlsl")
}

compile :: proc(dst: string, src: string) {
    opts := shader_compiler.Options{
        include_proc = shader_compiler.file_system_include_proc,
        include_dirs = {".", "debugdraw/"}, // HACK around slang vs d3dcompiler inconsistent include paths
    }
    bin := shader_compiler.compile(src, opts) or_else panic("Failed to load")
    os.write_entire_file(dst, bin.data) or_else panic("Failed to write")
}