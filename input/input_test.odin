#+test
#+vet unused shadowing
package ravn_input

import "../platform"
import "core:testing"

@(test)
_test_common :: proc(t: ^testing.T) {
    init()
    defer shutdown()

    testing.expect(t, !button_down(.Space))
    testing.expect(t, !button_pressed(.Space))

    apply_event(platform.Event_Button{button = .Space, pressed = true})
    testing.expect(t, button_down(.Space))
    testing.expect(t, button_pressed(.Space))
    testing.expect(t, button_down_time(.Space) == 0.0)
    update(0.1)
    testing.expect(t, button_down(.Space))
    testing.expect(t, button_down_time(.Space) > 0.015)

    apply_event(platform.Event_Button{button = .Space, pressed = false})
    testing.expect(t, !button_down(.Space))
    testing.expect(t, button_released(.Space))
    update(0.1)
    testing.expect(t, !button_down(.Space))
    testing.expect(t, !button_released(.Space))

    apply_event(platform.Event_Button{button = .A, pressed = true})
    update(0.1)
    testing.expect(t, button_pressed(.A, 0.5))

    apply_event(platform.Event_Button{button = .B, pressed = true})
    update(1.0)
    testing.expect(t, !button_pressed(.B, 0.5))
}
