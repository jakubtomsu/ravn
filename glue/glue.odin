package ravn_glue

import "../gpu"
import "../shader_compiler"

when gpu.BACKEND == gpu.BACKEND_D3D11 {
    SHADER_TARGET :: shader_compiler.Target.DXBC
} else when gpu.BACKEND == gpu.BACKEND_WGPU {
    SHADER_TARGET :: shader_compiler.Target.WGSL
} else {
    SHADER_TARGET :: shader_compiler.Target.Invalid
}
