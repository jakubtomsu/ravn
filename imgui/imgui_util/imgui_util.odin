package ravn_imgui_util

import ".."
import "../imgui_impl_platform"
import "../imgui_impl_gpu"
import "../../gpu"
import "../../platform"

init :: proc(window: platform.Window) {
    imgui.CHECKVERSION()
    imgui.CreateContext()
    io := imgui.GetIO()
    io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad, .DockingEnable}
    set_palette_style()
    imgui_impl_platform.init(window)
    imgui_impl_gpu.init()
}

shutdown :: proc() {
	imgui_impl_platform.shutdown()
	imgui_impl_gpu.shutdown()	
}

process_event :: imgui_impl_platform.process_event

new_frame :: proc() {
	imgui_impl_platform.new_frame()
	imgui_impl_gpu.new_frame()
	imgui.NewFrame()
}

render_pass :: proc(
	color 		:= gpu.SWAPCHAIN_HANDLE,
	clear_mode:	gpu.Clear_Mode = .Keep,
	clear_val:	[4]f32 = 0,
) {
	imgui.Render()
	draw_data := imgui.GetDrawData()

	imgui_impl_gpu.upload_draw_data(draw_data)

	gpu.begin_graphics_pass("imgui", {
		colors = { 0 = { resource = color, clear_mode = clear_mode, clear_val = clear_val }},
	})
	
	imgui_impl_gpu.render_draw_data(draw_data)
	
	gpu.end_graphics_pass()
}