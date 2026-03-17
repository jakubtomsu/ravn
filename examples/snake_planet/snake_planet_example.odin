package raven_snake_planet_example

import "core:math/rand"
import "core:math/linalg"
import "core:math"
import rv "../.."
import "../../platform"
import "../../base/ufmt"
import "../../audio"

SNAKE_RED :: rv.Vec4{1, 0.3, 0, 1}
SNAKE_ORANGE :: rv.ORANGE

state: ^State

State :: struct {
    cam_pos:        rv.Vec3,
    cam_rot:        rv.Quat,
    cam_fov:        f32,

    obsts:          [64]Obstacle,
    num_obsts:      i32,

    berry:          Berry,
    berry_timer:    f32,

    max_score:      i32,
    screen:         Screen_ID,

    snake:          Snake,

    berry_sound:    rv.Sound_Resource_Handle,
    death_sound:    rv.Sound_Resource_Handle,
    music_res:      rv.Sound_Resource_Handle,
    music:          rv.Sound_Handle,
}

Screen_ID :: enum u8 {
    Menu,
    Game,
    Death,
}

Obstacle :: struct {
    pos:    rv.Vec3,
    rad:    f32,
}

Berry :: struct {
    pos:    rv.Vec3,
}

MAX_SEGMENTS :: 512

Snake :: struct {
    dir:            rv.Vec2,
    pos:            rv.Vec3,
    segments:       [MAX_SEGMENTS]Segment,
    num_segments:   i32,
    segment_timer:  f32,
}

