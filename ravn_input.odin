#+vet explicit-allocators shadowing style
package ravn

import "platform"
import "core:math/linalg"
import "base:intrinsics"

MAX_GAMEPADS :: platform.MAX_GAMEPADS

Key :: platform.Key
Mouse_Button :: platform.Mouse_Button
Gamepad_Button :: platform.Gamepad_Button
Gamepad_Axis :: platform.Gamepad_Axis

Input :: struct {
    mouse_delta:        [2]f32,
    mouse_pos:          [2]f32,
    scroll_delta:       [2]f32,

    keys:               Input_Digital_Buffer(Key),
    mouse_buttons:      Input_Digital_Buffer(Mouse_Button),

    gamepads:           [MAX_GAMEPADS]Input_Gamepad,
    gamepads_connected: bit_set[0..<MAX_GAMEPADS],
}

Input_Gamepad :: struct {
    buttons:    Input_Digital_Buffer(Gamepad_Button),
    axes:       [Gamepad_Axis]f32,
}

Input_Digital_Buffer :: struct($E: typeid) where intrinsics.type_is_enum(E) {
    down:       bit_set[E],
    pressed:    bit_set[E],
    released:   bit_set[E],
    repeated:   bit_set[E],
    buffered:   bit_set[E],
    timer:      [E]f32,
}


// MARK: Keys

get_key_down :: proc(key: Key) -> bool {
    return key in _state.input.keys.down
}

// Down time is 0 on pressed.
get_key_down_time :: proc(key: Key) -> f32 {
    return _state.input.keys.timer[key]
}

get_key_repeated :: proc(key: Key) -> bool {
    return key in _state.input.keys.repeated
}

get_key_released :: proc(key: Key) -> bool {
    return key in _state.input.keys.released
}

// buf: buffering window duration in seconds
get_key_pressed :: proc(key: Key, buf: f32 = 0) -> bool {
    if buf > 0.0001 &&
        key in _state.input.keys.buffered &&
        _state.input.keys.timer[key] <= buf
    {
        _state.input.keys.buffered -= {key}
        return true
    }

    if key in _state.input.keys.pressed {
        return true
    }

    return false
}


// MARK: Mouse

// NOTE: [0, 0] is the bottom left corner.
get_mouse_pos :: proc() -> [2]f32 {
    return _state.input.mouse_pos
}

// Positive Y is up.
get_mouse_delta :: proc() -> [2]f32 {
    return _state.input.mouse_delta
}

get_scroll_delta :: proc() -> [2]f32 {
    return _state.input.scroll_delta
}

get_mouse_down :: proc(button: Mouse_Button) -> bool {
    return button in _state.input.mouse_buttons.down
}

// Down time is 0 on pressed.
get_mouse_down_time :: proc(button: Mouse_Button) -> f32 {
    return _state.input.mouse_buttons.timer[button]
}

get_mouse_repeated :: proc(button: Mouse_Button) -> bool {
    return button in _state.input.mouse_buttons.repeated
}

get_mouse_released :: proc(button: Mouse_Button) -> bool {
    return button in _state.input.mouse_buttons.released
}

// buf: buffering window duration in seconds
get_mouse_pressed :: proc(button: Mouse_Button, buf: f32 = 0) -> bool {
    if buf > 0.0001 &&
        button in _state.input.mouse_buttons.buffered &&
        _state.input.mouse_buttons.timer[button] <= buf
    {
        _state.input.mouse_buttons.buffered -= {button}
        return true
    }

    if button in _state.input.mouse_buttons.pressed {
        return true
    }

    return false
}


// MARK: Gamepads

get_gamepad_axis :: proc(gamepad_index: int, axis: Gamepad_Axis, deadzone: f32 = 0.01) -> f32 {
    gamepad := _state.input.gamepads[gamepad_index]
    val := gamepad.axes[axis]
    return abs(val) < deadzone ? 0 : val
}

get_gamepad_down :: proc(gamepad_index: int, button: Gamepad_Button) -> bool {
    gamepad := _state.input.gamepads[gamepad_index]
    return button in gamepad.buttons.down
}

// Down time is 0 on pressed
get_gamepad_down_time :: proc(gamepad_index: int, button: Gamepad_Button) -> f32 {
    gamepad := _state.input.gamepads[gamepad_index]
    return gamepad.buttons.timer[button]
}

get_gamepad_repeated :: proc(gamepad_index: int, button: Gamepad_Button) -> bool {
    gamepad := _state.input.gamepads[gamepad_index]
    return button in gamepad.buttons.repeated
}

get_gamepad_released :: proc(gamepad_index: int, button: Gamepad_Button) -> bool {
    gamepad := _state.input.gamepads[gamepad_index]
    return button in gamepad.buttons.released
}

