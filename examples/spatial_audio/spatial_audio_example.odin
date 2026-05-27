package ravn_spatial_audio_example

// TODO: Add the music back in once the audio engine supports QOA

import rv "../.."
import "../../platform"
import "../../audio"

import "core:math/linalg"
import "core:math"

state: ^State

State :: struct {
    cam_pos:    [3]f32,
    cam_ang:    [3]f32,
    res0:       rv.Sound_Resource_Handle,
    res1:       rv.Sound_Resource_Handle,
    sound:      rv.Sound_Handle,
    sound_x:    f32,
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

ATTENUATION_RANGE :: [2]f32{1, 40}

_init :: proc() {
    state = new(State)

    // TODO: FIXME: relative and non-relative mouse have inverted delta
    platform.set_mouse_relative(rv.get_window(), true)
    platform.set_mouse_visible(false)

    state.cam_pos = {1.5, 3, -8}
    state.cam_ang = {0.3, 0, 0}

    state.res0 = rv.create_sound_resource_encoded("sound", #load("../data/snake_death_sound.wav"))
    state.res1 = rv.create_sound_resource_encoded("sound", #load("../data/snake_powerup_sound.wav"))
    state.sound = rv.create_sound(state.res1,
        flags = {.Loop, .Spatial},
        attenuation_range = ATTENUATION_RANGE,
    )
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

    speed: f32 = 2.0
    if rv.get_key_down(.Left_Shift) {
        speed *= 10
    } else if rv.get_key_down(.Left_Control) {
        speed *= 0.1
    }

    cam_vel: [3]f32
    cam_vel += mat[0] * move.x * speed
    cam_vel += mat[2] * move.z * speed
    cam_vel.y += move.y * speed
    state.cam_pos += cam_vel * delta

    rv.set_layer_params(0, rv.make_3d_perspective_camera(state.cam_pos, cam_rot))
    rv.set_layer_params(1, rv.make_screen_camera())

    rv.set_draw_depth(.Depth)

    audio.set_listener(state.cam_pos, cam_vel, forw = mat[2], right = mat[0])

    sound_vel := math.cos_f32(rv.get_time() * 2) * 10
    state.sound_x += sound_vel * delta
    sound_pos := [3]f32{state.sound_x, 1, 0}

    audio.set_sound_transform(state.sound, sound_pos, {sound_vel, 0, 0})

    if rv.get_key_pressed(.Space) {
        sound := rv.create_sound(state.res0, pitch = 2)
        audio.set_sound_param(sound, .Pitch, 0.1, 3.0)
    }

    if rv.scope_draw_state() {
        rv.set_draw_texture(rv.get_builtin_texture(.Default))
        rv.set_draw_blend(.Alpha)
        rv.set_draw_fill(.Front)

        rv.draw_line_grid(col = rv.WHITE * 0.7)

        rv.draw_mesh(rv.get_builtin_mesh(.Icosphere_1), sound_pos, scale = 0.5, col = rv.ORANGE)
        rv.draw_line_sphere(sound_pos, ATTENUATION_RANGE[0], rv.ORANGE * rv.fade(0.5))
        rv.draw_line_sphere(sound_pos, ATTENUATION_RANGE[1], rv.ORANGE * rv.fade(0.5))

        rv.draw_mesh(rv.get_builtin_mesh(.Cube), {2, 1, 3}, col = rv.oklerp(rv.GRAY, rv.BLUE, 0.5))
        rv.draw_mesh(rv.get_builtin_mesh(.Cube), {0, 2, -2}, scale = {1, 2, 1}, col = rv.oklerp(rv.GRAY, rv.DARK_GREEN, 0.5))
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
