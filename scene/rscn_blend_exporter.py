# You can run this from command line like so:
# blender.exe scene.blend --background --python rscn_blend_exporter.py
# TODO: support adding this as a plugin
import bpy
import os
import time
import mathutils
import re
import numpy as np
from pathlib import Path
from pprint import pprint
import struct
from types import TracebackType

BIN_MAGIC = b"rscn"

VERSION = 0

bl_info = {
    "name": "RAVN Scene Exporter",
    "blender": (5, 0, 0),
    "category": "Import-Export",
    "version": (VERSION, 0, 0),
    "author": "Jakub Tomsu",
}

header_dtype = np.dtype([
    ('magic', np.uint32, 1),
    ('version', np.uint32, 1),

    ('string_range', np.uint64, 2),
    ('node_range', np.uint64, 2),
    ('image_range', np.uint64, 2),
    ('mesh_range', np.uint64, 2),
    ('skin_range', np.uint64, 2),
    ('spline_range', np.uint64, 2),
    ('skeleton_range', np.uint64, 2),
    ('bone_range', np.uint64, 2),
    ('anim_range', np.uint64, 2),
    ('mesh_vert_range', np.uint64, 2),
    ('skin_vert_range', np.uint64, 2),
    ('spline_vert_range', np.uint64, 2),
    ('index_range', np.uint64, 2),
    ('anim_curve_range', np.uint64, 2),
    ('anim_float3_frame_range', np.uint64, 2),
    ('anim_float4_frame_range', np.uint64, 2),
])

image_dtype = np.dtype([
    ('path_range', np.uint32, 2),
    ('mat_name_range', np.uint32, 2),
])

NODE_KIND_NONE = 0
NODE_KIND_MESH = 1
NODE_KIND_SKIN = 2
NODE_KIND_SPLINE = 3

node_dtype = np.dtype([
    ('name_range', np.uint32, 2),
    ('parent', np.uint32, 1),
    ('material_name_range', np.uint32, 2),
    ('kind', np.uint8, 1),
    ('pos', np.float32, 3),
    ('rot', np.float32, 4),
    ('scale', np.float32, 3),
])

# TODO: material?
mesh_dtype = np.dtype([
    ('name_range', np.uint32, 2),
    ('vert_range', np.uint32, 2),
    ('index_range', np.uint32, 2),
])

skin_dtype = np.dtype([
    ('name_range', np.uint32, 2),
    ('skeleton', np.uint32, 1),
    ('vert_range', np.uint32, 2),
    ('index_range', np.uint32, 2),
])

skeleton_dtype = np.dtype([
    ('name_range', np.uint32, 2),
    ('bone_range', np.uint32, 2),
])

bone_dtype = np.dtype([
    ('name_range', np.uint32, 2),
    ('parent', np.uint32, 1),
    ('pos', np.float32, 3),
    ('length', np.float32, 1),
    ('rot', np.float32, 4),
])

anim_dtype = np.dtype([
    ('name_range', np.uint32, 2),
    ('curve_range', np.uint32, 2),
])

mesh_vert_dtype = np.dtype([
    ('pos', np.float32, 3),
    ('uv',  np.float32, 2),
    ('nor', np.int8,    3),
    ('col', np.uint8,   3),
])

skin_vert_dtype = np.dtype([
    ('pos',     np.float32, 3),
    ('uv',      np.float32, 2),
    ('nor',     np.int8,    3),
    ('col',     np.uint8,   3),
    ('bones',   np.uint8,   4),
    ('weights', np.uint8,   4),
])

spline_dtype = np.dtype([
    ('name_range', np.uint32, 2),
    ('vert_range', np.uint32, 2),
])

spline_vert_dtype = np.dtype([
    ('pos',  np.float32, 3),
    ('rad',  np.float32, 1),
    ('tilt', np.float32, 1),
])

anim_curve_dtype = np.dtype([
    ('name_range', np.uint32, 2),
    ('pos_range', np.uint32, 2),
    ('rot_range', np.uint32, 2),
    ('scale_range', np.uint32, 2),
])

anim_float3_frame_dtype = np.dtype([
    ('time',  np.uint32,  1),
    ('value', np.float32, 3),
])

anim_float4_frame_dtype = np.dtype([
    ('time',  np.uint32,  1),
    ('value', np.float32, 4),
])



# MARK: Util

