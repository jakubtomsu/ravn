package ravn_example_hello

import rv "../.."
import "../../base"
import "core:math/rand"
import "core:math/linalg"

N :: 4096

state: ^State

// NOTE: those pools are not generational. That can be easily added.
State :: struct {
    // Using the GPU bit pool. A datastructure package for users might get added later.
    pool:       base.Bit_Pool(4096),
    parts:      [4096]Particle,

    ll_parts:   [N]Particle,
    ll_next:    [N]u32,
    ll_free:    u32,
    ll_max:     u32,
}

Particle :: struct {
    pos:    [2]f32,
    vel:    [2]f32,
    timer:  f32,
    dur:    f32,
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
}

_shutdown :: proc() {
    free(state)
}

ll_find_index :: proc() -> (index: int, ok: bool) {
    index = int(state.ll_free)
    if index > 0 && index < N {
        state.ll_free = state.ll_next[index]
    } else {
        // push to the end
        if state.ll_max < 0 || int(state.ll_max + 1) >= N {
            return 0, false
        }
        state.ll_max += 1
        index = int(state.ll_max)
    }
    assert(index < N)
    return index, true
}

ll_remove_index :: proc(index: int) {
    state.ll_next[index] = state.ll_free
    state.ll_free = u32(index)
}

_update :: proc(hot_state: rawptr) -> rawptr {
    if hot_state != nil {
        state = cast(^State)hot_state
    }

    if rv.get_key_pressed(.Escape) {
        rv.request_shutdown()
    }

    delta := rv.get_delta_time()

    rv.update_draw_layer(0, rv.make_screen_camera())
    rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.set_draw_blend(.Alpha)

    if rv.get_mouse_down(.Left) {
        num := 64
        vel: f32 = 200
        if rv.get_mouse_pressed(.Left) {
            num *= 2
        }

        for i in 0..<num {
            p: Particle = {
                pos = rv.get_mouse_pos() + 5 * {
                    rand.float32() * 2.0 - 1.0,
                    rand.float32() * 2.0 - 1.0,
                },
                vel = vel * rand.float32() * linalg.normalize0([2]f32{
                    rand.float32() * 2.0 - 1.0,
                    rand.float32() * 2.0 - 1.0,
                }),
                timer = rand.float32_range(1, 2),
            }

            {
                index, index_ok := base.bit_pool_find_0(state.pool)
                if index_ok {
                    base.bit_pool_set_1(&state.pool, index)
                    state.parts[index] = p
                } else {
                    base.log_err("Bit Pool full!")
                }
            }

            {
                index, index_ok := ll_find_index()
                if index_ok {
                    state.ll_next[index] = max(u32)
                    state.ll_parts[index] = p
                } else {
                    base.log_err("List Pool full!")
                }
            }
        }
    }

    sim_delta := delta

    if rv.get_key_down(.Space) {
        sim_delta *= 5
    }

    for &p, index in state.parts {
        if !base.bit_pool_check_1(state.pool, index) {
            continue
        }

        if p.timer < 0 {
            base.bit_pool_set_0(&state.pool, index)
            continue
        }

        p.timer -= sim_delta
        p.vel = rv.lexp(p.vel, 0, sim_delta)
        p.pos += p.vel * sim_delta

        rv.draw_sprite(
            {p.pos.x, p.pos.y, 0.5},
            rv.font_slot(rv.rune_to_char('■')),
            scale = 2,
            col = rv.YELLOW * rv.fade(rv.smoothstep(0, 1, p.timer)),
        )
    }


    for &p, index in state.ll_parts {
        if state.ll_next[index] != max(u32) {
            continue
        }

        if p.timer < 0 {
            ll_remove_index(index)
            continue
        }

        p.timer -= sim_delta
        p.vel = rv.lexp(p.vel, 0, sim_delta)
        p.pos += p.vel * sim_delta

        rv.draw_sprite(
            {p.pos.x, p.pos.y, 0.25},
            rv.font_slot(rv.rune_to_char('■')),
            scale = 1,
            col = rv.GREEN * rv.fade(rv.smoothstep(0, 1, p.timer)),
        )
    }

    rv.set_draw_texture(rv.get_builtin_texture(.White))

    for i in 0..<64 {
        block_full := (state.pool.l1[0] & (1 << uint(i))) != 0
        block := state.pool.l0[i]

        if block_full {
            assert(~block == 0)
        }

        base_pos := [3]f32{
            64 + f32(i % 8) * (32 + 4),
            64 + f32(i / 8) * (32 + 4),
            0.1,
        }

        block_any := block != 0

        rv.draw_sprite(
            base_pos,
            scale = {32, 32},
            col = block_full ? rv.RED : (block_any ? rv.PURPLE : rv.TRANSPARENT),
            scaling = .Absolute,
        )

        for i_local in 0..<64 {
            local_pos := base_pos + [3]f32{
                f32(i_local % 8) * 4 - 14,
                f32(i_local / 8) * 4 - 14,
                -0.05,
            }

            local_full := (block & (1 << uint(i_local))) != 0

            if local_full {
                rv.draw_sprite(
                    local_pos,
                    scale = 4,
                    scaling = .Absolute,
                )
            }

            // rv.draw_sprite()
        }
    }

    // LL

    for i in 0..<64 {
        base_pos := [3]f32{
            64  + f32(i % 8) * (32 + 4),
            512 + f32(i / 8) * (32 + 4),
            0.1,
        }

        block_full := true
        block_any := false

        // "emulate" the block masks to get the same comparison
        for i_local in 0..<64 {
            index := i * 64 + i_local
            local_full := state.ll_next[index] == max(u32)
            if local_full {
                block_any = true
            } else {
                block_full = false
            }
        }

        rv.draw_sprite(
            base_pos,
            scale = {32, 32},
            col = block_full ? rv.RED : (block_any ? rv.PURPLE : rv.TRANSPARENT),
            scaling = .Absolute,
        )

        for i_local in 0..<64 {
            local_pos := base_pos + [3]f32{
                f32(i_local % 8) * 4 - 14,
                f32(i_local / 8) * 4 - 14,
                -0.05,
            }

            index := i * 64 + i_local

            local_full := state.ll_next[index] == max(u32)

            if local_full {
                rv.draw_sprite(
                    local_pos,
                    scale = 4,
                    scaling = .Absolute,
                )
            }
        }
    }

    rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))

    rv.draw_text("LMB to spawn particles", {10, 10, 0}, scale = 2)

    rv.submit_layers()
    rv.render_layer(0, rv.DEFAULT_RENDER_TEXTURE, clear_color = [3]f32{0, 0, 0.1}, clear_depth = true)

    return state
}
