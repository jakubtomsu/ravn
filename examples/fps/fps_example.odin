package raven_fps_example

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:math/noise"
import rv "../.."
import "../../base"
import "../../platform"
import "../../base/ufmt"

TERRAIN_SIZE :: 32
TERRAIN_SCALE :: 6

state: ^State

State :: struct {
    pos:            rv.Vec3,
    vel:            rv.Vec3,
    angle:          rv.Vec3,
    pos_spr:        [2]rv.Vec3,
    angle_spr:      [2]rv.Vec3,
    group:          rv.Group_Handle,
    terrain_mesh:   rv.Mesh_Handle,
    terrain:        [TERRAIN_SIZE][TERRAIN_SIZE]f16
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

    // TODO: this is a bit hacky
    platform.set_window_title(rv.get_window(), "Raven FPS")
    platform.set_window_style(rv.get_window(), .Borderless)
    platform.set_window_pos(rv.get_window(), 0)
    platform.set_window_size(rv.get_window(), platform.get_main_monitor_rect().size)
    platform.set_mouse_relative(rv.get_window(), true)
    platform.set_mouse_visible(false)

    state.pos = {0, 1, 0}
    state.angle = {0, 0, 0}

    // Generate a simple heightmap

    for x in 0..<TERRAIN_SIZE {
        for y in 0..<TERRAIN_SIZE {
            height: f32
            height += rand.float32() * 0.9
            prim := 0.5 + 0.5 * f32(noise.noise_2d(29837293, {f64(x), f64(y)} * 0.0742 + 13.2329))
            prim = prim > 0.5 ? 1 : 0
            height += prim
            height += f32(0.5 + 0.5 * noise.noise_2d(980273, {f64(x), f64(y)} * 0.0542 - 1300.2329)) * 8
            state.terrain[x][y] = f16(height * 2)
        }
    }

    // Turn the heightmap into a mesh
    // (currently the verts are duplicated)

    NUM_QUADS :: TERRAIN_SIZE * TERRAIN_SIZE

    verts := make([]rv.Vertex, NUM_QUADS * 6 , context.temp_allocator)
    inds  := make([]rv.Vertex_Index, NUM_QUADS * 6, context.temp_allocator)

    for &ind, i in inds {
        ind = rv.Vertex_Index(i)
    }

    verts_offs := 0
    for x in 0..<i32(TERRAIN_SIZE)-1 {
        for y in 0..<i32(TERRAIN_SIZE)-1 {
            index := x + TERRAIN_SIZE * y

            _tri(verts[index * 6 + 0:], {{x + 0, y + 0}, {x + 1, y + 0}, {x + 0, y + 1}})
            _tri(verts[index * 6 + 3:], {{x + 1, y + 1}, {x + 0, y + 1}, {x + 1, y + 0}})

            _tri :: proc(verts: []rv.Vertex, coords: [3][2]i32) {
                for coord, i in coords {
                    height := f32(state.terrain[coord.x][coord.y])
                    verts[i] = rv.Vertex{
                        pos = {f32(coord.x), height, f32(coord.y)},
                        col = u8(rv.remap_clamped(height, 0, 10, 0, 200)),
                        uv = rv.Vec2{f32(coord.x), f32(coord.y)} / 16.0,
                    }
                    verts[i].pos.xz -= TERRAIN_SIZE * 0.5
                    verts[i].pos.xz *= TERRAIN_SCALE
                }

                normal := linalg.normalize0(linalg.cross(verts[1].pos - verts[0].pos, verts[2].pos - verts[0].pos))

                for &v in verts[:3] {
                    v.normal = rv.pack_unorm8(normal.xyzz).xyz // hack
                }
            }
        }
    }

    state.group = rv.create_group()

    state.terrain_mesh = rv.create_mesh_from_data("terrain", state.group, verts, inds)
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

    ground_height := sample_terrain(state.pos.xz)
    grounded := state.pos.y <= (ground_height + 1)

    // TODO: abstract basic flycam controls into a simple util?

    move: rv.Vec2
    if rv.key_down(.D) do move.x += 1
    if rv.key_down(.A) do move.x -= 1
    if rv.key_down(.W) do move.y += 1
    if rv.key_down(.S) do move.y -= 1

    state.angle.xy += rv.mouse_delta().yx * 0.002
    state.angle.x = clamp(state.angle.x, -math.PI * 0.49, math.PI * 0.49)
    state.angle.z = rv.lexp(state.angle.z, 0, delta * 5)
    state.angle.z += move.x * delta * -0.2
    state.angle.z += rv.mouse_delta().x * -0.0001

    state.angle_spr[1].xy += rv.mouse_delta().yx * {-1, 1} * 0.006
    state.angle_spr[1].z += move.x * delta * -30

    rv.spring2(&state.pos_spr, state.pos, 0.5, 22.0, delta)
    rv.spring2(&state.angle_spr, 0, 0.5, 20.0, delta)
    state.angle_spr[1].x += state.vel.y * delta * 4

    gun_rot := linalg.quaternion_normalize(rv.euler_rot(state.angle + state.angle_spr[0]))
    cam_rot := linalg.quaternion_normalize(rv.euler_rot(state.angle))
    mat := linalg.matrix3_from_quaternion_f32(cam_rot)

    speed: f32 = grounded ? 60 : 20
    state.vel += mat[0] * move.x * delta * speed
    state.vel += mat[2] * move.y * delta * speed

    if grounded && rv.key_pressed(.Space, buf = 0.2) {
        state.vel.y = 10
        grounded = false
    }

    state.vel.y -= delta * (state.vel.y < 0 ? 30 : 20)
    state.vel = rv.lexp(state.vel, 0, delta * 0.5)

    state.pos += state.vel * delta

    ground_height = sample_terrain(state.pos.xz)
    grounded = state.pos.y <= (ground_height + 1)

    if grounded {
        state.pos.y = ground_height + 0.9999
        state.vel = rv.lexp(state.vel, 0, delta * 8)
    }

    gun_pos := state.pos_spr[0] + mat * rv.Vec3{0.2, -0.1, 0.1}

    if grounded {
        gun_pos.y += 0.005 * math.sin_f32(rv.get_time() * 11) * rv.remap_clamped(linalg.length(state.vel.xz), 0, 2, 0, 1)
    }

    if rv.mouse_pressed(.Left) {
        state.angle_spr[1].x -= 10
    }

    fov := 110 + rv.smoothstep(5, 40, linalg.length(state.vel)) * 10
    rv.set_layer_params(0, rv.make_3d_perspective_camera(state.pos_spr[0], cam_rot, rv.deg(fov)))
    rv.set_layer_params(1, rv.make_screen_camera())

    rv.bind_texture("default")
    rv.bind_depth(.Depth)
    rv.bind_fill(.All)

    rv.draw_mesh(rv.get_mesh("Cube"),
        gun_pos,
        rot = gun_rot,
        scale = {0.03, 0.05, 0.25},
    )

    terrain_t := intersect_terrain(state.pos, mat[2])
    rv.draw_mesh(rv.get_mesh("Cube"),
        state.pos + mat[2] * terrain_t,
        scale = 0.2,
        col = rv.BLUE,
    )

    rv.draw_mesh(state.terrain_mesh, 0)

    rv.draw_mesh(
        rv.get_mesh("Plane"),
        {0, 0, 0},
        scale = 25,
        col = rv.GRAY,
    )

    rv.bind_layer(1)

    rv.bind_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.draw_text("Use WASD and QE to move, mouse to look", {14, 14, 0.1}, scale = 2)
    rv.draw_text(ufmt.tprintf("speed: %v, vel: %v", linalg.length(state.vel), state.vel),
        {14, 64, 0.1}, scale = math.ceil(rv._state.dpi_scale)) // DPI HACK

    rv.draw_perf_scopes()

    rv.submit_layers()
    rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE, rv.Vec3{0, 0, 0.1}, true)
    rv.render_layer(1, rv.DEFAULT_RENDER_TEXTURE, nil, false)

    return state
}

