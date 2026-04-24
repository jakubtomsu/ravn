package raven_collision_example

import rv "../.."
import "../../platform"
import coll "../../collision"
import geom "../../geometry"

import "core:math/linalg"
import "core:math"

state: ^State

State :: struct {
    cam_pos:    rv.Vec3,
    cam_ang:    rv.Vec3,
    arena:      coll.Arena_Handle,
    mesh:       coll.Mesh_Handle,
    point:      bool,
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

    state.cam_pos = {1.5, 3, -8}
    state.cam_ang = {0.3, 0, 0}

    coll.init(new(coll.State))

    for &t in _triangles {
        t -= 1 // OBJ indices are 1-based
    }

    state.arena = coll.create_arena(1024 * 1024)
    state.mesh = coll.create_mesh(state.arena, _verts, _triangles)
}

_shutdown :: proc() {
    free(state)
}

_update :: proc(hot_state: rawptr) -> rawptr {
    if hot_state != nil {
        state = cast(^State)hot_state
    }

    rv.perf_scope()

    if rv.key_pressed(.Escape) {
        rv.request_shutdown()
    }

    delta := rv.get_delta_time()

    // Flycam controls
    mat: rv.Mat3
    {
        move: rv.Vec3
        if rv.key_down(.D) do move.x += 1
        if rv.key_down(.A) do move.x -= 1
        if rv.key_down(.W) do move.z += 1
        if rv.key_down(.S) do move.z -= 1
        if rv.key_down(.E) do move.y += 1
        if rv.key_down(.Q) do move.y -= 1

        state.cam_ang.xy += rv.mouse_delta().yx * 0.005
        state.cam_ang.x = clamp(state.cam_ang.x, -math.PI * 0.49, math.PI * 0.49)

        cam_rot := rv.euler_rot(state.cam_ang)
        mat = linalg.matrix3_from_quaternion_f32(cam_rot)

        speed: f32 = 4.0
        if rv.key_down(.Left_Shift) {
            speed *= 10
        } else if rv.key_down(.Left_Control) {
            speed *= 0.1
        }

        state.cam_pos += mat[0] * move.x * delta * speed
        state.cam_pos += mat[2] * move.z * delta * speed
        state.cam_pos.y += move.y * delta * speed

        rv.set_layer_params(0, rv.make_3d_perspective_camera(state.cam_pos, cam_rot))
        rv.set_layer_params(1, rv.make_screen_camera())
    }

    rv.set_draw_depth(.Depth)

    if rv.key_pressed(.Space) {
        state.point = !state.point
    }

    N :: 32
    for x in 0..<N {
        for y in 0..<N {
            SCALE :: 8
            HEIGHT :: 6
            p := [3]f32{
                ((f32(x) / N) - 0.5) * SCALE,
                HEIGHT,
                ((f32(y) / N) - 0.5) * SCALE,
            }

            t: f32
            prim: int
            hit_ok: bool
            if state.point {
                t, prim, hit_ok = coll.sweep_point_vs_mesh_local(p, {0, -1, 0}, state.mesh, HEIGHT)
            } else {
                t, prim, hit_ok = coll.sweep_sphere_vs_mesh_local(p, {0, -1, 0}, 0.25, state.mesh, HEIGHT)
            }

            hit := p + {0, -t, 0}

            rv.draw_mesh(
                rv.get_builtin_mesh(.Icosphere_0),
                hit,
                scale = 0.02,
                col = hit_ok ? rv.GREEN : rv.RED,
            )
        }
    }

    t: f32
    prim: int
    hit_ok: bool
    if state.point {
        t, prim, hit_ok = coll.sweep_point_vs_mesh_local(state.cam_pos, mat[2], state.mesh, 100)
    } else {
        t, prim, hit_ok = coll.sweep_sphere_vs_mesh_local(state.cam_pos, mat[2], 0.25, state.mesh, 100)
    }
    hit := state.cam_pos + mat[2] * t

    {
        rv.scope_draw_state()

        // for v in _verts {
        //     rv.draw_mesh(
        //         rv.get_builtin_mesh(.UV_Sphere_0),
        //         v,
        //         scale = 0.25,
        //     )
        // }

        for tri, i in _triangles {
            p := [3][3]f32{
                _verts[tri[0]],
                _verts[tri[1]],
                _verts[tri[2]],
            }

            rv.draw_triangle(p, col = i == prim ? rv.YELLOW : rv.WHITE)
        }

        rv.draw_mesh(
            rv.get_builtin_mesh(.UV_Sphere_0),
            hit,
            col = rv.ORANGE,
            scale = 0.1,
        )

        // if tri, tri_ok := coll.get_mesh_triangle(state.mesh, prim); tri_ok {
        //     _, nor := geom.get_triangle_dist_grad(state.cam_pos + mat[2] * (t - 0.001), tri)
        //     rv.draw_line(hit, hit + nor, rv.YELLOW)
        // }

    }


    rv.set_draw_layer(1)
    rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.set_draw_depth(.Depth)
    rv.draw_text("Use WASD and QE to move, mouse to look, Space to toggle animation", {20, 20, 0.1}, scale = 1)
    rv.draw_text(rv.tprintf("Dist %v, Tri %v", t, prim), {20, 40, 0.1}, scale = 1, col = hit_ok ? rv.GREEN : rv.RED)

    rv.draw_perf_scopes({10, 60, 0.1})

    rv.submit_layers()
    rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE, rv.Vec3{0, 0, 0.1}, true)
    rv.render_layer(1, rv.DEFAULT_RENDER_TEXTURE, nil, true)

    return state
}

// https://graphics.cs.utah.edu/teapot/

