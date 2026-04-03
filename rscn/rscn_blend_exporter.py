# You can run this from command line like so:
# blender.exe scene.blend --background --python rscn_blend_exporter.py
# TODO: support adding this as a plugin
import bpy
import os
import time
import mathutils
import numpy as np
from bpy.props import BoolProperty, StringProperty
from bpy_extras.io_utils import ExportHelper

VERSION_MAJOR = 0
VERSION_MINOR = 1

bl_info = {
    "name": "Raven Scene Exporter",
    "blender": (5, 0, 0),
    "category": "Import-Export",
    "version": (VERSION_MAJOR, VERSION_MINOR, 0),
    "author": "Jakub Tomsu",
}

def isalnum_ascii(c):
    return ('A' <= c <= 'Z' or 'a' <= c <= 'z' or '0' <= c <= '9')

def norm_name(name):
    out = []
    for c in name:
        if c == ' ':
            out.append('_')
        else:
            out.append(c)
    return ''.join(out)

def srgb_to_linear(x):
    return np.where( x >= 0.04045,((x + 0.055) / 1.055)**2.4, x/12.92 )

def print_dtype_info(dtype):
    print(f"{'Field':<10} {'Offset':<10} {'Size (bytes)':<12} {'Type'}")
    print("-" * 45)
    for name, (field_dtype, offset) in dtype.fields.items():
        print(f"{name:<10} {offset:<10} {field_dtype.itemsize:<12} {field_dtype}")
    print("Total serialized size:", dtype.itemsize, "bytes")


vert_dtype = np.dtype([
    ('pos', np.float32, 3),
    ('uv',  np.float32, 2),
    ('nor', np.int8,  3),
    ('col', np.uint8, 3),
])


conv_mat = mathutils.Matrix((
    ( 1.0, 0.0, 0.0),
    ( 0.0, 0.0, 1.0),
    ( 0.0, 1.0, 0.0),
))

conv_mat_inv = conv_mat.inverted()

conv_mat_np = np.array(conv_mat)
conv_mat_inv_np = np.linalg.inv(conv_mat_np)


_prof = {
    "time": time.perf_counter(),
    "table": {},
}

def prof(name: str):
    now = time.perf_counter()
    dur = now - _prof["time"]
    _prof["time"] = now
    total, num = _prof["table"].get(name, (0.0, 0))
    _prof["table"][name] = (total + dur, num + 1)

def prof_print():
    print("Profiler timings:")
    data = list(_prof["table"].items())

    total_time = 0.0
    for name, (total, count) in data:
        total_time += total

    data = sorted(data, key=lambda x: x[1][0], reverse=True)

    print()
    header = f"{'Name':20s} | {'Total (ms)':>10s} | {'Avg (ms)':>9s} | {'Hits':>5s} | {'%':>6s}"
    print(header)
    print("-" * len(header))

    for name, (total, count) in data:
        total_ms = total * 1e3
        avg_ms = (total / count) * 1e3
        pct = (total / total_time) * 100
        print(f"{name:20s} | {total_ms:10.3f} | {avg_ms:9.3f} | {count:5d} | {pct:6.2f}")
    print()

def buf_append(b, data):
    b['data'].append(data)
    b['len'] += len(data)
    b['size'] += data.nbytes

