#+test
#+vet unused shadowing
package ravn_base

import "core:testing"
import "core:thread"

@(test)
_test_spsc_basic :: proc(t: ^testing.T) {
    q: SPSC(4, int)

    testing.expect(t, spsc_push(&q, 10))
    testing.expect(t, spsc_push(&q, 20))
    testing.expect(t, spsc_push(&q, 30))

    v, ok := spsc_pop(&q)
    testing.expect(t, ok && v == 10)
    v, ok = spsc_pop(&q)
    testing.expect(t, ok && v == 20)

    testing.expect(t, spsc_push(&q, 40))
    testing.expect(t, spsc_push(&q, 50))
    testing.expect(t, spsc_push(&q, 60))
    testing.expect(t, !spsc_push(&q, 70))

    buf: [4]int
    popped := spsc_pop_elems(&q, buf[:])
    testing.expect(t, len(popped) == 4)
    testing.expect(t, popped[0] == 30 && popped[1] == 40 && popped[2] == 50 && popped[3] == 60)

    _, ok = spsc_pop(&q)
    testing.expect(t, !ok)
}

@(test)
_test_spsc_fuzz :: proc(t: ^testing.T) {
    State :: struct {
        q:      ^SPSC(4096, int),
        total:  int,
        failed: bool,
    }

    q: SPSC(4096, int)
    ctx := State{q = &q, total = 10_000_000, failed = false}

    producer := thread.create(proc(t: ^thread.Thread) {
        c := cast(^State)t.data
        for i in 1..=c.total {
            for !spsc_push(c.q, i) {
                thread.yield()
            }
        }
    })
    producer.data = &ctx

    consumer := thread.create(proc(t: ^thread.Thread) {
        c := cast(^State)t.data
        for i in 1..=c.total {
            val: int
            ok: bool
            for {
                val, ok = spsc_pop(c.q)
                if ok do break
                thread.yield()
            }
            if val != i do c.failed = true
        }
    })
    consumer.data = &ctx

    thread.start(consumer)
    thread.start(producer)

    thread.join(producer)
    thread.join(consumer)
    thread.destroy(producer)
    thread.destroy(consumer)

    testing.expect(t, !ctx.failed, "Consumer received values out of order or corrupted")
}