Segment :: struct {
    pos:    rv.Vec3,
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

    platform.set_window_title(rv.get_window(), "Snake Planet")
    platform.set_mouse_relative(rv.get_window(), true)
    platform.set_mouse_visible(false)

    state.death_sound = rv.create_sound_resource_encoded("death", #load("../data/snake_death_sound.wav")) or_else panic("load")
    state.berry_sound = rv.create_sound_resource_encoded("berry", #load("../data/snake_powerup_sound.wav")) or_else panic("load")
    state.music_res = rv.create_sound_resource_encoded("music", #load("../data/Emerald.ogg")) or_else panic("load")

    state.screen = .Menu
}

_shutdown :: proc() {
    free(state)
}

new_game :: proc() {
    state.screen = .Game
    state.cam_pos = {0, 0, -10}
    state.cam_rot = 1
    state.cam_fov = rv.deg(90)
    state.berry_timer = 100
    state.snake = {
        pos = {0, 0, -1},
        dir = {0, 1},
        num_segments = 1,
        segments = {
            0 = {
                pos = {0, 0, -1},
            },
        },
    }

    state.num_obsts = 10
    for i in 0..<state.num_obsts {
        state.obsts[i] = {
            pos = rand_dir(),
            rad = rand.float32_range(0.1, 0.2),
        }
    }

    state.snake.pos = repel_from_obstacles(state.snake.pos, 0.3)

    rv.destroy_sound(state.music)
    state.music = rv.create_sound(state.music_res, flags = {.Loop})

    spawn_berry()
}

spawn_berry :: proc() {
    state.berry = {
        pos = rand_dir(),
    }

    for i in 0..<5 {
        state.berry.pos = repel_from_obstacles(state.berry.pos, 0.5)
    }

    rv.create_sound(state.berry_sound, pitch = rand.float32_range(0.9, 1.2))
}

rand_dir :: proc() -> rv.Vec3 {
    return linalg.normalize0(rv.Vec3{
        rand.float32() * 2.0 - 1.0,
        rand.float32() * 2.0 - 1.0,
        rand.float32() * 2.0 - 1.0,
    })
}

add_snake_segment :: proc() {
    snake := &state.snake
    assert(snake.num_segments > 0)
    pos := snake.num_segments == 0 ? snake.pos : snake.segments[snake.num_segments - 1].pos
    offs: rv.Vec3
    if snake.num_segments > 1 {
        offs = pos - snake.segments[snake.num_segments - 2].pos
    } else {
        offs = snake.segments[snake.num_segments - 1].pos - snake.pos
    }
    offs = linalg.normalize0(offs)
    snake.segments[snake.num_segments] = {
        pos = pos + offs,
    }
    snake.num_segments += 1
}

_update :: proc(hot_state: rawptr) -> rawptr {
    if hot_state != nil {
        state = cast(^State)hot_state
    }

    if rv.key_pressed(.Escape) {
        rv.request_shutdown()
    }

    delta := rv.get_delta_time()

    //
    // MARK: TICK
    //

    if state.screen == .Game {
        snake := &state.snake

        mat := linalg.matrix3_from_quaternion_f32(state.cam_rot)

        // TODO: Gamepad
        move_inp: rv.Vec2

        if rv.key_down(.D) do move_inp.x += 1
        if rv.key_down(.A) do move_inp.x -= 1
        if rv.key_down(.W) do move_inp.y += 1
        if rv.key_down(.S) do move_inp.y -= 1

        if rv.key_down(.Right) do move_inp.x += 1
        if rv.key_down(.Left) do move_inp.x -= 1
        if rv.key_down(.Up) do move_inp.y += 1
        if rv.key_down(.Down) do move_inp.y -= 1

        // move_dir := move_inp.x * rv.Vec3{1, 0, 0} + mat[1] * rv.Vec3{0, 1, 0}

        if linalg.length2(move_inp) > 0.1 {
            move_inp = linalg.normalize0(move_inp)
        }

        snake.dir += move_inp * delta * 8
        snake.dir = linalg.normalize0(snake.dir)

        world_dir := mat[0] * snake.dir.x + mat[1] * snake.dir.y

        speed: f32 = 0.7 + f32(snake.num_segments / 4) * 0.05
        speed *= rv.remap_clamped(state.berry_timer, 0, 0.5, 1.5, 1)

        snake.pos += world_dir * delta * speed
        snake.pos = linalg.normalize0(snake.pos)

        state.berry_timer += delta

        if linalg.distance(state.berry.pos, snake.pos) < 0.2 {
            spawn_berry()

            add_snake_segment()
            add_snake_segment()
            state.berry_timer = 0
        }

        for &seg, i in snake.segments[:snake.num_segments] {
            seg.pos = repel_from_obstacles(seg.pos, 0.1)
        }

        for &seg, i in snake.segments[:snake.num_segments] {
            prev := i == 0 ? snake.pos : snake.segments[i - 1].pos

            seg.pos = prev + linalg.normalize0(seg.pos - prev) * 0.15
        }

        die := false

        for obst in state.obsts[:state.num_obsts] {
            if linalg.distance(obst.pos, snake.pos) < obst.rad {
                die = true
            }
        }

        for &seg, i in snake.segments[:snake.num_segments] {
            seg.pos = linalg.normalize0(seg.pos)

            if i > 0 && linalg.distance(seg.pos, snake.pos) < 0.15 {
                die = true
            }
        }

        state.cam_pos = rv.lexp(state.cam_pos, snake.pos * 2.5 + world_dir * 0.6, delta * 6)

        target_rot := linalg.quaternion_from_forward_and_up_f32(
            state.cam_pos,
            mat[1],
        )
        state.cam_rot = target_rot
        state.cam_fov = rv.lexp(state.cam_fov, rv.deg(65 + rv.remap_clamped(state.berry_timer, 0, 0.5, 7, 0)), delta * 15)

        if die {
            rv.create_sound(state.death_sound, pitch = rand.float32_range(0.9, 1.2))
            rv.destroy_sound(state.music)
            state.music = {}
            state.screen = .Death
        }
    }


    //
    // MARK: DRAW
    //

    rv.set_layer_params(0, rv.make_3d_perspective_camera(state.cam_pos, state.cam_rot, state.cam_fov))
    rv.set_layer_params(1, rv.make_screen_camera())

    if state.screen == .Game {
        snake := state.snake

        rv.bind_depth_test(true)
        rv.bind_depth_write(true)
        rv.bind_texture("default")

        sph := rv.get_mesh("Icosphere")

        rv.draw_mesh(sph, 0, col = rv.Vec4{0.0, 0.6, 0.2, 1})

        rv.bind_texture("white")

        rv.draw_mesh(sph, snake.pos, scale = 0.15, col = rv.ORANGE + rv.YELLOW * 0.1)
        for seg, i in snake.segments[:snake.num_segments] {
            rv.draw_mesh(sph,
                seg.pos * (1.0 + 0.025 * rv.nsin(f32(i) * 0.21 - rv.get_time())),
                scale = 0.15, col = i % 2 == 0 ? SNAKE_RED : SNAKE_ORANGE)
        }

        for obst in state.obsts[:state.num_obsts] {
            rv.draw_mesh(sph, obst.pos, scale = obst.rad, col = rv.Vec4{0.0, 0.6, 0.2, 1})
            rv.draw_mesh(sph, obst.pos * 1.1, scale = obst.rad * 1.2, col = rv.Vec4{0.2, 0.7, 0.3, 1})
        }

        rv.draw_mesh(sph, state.berry.pos * 1.1, scale = 0.2 + 0.05 * rv.nsin(rv.get_time() * 2), col = rv.RED)
    }

    rv.bind_layer(1)
    rv.bind_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.bind_depth_test(true)
    rv.bind_depth_write(true)

    screen := rv.get_viewport()

    score := state.snake.num_segments / 2
    state.max_score = max(score, state.max_score)

    switch state.screen {
    case .Game:
        rv.draw_text(ufmt.tprintf("SCORE %i", score), {screen.x * 0.5, screen.y - 30, 0.1}, anchor = 0,
            scale = rv.remap_clamped(state.berry_timer, 0, 0.4, 4, 2))

        rv.draw_text("Use WASD to move", {screen.x * 0.5, 24, 0.1}, anchor = 0, scale = 2)

    case .Death:

        rv.draw_text("GAME OVER!",
            {screen.x * 0.5, screen.y * 0.5, 0.1}, anchor = 0,
            scale = 4,
            col = rv.RED,
        )

        rv.draw_text(ufmt.tprintf("SCORE %i", score), {screen.x * 0.5, screen.y * 0.65, 0.1}, anchor = 0, scale = 2)
        rv.draw_text("Press SPACE to continue", {screen.x * 0.5, screen.y * 0.75, 0.1}, anchor = 0, scale = 2, col = rv.LIGHT_GRAY)

        if rv.key_pressed(.Space) {
            state.screen = .Menu
        }

    case .Menu:

        char_sprites := rv.draw_text("SNAKE PLANET",
            {screen.x * 0.5, screen.y * 0.5 + math.sin_f32(rv.get_time() * 2) * 4, 0},
            anchor = 0,
            scale = 4,
            col = SNAKE_ORANGE,
        )

        // Animate individual characters
        for &inst, i in char_sprites {
            inst.pos.y += math.sin_f32(f32(i) * 0.7334 + rv.get_time()) * 10
            if i % 2 == 0 {
                inst.col = rv.pack_unorm8(SNAKE_RED)
            }
        }

        rv.draw_text("Press SPACE to play", {screen.x * 0.5, screen.y * 0.75, 0.1}, anchor = 0, scale = 2, col = rv.LIGHT_GRAY)
        rv.draw_text(ufmt.tprintf("HIGHSCORE %i", state.max_score), {screen.x * 0.5, screen.y * 0.65, 0.1}, anchor = 0, scale = 2)
        rv.draw_text("Music by Nolram. Thank you!", {screen.x * 0.5, screen.y - 32, 0.1}, anchor = 0, scale = 2, col = rv.hex_color(0x06e4c2))

        if rv.key_pressed(.Space) {
            new_game()
        }
    }


    rv.draw_counter(.CPU_Frame_Ns, {10, 50, 0.2}, scale = 2, unit = 1e-6, col = rv.DARK_GREEN)
    rv.draw_counter(.CPU_Frame_Work_Ns, {10, 50, 0.1}, scale = 2, unit = 1e-6, col = rv.GREEN, show_text = false)

    rv.upload_gpu_layers()
    rv.render_gpu_layer(0, rv.DEFAULT_RENDER_TEXTURE, rv.Vec3{0.05, 0.1, 0.2}, true)
    rv.render_gpu_layer(1, rv.DEFAULT_RENDER_TEXTURE, nil, false)

    // rv.end_frame(false) // disable VSYNC

    return state
}

repel_from_obstacles :: proc(pos: rv.Vec3, rad: f32) -> rv.Vec3 {
    pos := pos
    for obst in state.obsts[:state.num_obsts] {
        dist := linalg.length(pos - obst.pos)

        r := obst.rad + rad

        if dist > r {
            continue
        }

        dir := linalg.normalize0(pos - obst.pos)

        pos = linalg.normalize0(pos + dir * (r - dist))
    }

    return pos
}
