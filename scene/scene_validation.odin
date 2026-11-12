#+vet style unused explicit-allocators shadowing
package ravn_scene

import "core:log"

validate :: proc(scene: Scene) -> bool {
	for img, i in scene.image_data {
		if !range_is_valid(scene.string_data, img.path_range) { log.errorf("Image %d: path_range invalid", i); return false }
		if !range_is_valid(scene.string_data, img.mat_name_range) { log.errorf("Image %d: mat_name_range invalid", i); return false }
	}

	for node, i in scene.node_data {
		if !range_is_valid(scene.string_data, node.name_range) { log.errorf("Node %d: name_range invalid", i); return false }
		if !range_is_valid(scene.string_data, node.material_name_range) { log.errorf("Node %d: material_name_range invalid", i); return false }

		if node.parent != INVALID_PARENT {
			if int(node.parent) >= len(scene.node_data) { log.errorf("Node %d: parent out of bounds", i); return false }

			curr := node.parent
			depth := 0
			for curr != INVALID_PARENT && depth <= len(scene.node_data) {
				if int(curr) >= len(scene.node_data) {
					log.errorf("Node %d: parent chain hits out of bounds at %d", i, curr)
					return false
				}
				curr = scene.node_data[curr].parent
				depth += 1
			}
			if depth > len(scene.node_data) { log.errorf("Node %d: circular parent reference detected", i); return false }
		}
	}

	for mesh, i in scene.mesh_data {
		if !range_is_valid(scene.string_data, mesh.name_range) { log.errorf("Mesh %d: name_range invalid", i); return false }
		if !range_is_valid(scene.mesh_vert_data, mesh.vert_range) { log.errorf("Mesh %d: vert_range invalid", i); return false }
		if !range_is_valid(scene.index_data, mesh.index_range) { log.errorf("Mesh %d: index_range invalid", i); return false }
		indices := get_range_slice(scene.index_data, mesh.index_range)
		for idx in indices {
			if idx >= mesh.vert_range[1] { log.errorf("Mesh %d: index %d out of bounds for vert count %d", i, idx, mesh.vert_range[1]); return false }
		}
	}

	for skel, i in scene.skeleton_data {
		if !range_is_valid(scene.string_data, skel.name_range) { log.errorf("Skeleton %d: name_range invalid", i); return false }
		if !range_is_valid(scene.bone_data, skel.bone_range) { log.errorf("Skeleton %d: bone_range invalid", i); return false }
		for b_idx in 0..<skel.bone_range[1] {
			global_b_idx := skel.bone_range[0] + b_idx
			if scene.bone_data[global_b_idx].skeleton != u32(i) {
				log.errorf("Skeleton %d: bone %d points to wrong skeleton %d", i, global_b_idx, scene.bone_data[global_b_idx].skeleton)
				return false
			}
		}
	}

	for bone, i in scene.bone_data {
		if !range_is_valid(scene.string_data, bone.name_range) { log.errorf("Bone %d: name_range invalid", i); return false }
		if int(bone.skeleton) >= len(scene.skeleton_data) { log.errorf("Bone %d: skeleton %d out of bounds", i, bone.skeleton); return false }

		skel := scene.skeleton_data[bone.skeleton]
		if !is_in_range(skel.bone_range, u32(i)) {
			log.errorf("Bone %d: index not within its skeleton's bone_range [%d, %d)", i, skel.bone_range.x, skel.bone_range.x + skel.bone_range.y)
			return false
		}

		if bone.parent != INVALID_PARENT {
			if int(bone.parent) >= len(scene.bone_data) { log.errorf("Bone %d: parent %d out of bounds", i, bone.parent); return false }
			if bone.parent >= u32(i) { log.errorf("Bone %d: parent %d not ordered by depth (must be < %d)", i, bone.parent, i); return false }
			if !is_in_range(skel.bone_range, bone.parent) {
				log.errorf("Bone %d: parent %d outside of skeleton %d's bone_range [%d, %d)", i, bone.parent, bone.skeleton, skel.bone_range.x, skel.bone_range.x + skel.bone_range.y)
				return false
			}
		}
	}

	for skin, i in scene.skin_data {
		if !range_is_valid(scene.string_data, skin.name_range) { log.errorf("Skin %d: name_range invalid", i); return false }
		if int(skin.skeleton) >= len(scene.skeleton_data) { log.errorf("Skin %d: skeleton %d out of bounds", i, skin.skeleton); return false }
		if !range_is_valid(scene.skin_vert_data, skin.vert_range) { log.errorf("Skin %d: vert_range invalid", i); return false }
		if !range_is_valid(scene.index_data, skin.index_range) { log.errorf("Skin %d: index_range invalid", i); return false }

		indices := get_range_slice(scene.index_data, skin.index_range)
		for idx in indices {
			if idx >= skin.vert_range[1] { log.errorf("Skin %d: index %d out of bounds", i, idx); return false }
		}

		skel := scene.skeleton_data[skin.skeleton]
		verts := get_range_slice(scene.skin_vert_data, skin.vert_range)
		for v, v_idx in verts {
			for b_idx in 0..<4 {
				if u32(v.bones[b_idx]) >= skel.bone_range[1] {
					log.errorf("Skin %d: vert %d references invalid local bone %d", i, v_idx, v.bones[b_idx]); return false
				}
			}
		}
	}

	for spline, i in scene.spline_data {
		if !range_is_valid(scene.string_data, spline.name_range) { log.errorf("Spline %d: name_range invalid", i); return false }
		if !range_is_valid(scene.spline_vert_data, spline.vert_range) { log.errorf("Spline %d: vert_range invalid", i); return false }
	}

	seen_bones := make([]bool, len(scene.bone_data), context.temp_allocator)
	defer delete(seen_bones, context.temp_allocator)

	for anim, i in scene.anim_data {
		if !range_is_valid(scene.string_data, anim.name_range) { log.errorf("Anim %d: name_range invalid", i); return false }
		if int(anim.skeleton) >= len(scene.skeleton_data) { log.errorf("Anim %d: skeleton %d out of bounds", i, anim.skeleton); return false }
		if !range_is_valid(scene.anim_curve_data, anim.curve_range) { log.errorf("Anim %d: curve_range invalid", i); return false }

		for b in 0..<len(seen_bones) { seen_bones[b] = false }

		skel := scene.skeleton_data[anim.skeleton]

		curves := get_range_slice(scene.anim_curve_data, anim.curve_range)
		for c, c_idx in curves {
			if int(c.bone) >= len(scene.bone_data) { log.errorf("Anim %d: curve %d bone %d out of bounds", i, c_idx, c.bone); return false }

			if is_in_range(skel.bone_range, c.bone) {
				log.errorf("Anim %d: curve %d bone %d is outside skeleton %d's bone_range [%d, %d)", i, c_idx, c.bone, anim.skeleton, skel.bone_range.x, skel.bone_range.x + skel.bone_range.y)
				return false
			}

			if seen_bones[c.bone] { log.errorf("Anim %d: duplicate curve for bone %d", i, c.bone); return false }
			seen_bones[c.bone] = true

			if !range_is_valid(scene.anim_float3_frame_data, c.pos_range) { log.errorf("Anim %d: curve %d pos_range invalid", i, c_idx); return false }
			if !range_is_valid(scene.anim_float4_frame_data, c.rot_range) { log.errorf("Anim %d: curve %d rot_range invalid", i, c_idx); return false }
			if !range_is_valid(scene.anim_float3_frame_data, c.scale_range) { log.errorf("Anim %d: curve %d scale_range invalid", i, c_idx); return false }

			pos_frames := get_range_slice(scene.anim_float3_frame_data, c.pos_range)
			for f := 1; f < len(pos_frames); f += 1 {
				if pos_frames[f].time <= pos_frames[f-1].time { log.errorf("Anim %d: curve %d pos frames not sorted at %d", i, c_idx, f); return false }
			}

			rot_frames := get_range_slice(scene.anim_float4_frame_data, c.rot_range)
			for f := 1; f < len(rot_frames); f += 1 {
				if rot_frames[f].time <= rot_frames[f-1].time { log.errorf("Anim %d: curve %d rot frames not sorted at %d", i, c_idx, f); return false }
			}

			scale_frames := get_range_slice(scene.anim_float3_frame_data, c.scale_range)
			for f := 1; f < len(scale_frames); f += 1 {
				if scale_frames[f].time <= scale_frames[f-1].time { log.errorf("Anim %d: curve %d scale frames not sorted at %d", i, c_idx, f); return false }
			}
		}
	}

	return true
}