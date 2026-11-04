package ravn_debugdraw_example

import "core:math"
import "core:math/linalg"
import "core:debug/trace"
import "core:time"
import "../../debugdraw"
import "../../base"
import "../../gpu"
import "../../platform"
import "../../input"

main :: proc() {
    context.logger = base.make_logger()
    context.assertion_failure_proc = trace.assertion_failure_proc;

    platform.init()
    defer platform.shutdown()

    window := platform.create_window("RAVN Example")

    gpu.init(window = platform.get_native_window_ptr(window))
    defer gpu.shutdown()

    depthbuf: gpu.Resource_Handle
    if !gpu.create_texture_2d(&depthbuf,
        gpu.make_texture_desc(.Depth_F32, {**platform.get_window_rect(window).size, 1}, flags = {.Render_Texture}),
    ) {

    }

    debugdraw.init(
        target_color = gpu.SWAPCHAIN_HANDLE,
        target_depth = depthbuf,
        depth_write = true,
        depth_comparison = .Less_Equal,
    )

    input.init()
    defer input.shutdown()

    timer: f32

    prev_tick := time.tick_now()
    main_loop: for {
        curr_tick := time.tick_now()
        delta := f32(time.duration_seconds(time.tick_diff(prev_tick, curr_tick)))
        prev_tick = curr_tick

        timer += delta

        input.update(delta)
        for event in platform.poll_window_events(window) {
            input.apply_event(event)
            #partial switch ev in event {
            case platform.Event_Exit:
                break main_loop
            }
        }

        if input.button_pressed(.Escape) {
            break main_loop
        }

        if input.button_pressed(.Space) {
            debugdraw.sphere(0, 1, time = 1) // persistent
        }

        // Debugdraw demo
        {
            debugdraw.grid({0, -0.01, 0}, {2, 0, 0}, {0, 0, 2}, col = {debugdraw.LIGHT_GRAY/2, debugdraw.GRAY/2})
            // debugdraw.basis(0, 1)

            debugdraw.tri(
                {1, 0, 1} + {-1, 0, -1} * 0.6,
                {1, 0, 1} + { 0, 0,  1} * 0.6,
                {1, 0, 1} + { 1, 0,  0} * 0.6,
            )

            debugdraw.tri(
                {1, 0, 1} + {-1, 0, -1} * 0.5,
                {1, 0, 1} + { 0, 0,  1} * 0.5,
                {1, 0, 1} + { 1, 0,  0} * 0.5,
                col = debugdraw.LIGHT_BLUE,
                fill = true,
            )

            debugdraw.arrow(0, 1, 0.1)
            debugdraw.arrow(0, {0, 1, 0}, 0.1, debugdraw.RED)

            debugdraw.circle({-1, 0, 1}, 0.6)
            debugdraw.circle({-1, 0, 1}, 0.5, col = debugdraw.LIGHT_GREEN, fill = true)

            debugdraw.box({-1, 0, -1}, 0.6)
            debugdraw.box({-1, 0, -1}, 0.5, col = debugdraw.ORANGE, fill = true)

            debugdraw.sphere({1, 0, -1}, 0.6)
            debugdraw.sphere({1, 0, -1}, 0.5, col = debugdraw.ORANGE, fill = true)

            debugdraw.hemisphere({3, 0, -1}, 0.6)
            debugdraw.hemisphere({3, 0, -1}, 0.5, col = debugdraw.RED, fill = true)

            debugdraw.cylinder({1, 0, -3}, 0.6)
            debugdraw.cylinder({1, 0, -3}, 0.5, col = debugdraw.YELLOW, fill = true)

            debugdraw.cone({-3, 0, 1}, 0.6)
            debugdraw.cone({-3, 0, 1}, 0.5, col = debugdraw.PURPLE, fill = true)
        }

        framebuffer_size := platform.get_window_rect(window).size
        gpu.resize_swapchain(platform.get_native_window_ptr(window), framebuffer_size)
        gpu.resize_texture(&depthbuf, {**framebuffer_size, 1})

        cam_proj :=
            linalg.matrix4_perspective_f32(math.PI * 0.4, f32(framebuffer_size.x) / f32(framebuffer_size.y), 0.01, 1000.0) *
            linalg.matrix4_translate_f32({0, 0, -5}) *
            linalg.matrix4_rotate_f32(0.5, {1, 0, 0}) *
            linalg.matrix4_rotate_f32(timer * 0.5, {0, 1, 0})

        if gpu.begin_frame() {
            defer gpu.end_frame(true)

            debugdraw.render_pass(cam_proj, delta, .Clear, 0, .Clear, 1)
        }
    }
}
