package ravn_imgui_example

import "core:debug/trace"
import "../../base"
import "../../gpu"
import "../../platform"
import "../../imgui"
import "../../imgui/imgui_impl_gpu"
import "../../imgui/imgui_impl_platform"
import "../../imgui/imgui_util"

main :: proc() {
    context.logger = base.make_logger()
    context.assertion_failure_proc = trace.assertion_failure_proc

    platform.init()
    defer platform.shutdown()

    window := platform.create_window("RAVN Dear ImGui Example")

    gpu.init(window = platform.get_native_window_ptr(window))
    defer gpu.shutdown()

    imgui_util.init(window)
    defer imgui_util.shutdown()

    main_loop: for {
        for event in platform.poll_window_events(window) {
            imgui_impl_platform.process_event(event)

            #partial switch ev in event {
            case platform.Event_Exit:
                break main_loop
            case platform.Event_Button:
                if ev.button == .Escape {
                    break main_loop
                }
            }
        }

        imgui_util.new_frame()

        imgui.ShowDemoWindow()

        gpu.resize_swapchain(platform.get_native_window_ptr(window), platform.get_window_rect(window).size)

        gpu.begin_frame()

        imgui_util.render_pass(clear_mode = .Clear)

        gpu.end_frame(false)
    }
}