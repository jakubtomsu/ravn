// Dummy backend for testing.
// Everything *must compile* on all targets, but won't run (by design)
// This can be a starting point when writing a new backend from scratch.
package raven_gpu

when BACKEND == BACKEND_DUMMY {

    _State :: struct { _: u8 }

    _Pipeline :: struct { _: u8 }
    _Compute_Pipeline :: struct { _: u8 }
    _Shader :: struct { _: u8 }
    _Resource :: struct { _: u8 }


    dummy :: proc "contextless" () -> ! {
        panic_contextless("Error: trying to call GPU procedures with the dummy backend")
    }


    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: General
    //

    @(require_results) _init :: proc(native_window: rawptr) -> bool { dummy() }
    _shutdown :: proc() { dummy() }
    @(require_results) _begin_frame :: proc() -> bool { dummy() }
    _end_frame :: proc(sync: bool) { dummy() }



    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Create
    //

    @(require_results) _update_swapchain :: proc(swapchain: ^_Resource, window: rawptr, size: [2]i32) -> (ok: bool) { dummy() }

    @(require_results) _create_pipeline :: proc(name: string, desc: Pipeline_Desc) -> (result: _Pipeline, ok: bool) { dummy() }
    @(require_results) _create_compute_pipeline :: proc(name: string, desc: Compute_Pipeline_Desc) -> (result: _Compute_Pipeline, ok: bool) { dummy() }
    @(require_results) _create_constants :: proc(name: string, item_size: i32, item_num: i32) -> (result: _Resource, ok: bool) { dummy() }
    @(require_results) _create_shader :: proc(name: string, data: []u8, kind: Shader_Kind) -> (result: _Shader, ok: bool) { dummy() }
    @(require_results) _create_texture_2d :: proc(name: string, format: Texture_Format, size: [2]i32, usage: Usage, mips: i32, array_depth: i32, render_texture: bool, rw_resource: bool, data: []byte) -> (result: _Resource, ok: bool) { dummy() }
    @(require_results) _create_buffer :: proc(name: string, stride: i32, size: i32, usage: Usage, data: []u8) -> (result: _Resource, ok: bool) { dummy() }
    @(require_results) _create_index_buffer :: proc(name: string, size: i32, data: []u8, usage: Usage) -> (result: _Resource, ok: bool) { dummy() }



    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Destroy
    //

    _destroy_shader :: proc(shader: Shader_State) { dummy() }
    _destroy_constants :: proc(constants: Resource_State) { dummy() }
    _destroy_resource :: proc(resource: Resource_State) { dummy() }


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Actions
    //

    _begin_pass :: proc(name: string, desc: Pass_Desc) { dummy() }
    _end_pass :: proc() { dummy() }

    _begin_compute_pass :: proc(name: string) { dummy() }
    _end_compute_pass :: proc() { dummy() }

    _set_pipeline :: proc(curr_pip: Pipeline_State, curr: Pipeline_Desc, prev: Pipeline_Desc) { dummy() }
    _set_compute_pipeline :: proc(curr_pip: Compute_Pipeline_State, curr: Compute_Pipeline_Desc, prev: Compute_Pipeline_Desc) { dummy() }

    _update_constants :: proc(consts: ^Resource_State, data: []u8) { dummy() }
    _update_buffer :: proc(res: ^Resource_State, offset: int, buffers: [][]u8) { dummy() }
    _map_buffer :: proc(res: _Resource) -> []byte { dummy() }
    _unmap_buffer :: proc(res: _Resource) { dummy() }
    _update_texture_2d :: proc(res: Resource_State, data: []byte, slice: i32) { dummy() }

    _draw_non_indexed :: proc(vertex_num: u32, instance_num: u32, const_offsets: []u32) { dummy() }
    _draw_indexed :: proc(index_num: u32, instance_num: u32, index_offset: u32, const_offsets: []u32) { dummy() }
    _dispatch_compute :: proc(size: [3]i32) { dummy() }

}