read_terrain :: proc(coord: [2]i32) -> f32 {
    return f32(state.terrain[clamp(coord.x, 0, TERRAIN_SIZE - 1)][clamp(coord.y, 0, TERRAIN_SIZE - 1)])
}

sample_terrain :: proc(pos: rv.Vec2) -> f32 {
    p := pos * (1.0 / TERRAIN_SCALE)
    fcoord := rv.floor(p)
    coord := [2]i32{
        i32(fcoord.x) + TERRAIN_SIZE / 2,
        i32(fcoord.y) + TERRAIN_SIZE / 2,
    }

    sub := p - fcoord

    samples := [4]f32{
        read_terrain(coord + {0, 0}),
        read_terrain(coord + {1, 0}),
        read_terrain(coord + {0, 1}),
        read_terrain(coord + {1, 1}),
    }

    // trianglele check
    if sub.x + sub.y <= 1.0 {
        // interpolating within bottom left trianglele
        return samples[0] + sub.x * (samples[1] - samples[0]) + sub.y * (samples[2] - samples[0])
    }
    else {
        // interpolating within upper right trianglele
        sub = rv.Vec2{1.0, 1.0} - sub
        return samples[3] + sub.x * (samples[2] - samples[3]) + sub.y * (samples[1] - samples[3])
    }
}

@(require_results)
intersect_terrain :: proc(
    pos:        rv.Vec3,
    dir:        rv.Vec3,
    tmin:       f32 = 0.15,
    tmax:       f32 = 100.0,
    step_size:  f32 = 0.025,
) -> (time: f32, ok: bool) #optional_ok {
    // https://iquilezles.org/articles/terrainmarching/

    dt: f32 = 0.1
    lh: f32 = 0.0
    ly: f32 = 0.0
    steps := 0

    // accuracy proportional to the distance
    for t: f32 = tmin; t < tmax; t += t * step_size {
        p := pos + dir * t
        h := sample_terrain(p.xz)
        if p.y < h {
            // interpolate intersection distance
            time = t-dt+dt*(lh-ly)/(p.y-ly-h+lh)
            return time, true
        }
        lh = h
        ly = p.y
        steps += 1
    }


    return tmax, false
}