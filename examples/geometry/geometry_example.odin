package raven_geometry_example

import rv "../.."
import "../../platform"
import geom "../../geometry"

import "core:math/linalg"
import "core:math"

state: ^State

State :: struct {
    cam_pos:    rv.Vec3,
    cam_ang:    rv.Vec3,
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
    Capsule,
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

    if rv.key_pressed(.Escape) {
        rv.request_shutdown()
    }

    delta := rv.get_delta_time()

    // Flycam controls
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
        mat := linalg.matrix3_from_quaternion_f32(cam_rot)

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
    
    rv.bind_depth(.Depth)
    
    if rv.key_pressed(.Space) {
        state.anim_rot = !state.anim_rot
    }

    { rv.scope_binds()
        rv.bind_texture(rv.get_builtin_texture(.Default))
        rv.bind_blend(.Alpha)
        rv.bind_fill(.All)
        
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
        
        rot := linalg.quaternion_angle_axis_f32(rv.get_time(), 1)
        
        for &d in points {
            d = linalg.normalize(d)
            if state.anim_rot {
                d = linalg.quaternion128_mul_vector3(rot, d)
            }
        }
        
        center: [3]f32 = 0
        
        for shape in Shape_Kind {
            draw_shape(shape, center)
            
            // TODO:
            // - reflection from hit
            // - raycast parallel to surface
            
            for d in points {
                start := center + d * 3
                move := -d * 3
                
                t, hit, nor, ok := sweep_point_vs_shape(start, move, shape, center)
                
                rv.draw_line(start, hit, {ok ? rv.GREEN : rv.RED, rv.fade(0)})
                
                if ok {
                    rv.draw_line(hit, hit + nor * 0.25, rv.YELLOW)
                    rv.draw_mesh(rv.get_builtin_mesh(.Icosphere), hit, scale = 0.05, col = rv.GREEN)
                    
                    // refl := linalg.reflect(move, nor)
                    // t2, hit2, nor2, ok2 := sweep_point_vs_shape(hit, refl, shape, center)
                    // if !ok2 {
                    //     rv.draw_line(hit, hit2, rv.CYAN)
                    // }
                }
            }
            
            center.z += 10
            
            draw_shape(shape, center)
            
            for offs0 in 0..<i32(12) {
                for offs1 in 0..<i32(12) {
                    v := rv.vcast(f32, [3]i32{offs0, 6, offs1} - 6) / 6.0
                    
                    if state.anim_rot {
                        v = linalg.quaternion128_mul_vector3(
                            rv.quat_angle_axis(rv.get_time(), {0, 1, 0}),
                            v,
                        )
                    }
                    
                    start := center + v * 2 + {0, 3, 0}
                    
                    move := [3]f32{0, -6, 0}
                    
                    t, hit, nor, ok := sweep_point_vs_shape(start, move, shape, center)
                                        
                    rv.draw_mesh(rv.get_builtin_mesh(.Icosphere), hit, scale = 0.05, col = ok ? rv.GREEN : rv.RED)
                }
            }
            
            center.z = 0
            center.x += 10
        }
    }

    rv.bind_layer(1)
    rv.bind_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.bind_depth(.Depth)
    rv.draw_text("Use WASD and QE to move, mouse to look, Space to toggle animation", {20, 20, 0.1}, scale = math.ceil(rv._state.dpi_scale)) // DPI HACK

    rv.submit_layers()
    rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE, rv.Vec3{0, 0, 0.1}, true)
    rv.render_layer(1, rv.DEFAULT_RENDER_TEXTURE, nil, false)

    return state
}

draw_shape :: proc(shape: Shape_Kind, center: rv.Vec3) {
    switch shape {
    case .Box:
        rv.draw_mesh(rv.get_builtin_mesh(.Cube), center, col = rv.GRAY)
        
    case .Sphere:
        rv.draw_mesh(rv.get_builtin_mesh(.Icosphere), center, col = rv.GRAY)
    
    case .Plane:
        rv.draw_mesh(rv.get_builtin_mesh(.Disk), center, col = rv.GRAY)
    
    case .Capsule:
        rv.draw_mesh(rv.get_builtin_mesh(.Cylinder), center, col = rv.GRAY)
        rv.draw_mesh(rv.get_builtin_mesh(.Icosphere), center + {0, 1, 0}, col = rv.GRAY)
        rv.draw_mesh(rv.get_builtin_mesh(.Icosphere), center + {0, -1, 0}, col = rv.GRAY)
    
    case .Triangle:
        tri := TRI
        for &v in tri {
            v += center
        }
        rv.draw_triangle(tri, col = rv.GRAY)
    }
}

sweep_point_vs_shape :: proc(start: rv.Vec3, move: rv.Vec3, shape: Shape_Kind, center: rv.Vec3) -> (t: f32, hit: [3]f32, nor: [3]f32, ok: bool) {
    switch shape {
    case .Box:
        t, ok = geom.sweep_point_vs_aabb(start, move, center - 1, center + 1)
        hit = start + move * t
        if ok {
            centered := hit - center
            rel := linalg.abs(centered) - 1
            switch max(rel.x, rel.y, rel.z) {
            case rel.x: nor.x = centered.x > 0 ? 1 : -1
            case rel.y: nor.y = centered.y > 0 ? 1 : -1
            case rel.z: nor.z = centered.z > 0 ? 1 : -1
            }
        }
        
    case .Plane:
        t, ok = geom.sweep_point_vs_plane(start, move, {0, 1, 0}, center.y)
        hit = start + move * t
        nor = {0, 1, 0}
        
    case .Sphere:
        t, ok = geom.sweep_point_vs_sphere(start, move, center, 1)
        hit = start + move * t
        if ok {
            nor = linalg.normalize(hit - center)
        }
    
    case .Capsule:
        points := [2][3]f32{center + {0, -1, 0}, center + {0, 1, 0}}
        t, ok = geom.sweep_point_vs_capsule(start, move, points, 1)
        hit = start + move * t
        if ok {
            rel := hit - points[0]
            axis := points[1] - points[0]
            h := clamp(linalg.dot(rel, axis) / linalg.length2(axis), 0, 1)
            close := points[0] + axis * h
            nor = linalg.normalize(hit - close)
        }
        
    case .Triangle:
        tri := TRI
        for &v in tri {
            v += center
        }
        t, ok = geom.sweep_point_vs_triangle(start, move, tri)
        hit = start + move * t
        if ok {
            nor = linalg.normalize(linalg.cross(
                tri[1] - tri[0],
                tri[2] - tri[0],
            ))
            
            if linalg.dot(move, nor) > 0 {
                nor = -nor
            }
        }
    }
    
    return t, hit, nor, ok
}

TRI :: [3][3]f32{
    {0, 0, 1},
    {-1, 0, -1},
    {1, 0, -1},
}
