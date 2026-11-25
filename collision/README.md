# RAVN Collision

Simple immediate-mode 3D collision package. Supports meshes and simple geometric primitives for colliders. This is not a traditional rigidbody physics engine.

The API lets you push colliders for a given physics sim step, and query them the next. The step state is double buffered - until you call `collision.end_step()` queries see the previous state.

You organize sim steps in two ways:
- Either always run queries along with new collider submission. The delay isn't major a problem and the result is a more stable sim compared to using the actual entity state when compared to always using the non-deterministic current entity state.
- Separate the frame into "collider submission step" which runs before the actual "update" step that performs queries. A bit more work to set up but gets rid of the double buffer latency.

Queries include:
- shape sweeps (find interection distance of a shape moving along a vector)
- shape tests (returns true if anything is overlapping the shape)
- shape overlaps (returns a slice of all overlapping shapes)
