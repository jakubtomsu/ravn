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

    ents: Entities(union{Foo, Bar, Baz}, union{Base, Named})
    init(&ents, default_cap = 64)
    defer shutdown(&ents)

    testing.expect(t, len(get_buffer(&ents, Foo)) == 0)
    testing.expect(t, len(get_buffer(&ents, Bar)) == 0)

    a := create_sub(&ents, Foo{name = "First", val = 1})
    testing.expect(t, a != {})
    testing.expect(t, a.variant == 0)

    testing.expect(t, len(get_buffer(&ents, Foo)) == 1)

    testing.expect(t, destroy(&ents, a))

    a_ptr, a_ok := get(&ents, a)
    testing.expect(t, !a_ok)
    testing.expect(t, a_ptr.base == nil)

    b_val := Foo{name = "Second", val = 2}
    b := create_val(&ents, b_val)

    testing.expect(t, b != {})
    testing.expect(t, b.index == a.index) // Slot reuse

    b_ptr, b_ok := get(&ents, b)
    testing.expect(t, b_ok)
    testing.expect(t, b_ptr.base != nil)
    testing.expect(t, b_ptr.variant.(^Foo).name == "Second")

    testing.expect(t, a != b)
}


@(test)
_iter_val_test :: proc(t: ^testing.T) {
    Foo :: struct { using base: Base, val: u8 }

    ents: Entities(union{Foo}, union{})
    init(&ents, default_cap = 64)
    defer shutdown(&ents)

    handles := []Handle{
        create(&ents, Foo{}),
        create(&ents, Foo{}),
        create(&ents, Foo{}),
        create(&ents, Foo{}),
        create(&ents, Foo{}),
    }

    destroy(&ents, handles[0])
    destroy(&ents, handles[2])
    destroy(&ents, handles[4])

    counter := 0
    for it := begin_val(&ents, Foo); _ in next(&it) {
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
    
    ents: Entities(union{Foo, Bar, Baz}, union{Base, Named})
    init(&ents, default_cap = 64)
    defer shutdown(&ents)

    handles := []Handle{
        create(&ents, Bar{name = "b"}),
        create(&ents, Bar{name = "b"}),
        create(&ents, Foo{name = "f"}),
        create(&ents, Baz{}),
        create(&ents, Foo{name = "f"}),
        create(&ents, Foo{name = "f"}),
        create(&ents, Bar{name = "b"}),
        create(&ents, Foo{name = "f"}),
        create(&ents, Baz{}),
        create(&ents, Bar{name = "b"}),
        create(&ents, Baz{}),
        create(&ents, Baz{}),
        create(&ents, Foo{name = "f"}),
    }

    destroy(&ents, handles[0])
    destroy(&ents, handles[1])
    destroy(&ents, handles[2])

    counter := 0
    for it := begin_sub(&ents, Named); _ in next(&it) {
        counter += 1
    }
    testing.expect(t, counter == 6)
}
