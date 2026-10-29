package ravn_imgui_example

import "core:debug/trace"
import "../../base"
import "../../gpu"
import "../../platform"
import "../../imgui"
import "../../imgui/imgui_impl_gpu"
import "../../imgui/imgui_impl_platform"

main :: proc() {
    context.logger = base.make_logger()
    context.assertion_failure_proc = trace.assertion_failure_proc

    platform.init()
    defer platform.shutdown()

    window := platform.create_window("RAVN Dear ImGui Example")

    gpu.init(window = platform.get_native_window_ptr(window))
    defer gpu.shutdown()

    imgui.CHECKVERSION()
    imgui.CreateContext()
    io := imgui.GetIO()
    io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad}

    imgui.StyleColorsDark()

    imgui_impl_platform.init(window)
    defer imgui_impl_platform.shutdown()

    imgui_impl_gpu.init()
    defer imgui_impl_gpu.shutdown()

    running := true
    for running {
        for event in platform.poll_window_events(window) {
            imgui_impl_platform.process_event(event)

            #partial switch ev in event {
            case platform.Event_Exit:
                running = false
            case platform.Event_Button:
                if ev.button == .Escape {
                    running = false
                }
            }
        }

        imgui_impl_platform.new_frame()
        imgui_impl_gpu.new_frame()
        imgui.NewFrame()

        imgui.ShowDemoWindow()

        gpu.resize_swapchain(platform.get_native_window_ptr(window), platform.get_window_rect(window).size)

        gpu.begin_frame()

        imgui.Render()
        draw_data := imgui.GetDrawData()

        imgui_impl_gpu.upload_draw_data(draw_data)

        gpu.begin_graphics_pass("main", {
            colors = { 0 = { resource = gpu.SWAPCHAIN_HANDLE, clear_mode = .Clear, clear_val = {0, 0, 0.2, 1} }},
        })
        imgui_impl_gpu.render_draw_data(draw_data)
        gpu.end_graphics_pass()

        gpu.end_frame(false)
    }
}