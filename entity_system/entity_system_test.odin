#+test
#+vet shadowing unused
package raven_entity_system

import "core:testing"

@(test)
_basic_test :: proc(t: ^testing.T) {
    Foo :: struct { using base: Base, using named: Named, val: u8 }
    Bar :: struct { using base: Base, using named: Named, val: f64 }
    Baz :: struct { using base: Base }
    Named :: struct { name: string, }

    sys: System(union{Foo, Bar, Baz}, union{Base, Named})
    init(&sys, default_cap = 64)
    defer shutdown(&sys)

    testing.expect(t, len(get_buffer(&sys, Foo)) == 0)
    testing.expect(t, len(get_buffer(&sys, Bar)) == 0)

    a := create_sub(&sys, Foo{name = "First", val = 1})
    testing.expect(t, a != {})
    testing.expect(t, a.variant == 0)

    testing.expect(t, len(get_buffer(&sys, Foo)) == 1)

    testing.expect(t, destroy(&sys, a))

    a_ptr, a_ok := get(&sys, a)
    testing.expect(t, !a_ok)
    testing.expect(t, a_ptr == nil)

    b_val := Foo{name = "Second", val = 2}
    b := create_val(&sys, b_val)

    testing.expect(t, b != {})
    testing.expect(t, b.index == a.index) // Slot reuse

    b_ptr, b_ok := get(&sys, b)
    testing.expect(t, b_ok)
    testing.expect(t, b_ptr != nil)
    testing.expect(t, b_ptr.(^Foo).name == "Second")

    testing.expect(t, a != b)

    create(&sys, Foo{})
    create(&sys, Foo{})
    create(&sys, Bar{})

    counter := 0
    for it := begin(&sys, Foo); _ in next(&it) {
        counter += 1
    }
    testing.expect(t, counter == 3)

    counter = 0
    for it := begin(&sys, Named); _ in next(&it) {
        counter += 1
    }
    testing.expect(t, counter == 4)
}
