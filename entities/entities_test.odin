#+test
#+vet shadowing unused
package ravn_entities

import "core:testing"

@(test)
_test_basic :: proc(t: ^testing.T) {
    Foo :: struct { using base: Base, using named: Named, val: u8 }
    Bar :: struct { using base: Base, using named: Named, val: f64 }
    Baz :: struct { using base: Base }
    Named :: struct { name: string, }

    ents: Entities(union{Foo, Bar, Baz}, union{})
    init(&ents, default_cap = 64)
    defer shutdown(&ents)

    testing.expect(t, len(get_values(ents, Foo)) == 0)
    testing.expect(t, len(get_values(ents, Bar)) == 0)

    a := create_sub(&ents, Foo{name = "First", val = 1})
    testing.expect(t, a != {})
    testing.expect(t, a.variant == 0)

    testing.expect(t, len(get_values(ents, Foo)) == 1)

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
_test_iter_val :: proc(t: ^testing.T) {
    Foo :: struct { using base: Base, val: u8 }
    Bar :: struct { using base: Base, x: f32 }
    ents: Entities(union{Foo, Bar}, union{})
    init(&ents, default_cap = 64)
    defer shutdown(&ents)

    handles := []Handle{
        create(&ents, Foo{val = 123}),
        create(&ents, Foo{}),
        create(&ents, Foo{}),
        create(&ents, Foo{}),
        create(&ents, Foo{}),
    }

    testing.expect(t, get(&ents, handles[0]).variant.(^Foo).val == 123)

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
_test_iter_sub :: proc(t: ^testing.T) {
    Foo :: struct { using base: Base, using named: Named, val: u8 }
    Bar :: struct { using base: Base, using named: Named, val: f64 }
    Baz :: struct { using base: Base }
    Named :: struct { name: string, }

    ents: Entities(union{Foo, Bar, Baz}, union{Base, Foo, Bar, Baz, Named})
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

    testing.expect(t, get_sub(&ents, handles[0], Named).name == "b")

    destroy(&ents, handles[0])
    destroy(&ents, handles[1])
    destroy(&ents, handles[2])

    counter := 0
    for it := begin_sub(&ents, Named); _ in next(&it) {
        counter += 1
    }
    testing.expect(t, counter == 6)
}

@(test)
_test_generation_aba :: proc(t: ^testing.T) {
    Foo :: struct { using base: Base, val: int }
    Bar :: struct { using base: Base, val: int, x: f32 }
    ents: Entities(union{Foo, Bar}, union{Base})
    init(&ents, default_cap = 64)
    defer shutdown(&ents)

    h1, _ := create(&ents, Foo{val = 10})
    destroy(&ents, h1)

    h2, _ := create(&ents, Foo{val = 20})

    testing.expect(t, h1.index == h2.index, "Freelist should reuse the old slot")
    testing.expect(t, h1.gen != h2.gen, "Generation counter must increment on reuse")

    _, ok1 := get(&ents, h1)
    testing.expect(t, !ok1, "Old handle should be fully invalidated")

    ptr2, ok2 := get(&ents, h2)
    testing.expect(t, ok2 && ptr2.variant.(^Foo).val == 20)
}

@(test)
_test_capacity_limits :: proc(t: ^testing.T) {
    Foo :: struct { using base: Base }
    Bar :: struct { using base: Base, x: f32 }
    ents: Entities(union{Foo, Bar}, union{Base})

    init(&ents, default_cap = 4)
    defer shutdown(&ents)

    _, ok1 := create(&ents, Foo{})
    _, ok2 := create(&ents, Foo{})
    h3, ok3 := create(&ents, Foo{})
    testing.expect(t, ok1 && ok2 && ok3, "Should successfully allocate up to capacity")

    _, ok4 := create(&ents, Foo{})
    testing.expect(t, !ok4, "Should reject allocations past capacity")

    destroy(&ents, h3)
    h5, ok5 := create(&ents, Foo{})

    testing.expect(t, ok5, "Should allocate after freeing a slot")
    testing.expect(t, h5.index == h3.index, "Should reuse the recently freed slot")
}

@(test)
_test_clear_invalidation :: proc(t: ^testing.T) {
    Foo :: struct { using base: Base }
    Bar :: struct { using base: Base, x: f32 }
    ents: Entities(union{Foo, Bar}, union{Base})
    init(&ents, default_cap = 64)
    defer shutdown(&ents)

    h1, _ := create(&ents, Foo{})
    h2, _ := create(&ents, Foo{})

    clear(&ents)

    _, ok1 := get(&ents, h1)
    _, ok2 := get(&ents, h2)
    testing.expect(t, !ok1 && !ok2, "Clear must immediately invalidate active handles")

    h3, _ := create(&ents, Foo{})
    testing.expect(t, h3.index == 1, "Clear should reset the top index watermark")
    testing.expect(t, h3.gen != h1.gen, "Clear must bump the generation counter of reused slots")
}

@(test)
_test_clone :: proc(t: ^testing.T) {
    Foo :: struct { using base: Base, val: int }
    Bar :: struct { using base: Base, x: f32 }
    ents: Entities(union{Foo, Bar}, union{Base})
    init(&ents, default_cap = 64)
    defer shutdown(&ents)

    h1, _ := create(&ents, Foo{val = 10})

    ents_clone := clone(&ents)
    defer shutdown(&ents_clone)

    ptr_clone, _ := get(&ents_clone, h1)
    ptr_clone.variant.(^Foo).val = 99
    ptr_orig, _ := get(&ents, h1)
    testing.expect(t, ptr_orig.variant.(^Foo).val == 10)
}
