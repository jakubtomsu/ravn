#+test
#+private file
package ravn_scene

import "core:fmt"
import "core:strings"
import "core:testing"

@(test)
_tri :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	sc, err := load(#load("test_data/test_tri.rscn"))
	testing.expectf(t, err == nil, "Load Error: %v", err)
	str := to_string(sc, include_data = true)
	fmt.println(str)
	EXPECT :: """
	{
		nodes = {
			"Plane" = { parent="<NONE>", material="", kind=Mesh, pos=[0, 0, 0], rot=[1, 0, 0, 0], scale=[1, 1, 1] },
		},
		meshes = {
			"Plane" = {
				verts = {
					Mesh_Vert{pos = [0, 0, 0], uv = [0, 1], nor = [0, 127, 0], col = [255, 255, 255]},
					Mesh_Vert{pos = [0, 0, -2], uv = [0, 0], nor = [0, 127, 0], col = [255, 255, 255]},
					Mesh_Vert{pos = [2, 0, 0], uv = [1, 1], nor = [0, 127, 0], col = [255, 255, 255]},
				},
				indices = {
					1, 0, 2,
				},
			},
		},
	}
	"""
	_expect_equal_strings(t, EXPECT, str)
}

_expect_equal_strings :: proc(t: ^testing.T, a, b: string) {
	a := a
	b := b

	for i := 0;; i += 1{
		line_a, ok_a := strings.split_lines_iterator(&a)
		line_b, ok_b := strings.split_lines_iterator(&b)

		if !ok_a && !ok_b {
			break
		}

		if !testing.expectf(t, ok_a == ok_b, "Line %i", i) {
			break
		}

		if !testing.expectf(t, line_a == line_b, "Line %i: %q vs %q", i + 1, line_a, line_b) {
			break
		}
	}
}