package ravn_gpu

import "core:sys/windows"
import "vendor:wgpu"

_wgpu_create_native_surface :: proc(instance: wgpu.Instance, window: rawptr, ptr: rawptr) -> wgpu.Surface {
    assert(window != nil)
    return wgpu.InstanceCreateSurface(
        instance,
        &wgpu.SurfaceDescriptor{
            nextInChain = &wgpu.SurfaceSourceWindowsHWND{
                chain = wgpu.ChainedStruct{
                    sType = .SurfaceSourceWindowsHWND,
                },
                hinstance = windows.GetModuleHandleW(nil),
                hwnd      = window,
            },
        },
    )
}