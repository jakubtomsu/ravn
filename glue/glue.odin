package ravn_glue

import "../gpu"
import "../shaderc"

when gpu.BACKEND == gpu.BACKEND_D3D11 {
    SHADER_TARGET :: shaderc.Target.DXBC
} else when gpu.BACKEND == gpu.BACKEND_WGPU {
    SHADER_TARGET :: shaderc.Target.WGSL
} else {
    SHADER_TARGET :: shaderc.Target.Invalid
}