conv_mat = mathutils.Matrix((
    ( 1.0, 0.0, 0.0),
    ( 0.0, 0.0, 1.0),
    ( 0.0, 1.0, 0.0),
))

conv_mat_inv = conv_mat.inverted()

conv_mat_np = np.array(conv_mat)
conv_mat_inv_np = np.linalg.inv(conv_mat_np)


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

def dump_bpy(obj):
    """Converts a bpy_struct into a readable dictionary of its properties."""
    if obj is None:
        return None

    data = {}
    for prop in obj.bl_rna.properties:
        if prop.identifier in {'rna_type'} or prop.type == 'COLLECTION':
            continue
        try:
            val = getattr(obj, prop.identifier)
            if hasattr(val, "to_tuple"):
                val = val.to_tuple()
            data[prop.identifier] = val
        except Exception:
            pass

    return data

def get_mesh_loop_verts(mesh, dtype):
    tri_loops = np.empty((len(mesh.loop_triangles), 3), dtype=np.uint32)
    mesh.loop_triangles.foreach_get('loops', tri_loops.ravel())

    tri_vert_indices = np.empty(len(mesh.loop_triangles) * 3, dtype=np.uint32)
    mesh.loop_triangles.foreach_get('vertices', tri_vert_indices.ravel())

    vert_positions = np.empty((len(mesh.vertices), 3), dtype=np.float32)
    loop_normals = np.empty((len(mesh.loops), 3), dtype=np.float32)

    mesh.vertices.foreach_get('co', vert_positions.ravel())
    mesh.loops.foreach_get('normal', loop_normals.ravel())

    vert_positions = vert_positions @ conv_mat_np.T
    loop_normals = loop_normals @ conv_mat_inv_np.T

    loop_normals = np.rint(loop_normals.clip(-1.0, 1.0) * 127).astype(np.int8)

    loop_verts = np.empty(len(mesh.loop_triangles) * 3, dtype=dtype)

    loop_verts['pos'] = vert_positions[tri_vert_indices.ravel()]
    loop_verts['nor'] = loop_normals[tri_loops.ravel()]

    loop_uvs = np.empty((len(mesh.loops), 2), dtype=np.float32)
    if mesh.uv_layers.active:
        uv_layer = mesh.uv_layers.active.data
        uv_layer.foreach_get('uv', loop_uvs.ravel())
    else:
        loop_uvs.fill(0.0)
    # loop_uvs[:, 1] = 1.0 - loop_uvs[:, 1]
    loop_verts['uv'] = loop_uvs[tri_loops.ravel()]

    if mesh.vertex_colors:
        col_layer = mesh.vertex_colors.active.data
        colors = np.empty((len(mesh.loops), 4), dtype=np.float32)
        col_layer.foreach_get('color', colors.ravel())
        loop_colors = (srgb_to_linear(colors[:, :3]) * 255).astype(np.uint8)
        loop_verts['col'] = loop_colors[tri_loops.ravel()]
    else:
        loop_verts['col'].fill(255)

    return loop_verts, tri_vert_indices

def get_mesh_skinning_data(mesh_obj, armature_obj, max_influences=4):
    mesh = mesh_obj.data
    num_verts = len(mesh.vertices)

    bone_names = {b.name: i for i, b in enumerate(armature_obj.data.bones)}
    num_bones = len(bone_names)

    vg_idx_to_bone = {
        vg.index: bone_names[vg.name]
        for vg in mesh_obj.vertex_groups if vg.name in bone_names
    }

    total_cols = max(num_bones, max_influences)
    weight_matrix = np.zeros((num_verts, total_cols), dtype=np.float32)

    row_idx = []
    col_idx = []
    weights_flat = []

    vg_map = vg_idx_to_bone
    for v in mesh.vertices:
        vi = v.index
        for g in v.groups:
            gi = g.group
            if gi in vg_map:
                row_idx.append(vi)
                col_idx.append(vg_map[gi])
                weights_flat.append(g.weight)

    weight_matrix[row_idx, col_idx] = weights_flat

    top_4_idx = np.argpartition(weight_matrix, -max_influences, axis=1)[:, -max_influences:]

    top_4_weights = np.take_along_axis(weight_matrix, top_4_idx, axis=1)
    sort_order = np.argsort(-top_4_weights, axis=1)

    indices = np.take_along_axis(top_4_idx, sort_order, axis=1)
    weights = np.take_along_axis(top_4_weights, sort_order, axis=1)

    weight_sums = weights.sum(axis=1, keepdims=True)
    weight_sums[weight_sums == 0.0] = 1.0
    weights /= weight_sums

    return indices, weights


