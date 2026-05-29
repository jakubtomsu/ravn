package ravn_geometry_example

import "core:fmt"
import "core:math/rand"
import rv "../.."
import "../../platform"
import geom "../../geometry"

import "core:math/linalg"
import "core:math"

state: ^State

State :: struct {
    cam_pos:    [3]f32,
    cam_ang:    [3]f32,
    anim_rot:   bool,
}

@export _module_desc := rv.Module_Desc {
    state_size = size_of(State),
    init = _init,
    shutdown = _shutdown,
    update = _update,
}

Shape_Kind :: enum u8 {
    Plane,
    Triangle,
    Box,
    Sphere,
    Cylinder,
    Capsule,
    Uncapped_Cylinder,
    Rounded_Triangle,
    Rounded_Box,
}

main :: proc() {
    rv.run_main_loop(_module_desc)
}

_init :: proc() {
    state = new(State)

    // TODO: FIXME: relative and non-relative mouse have inverted delta
    platform.set_mouse_relative(rv.get_window(), true)
    platform.set_mouse_visible(false)

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
    mat: matrix[3, 3]f32
    {
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
        mat = linalg.matrix3_from_quaternion_f32(cam_rot)

        speed: f32 = 4.0
        if rv.get_key_down(.Left_Shift) {
            speed *= 10
        } else if rv.get_key_down(.Left_Control) {
            speed *= 0.1
        }

        state.cam_pos += mat[0] * move.x * delta * speed
        state.cam_pos += mat[2] * move.z * delta * speed
        state.cam_pos.y += move.y * delta * speed

        rv.update_draw_layer(0, rv.make_perspective_3d_camera(rv.get_screen_size(), state.cam_pos, cam_rot))
        rv.update_draw_layer(1, rv.make_screen_camera(rv.get_screen_size()))
    }

    rv.set_draw_depth(.Depth)

    if rv.get_key_pressed(.Space) {
        state.anim_rot = !state.anim_rot
    }

    cam_sweep: Sweep = {
        t = 10000,
        hit = state.cam_pos + mat[2] * 10000,
    }

    { rv.scope_draw_state()
        rv.set_draw_texture(rv.get_builtin_texture(.Default))
        rv.set_draw_blend(.Alpha)
        rv.set_draw_fill(.All)

        points := [?][3]f32{
            {-1,  0,  0},
            { 1,  0,  0},
            { 0, -1,  0},
            { 0,  1,  0},
            { 0,  0, -1},
            { 0,  0,  1},

            {-1, -1, -1},
            {-1, -1,  1},
            {-1,  1, -1},
            {-1,  1,  1},
            { 1, -1, -1},
            { 1, -1,  1},
            { 1,  1, -1},
            { 1,  1,  1},

            {-1, -1,  0},
            {-1,  1,  0},
            { 1, -1,  0},
            { 1,  1,  0},
            {-1,  0, -1},
            {-1,  0,  1},
            { 1,  0, -1},
            { 1,  0,  1},
            { 0, -1, -1},
            { 0, -1,  1},
            { 0,  1, -1},
            { 0,  1,  1},
        }

        rot := linalg.quaternion_angle_axis_f32(rv.get_time(), {1, 0, 0})

        for &d in points {
            d = linalg.normalize(d)
            if state.anim_rot {
                d = linalg.quaternion128_mul_vector3(rot, d)
            }
        }

        center: [3]f32 = 0

        for shape in Shape_Kind {
            draw_shape(shape, center)
            draw_shape(shape, center + {0, 0, 10})

            if shape != .Plane {
                update_sweep_point_vs_shape(&cam_sweep, state.cam_pos, mat[2], shape, center)
                update_sweep_point_vs_shape(&cam_sweep, state.cam_pos, mat[2], shape, center + {0, 0, 10})
            }

            rnd := rand.create_u64(123)
            context.random_generator = rand.default_random_generator(&rnd)

            for d in points {
            // for i in 0..<200 {
                // d := linalg.normalize([3]f32{
                //     rand.float32() - 0.5,
                //     rand.float32() - 0.5,
                //     rand.float32() - 0.5,
                // })

                // if state.anim_rot {
                //     d = linalg.quaternion128_mul_vector3(rot, d)
                // }

                start := center + d * 3
                move := -d * 3

                t, hit, nor, ok := sweep_point_vs_shape(start, move, shape, center)

                rv.draw_line(start, hit, {ok ? rv.GREEN * rv.fade(0.5) : rv.RED, rv.fade(0)})

                if ok {
                    rv.draw_line(hit, hit + nor * 0.25, rv.YELLOW)
                    rv.draw_mesh(rv.get_builtin_mesh(.Icosphere_1), hit, scale = 0.05, col = rv.GREEN)
                }
            }

            center.z += 10

            for offs0 in 0..<i32(24) {
                for offs1 in 0..<i32(24) {
                    v := rv.vcast(f32, [3]i32{offs0, 12, offs1} - 12) / 12.0

                    if state.anim_rot {
                        v = linalg.quaternion128_mul_vector3(
                            rv.quat_angle_axis(rv.get_time(), {0, 1, 0}),
                            v,
                        )
                    }

                    start := center + v * 2 + {0, 3, 0}

                    move := [3]f32{0, -6, 0}

                    t, hit, nor, ok := sweep_point_vs_shape(start, move, shape, center)

                    rv.draw_mesh(rv.get_builtin_mesh(.Icosphere_1), hit, scale = 0.05, col = ok ? rv.GREEN : rv.RED)
                }
            }

            center.z = 0
            center.x += 10
        }

        rv.draw_mesh(rv.get_builtin_mesh(.Icosphere_1), cam_sweep.hit, scale = 0.075, col = rv.YELLOW)
        rv.draw_mesh(rv.get_builtin_mesh(.Icosphere_1), cam_sweep.hit + cam_sweep.nor * 0.1, scale = 0.05, col = rv.ORANGE)
    }

    rv.set_draw_layer(1)
    rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.set_draw_depth(.Depth)
    rv.draw_text("Use WASD and QE to move, mouse to look, Space to toggle animation", {20, 20, 0.1}, scale = 1)
    rv.draw_text(rv.tprintf("%f", cam_sweep.t), {20, 40, 0.1}, scale = 1)

    rv.submit_layers()
    rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE, [3]f32{0, 0, 0.1}, true)
    rv.render_layer(1, rv.DEFAULT_RENDER_TEXTURE, nil, true)

    return state
}