_verts := [][3]f32{
    {-1.5, 2.25, 0},
    {-1.6, 2.025, 0},
    {-3, 1.8, 0},
    {-2.7, 1.8, 0},
    {-1.9, 0.6, 0},
    {-2, 0.9, 0},
    {2.8, 2.4, 0},
    {3.2, 2.4, 0},
    {2.7, 2.4, 0},
    {3.3, 2.4, 0},
    {1.7, 1.425, 0},
    {1.7, 0.6, 0},
    {0, 3.15, 0},
    {-0.2, 2.7, 0},
    {8.742278e-9, 2.7, -0.2},
    {0.2, 2.7, 8.742278e-9},
    {0, 2.7, 0.2},
    {-1.3, 2.4, 0},
    {5.68248e-8, 2.4, -1.3},
    {1.3, 2.4, 5.68248e-8},
    {0, 2.4, 1.3},
    {-1.4, 2.4, 0},
    {6.119594e-8, 2.4, -1.4},
    {-1.5, 2.4, 0},
    {6.556708e-8, 2.4, -1.5},
    {1.4, 2.4, 6.119594e-8},
    {1.5, 2.4, 6.556708e-8},
    {0, 2.4, 1.4},
    {0, 2.4, 1.5},
    {-2, 0.9, 0},
    {8.742278e-8, 0.9, -2},
    {2, 0.9, 8.742278e-8},
    {0, 0.9, 2},
    {-1.5, 0.15, 0},
    {6.556708e-8, 0.15, -1.5},
    {1.5, 0.15, 6.556708e-8},
    {0, 0.15, 1.5},
    {0, 0, 0},
    {1.7, 1.287525, 0},
    {1.7, 0.737475, 0},
    {2.8, 2.4, 0},
    {3.2, 2.4, 0},
    {0, 0.18, 0},
    {-1.15, 0.21, 0},
    {5.02681e-8, 0.21, -1.15},
    {1.15, 0.21, 5.02681e-8},
    {0, 0.21, 1.15},
    {-1.8, 1.37, 0},
    {7.86805e-8, 1.37, -1.8},
    {1.8, 1.37, 7.86805e-8},
    {0, 1.37, 1.8},
    {-1.21, 2.35, 0},
    {5.289078e-8, 2.35, -1.21},
    {1.21, 2.35, 5.289078e-8},
    {0, 2.35, 1.21},
    {-1.165, 2.35, 0},
    {5.092377e-8, 2.35, -1.165},
    {1.165, 2.35, 5.092377e-8},
    {0, 2.35, 1.165},
    {-1.05, 2.41, 0},
    {4.589696e-8, 2.41, -1.05},
    {1.05, 2.41, 4.589696e-8},
    {0, 2.41, 1.05},
    {0, 2.55, 0},
}

_triangles := [][3]u16{
    {2, 3, 1},
    {3, 2, 4},
    {3, 2, 1},
    {2, 3, 4},
    {4, 5, 3},
    {5, 4, 6},
    {5, 4, 3},
    {4, 5, 6},
    {8, 9, 7},
    {9, 8, 10},
    {9, 8, 7},
    {8, 9, 10},
    {10, 11, 9},
    {11, 10, 12},
    {11, 10, 9},
    {10, 11, 12},
    {13, 15, 14},
    {13, 16, 15},
    {17, 16, 13},
    {14, 17, 13},
    {15, 18, 14},
    {18, 15, 19},
    {16, 19, 15},
    {19, 16, 20},
    {21, 16, 17},
    {16, 21, 20},
    {18, 17, 14},
    {17, 18, 21},
    {23, 24, 22},
    {24, 23, 25},
    {26, 25, 23},
    {25, 26, 27},
    {29, 26, 28},
    {26, 29, 27},
    {24, 28, 22},
    {28, 24, 29},
    {25, 30, 24},
    {30, 25, 31},
    {27, 31, 25},
    {31, 27, 32},
    {33, 27, 29},
    {27, 33, 32},
    {30, 29, 24},
    {29, 30, 33},
    {31, 34, 30},
    {34, 31, 35},
    {32, 35, 31},
    {35, 32, 36},
    {37, 32, 33},
    {32, 37, 36},
    {34, 33, 30},
    {33, 34, 37},
    {35, 38, 34},
    {36, 38, 35},
    {37, 38, 36},
    {34, 38, 37},
    {40, 7, 39},
    {7, 40, 8},
    {41, 40, 39},
    {40, 41, 42},
    {43, 45, 44},
    {43, 46, 45},
    {47, 46, 43},
    {44, 47, 43},
    {45, 48, 44},
    {48, 45, 49},
    {46, 49, 45},
    {49, 46, 50},
    {51, 46, 47},
    {46, 51, 50},
    {48, 47, 44},
    {47, 48, 51},
    {49, 52, 48},
    {52, 49, 53},
    {50, 53, 49},
    {53, 50, 54},
    {55, 50, 51},
    {50, 55, 54},
    {52, 51, 48},
    {51, 52, 55},
    {53, 22, 52},
    {22, 53, 23},
    {54, 23, 53},
    {23, 54, 26},
    {28, 54, 55},
    {54, 28, 26},
    {22, 55, 52},
    {55, 22, 28},
    {19, 56, 18},
    {56, 19, 57},
    {20, 57, 19},
    {57, 20, 58},
    {59, 20, 21},
    {20, 59, 58},
    {56, 21, 18},
    {21, 56, 59},
    {57, 60, 56},
    {60, 57, 61},
    {58, 61, 57},
    {61, 58, 62},
    {63, 58, 59},
    {58, 63, 62},
    {60, 59, 56},
    {59, 60, 63},
    {61, 64, 60},
    {62, 64, 61},
    {63, 64, 62},
    {60, 64, 63},
}