def iter_objects_parent_first():
    def traverse(obj):
        yield obj
        for child in obj.children:
            yield from traverse(child)

    # Start with objects that have no parent
    roots = [obj for obj in bpy.data.objects if obj.parent is None]

    for root in roots:
        yield from traverse(root)

# MARK: Append buf

class AppendBuffer:
    def __init__(self, dtype: np.dtype):
        self.buffers = []
        self.len = 0
        self.dtype = np.dtype(dtype)
        self.write_offset = 0

    def append(self, buf: np.array) -> int:
        start_offset = self.len
        if buf.dtype != self.dtype:
            raise TypeError(f"Expected {self.dtype.name}, got {buf.dtype.name}")
        self.buffers.append(buf)
        self.len += len(buf)
        return start_offset

    def write(self, fh, offset: int) -> int:
        self.write_offset = offset
        total_bytes = 0
        for buf in self.buffers:
            b = buf.tobytes()
            fh.write(b)
            total_bytes += len(b)
        return total_bytes


# MARK: Prof

_prof_data = {
    "time": time.perf_counter(),
    "table": {},
}

def prof(name: str):
    now = time.perf_counter()
    dur = now - _prof_data["time"]
    _prof_data["time"] = now
    total, num = _prof_data["table"].get(name, (0.0, 0))
    _prof_data["table"][name] = (total + dur, num + 1)

def prof_print():
    print("Profiler timings:")
    data = list(_prof_data["table"].items())

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


def get_interned_str(m: dict, buf: AppendBuffer, s):
    if s == None:
        return np.array([0, 0], dtype=np.uint32)
    if s in m:
        return m[s]
    arr = np.frombuffer(s.encode("utf-8"), dtype=np.uint8)
    start_offs = buf.len
    buf.append(arr)
    entry = np.array((start_offs, len(arr)), dtype=np.uint32)
    m[s] = entry
    return entry

# MARK: Export

