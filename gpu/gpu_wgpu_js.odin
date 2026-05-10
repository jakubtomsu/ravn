package ravn_gpu

import "vendor:wgpu"

_wgpu_create_native_surface :: proc(instance: wgpu.Instance, window: rawptr, ptr: rawptr) -> wgpu.Surface {
    return wgpu.InstanceCreateSurface(
        instance,
        &wgpu.SurfaceDescriptor{
            nextInChain = &wgpu.SurfaceSourceCanvasHTMLSelector{
                sType = .SurfaceSourceCanvasHTMLSelector,
                selector = "#ravn-canvas",
            },
        },
    )
}