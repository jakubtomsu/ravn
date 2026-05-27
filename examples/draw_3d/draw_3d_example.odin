package ravn_draw_3d_example

import rv "../.."
import "../../platform"

import "core:math/linalg"
import "core:math"

state: ^State

State :: struct {
    cam_pos:    [3]f32,
    cam_ang:    [3]f32,
    shader:     rv.Pixel_Shader_Handle,
}

@export _module_desc := rv.Module_Desc {
    state_size = size_of(State),
    init = _init,
    shutdown = _shutdown,
    update = _update,
}

main :: proc() {
    rv.run_main_loop(_module_desc)
}

_init :: proc() {
    state = new(State)

    // TODO: FIXME: relative and non-relative mouse have inverted delta
    platform.set_mouse_relative(rv.get_window(), true)
    platform.set_mouse_visible(false)

    rv.register_file_data("test_shader.ps.hlsl", #load("../data/test_shader.ps.hlsl"))

    state.shader = rv.load_pixel_shader("test_shader.ps.hlsl")

    state.cam_pos = {1.5, 3, -8}
    state.cam_ang = {0.3, 0, 0}
}

_shutdown :: proc() {
    free(state)
}

_update :: proc(hot_state: rawptr) -> rawptr {
    if hot_state != nil {
        state = cast(^State)hot_state
    }

    if rv.get_key_pressed(.Escape) {
        rv.request_shutdown()
    }

    delta := rv.get_delta_time()

    // Flycam controls

    move: [3]f32
    if rv.get_key_down(.D) do move.x += 1
    if rv.get_key_down(.A) do move.x -= 1
    if rv.get_key_down(.W) do move.z += 1
    if rv.get_key_down(.S) do move.z -= 1
    if rv.get_key_down(.E) do move.y += 1
    if rv.get_key_down(.Q) do move.y -= 1

    state.cam_ang.xy += rv.get_mouse_delta().yx * 0.005
    state.cam_ang.x = clamp(state.cam_ang.x, -math.PI * 0.49, math.PI * 0.49)

    cam_rot := rv.euler_rot(state.cam_ang)
    mat := linalg.matrix3_from_quaternion_f32(cam_rot)

    speed: f32 = 1.0
    if rv.get_key_down(.Left_Shift) {
        speed *= 10
    } else if rv.get_key_down(.Left_Control) {
        speed *= 0.1
    }

    state.cam_pos += mat[0] * move.x * delta * speed
    state.cam_pos += mat[2] * move.z * delta * speed
    state.cam_pos.y += move.y * delta * speed

    rv.set_layer_params(0, rv.make_3d_perspective_camera(state.cam_pos, cam_rot))
    rv.set_layer_params(1, rv.make_screen_camera())

    rv.set_draw_depth(.Depth)

    if rv.scope_draw_state() {
        rv.set_draw_texture(rv.get_builtin_texture(.Default))
        rv.set_draw_blend(.Alpha)
        rv.set_draw_fill(.Front)

        // Meshes

        for mesh in rv.Builtin_Mesh {
            rv.draw_mesh(
                rv.get_builtin_mesh(mesh),
                {f32(int(mesh)) * 3, 0, 0},
                col = int(mesh) % 2 == 0 ? rv.WHITE : rv.GRAY,
            )
        }

        rv.set_draw_fill(.All)

        // Custom triangles

        rv.draw_triangle(
            pos = {
                [3]f32{-0.5, 0, 0} + {-6, 0, 0},
                [3]f32{ 0, 0.7, 0} + {-6, 0, 0},
                [3]f32{ 0.5, 0, 0} + {-6, 0, 0},
            },
            col = {rv.RED, rv.BLUE, rv.GREEN},
        )

        rv.draw_triangle(
            pos = {
                [3]f32{-0.5, 0, 0} + {-6, 0, 0},
                [3]f32{ 0, -0.7, 0} + {-6, 0, 0},
                [3]f32{ 0.5, 0, 0} + {-6, 0, 0},
            },
            col = {rv.RED, rv.GREEN, rv.CYAN},
        )

        // Line shapes

        rv.draw_line({-3, 0, 5}, {-3, 1, 5}, col = rv.YELLOW)
        rv.draw_line_mat3({-2, 0, 5})
        rv.draw_line_box({1, 0, 5}, 1, rv.GRAY)
        rv.draw_line_circle({4, 0, 5}, col = rv.ORANGE)
        rv.draw_line_cylinder({{6, -1, 5}, {6, 1, 5}}, rad = 0.5)
        rv.draw_line_sphere({8, 0, 5}, mat = 0.7, col = rv.RED)

        rv.set_draw_pixel_shader(state.shader)
        rv.draw_mesh(rv.get_builtin_mesh(.Cube), {3, -5, 0}, col = rv.GRAY, add_col = rv.WHITE * rv.nsin(rv.get_time()))
    }

    rv.set_draw_layer(1)
    rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.set_draw_depth(.Depth)
    rv.draw_text("Use WASD and QE to move, mouse to look", {20, 20, 0.1}, scale = math.ceil(rv._state.dpi_scale)) // DPI HACK

    rv.submit_layers()
    rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE, [3]f32{0, 0, 0.1}, true)
    rv.render_layer(1, rv.DEFAULT_RENDER_TEXTURE, nil, false)

    return state
}