def export_rscn(context, out_name):
    if not bpy.data.filepath:
        raise Exception("Blend file is not saved")

    depsgraph = context.evaluated_depsgraph_get()

    str_map = {}
    skeleton_map = {}
    node_map = {}

    str_buf  = AppendBuffer(np.uint8)
    node_buf = AppendBuffer(node_dtype)
    mesh_buf = AppendBuffer(mesh_dtype)
    skin_buf = AppendBuffer(skin_dtype)
    skeleton_buf = AppendBuffer(skeleton_dtype)
    bone_buf = AppendBuffer(bone_dtype)
    anim_buf = AppendBuffer(anim_dtype)
    anim_curve_buf = AppendBuffer(anim_curve_dtype)
    image_buf = AppendBuffer(image_dtype)
    spline_buf = AppendBuffer(spline_dtype)

    mesh_vertex_buf = AppendBuffer(mesh_vert_dtype)
    skin_vertex_buf = AppendBuffer(skin_vert_dtype)
    index_buf = AppendBuffer(np.uint32)
    spline_vert_buf = AppendBuffer(spline_vert_dtype)
    anim_float3_frame_buf = AppendBuffer(anim_float3_frame_dtype)
    anim_float4_frame_buf = AppendBuffer(anim_float4_frame_dtype)

    prof("start")

    # MARK: Materials
    for mat in bpy.data.materials:
        if mat.is_grease_pencil:
            continue

        if mat.node_tree is None:
            continue

        mat_name_range = get_interned_str(str_map, str_buf, norm_name(mat.name))

        for node in mat.node_tree.nodes:
            if node.type != 'TEX_IMAGE' or not node.image:
                continue

            path_range = get_interned_str(str_map, str_buf, norm_name(Path(node.image.filepath).name))

            entry = np.zeros(1, dtype=image_dtype)
            entry[0]['path_range'] = path_range
            entry[0]['mat_name_range'] = mat_name_range
            image_buf.append(entry)

    prof("Materials")

    # MARK: Skeletons
    for obj in bpy.data.objects:
        if obj.type != 'ARMATURE':
            continue

        bones = []

        for bone in obj.pose.bones:
            rot_mat = conv_mat @ bone.matrix.to_3x3() @ conv_mat_inv
            rot_quat = rot_mat.to_quaternion()
            depth = 0
            curr_parent = bone.parent
            while curr_parent != None:
                depth += 1
                curr_parent = curr_parent.parent

            bone_name_range = get_interned_str(str_map, str_buf, norm_name(bone.name))

            bone_entry = np.zeros(1, dtype=bone_dtype)
            bone_entry[0]['name_range'] = bone_name_range
            bone_entry[0]['parent'] = 0 # later
            bone_entry[0]['pos'] = conv_mat @ bone.head
            bone_entry[0]['length'] = bone.bone.length
            bone_entry[0]['rot'] = [rot_quat.x, rot_quat.y, rot_quat.z, rot_quat.w]
            print(bone_entry)
            bones.append((depth, bone_entry, bone))

        bones = sorted(bones, key=lambda x: x[0])

        bone_start = bone_buf.len
        bone_offsets = {}
        for i, (_, _, bone) in enumerate(bones):
            bone_offsets[bone.name] = bone_start + i

        for depth, b, bone in bones:
            b[0]['parent'] = bone_offsets[bone.parent.name] if bone.parent else 0xffffffff

        for b in bones:
            bone_buf.append(b[1])

        name_range = get_interned_str(str_map, str_buf, norm_name(obj.name))

        entry = np.zeros(1, dtype=skeleton_dtype)
        entry[0]['name_range'] = name_range
        entry[0]['bone_range'] = np.array((bone_start, len(bones)), dtype=np.uint32)
        skeleton_map[obj.name] = skeleton_buf.append(entry)

    prof("Skeletons")

    # MARK: Anims
    for action in bpy.data.actions:
        print(f"ACTION {action.name}")
        total_curves = 0
        for layer in getattr(action, "layers", []):
            for strip in layer.strips:
                for channel in strip.channelbags:
                    for fcurve in channel.fcurves:
                        total_curves += 1

        entry = [f"\t{norm_name(action.name)} {total_curves} {{\n"]

        bone_curves = {}

        for layer in getattr(action, "layers", []):
            for strip in layer.strips:
                for channel in strip.channelbags:
                    for fcurve in channel.fcurves:
                        match = re.match(r'pose\.bones\["([^"]+)"\]\.(location|rotation_euler|rotation_quaternion|scale)',
                                        fcurve.data_path)
                        if not match:
                            continue

                        bone_name = match.group(1)
                        transform_type = match.group(2)

                        assert(transform_type != "rotation_euler")

                        bone_curve = bone_curves.get(bone_name, {'rot': {}, 'pos': {}, 'scale': {}})

                        if transform_type == "location":
                            for point in fcurve.keyframe_points:
                                val = bone_curve['pos'].get(int(point.co[0]), np.array([0, 0, 0], dtype=np.float32))
                                val[fcurve.array_index] = point.co[1]
                                bone_curve['pos'][int(point.co[0])] = val

                        elif transform_type == "rotation_quaternion":
                            for point in fcurve.keyframe_points:
                                blender_index = fcurve.array_index # wxyz
                                index = 3 if blender_index==0 else blender_index-1 # xyzw
                                val = bone_curve['rot'].get(int(point.co[0]), np.array([0, 0, 0, 0], dtype=np.float32))
                                val[index] = point.co[1]
                                bone_curve['rot'][int(point.co[0])] = val

                        elif transform_type == "scale":
                            for point in fcurve.keyframe_points:
                                val = bone_curve['scale'].get(int(point.co[0]), np.array([1, 1, 1], dtype=np.float32))
                                val[fcurve.array_index] = point.co[1]
                                bone_curve['scale'][int(point.co[0])] = val

                        bone_curves[bone_name] = bone_curve

        anim_curve_offset = anim_curve_buf.len
        for name, curves in bone_curves.items():
            bone_name_range = get_interned_str(str_map, str_buf, norm_name(name))

            for frame, value in curves['pos'].items():
                curves['pos'][frame] = conv_mat_np @ value
            for frame, value in curves['rot'].items():
                quat = mathutils.Quaternion((value[3], value[0], value[1], value[2]))
                rot_mat = conv_mat @ quat.to_matrix() @ conv_mat_inv
                quat = rot_mat.to_quaternion()
                curves['rot'][frame] = np.array((quat.x, quat.y, quat.z, quat.w), dtype=np.float32)
            for frame, value in curves['scale'].items():
                curves['scale'][frame] = conv_mat_np @ value

            pos_data = np.array(sorted(curves['pos'].items()), dtype=anim_float3_frame_dtype)
            rot_data = np.array(sorted(curves['rot'].items()), dtype=anim_float4_frame_dtype)
            scale_data = np.array(sorted(curves['scale'].items()), dtype=anim_float3_frame_dtype)
            pos_offset = anim_float3_frame_buf.append(pos_data)
            rot_offset = anim_float4_frame_buf.append(rot_data)
            scale_offset = anim_float3_frame_buf.append(scale_data)

            curve_entry = np.zeros(1, dtype=anim_curve_dtype)
            curve_entry[0]['name_range'] = bone_name_range
            curve_entry[0]['pos_range'] = np.array([pos_offset, len(pos_data)], dtype=np.uint32)
            curve_entry[0]['rot_range'] = np.array([rot_offset, len(rot_data)], dtype=np.uint32)
            curve_entry[0]['scale_range'] = np.array([scale_offset, len(scale_data)], dtype=np.uint32)
            anim_curve_buf.append(curve_entry)

        name_range = get_interned_str(str_map, str_buf, norm_name(action.name))

        entry = np.zeros(1, dtype=anim_dtype)
        entry[0]['name_range'] = name_range
        entry[0]['curve_range'] = np.array([anim_curve_offset, len(bone_curves)], dtype=np.uint32)
        anim_buf.append(entry)

    prof("Anims")

    # MARK: Meshes+Skins
    for obj in bpy.data.objects:
        if obj.type != 'MESH':
            continue

        eval_obj = obj.evaluated_get(depsgraph)
        mesh = eval_obj.to_mesh()

        armature = obj.find_armature()

        name_range = get_interned_str(str_map, str_buf, norm_name(obj.name))

        if armature == None:
            loop_verts, tri_vert_indices = get_mesh_loop_verts(mesh, dtype=mesh_vert_dtype)

            verts, loop_to_unique = np.unique(loop_verts, return_inverse=True)
            indices = loop_to_unique.astype(np.uint32).reshape(-1, 3)[:, [0, 2, 1]].ravel()

            verts_offset = mesh_vertex_buf.append(verts)
            indices_offset = index_buf.append(indices)

            entry = np.zeros(1, dtype=mesh_dtype)
            entry[0]['name_range'] = name_range
            entry[0]['vert_range'] = np.array([verts_offset, len(verts)], dtype=np.uint32)
            entry[0]['index_range'] = np.array([indices_offset, len(indices)], dtype=np.uint32)
            mesh_buf.append(entry)

        else:
            loop_verts, tri_vert_indices = get_mesh_loop_verts(mesh, dtype=skin_vert_dtype)
            vert_bones, vert_weights = get_mesh_skinning_data(obj, armature)

            vert_weights = np.round(vert_weights * 255.0).astype(np.uint8)

            loop_verts['bones'] = vert_bones[tri_vert_indices.ravel()]
            loop_verts['weights'] = vert_weights[tri_vert_indices.ravel()]

            verts, loop_to_unique = np.unique(loop_verts, return_inverse=True)
            indices = loop_to_unique.astype(np.uint32).reshape(-1, 3)[:, [0, 2, 1]].ravel()

            verts_offset = skin_vertex_buf.append(verts)
            indices_offset = index_buf.append(indices)

            skeleton_offset = skeleton_map[armature.name]

            entry = np.zeros(1, dtype=skin_dtype)
            entry[0]['name_range'] = name_range
            entry[0]['skeleton'] = skeleton_offset
            entry[0]['vert_range'] = np.array([verts_offset, len(verts)], dtype=np.uint32)
            entry[0]['index_range'] = np.array([indices_offset, len(indices)], dtype=np.uint32)
            skin_buf.append(entry)

        eval_obj.to_mesh_clear()

    prof("Mesh+Skin")

    # MARK: Splines
    for obj in bpy.data.objects:
        if obj.type != 'CURVE':
            continue
        curve = obj.to_curve(depsgraph, apply_modifiers=True)

        name_range = get_interned_str(str_map, str_buf, norm_name(obj.name))

        if len(curve.splines) > 1:
            print("Warning: multi-segment splines only save the first segment")

        for i, spl in enumerate(curve.splines):
            if spl.type == 'BEZIER':
                continue

            pos = np.empty((len(spl.points), 4), dtype=np.float32)
            radius = np.empty(len(spl.points), dtype=np.float32)
            tilt = np.empty(len(spl.points), dtype=np.float32)

            spl.points.foreach_get("co", pos.ravel())
            spl.points.foreach_get("radius", radius)
            spl.points.foreach_get("tilt", tilt)

            points = np.empty(len(spl.points), dtype=spline_vert_dtype)
            points['pos'] = pos[:, :3] @ conv_mat_np.T
            points['rad'] = radius
            points['tilt'] = tilt

            verts_offset = spline_vert_buf.append(points)

            entry = np.zeros(1, dtype=spline_dtype)
            entry[0]['name_range'] = name_range
            entry[0]['vert_range'] = np.array([verts_offset, len(points)], dtype=np.uint32)
            spline_buf.append(entry)

            break

        obj.to_curve_clear()

    prof("Curves")

    # MARK: Nodes
    for obj in iter_objects_parent_first():
        kind = NODE_KIND_NONE
        if obj.type == 'EMPTY':
            kind = NODE_KIND_NONE
        elif obj.type == 'MESH':
            kind = NODE_KIND_MESH
        elif obj.type == 'CURVE':
            kind = NODE_KIND_SPLINE
        else:
            continue

        name_range = get_interned_str(str_map, str_buf, norm_name(obj.name))
        mat_name = get_interned_str(str_map, str_buf, norm_name(obj.active_material.name) if obj.active_material else None)

        parent = 0xffffffff
        parent_obj = obj.parent
        while parent_obj:
            if parent_obj.name in node_map:
                parent = node_map[parent_obj.name]
                break
            else:
                parent_obj = parent_obj.parent

        pos = obj.matrix_local.to_translation()
        pos = conv_mat @ pos
        scale = conv_mat @ obj.matrix_local.to_scale()
        mat = obj.matrix_local.to_3x3()
        mat = conv_mat @ mat @ conv_mat_inv
        rot = mat.to_quaternion()

        print(obj.name, pos.xyz, obj.location.xyz)

        entry = np.zeros(1, dtype=node_dtype)
        entry[0]['name_range'] = name_range
        entry[0]['parent'] = parent
        entry[0]['material_name_range'] = mat_name
        entry[0]['kind'] = kind
        entry[0]['pos'] = pos
        entry[0]['rot'] = rot
        entry[0]['scale'] = scale
        node_map[obj.name] = node_buf.append(entry)


    prof("Nodes")

    bin_offset = 0
    with open(out_name, "wb") as fh:
        header = np.zeros(1, dtype=header_dtype)

        header_bin = header.tobytes()
        fh.write(header_bin)
        bin_offset += len(header_bin)

        bufs = [
            ("string_range",            str_buf),
            ("node_range",              node_buf),
            ("image_range",             image_buf),
            ("mesh_range",              mesh_buf),
            ("skin_range",              skin_buf),
            ("spline_range",            spline_buf),
            ("skeleton_range",          skeleton_buf),
            ("bone_range",              bone_buf),
            ("anim_range",              anim_buf),
            ("mesh_vert_range",         mesh_vertex_buf),
            ("skin_vert_range",         skin_vertex_buf),
            ("spline_vert_range",       spline_vert_buf),
            ("index_range",             index_buf),
            ("anim_curve_range",        anim_curve_buf),
            ("anim_float3_frame_range", anim_float3_frame_buf),
            ("anim_float4_frame_range", anim_float4_frame_buf),
        ]

        header[0]['magic'] = int.from_bytes(BIN_MAGIC, byteorder='little')
        header[0]['version'] = VERSION

        for name, buf in bufs:
            written_bytes = buf.write(fh, bin_offset)
            header[0][name] = np.array((bin_offset, written_bytes), np.uint64)
            bin_offset += written_bytes

        fh.seek(0)

        header_bin = header.tobytes()
        fh.write(header_bin)

        prof("Write")



# MARK: Main

def main():
    start = time.perf_counter()

    out_name = os.path.splitext(bpy.data.filepath)[0] + ".rscn"

    print(f"\nExporting '{out_name}' and '{out_name}...")

    export_rscn(bpy.context, out_name)

    end = time.perf_counter()

    prof_print()

    print(f"Exporting finished in {(end - start) * 1e3:.3f} ms")


if __name__ == "__main__":
    main()
