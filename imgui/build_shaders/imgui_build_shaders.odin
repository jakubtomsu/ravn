// Small util for precompiling the imgui_impl_gpu shaders.
// Run it from the imgui/ parent repo to make sure slang.dll is in your path.
package ravn_imgui_impl_build_shaders

import "core:fmt"
import "core:os"
import "core:debug/trace"
import "../../shader_compiler"
import "../../base"

main :: proc() {
    context.logger = base.make_logger()
    context.assertion_failure_proc = trace.assertion_failure_proc

    os.remove("imgui/imgui_impl_gpu/main.vs.dxbc")
    os.remove("imgui/imgui_impl_gpu/main.ps.dxbc")
    os.remove("imgui/imgui_impl_gpu/main.vs.wgsl")
    os.remove("imgui/imgui_impl_gpu/main.ps.wgsl")

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
    vs := shader_compiler.compile("imgui/imgui_impl_gpu/main.vs.hlsl") or_else panic("vs")
    ps := shader_compiler.compile("imgui/imgui_impl_gpu/main.ps.hlsl") or_else panic("ps")
    os.write_entire_file(fmt.tprintf("imgui/imgui_impl_gpu/main.vs.%s", ext), vs.data, truncate = false) or_else panic("write")
    os.write_entire_file(fmt.tprintf("imgui/imgui_impl_gpu/main.ps.%s", ext), ps.data, truncate = false) or_else panic("write")
}