def export_rscn(context):
    if not bpy.data.filepath:
        raise Exception("Blend file is not saved")

    depsgraph = context.evaluated_depsgraph_get()

    out_name = os.path.splitext(bpy.data.filepath)[0] + ".rscn"

    print(f"\nExporting '{out_name}' and '{out_name}...")

    elems = []

    vert_buf = {'data': [], 'len': 0, 'size': 0}
    ind_buf = {'data': [], 'len': 0, 'size': 0}
    spl_buf = {'data': [], 'len': 0, 'size': 0}

    mesh_table = {}
    spl_table = {}
    obj_table = {}
    image_table = {}
    mat_to_img_idx_table = {}

    elems.append(f"# Blender {bpy.app.version_string}\n")

    prof("start")
    elems.append("\n@imgs\n")

    for mat in bpy.data.materials:
        for node in mat.node_tree.nodes:
            if node.type != 'TEX_IMAGE' or not node.image:
                continue

            texname = os.path.basename(node.image.filepath)

            if texname in image_table:
                continue

            elems.append(f"{texname}\n")

            mat_to_img_idx_table[mat.name] = len(image_table)
            image_table[texname] = len(image_table)

    prof("Materials")

    elems.append("\n@mshs\n")

    for obj in bpy.data.objects:
        if obj.type in ['EMPTY', 'MESH', 'CURVE']:
            obj_table[norm_name(obj.name)] = len(obj_table)

    prof("Objs")

    for obj in bpy.data.objects:
        if obj.type != 'MESH':
            continue

        mesh = obj.data

        mesh_name = norm_name(mesh.name)

        if mesh_name in mesh_table:
            print(f"WARNING: skipping {obj.name}")
            continue
        mesh_table[mesh_name] = len(mesh_table)

        prof("Mesh begin")

        eval_obj = obj.evaluated_get(depsgraph)

        mesh = eval_obj.to_mesh()

        prof("Mesh tomesh")

        tri_loops = np.empty((len(mesh.loop_triangles), 3), dtype=np.uint32)
        mesh.loop_triangles.foreach_get('loops', tri_loops.ravel())

        tri_verts = np.empty(len(mesh.loop_triangles) * 3, dtype=np.uint16)
        mesh.loop_triangles.foreach_get('vertices', tri_verts.ravel())

        prof("Mesh tris")

        vert_positions = np.empty((len(mesh.vertices), 3), dtype=np.float32)
        loop_normals = np.empty((len(mesh.loops), 3), dtype=np.float32)

        mesh.vertices.foreach_get('co', vert_positions.ravel())
        mesh.loops.foreach_get('normal', loop_normals.ravel())

        # vert_positions[:, 1] *= -1
        vert_positions = vert_positions @ conv_mat_np.T
        loop_normals = loop_normals @ conv_mat_inv_np.T

        loop_normals = ((loop_normals * 0.5 + 0.5).clip(0.0, 1.0) * 127).astype(np.uint8)

        loop_verts = np.empty(len(mesh.loop_triangles) * 3, dtype=vert_dtype)

        loop_verts['pos'] = vert_positions[tri_verts.ravel()]
        loop_verts['nor'] = loop_normals[tri_loops.ravel()]

        prof("Mesh pos nor")

        uv_layer = mesh.uv_layers.active.data
        loop_uvs = np.empty((len(mesh.loops), 2), dtype=np.float32)
        uv_layer.foreach_get('uv', loop_uvs.ravel())
        loop_uvs[:, 1] = 1.0 - loop_uvs[:, 1]
        loop_verts['uv'] = loop_uvs[tri_loops.ravel()]

        prof("Mesh uvs")

        if mesh.vertex_colors:
            col_layer = mesh.vertex_colors.active.data
            colors = np.empty((len(mesh.loops), 4), dtype=np.float32)
            col_layer.foreach_get('color', colors.ravel())
            loop_colors = (srgb_to_linear(colors[:, :3]) * 255).astype(np.uint8)
            loop_verts['col'] = loop_colors[tri_loops.ravel()]
        else:
            loop_verts['col'].fill(255)

        prof("Mesh colors")

        if True:
            verts, loop_to_unique = np.unique(loop_verts, return_inverse=True)
        else:
            verts = loop_verts
            loop_to_unique = np.arange(len(loop_verts), dtype=np.uint16)

        prof("Mesh unique")

        indices = loop_to_unique.astype(np.uint16)

        elems.append(f"{mesh_name} {len(indices)} {len(verts)} {ind_buf['len']:X} {vert_buf['len']:X}")

        buf_append(ind_buf, indices)
        buf_append(vert_buf, verts)

        prof("Mesh tobytes")

        elems.append("\n")

        prof("Mesh colors")

        eval_obj.to_mesh_clear()

        prof("Mesh end")

    elems.append("\n@spls\n")
    for obj in bpy.data.objects:
        if obj.type != 'CURVE':
            continue
        curve = obj.to_curve(depsgraph, apply_modifiers=True)

        for i, spl in enumerate(curve.splines):
            name = norm_name(obj.name)
            if len(curve.splines) > 1:
                name = name + f"{i}"

            if spl.type == 'BEZIER':
                continue


            if name in spl_table:
                print(f"WARNING: skipping spline {obj.name}")
                continue
            spl_table[name] = len(spl_table)


            pos = np.empty((len(spl.points), 4), dtype=np.float32)
            radius = np.empty(len(spl.points), dtype=np.float32)
            tilt = np.empty(len(spl.points), dtype=np.float32)

            spl.points.foreach_get("co", pos.ravel())
            spl.points.foreach_get("radius", radius)
            spl.points.foreach_get("tilt", tilt)

            points = np.empty((len(spl.points), 5), dtype=np.float32)
            points[:, :3] = pos[:, :3] @ conv_mat_np.T
            points[:, 3] = radius
            points[:, 4] = tilt

            elems.append(f"{name} {len(points)} {spl_buf['len']:X}\n")
            buf_append(spl_buf, points)

        obj.to_curve_clear()

    prof("Curves")

    elems.append("\n@objs\n")
    for obj in bpy.data.objects:
        if obj.type == 'EMPTY':
            elems.append(f"emp ")
        elif obj.type == 'MESH':
            mesh_index = mesh_table[norm_name(obj.data.name)]
            elems.append(f"msh {mesh_index} ")
        elif obj.type == 'CURVE':
            elems.append(f"spl ")
        else:
            continue

        parent_index = -1
        if obj.parent != None:
            parent_name = norm_name(obj.parent.name)
            if parent_name in obj_table:
                parent_index = obj_table[parent_name]

        tex = -1
        if obj.active_material:
            tex = mat_to_img_idx_table.get(obj.active_material.name, -1)

        pos = obj.matrix_local.to_translation()
        # pos = mathutils.Vector((pos.x, pos.z, pos.y))
        pos = conv_mat @ pos
        rot = obj.matrix_local.to_quaternion()
        mat = obj.matrix_local.to_3x3()
        mat = conv_mat @ mat @ conv_mat_inv

        print(obj.name, pos.xyz, obj.location.xyz)

        elems.append(f"{norm_name(obj.name)} {parent_index} {tex} [{pos.x:.6g} {pos.y:.6g} {pos.z:.6g}] [{mat[0][0]:.6g} {mat[1][0]:.6g} {mat[2][0]:.6g} {mat[0][1]:.6g} {mat[1][1]:.6g} {mat[2][1]:.6g} {mat[0][2]:.6g} {mat[1][2]:.6g} {mat[2][2]:.6g}]\n")

    prof("Object Tree")

    ind_offs = 0
    vert_offs = 0
    spl_offs = 0

    with open(out_name + ".bin", "wb") as fh:
        MAGIC = b"rscn\n"
        fh.write(MAGIC)

        ind_offs = len(MAGIC)

        for b in ind_buf['data']:
            fh.write(b.tobytes())

        vert_offs = ind_offs + ind_buf['size']

        for b in vert_buf['data']:
            fh.write(b.tobytes())

        spl_offs = vert_offs + vert_buf['size']

        for b in spl_buf['data']:
            fh.write(b.tobytes())


        for data in ind_buf['data']:
            b = data.tobytes()
            fh.write(b)
        prof("Write Bin")


    header = []

    # NOTE: comments must be after the header is finished
    header.append("rscn\n")
    header.append(f"ver {VERSION_MAJOR} {VERSION_MINOR}\n")
    # header.append(f"siz {bin['offs']}\n")
    header.append(f"img {len(image_table)}\n")
    header.append(f"msh {len(mesh_table)} {ind_offs:X} {ind_buf['len']:X} {vert_offs:X} {vert_buf['len']:X}\n")
    header.append(f"spl {len(spl_table)} {spl_offs:X} {spl_buf['len']:X}\n")
    header.append(f"obj {len(obj_table)}\n")
    header.append(f"\n") # NOTE: the header end must be marked with empty line

    prof("Header")

    with open(out_name, "wb") as fh:
        fh.write("".join(header).encode("ascii"))
        # fh.write("".join(elems).encode("ascii"))
        for p in elems:
            fh.write(p.encode("ascii"))
        prof("Write ASCII")

    for action in bpy.data.actions:
        start = int(action.frame_range[0])
        end = int(action.frame_range[1])
        print(f"Action: {action.name}, frames: {start}..{end}")
        for frame in range(start, end):
            bpy.context.scene.frame_set(frame)
            for obj in bpy.data.objects:
                if obj.type != 'ARMATURE':
                    continue


def main():
    start = time.perf_counter()
    export_rscn(bpy.context)
    end = time.perf_counter()

    # print_dtype_info(vert_dtype)

    prof_print()

    print(f"Exporting rscn finished in {(end - start) * 1e3:.3f} ms")


if __name__ == "__main__":
    main()
