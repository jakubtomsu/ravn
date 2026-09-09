package ravn_gpu

// Dummy backend for testing.
// Everything *must compile* on all targets, but won't run (by design)
// This can be a starting point when writing a new backend from scratch.

import "../base"

when BACKEND == BACKEND_DUMMY {

    _State :: struct { _: u8 }
    _Graphics_Pipeline_State :: struct { _: u8 }
    _Compute_Pipeline_State :: struct { _: u8 }
    _Shader_State :: struct { _: u8 }
    _Resource_State :: struct { _: u8 }
    _Bindings_Layout_State :: struct { _: u8 }
    _Bindings_State :: struct { _: u8 }

    dummy :: proc "contextless" () -> ! {
        panic_contextless("Error: dummy GPU backend")
    }

    @(require_results) _init :: proc(native_window: rawptr) -> bool { dummy() }
    _shutdown :: proc() { dummy() }
    @(require_results) _begin_frame :: proc() -> bool { dummy() }
    _end_frame :: proc(sync: bool) { dummy() }
    @(require_results) _resize_swapchain :: proc(window: rawptr, size: [2]i32) -> (ok: bool) { dummy() }

    @(require_results) _create_bindings_layout :: proc(id: base.Debug_ID, desc: Bindings_Layout_Desc) -> (result: _Bindings_Layout_State, ok: bool) { dummy() }
    @(require_results) _create_bindings :: proc(id: base.Debug_ID, desc: Bindings_Desc) -> (result: _Bindings_State, ok: bool) { dummy() }
    @(require_results) _create_graphics_pipeline :: proc(id: base.Debug_ID, desc: Graphics_Pipeline_Desc) -> (result: _Graphics_Pipeline_State, ok: bool) { dummy() }
    @(require_results) _create_compute_pipeline :: proc(id: base.Debug_ID, desc: Compute_Pipeline_Desc) -> (result: _Compute_Pipeline_State, ok: bool) { dummy() }
    @(require_results) _create_constants :: proc(id: base.Debug_ID, item_size: i32, item_num: i32) -> (result: _Resource_State, ok: bool) { dummy() }
    @(require_results) _create_shader :: proc(id: base.Debug_ID, data: []u8, kind: Shader_Kind) -> (result: _Shader_State, ok: bool) { dummy() }
    @(require_results) _create_texture_2d :: proc(id: base.Debug_ID, format: Texture_Format, size: [2]i32, usage: Usage, mips: i32, array_depth: i32, render_texture: bool, rw_resource: bool, data: []byte) -> (result: _Resource_State, ok: bool) { dummy() }
    @(require_results) _create_buffer :: proc(id: base.Debug_ID, kind: Buffer_Kind, stride: i32, size: i32, usage: Usage, data: []u8) -> (result: _Resource_State, ok: bool) { dummy() }

    _destroy_shader :: proc(state: Shader_State) { dummy() }
    _destroy_resource :: proc(state: Resource_State) { dummy() }
    _destroy_bindings :: proc(state: Bindings_State) { dummy() }
    _destroy_bindings_layout :: proc(state: Bindings_Layout_State) { dummy() }
    _destroy_graphics_pipeline :: proc(state: Graphics_Pipeline_State) { dummy() }
    _destroy_compute_pipeline :: proc(state: Compute_Pipeline_State) { dummy() }

    _begin_graphics_pass :: proc(id: base.Debug_ID, desc: Graphics_Pass_Desc) { dummy() }
    _end_graphics_pass :: proc() { dummy() }

    _begin_compute_pass :: proc(id: base.Debug_ID) { dummy() }
    _end_compute_pass :: proc() { dummy() }

    _set_graphics_pipeline :: proc(curr_pip: ^Graphics_Pipeline_State, curr: Graphics_Pipeline_Desc, prev: Graphics_Pipeline_Desc) { dummy() }
    _set_compute_pipeline :: proc(curr_pip: ^Compute_Pipeline_State, prev: Compute_Pipeline_Desc) { dummy() }

    _set_bindings :: proc(bindings: ^Bindings_State, offsets: []u32) { dummy() }
    _set_index_buffer :: proc(res: ^Resource_State, format: Index_Format, offset: u64) { dummy() }

    _update_constants :: proc(res: ^Resource_State, data: []u8) { dummy() }
    _update_buffer :: proc(res: ^Resource_State, offset: int, buffers: [][]u8) { dummy() }
    _update_texture_2d :: proc(res: ^Resource_State, data: []byte, slice: i32) { dummy() }

    _draw_non_indexed :: proc(vertex_num: u32, instance_num: u32) { dummy() }
    _draw_indexed :: proc(index_num: u32, instance_num: u32, index_offset: u32) { dummy() }
    _dispatch_compute :: proc(size: [3]i32) { dummy() }

}