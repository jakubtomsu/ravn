import bpy
import bmesh
import os

# Helper to format vertices with aligned padding for clean columns.
# Maps to our coord space by swapping Y and Z
def fmt_v(v):
    return f"{{{v.x:>10.6f}, {v.z:>10.6f}, {v.y:>10.6f}, 0}}"

# Non-indexed
def export_shapes() -> str:
    output = ""

    output += "// Machine generated. Do not edit.\n"
    output += "package ravn_debugdraw\n\n"
    output += "@(rodata)\n"
    output += "_buffer_shape_verts := [Shape_Kind][]Shape_Vertex{\n"

    depsgraph = bpy.context.evaluated_depsgraph_get()

    for obj in bpy.data.objects:
        if obj.type not in {'MESH', 'CURVE', 'FONT', 'SURFACE'}:
            continue

        eval_obj = obj.evaluated_get(depsgraph)

        try:
            mesh = eval_obj.to_mesh()
        except RuntimeError:
            continue

        shape_name = obj.name.replace(" ", "_").replace(".", "_")
        output += f"    .{shape_name} = {{ // MARK: {shape_name}\n"

        if len(mesh.polygons) > 0:
            # Triangles
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bmesh.ops.triangulate(bm, faces=bm.faces[:])
            bm.to_mesh(mesh)
            bm.free()

            for poly in mesh.polygons:
                line_str = "        "
                for loop_index in reversed(poly.loop_indices):
                    v = mesh.vertices[mesh.loops[loop_index].vertex_index].co
                    line_str += f"{fmt_v(v)}, "

                output += line_str.rstrip() + "\n"
        else:
            # Lines
            for edge in mesh.edges:
                v1 = mesh.vertices[edge.vertices[0]].co
                v2 = mesh.vertices[edge.vertices[1]].co

                output += f"        {fmt_v(v1)}, {fmt_v(v2)},\n"

        output += "    },\n\n"
        eval_obj.to_mesh_clear()

    output += "}\n"

    return output


if __name__ == "__main__":
    text = export_shapes()
    out_name = os.path.join(os.path.dirname(bpy.data.filepath), "debugdraw_shape_data.odin")
    print(out_name)
    with open(out_name, "w") as fh:
        fh.write(text)