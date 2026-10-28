#+vet explicit-allocators shadowing style
package ravn

import "../platform"
import "base:runtime"
import "base:intrinsics"
import "core:math/linalg"

DEFAULT_DEADZONE :: #config(INPUT_DEFAULT_DEADZONE, 0.05)

MAX_GAMEPADS :: platform.MAX_GAMEPADS

Button :: platform.Button
Gamepad_Button :: platform.Gamepad_Button
Gamepad_Axis :: platform.Gamepad_Axis

_state: ^State

State :: struct {
    state_allocator:    runtime.Allocator,

    mouse_delta:        [2]f32,
    mouse_pos:          [2]f32,
    scroll_delta:       [2]f32,

    buttons:            Button_Buffer(Button),

    gamepads:           [MAX_GAMEPADS]Gamepad,
    gamepads_connected: bit_set[0..<MAX_GAMEPADS],
}

Gamepad :: struct {
    buttons:    Button_Buffer(Gamepad_Button),
    axes:       [Gamepad_Axis]f32,
}

Gamepad_Stick :: enum u8 {
    Left,
    Right,
}

Button_Buffer :: struct($E: typeid) where intrinsics.type_is_enum(E) {
    down:       bit_set[E],
    pressed:    bit_set[E],
    released:   bit_set[E],
    repeated:   bit_set[E],
    buffered:   bit_set[E],
    timer:      [E]f32,
}

init :: proc(state: ^State, allocator := context.allocator) {
    state := state

    if _state != nil {
        return
    }

    if state == nil {
        state = new(State, allocator)
        state.state_allocator = allocator
    }

    _state = state
}

update :: proc(state: ^State, delta: f32) {
    input.mouse_delta = 0
    input.scroll_delta = 0

    button_buffer_update(&input.buttons, delta_time)
    button_buffer_update(&input.mouse_buttons, delta_time)

    for gpad, i in state.gamepads {
        button_buffer_update(&gpad.buttons, delta)
        gp.axes = {}

        state, state_ok := platform.get_gamepad_state(i)

        if !state_ok {
            input.gamepads[i] = {}
            input.gamepads_connected -= {i}
            continue
        } else {
            input.gamepads_connected += {i}
        }

        gamepad_apply_state(gpad, state)
    }
}



// MARK: Buttons

get_button_down :: proc(button: Button) -> bool {
    return button in _state.buttons.down
}

// Down time is 0 on pressed.
get_button_down_time :: proc(button: Button) -> f32 {
    return _state.buttons.timer[button]
}

get_button_repeated :: proc(button: Button) -> bool {
    return button in _state.buttons.repeated
}

get_button_released :: proc(button: Button) -> bool {
    return button in _state.buttons.released
}

// buf: buffering window duration in seconds
get_button_pressed :: proc(button: Button, buf: f32 = 0) -> bool {
    if buf > 0.0001 &&
        button in _state.buttons.buffered &&
        _state.buttons.timer[button] <= buf
    {
        _state.buttons.buffered -= {button}
        return true
    }

    if button in _state.buttons.pressed {
        return true
    }

    return false
}


// MARK: Mouse

// NOTE: [0, 0] is the bottom left corner.
get_mouse_pos :: proc() -> [2]f32 {
    return _state.mouse_pos
}

// Positive Y is up.
get_mouse_delta :: proc() -> [2]f32 {
    return _state.mouse_delta
}

get_scroll_delta :: proc() -> [2]f32 {
    return _state.scroll_delta
}

get_mouse_down :: proc(button: Mouse_Button) -> bool {
    return button in _state.mouse_buttons.down
}


// MARK: Gamepads

is_gamepad_connected :: proc(gamepad_index: int) -> bool {
    if gamepad_index < 0 || gamepad_index >= MAX_GAMEPADS {
        return false
    }
    return gamepad_index in _state.gamepads_connected
}

get_gamepad_axis :: proc(gamepad_index: int, axis: Gamepad_Axis, deadzone: f32 = DEFAULT_DEADZONE) -> f32 {
    if !is_gamepad_connected(gamepad_index) {
        return 0
    }
    gamepad := _state.gamepads[gamepad_index]
    val := gamepad.axes[axis]
    return abs(val) < deadzone ? 0 : val
}

