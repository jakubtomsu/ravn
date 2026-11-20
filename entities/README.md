# RAVN Entity system

Simple entity container focused on flexibility.

Entity type is a union of structs (variants). The container manages a separate free-list-based pool for each entity variant.

Allocates once at init

Entities can be iterated by types or by subtypes (components).

Example:
```odin
import "ravn/entities"

Shared_Component :: struct {
    pos:    [3]f32,
    rot:    quaternion128,
    scale:  [3]f32,
}

Foo :: struct {
    using base:     entities.Base,
    using shared:   Shared_Component,
    timer:          f32,
}

Bar :: struct {
    using base: entities.Base,
    using shared:   Shared_Component,
    health:     i16,
}

Entity :: union{ Foo, Bar, }
Component :: union { entities.Base, Shared_Component, }

ents := entities.Entities(Entity, Component)

```