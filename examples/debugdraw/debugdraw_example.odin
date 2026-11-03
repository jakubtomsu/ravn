package ravn_debugdraw_example

import "core:math/linalg"
import "core:debug/trace"
import "core:time"
import "../../debugdraw"
import "../../base"
import "../../gpu"
import "../../platform"

main :: proc() {
    context.logger = base.make_logger()
    context.assertion_failure_proc = trace.assertion_failure_proc;

    platform.init()
    defer platform.shutdown()

    window := platform.create_window("RAVN Example")

    gpu.init(window = platform.get_native_window_ptr(window))
    defer gpu.shutdown()

    debugdraw.init(
        target_color = gpu.SWAPCHAIN_HANDLE,
    )

    timer: f32

    prev_tick := time.tick_now()
    main_loop: for {
        curr_tick := time.tick_now()
        delta := f32(time.duration_seconds(time.tick_diff(prev_tick, curr_tick)))
        prev_tick = curr_tick

        timer += delta

        for event in platform.poll_window_events(window) {
            #partial switch ev in event {
            case platform.Event_Exit:
                break main_loop
            case platform.Event_Button:
                if ev.button == .Escape {
                    break main_loop
                }
            }
        }

        // debugdraw.line(0, {1, 0, 0}, debugdraw.RED)
        // debugdraw.line(0, {0, 1, 0}, debugdraw.LIGHT_GREEN)
        // debugdraw.line(0, {1, 1, 0}, debugdraw.CYAN)
        debugdraw.circle(0, 0.1, fill = true)

        debugdraw.basis(0, 0.1)

        debugdraw.cone(0, linalg.matrix3_scale_f32(0.1) * linalg.matrix3_rotate_f32(timer, {1, 0, 0}), fill = true)

        debugdraw.tri({1, 1, 0}, {1, 0, 0}, {0, -1, 0}, col = debugdraw.LIGHT_GREEN, fill=true)

        gpu.resize_swapchain(platform.get_native_window_ptr(window), platform.get_window_rect(window).size)

        gpu.begin_frame()

        gpu.begin_graphics_pass("main", {colors = {0 = {resource = gpu.SWAPCHAIN_HANDLE, clear_mode = .Clear, clear_val = {0.1, 0.1, 0.2, 1}}}})
        gpu.end_graphics_pass()

        // proj := linalg.matrix4_perspective_f32(linalg.to_radians(f32(90)), 1, 0.01, 1000.0)

        proj := linalg.matrix_ortho3d_f32(-1, 1, 1, -1, -1, 1)

        debugdraw.render_frame(proj, delta)

        gpu.end_frame(false)
    }
}