draw_shape :: proc(shape: Shape_Kind, center: [3]f32) {
    tri := TRI
    for &v in tri {
        v += center
    }

    switch shape {
    case .Box:
        rv.draw_box(center, col = rv.GRAY)

    case .Sphere:
        rv.draw_sphere(center, col = rv.GRAY)

    case .Plane:
        rv.draw_mesh(rv.get_builtin_mesh(.Disk_1), center, col = rv.GRAY)

    case .Cylinder, .Uncapped_Cylinder:
        rv.draw_mesh(rv.get_builtin_mesh(.Cylinder_1), center, col = rv.GRAY)

    case .Capsule:
        rv.draw_capsule(center + {0, 0, 1}, center + {0, 0, -1}, col = rv.GRAY)

    case .Triangle:
        rv.draw_triangle(tri, col = rv.GRAY)

    case .Rounded_Triangle:
        nor := linalg.normalize0(linalg.cross(tri[1] - tri[0], tri[2] - tri[0]))
        for s in 0..=1 {
            rv.draw_triangle(
                {
                    tri[0] + nor * (f32(s) - 0.5),
                    tri[1] + nor * (f32(s) - 0.5),
                    tri[2] + nor * (f32(s) - 0.5),
                },
                col = rv.GRAY,
            )
        }
        for v in tri {
            rv.draw_mesh(rv.get_builtin_mesh(.Icosphere_1), v, scale = 0.5, col = rv.GRAY)
        }

    case .Rounded_Box:
        rv.draw_mesh(rv.get_builtin_mesh(.Cube), center, scale = {1.5, 1, 1}, col = rv.GRAY)
        rv.draw_mesh(rv.get_builtin_mesh(.Cube), center, scale = {1, 1.5, 1}, col = rv.GRAY)
        rv.draw_mesh(rv.get_builtin_mesh(.Cube), center, scale = {1, 1, 1.5}, col = rv.GRAY)
        for x in 0..<8 {
            offs := [3]f32{
                bool(x & 1) ? 1 : -1,
                bool(x & 2) ? 1 : -1,
                bool(x & 4) ? 1 : -1,
            }
            rv.draw_mesh(rv.get_builtin_mesh(.UV_Sphere_1), center + offs, scale = 0.5, col = rv.GRAY)
        }
    }
}