get_gamepad_stick :: proc(gamepad_index: int, axis: Gamepad_Stick, deadzone: f32 = DEFAULT_DEADZONE) -> [2]f32 {
    if !is_gamepad_connected(gamepad_index) {
        return 0
    }

    gamepad := _state.gamepads[gamepad_index]

    vec: [2]f32
    switch stick {
    case .Left:
        vec = {
            gamepad.axes[.Left_Thumb_X],
            gamepad.axes[.Left_Thumb_y],
        }
    case .Right:
        vec = {
            gamepad.axes[.Right_Thumb_X],
            gamepad.axes[.Right_Thumb_y],
        }
    }

    length := linalg.length(vec)

    if length < deadzone {
        vec = 0
    } else if length > 1 {
        vec = vec / length
    }

    return vec
}

get_gamepad_down :: proc(gamepad_index: int, button: Gamepad_Button) -> bool {
    if !is_gamepad_connected(gamepad_index) {
        return false
    }
    gamepad := _state.gamepads[gamepad_index]
    return button in gamepad.buttons.down
}

// Down time is 0 on pressed
get_gamepad_down_time :: proc(gamepad_index: int, button: Gamepad_Button) -> f32 {
    if !is_gamepad_connected(gamepad_index) {
        return 0
    }
    gamepad := _state.gamepads[gamepad_index]
    return gamepad.buttons.timer[button]
}

get_gamepad_repeated :: proc(gamepad_index: int, button: Gamepad_Button) -> bool {
    if !is_gamepad_connected(gamepad_index) {
        return false
    }
    gamepad := _state.gamepads[gamepad_index]
    return button in gamepad.buttons.repeated
}

get_gamepad_released :: proc(gamepad_index: int, button: Gamepad_Button) -> bool {
    if !is_gamepad_connected(gamepad_index) {
        return false
    }
    gamepad := _state.gamepads[gamepad_index]
    return button in gamepad.buttons.released
}

// buf: buffering window duration in seconds
get_gamepad_pressed :: proc(gamepad_index: int, button: Gamepad_Button, buf: f32 = 0) -> bool {
    if !is_gamepad_connected(gamepad_index) {
        return false
    }
    gamepad := _state.gamepads[gamepad_index]

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

button_buffer_update :: proc(buf: ^Button_Buffer($T), delta: f32) {
    buf.pressed = {}
    buf.repeated = {}
    buf.released = {}
    for &t in buf.timer {
        t += delta
    }
}

button_buffer_apply_press :: proc(buf: ^Button_Buffer($T), elem: T) {
    if elem not_in buf.down {
        buf.pressed += {elem}
        buf.buffered += {elem}
        buf.timer[elem] = 0
    } else {
        buf.repeated += {elem}
    }
    buf.down += {elem}
}

button_buffer_apply_release :: proc(buf: ^Button_Buffer($T), elem: T) {
    if elem in buf.down {
        buf.released += {elem}
    }
    buf.down -= {elem}
}

button_buffer_apply_event :: proc(input: ^Input, event: platform.Event) {
    #partial switch v in event {
    case platform.Event_Button:
            if v.pressed {
                button_buffer_apply_press(&input.buttons, v.button)
            } else {
                button_buffer_apply_release(&input.buttons, v.button)
            }

    case platform.Event_Mouse_Button:
        if v.pressed {
            button_buffer_apply_press(&input.mouse_buttons, v.button)
        } else {
            button_buffer_apply_release(&input.mouse_buttons, v.button)
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

gamepad_apply_state :: proc(gpad: ^Gamepad, state: platform.Gamepad_State) {
    for btn in Gamepad_Button {
        if btn in state.buttons {
            button_buffer_apply_press(&gpad.buttons, btn)
        } else {
            button_buffer_apply_release(&gpad.buttons, btn)
        }
    }

    gpad.axes[.Left_Trigger ] = clamp(state.axes[.Left_Trigger ], 0, 1)
    gpad.axes[.Right_Trigger] = clamp(state.axes[.Right_Trigger], 0, 1)
    gpad.axes[.Left_Thumb_X ] = clamp(state.axes[.Left_Thumb_X ], -1, 1)
    gpad.axes[.Left_Thumb_Y ] = clamp(state.axes[.Left_Thumb_Y ], -1, 1)
    gpad.axes[.Right_Thumb_X] = clamp(state.axes[.Right_Thumb_X], -1, 1)
    gpad.axes[.Right_Thumb_Y] = clamp(state.axes[.Right_Thumb_Y], -1, 1)
}