// buf: buffering window duration in seconds
get_gamepad_pressed :: proc(gamepad_index: int, button: Gamepad_Button, buf: f32 = 0) -> bool {
    gamepad := _state.input.gamepads[gamepad_index]

    if buf > 0.0001 &&
        button in gamepad.buttons.buffered &&
        gamepad.buttons.timer[button] <= buf
    {
        gamepad.buttons.buffered -= {button}
        return true
    }

    if button in gamepad.buttons.pressed {
        return true
    }

    return false
}


// MARK: Internal

_input_digital_clear_temp_state :: proc(buf: ^Input_Digital_Buffer($T), delta: f32) {
    buf.pressed = {}
    buf.repeated = {}
    buf.released = {}
    for &t in buf.timer {
        t += delta
    }
}

_input_digital_press :: proc(buf: ^Input_Digital_Buffer($T), elem: T) {
    if elem not_in buf.down {
        buf.pressed += {elem}
        buf.buffered += {elem}
        buf.timer[elem] = 0
    } else {
        buf.repeated += {elem}
    }
    buf.down += {elem}
}

_input_digital_release :: proc(buf: ^Input_Digital_Buffer($T), elem: T) {
    if elem in buf.down {
        buf.released += {elem}
    }
    buf.down -= {elem}
}

_input_apply_event :: proc(input: ^Input, event: platform.Event) {
    #partial switch v in event {
    case platform.Event_Key:
            if v.pressed {
                _input_digital_press(&input.keys, v.key)
            } else {
                _input_digital_release(&input.keys, v.key)
            }

    case platform.Event_Mouse_Button:
        if v.pressed {
            _input_digital_press(&input.mouse_buttons, v.button)
        } else {
            _input_digital_release(&input.mouse_buttons, v.button)
        }

    case platform.Event_Mouse:
        input.mouse_delta.x += f32(v.move.x)
        input.mouse_delta.y += f32(v.move.y)
        input.mouse_pos.x = f32(v.pos.x)
        input.mouse_pos.y = f32(v.pos.y)

    case platform.Event_Scroll:
        input.scroll_delta += v.delta
    }
}

_input_clear_temp_state :: proc(input: ^Input, delta_time: f32) {
    input.mouse_delta = 0
    input.scroll_delta = 0

    _input_digital_clear_temp_state(&input.keys, delta_time)
    _input_digital_clear_temp_state(&input.mouse_buttons, delta_time)
    for &gp in input.gamepads {
        _input_digital_clear_temp_state(&gp.buttons, delta_time)
        gp.axes = {}
    }
}

_input_apply_gamepad_state :: proc(input: ^Input, index: int, state: platform.Gamepad_State, state_ok: bool) {
    if !state_ok {
        input.gamepads[index] = {}
        input.gamepads_connected -= {index}
        return
    } else {
        input.gamepads_connected += {index}
    }

    gpad := &input.gamepads[index]
    _input_gamepad_update_state(gpad, state)
}

_input_gamepad_update_state :: proc(gpad: ^Input_Gamepad, state: platform.Gamepad_State) {
    for btn in Gamepad_Button {
        if btn in state.buttons {
            _input_digital_press(&gpad.buttons, btn)
        } else {
            _input_digital_release(&gpad.buttons, btn)
        }
    }

    gpad.axes[.Left_Trigger] = state.axes[.Left_Trigger] > 0.1 ? clamp(gpad.axes[.Left_Trigger], 0, 1) : 0
    gpad.axes[.Right_Trigger] = state.axes[.Right_Trigger] > 0.1 ? clamp(gpad.axes[.Right_Trigger], 0, 1) : 0

    l_thumb := [2]f32{
        state.axes[.Left_Thumb_X],
        state.axes[.Left_Thumb_Y],
    }

    r_thumb := [2]f32{
        state.axes[.Right_Thumb_X],
        state.axes[.Right_Thumb_Y],
    }

    l_len := linalg.length(l_thumb)
    r_len := linalg.length(r_thumb)

    if l_len < 0.1 {
        l_thumb = 0
    } else if l_len > 1 {
        l_thumb = l_thumb / l_len
    }

    if r_len < 0.1 {
        r_thumb = 0
    } else if r_len > 1 {
        r_thumb = r_thumb / r_len
    }

    gpad.axes[.Left_Thumb_X] = l_thumb.x
    gpad.axes[.Left_Thumb_Y] = l_thumb.y
    gpad.axes[.Right_Thumb_X] = r_thumb.x
    gpad.axes[.Right_Thumb_Y] = r_thumb.y
}
