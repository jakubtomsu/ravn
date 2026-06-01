package ravn_gpu

import "vendor:wgpu"
import wgpu_sdl3_glue "vendor:wgpu/sdl3glue"
import "vendor:sdl3"

_wgpu_create_native_surface :: proc(instance: wgpu.Instance, window: rawptr, ptr: rawptr) -> wgpu.Surface {
    return wgpu_sdl3_glue.GetSurface(instance, cast(^sdl3.Window)window)
}
