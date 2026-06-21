#+test
#+vet shadowing unused
package ravn_entities

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
}


@(test)
_iter_val_test :: proc(t: ^testing.T) {
    Foo :: struct { using base: Base, val: u8 }

    sys: System(union{Foo}, union{})
    init(&sys, default_cap = 64)
    defer shutdown(&sys)

    handles := []Handle{
        create(&sys, Foo{}),
        create(&sys, Foo{}),
        create(&sys, Foo{}),
        create(&sys, Foo{}),
        create(&sys, Foo{}),
    }

    destroy(&sys, handles[0])
    destroy(&sys, handles[2])
    destroy(&sys, handles[4])

    counter := 0
    for it := begin_val(&sys, Foo); _ in next(&it) {
        counter += 1
    }
    testing.expect(t, counter == 2)
}


@(test)
_iter_sub_test :: proc(t: ^testing.T) {
    Foo :: struct { using base: Base, using named: Named, val: u8 }
    Bar :: struct { using base: Base, using named: Named, val: f64 }
    Baz :: struct { using base: Base }
    Named :: struct { name: string, }
    
    sys: System(union{Foo, Bar, Baz}, union{Base, Named})
    init(&sys, default_cap = 64)
    defer shutdown(&sys)

    handles := []Handle{
        create(&sys, Bar{name = "b"}),
        create(&sys, Bar{name = "b"}),
        create(&sys, Foo{name = "f"}),
        create(&sys, Baz{}),
        create(&sys, Foo{name = "f"}),
        create(&sys, Foo{name = "f"}),
        create(&sys, Bar{name = "b"}),
        create(&sys, Foo{name = "f"}),
        create(&sys, Baz{}),
        create(&sys, Bar{name = "b"}),
        create(&sys, Baz{}),
        create(&sys, Baz{}),
        create(&sys, Foo{name = "f"}),
    }

    destroy(&sys, handles[0])
    destroy(&sys, handles[1])
    destroy(&sys, handles[2])

    counter := 0
    for it := begin_sub(&sys, Named); _ in next(&it) {
        counter += 1
    }
    testing.expect(t, counter == 6)
}