sweep_point_vs_shape :: proc(start: [3]f32, move: [3]f32, shape: Shape_Kind, center: [3]f32, range: f32 = 1) -> (t: f32, hit: [3]f32, nor: [3]f32, ok: bool) {
    tri := TRI
    for &v in tri {
        v += center
    }

    switch shape {
    case .Box:
        t, ok = geom.sweep_point_vs_aabb(start, move, center - 1, center + 1, range = range)
        hit = start + move * t
        _, nor = geom.get_box_dist_grad(hit, center, 1)

    case .Plane:
        t, ok = geom.sweep_point_vs_plane(start, move, {0, 1, 0}, center.y, range = range)
        hit = start + move * t
        nor = {0, 1, 0}

    case .Sphere:
        t, ok = geom.sweep_point_vs_sphere(start, move, center, 1, range = range)
        hit = start + move * t
        if ok {
            nor = linalg.normalize(hit - center)
        }

    case .Capsule:
        points := [2][3]f32{center + {0, 0, -1}, center + {0, 0, 1}}
        t, ok = geom.sweep_point_vs_capsule(start, move, points, 1, range = range)
        hit = start + move * t
        _, nor = geom.get_line_dist_grad(hit, points)

    case .Cylinder:
        points := [2][3]f32{center + {0, -1, 0}, center + {0, 1, 1}}
        t, ok = geom.sweep_point_vs_cylinder(start, move, points, 1, range = range)
        hit = start + move * t

    case .Uncapped_Cylinder:
        points := [2][3]f32{center + {0, -1, 0}, center + {0, 1, 0}}
        t, ok = geom.sweep_point_vs_uncapped_cylinder(start, move, points, 1, range = range)
        hit = start + move * t

    case .Triangle:
        t, ok = geom.sweep_point_vs_triangle(start, move, tri, range = range)
        hit = start + move * t
        _, nor = geom.get_triangle_dist_grad(start + move * (t - 0.001), tri)

    case .Rounded_Triangle:
        t, ok = geom.sweep_sphere_vs_triangle(start, move, 0.5, tri, range = range)
        hit = start + move * t
        _, nor = geom.get_triangle_dist_grad(hit, tri)

    case .Rounded_Box:
        t, ok = geom.sweep_sphere_vs_aabb(start, move, rad = 0.5, aabb_min = center - 1, aabb_max = center + 1, range = range)
        hit = start + move * t
        _, nor = geom.get_box_dist_grad(hit, center, 1)
    }

    return t, hit, nor, ok
}

TRI :: [3][3]f32{
    {0, 1, 2},
    {-1, 0, -1},
    {2, 0, -1},
}

Sweep :: struct {
    t:      f32,
    hit:    [3]f32,
    nor:    [3]f32,
}

update_sweep_point_vs_shape :: proc(sweep: ^Sweep, start: [3]f32, move: [3]f32, shape: Shape_Kind, center: [3]f32) {
    t, hit, nor, ok := sweep_point_vs_shape(start, move, shape, center, range = sweep.t)

    if ok && t < sweep.t {
        sweep^ = {
            t = t,
            hit = hit,
            nor = nor,
        }
    }
}

