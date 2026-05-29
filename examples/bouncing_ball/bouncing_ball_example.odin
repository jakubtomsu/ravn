/*
    Ravn Bouncing Ball Example
    Credit: Example originally created by Ramon Santamaria (@raysan5) for Raylib
*/

package ravn_bouncing_ball_example

import rv "../.."

state: ^State

State :: struct {
    ball: Ball,
    ball_texture: rv.Texture_Handle,

    paused: bool,
}

Ball :: struct {
    position: [3]f32,
    speed: [2]f32,
    radius: f32,
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

    state.ball_texture = rv.create_texture_from_encoded_data(
        "circle",
        #load("../data/circle.png"),
    ) or_else panic("Failed to load ball texture")

    screen := rv.get_screen_size()
    state.ball = {
        position = {screen.x / 2, screen.y / 2, 0},
        speed = {5.0, 4.0},
        radius = 60,
    }
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

    ball := &state.ball
    screen := rv.get_screen_size()

    if rv.get_key_pressed(.Space) do state.paused = !state.paused

    if !state.paused {
        ball.position.x += ball.speed.x
        ball.position.y += ball.speed.y

        // Check wall collisions for bouncing
        if ball.position.x >= (screen.x - ball.radius) || ball.position.x <= ball.radius {
            ball.speed.x *= -1.0
        }
        if ball.position.y >= (screen.y - ball.radius) || ball.position.y <= ball.radius {
            ball.speed.y *= -1.0
        }
    }

    rv.update_draw_layer(0, rv.make_screen_camera())

    rv.set_draw_texture(rv.get_texture("circle"))
    rv.draw_sprite(
        pos = state.ball.position,
        scale = {ball.radius * 2, ball.radius * 2},
        col = {1.0, 0.0, 0.0, 1.0},
        scaling = .Absolute,
    )

    rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.set_draw_blend(.Alpha)
    rv.draw_text("PRESS SPACE to PAUSE BALL MOVEMENT", {20, 20, 0}, scale = 4, col = {0, 0, 0, 1})

    rv.submit_layers()
    rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE, clear_color = [3]f32{.98, .98, .98}, clear_depth = true)

    return state
}
