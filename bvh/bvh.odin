// Binary Volume Hierarchy
// This package implements multiple builders for AABB hierarchy acceleration structures.
// Based on:
// - https://jacco.ompf2.com/2022/04/13/how-to-build-a-bvh-part-1-basics/
package raven_bvh

MAX_BINS :: 32

BVH :: struct {
    nodes:          []Node,
    indices:        []u16, // Indexes prims
    prims:          [][2][3]f32,
    nodes_used:     i32,
    max_leaf_prims: i32,
}

Node :: struct #align(32) {
    min:    [3]f32,
    first:  i32, // Left child of first prim
    max:    [3]f32,
    len:    i32, // Num prims if leaf else 0
}

Node_SIMD4 :: struct #align(32) {
    min:    #simd[4]f32,
    max:    #simd[4]f32,
}


@(require_results)
max_nodes_for_prims :: proc "contextless" (#any_int num_prims: int) -> int {
    return max(1, 2 * num_prims - 1)
}

init :: proc(
    bvh:                    ^BVH,
    nodes:                  []Node,
    indices:                []u16,
    prims:                  [][2][3]f32 = nil,
    #any_int max_leaf_prims := 3,
) {
    assert(max_leaf_prims > 0)
    assert(len(nodes) < int(max(u16)))

    bvh^ = {
        nodes = nodes,
        indices = indices,
        prims = prims,
        nodes_used = 0,
        max_leaf_prims = i32(max_leaf_prims),
    }

    if prims != nil {
        init_prims(bvh, prims)
    }
}

// Re-initialize the primitive buffer only and clears the existing nodes.
init_prims :: proc(bvh: ^BVH, prims: [][2][3]f32) {
    assert(len(prims) < int(max(u16)))
    assert(len(bvh.indices) >= len(prims))

    bvh.prims = prims

    for i in 0..<len(prims) {
        bvh.indices[i] = u16(i)
    }

    // 1 for the root, another unused one to fill the first cache line
    bvh.nodes_used = 2
    bvh.nodes[0] = {
        first = 0,
        len = i32(len(prims))
    }
}


///////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Build
//

// Not actual BVH, contains a single huge node with all prims.
build_none :: proc(bvh: ^BVH) {
    _update_node_bounds(bvh, &bvh.nodes[0])
}

// Very fast but the result isn't a high-quality tree.
build_mid :: proc(bvh: ^BVH, curr_index := 0) #no_bounds_check {
    curr_index := curr_index

    for {
        node := &bvh.nodes[curr_index]
        mid_min, mid_max := _update_node_bounds_with_mid_bounds(bvh, node)

        if int(node.len) <= int(bvh.max_leaf_prims) {
            return
        }

        extent := mid_max - mid_min
        axis := 0
        if extent.y > extent.x do axis = 1
        if extent.z > extent[axis] do axis = 2
        split_pos := mid_min[axis] + extent[axis] * 0.5

        if !_split_leaf(bvh, node, axis = axis, split_pos = split_pos) {
            return
        }

        if bvh.nodes[int(node.first) + 0].len < bvh.nodes[int(node.first) + 1].len {
            build_mid(bvh, int(node.first) + 0)
            curr_index = int(node.first) + 1
        } else {
            build_mid(bvh, int(node.first) + 1)
            curr_index = int(node.first) + 0
        }
    }
}

// Similar to mid, spends more time selecting better split.
build_mean_sah :: proc(bvh: ^BVH, curr_index := 0) #no_bounds_check {
    curr_index := curr_index

    for {
        node := &bvh.nodes[curr_index]
        mean := _update_node_bounds_with_mean(bvh, node)

        if int(node.len) <= int(bvh.max_leaf_prims) {
            return
        }

        left_mins:  [3][3]f32 = max(f32)
        left_maxs:  [3][3]f32 = min(f32)
        right_mins: [3][3]f32 = max(f32)
        right_maxs: [3][3]f32 = min(f32)
        left_nums:  [3]i32
        right_nums: [3]i32

        for i in 0..<int(node.len) {
            prim := bvh.prims[bvh.indices[int(node.first) + i]]
            center := (prim[0] + prim[1]) * 0.5

            for axis in 0..<3 {
                if center[axis] < mean[axis] {
                    left_nums[axis] += 1
                    left_mins[axis] = vec_min(left_mins[axis], prim[0])
                    left_maxs[axis] = vec_max(left_maxs[axis], prim[1])
                } else {
                    right_nums[axis] += 1
                    right_mins[axis] = vec_min(right_mins[axis], prim[0])
                    right_maxs[axis] = vec_max(right_maxs[axis], prim[1])
                }
            }
        }

        best_cost := max(f32)
        best_axis := 0
        best_split_pos: f32

        for axis in 0..<3 {
            cost :=
                f32(left_nums[axis]) * surface_area(left_mins[axis], left_maxs[axis]) +
                f32(right_nums[axis]) * surface_area(right_mins[axis], right_maxs[axis])
            if cost <= 0 {
                continue
            }

            if cost < best_cost {
                best_cost = cost
                best_split_pos = mean[axis]
                best_axis = axis
            }
        }

        curr_cost := f32(node.len) * surface_area(node.min, node.max)
        if best_cost >= curr_cost {
            return
        }

        if !_split_leaf(bvh, node, axis = best_axis, split_pos = best_split_pos) {
            return
        }

        if bvh.nodes[int(node.first) + 0].len < bvh.nodes[int(node.first) + 1].len {
            build_mean_sah(bvh, int(node.first) + 0)
            curr_index = int(node.first) + 1
        } else {
            build_mean_sah(bvh, int(node.first) + 1)
            curr_index = int(node.first) + 0
        }
    }
}

// Very slow, each node is O(n_prims^2).
// This is mostly a reference impl, it's impractical for larger meshes.
build_sah :: proc(bvh: ^BVH, curr_index := 0) #no_bounds_check {
    curr_index := curr_index

    for {
        node := &bvh.nodes[curr_index]
        _update_node_bounds(bvh, node)

        if int(node.len) <= int(bvh.max_leaf_prims) {
            return
        }

        best_cost := max(f32)
        best_axis := 0
        best_split_pos: f32

        for p0_offs in 0..<int(node.len) {
            p0 := bvh.prims[bvh.indices[int(node.first) + p0_offs]]

            p0_center := (p0[0] + p0[1]) * 0.5

            costs: [3]f32

            left_mins: [3][3]f32 = max(f32)
            left_maxs: [3][3]f32 = min(f32)
            right_mins: [3][3]f32 = max(f32)
            right_maxs: [3][3]f32 = min(f32)
            left_nums: [3]i32
            right_nums: [3]i32

            for p1_offs in 0..<int(node.len) {
                p1 := bvh.prims[bvh.indices[int(node.first) + p1_offs]]

                p1_center := (p1[0] + p1[1]) * 0.5

                for axis in 0..<3 {
                    if p1_center[axis] < p0_center[axis] {
                        left_nums[axis] += 1
                        left_mins[axis] = vec_min(left_mins[axis], p1[0])
                        left_maxs[axis] = vec_max(left_maxs[axis], p1[1])
                    } else {
                        right_nums[axis] += 1
                        right_mins[axis] = vec_min(right_mins[axis], p1[0])
                        right_maxs[axis] = vec_max(right_maxs[axis], p1[1])
                    }
                }
            }

            for axis in 0..<3 {
                cost :=
                    f32(left_nums[axis]) * surface_area(left_mins[axis], left_maxs[axis]) +
                    f32(right_nums[axis]) * surface_area(right_mins[axis], right_maxs[axis])
                if cost <= 0 {
                    continue
                }

                if cost < best_cost {
                    best_cost = cost
                    best_split_pos = p0_center[axis]
                    best_axis = axis
                }
            }
        }

        curr_cost := f32(node.len) * surface_area(node.min, node.max)
        if best_cost >= curr_cost {
            return
        }

        if !_split_leaf(bvh, node, axis = best_axis, split_pos = best_split_pos) {
            return
        }

        if bvh.nodes[int(node.first) + 0].len < bvh.nodes[int(node.first) + 1].len {
            build_sah(bvh, int(node.first) + 0)
            curr_index = int(node.first) + 1
        } else {
            build_sah(bvh, int(node.first) + 1)
            curr_index = int(node.first) + 0
        }
    }
}

build_binned :: proc(bvh: ^BVH, num_bins := 8, curr_index := 0) #no_bounds_check {
    curr_index := curr_index
    assert(num_bins <= MAX_BINS)

    for {
        node := &bvh.nodes[curr_index]
        mid_min, mid_max := _update_node_bounds_with_mid_bounds(bvh, node)

        if int(node.len) <= int(bvh.max_leaf_prims) {
            return
        }

        bins_min: [MAX_BINS][3][3]f32 = max(f32)
        bins_max: [MAX_BINS][3][3]f32 = min(f32)
        bins_num: [MAX_BINS][3]i32 = 0

        bin_scale := f32(num_bins) / (mid_max - mid_min)

        for i in 0..<int(node.len) {
            prim := bvh.prims[bvh.indices[int(node.first) + i]]
            center := (prim[0] + prim[1]) * 0.5
            for axis in 0..<3 {
                bin := min(i32(num_bins) - 1, i32((center[axis] - mid_min[axis]) * bin_scale[axis]))
                bins_num[bin][axis] += 1
                bins_min[bin][axis] = vec_min(bins_min[bin][axis], prim[0])
                bins_max[bin][axis] = vec_max(bins_max[bin][axis], prim[1])
            }
        }

        left_sum:   [3]i32
        right_sum:  [3]i32

        left_min:   [3][3]f32 = max(f32)
        left_max:   [3][3]f32 = min(f32)
        right_min:  [3][3]f32 = max(f32)
        right_max:  [3][3]f32 = min(f32)

        left_area:  [MAX_BINS - 1][3]f32
        left_num:   [MAX_BINS - 1][3]i32
        right_area: [MAX_BINS - 1][3]f32
        right_num:  [MAX_BINS - 1][3]i32

        for i in 0..<num_bins - 1 {
            for axis in 0..<3 {
                left_sum[axis] += bins_num[i][axis]
                left_num[i][axis] = left_sum[axis]
                left_min[axis] = vec_min(left_min[axis], bins_min[i][axis])
                left_max[axis] = vec_max(left_max[axis], bins_max[i][axis])
                left_area[i][axis] = surface_area(left_min[axis], left_max[axis])

                right_sum[axis] += bins_num[num_bins - 1 - i][axis]
                right_num[num_bins - 2 - i][axis] = right_sum[axis]
                right_min[axis] = vec_min(right_min[axis], bins_min[num_bins - 1 - i][axis])
                right_max[axis] = vec_max(right_max[axis], bins_max[num_bins - 1 - i][axis])
                right_area[num_bins - 2 - i][axis] = surface_area(right_min[axis], right_max[axis])
            }
        }

        best_cost := max(f32)
        best_axis := 0
        best_split_pos: f32

        bin_size := (mid_max - mid_min) / f32(num_bins)
        for i in 0..<num_bins - 1 {
            for axis in 0..<3 {
                cost :=
                    f32(left_num[i][axis]) * left_area[i][axis] +
                    f32(right_num[i][axis]) * right_area[i][axis]
                if cost < best_cost {
                    best_cost = cost
                    best_axis = axis
                    best_split_pos = mid_min[axis] + bin_size[axis] * f32(i + 1)
                }
            }
        }

        curr_cost := f32(node.len) * surface_area(node.min, node.max)
        if best_cost >= curr_cost {
            return
        }

        if !_split_leaf(bvh, node, axis = best_axis, split_pos = best_split_pos) {
            return
        }

        if bvh.nodes[int(node.first) + 0].len < bvh.nodes[int(node.first) + 1].len {
            build_binned(bvh, num_bins, int(node.first) + 0)
            curr_index = int(node.first) + 1
        } else {
            build_binned(bvh, num_bins, int(node.first) + 1)
            curr_index = int(node.first) + 0
        }
    }
}



///////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Iter
//

/* Example usage:

it := bvh.iter(&my_bvh)

for {
    if it.len == 0 {
        // intersect leaf ...
        bvh.iter_pop(&it) or_break
    } else {
        t0, t1 := itersect_two_children(it.node)
        bvh.iter_next(&) or_break
    }
}

*/
Iter :: struct {
    bvh:        ^BVH,
    using node: ^Node,
    stack:      [64 * 2]u16,
    stack_len:  i32,
}

iter :: proc(bvh: ^BVH) -> Iter {
    return {
        bvh = bvh,
        node = bvh.nodes_used > 0 ? &bvh.nodes[0] : nil,
    }
}

iter_pop :: proc(iter: ^Iter) -> bool {
    if iter.stack_len == 0 {
        return false
    }
    iter.stack_len -= 1
    iter.node = &iter.bvh.nodes[iter.stack[iter.stack_len]]
    return true
}

// t0, t1: intersection times for the children of the current node. Use max(f32) on miss.
iter_next :: proc(iter: ^Iter, t0, t1: f32) -> bool {
    t0 := t0
    t1 := t1
    child0 := iter.first + 0
    child1 := iter.first + 1

    assert(child0 < iter.bvh.nodes_used)

    if t0 > t1 {
        t0, t1 = t1, t0
        child0, child1 = child1, child0
    }

    if t0 == max(f32) {
        iter_pop(iter) or_return
    } else {
        if t1 != max(f32) {
            iter.stack[iter.stack_len] = u16(child1)
            iter.stack_len += 1
        }
        iter.node = &iter.bvh.nodes[child0]
    }

    return true
}

iter_unsorted_next :: proc(iter: ^Iter, hit0, hit1: bool) -> bool {
    child0 := iter.first + 0
    child1 := iter.first + 1

    assert(child0 < iter.bvh.nodes_used)

    if hit0 {
        if hit1 {
            iter.stack[iter.stack_len] = u16(child1)
            iter.stack_len += 1
            iter.node = &iter.bvh.nodes[child0]
        } else {
            iter.node = &iter.bvh.nodes[child0]
        }
    } else {
        if hit1 {
            iter.node = &iter.bvh.nodes[child1]
        } else {
            iter_pop(iter) or_return
        }
    }

    return true
}




///////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Utils
//

refit :: proc(bvh: ^BVH, index := 0) #no_bounds_check {
    node := &bvh.nodes[index]

    if node.len != 0 {
        node.min = max(f32)
        node.max = min(f32)
        for i in 0..<int(node.len) {
            prim := bvh.prims[bvh.indices[int(node.first) + i]]
            node.min = vec_min(node.min, prim[0])
            node.max = vec_max(node.max, prim[1])
        }
    } else {
        refit(bvh, int(node.first) + 0)
        refit(bvh, int(node.first) + 1)

        left := &bvh.nodes[node.first + 0]
        right := &bvh.nodes[node.first + 1]
        node.min = vec_min(left.min, right.min)
        node.max = vec_max(left.max, right.max)
    }
}

// Can be normalized by root surface area.
@(require_results)
calc_sah :: proc(bvh: BVH, index := 0) -> f32 {
    node := bvh.nodes[index]
    area := surface_area(node.min, node.max)

    if node.len == 0 { // Internal
        return  calc_sah(bvh, int(node.first) + 0) +
                calc_sah(bvh, int(node.first) + 1) +
                area
    } else { // Leaf
        return f32(node.len) * area
    }
}

@(require_results)
calc_height :: proc(bvh: BVH, index := 0) -> int {
    node := bvh.nodes[index]
    if node.len != 0 {
        return 0
    }

    return 1 + max(
        calc_height(bvh, int(node.first) + 0),
        calc_height(bvh, int(node.first) + 1),
    )
}

@(require_results)
_split_leaf :: proc(bvh: ^BVH, node: ^Node, axis: int, split_pos: f32) -> bool #no_bounds_check {
    // In-place partition
    i := int(node.first)
    j := i + int(node.len) - 1
    for i <= j {
        prim := bvh.prims[bvh.indices[i]]
        mid := (prim[0] + prim[1]) * 0.5
        if mid[axis] < split_pos {
            i += 1
        } else {
            bvh.indices[i], bvh.indices[j] = bvh.indices[j], bvh.indices[i]
            j -= 1
        }
    }

    // Abort if one of the sides is empty
    left_count := i - int(node.first)
    if left_count == 0 || left_count == int(node.len) {
        return false
    }

    // Create children
    first_child := bvh.nodes_used
    bvh.nodes_used += 2

    bvh.nodes[first_child + 0].first = node.first
    bvh.nodes[first_child + 0].len = i32(left_count)
    bvh.nodes[first_child + 1].first = i32(i)
    bvh.nodes[first_child + 1].len = i32(int(node.len) - left_count)

    node.first = i32(first_child)
    node.len = 0 // not a leaf anymore

    return true
}

_update_node_bounds :: proc(bvh: ^BVH, node: ^Node) #no_bounds_check {
    node.min = max(f32)
    node.max = min(f32)
    for i in 0..<int(node.len) {
        prim_index := bvh.indices[int(node.first) + i]
        prim := bvh.prims[prim_index]
        node.min = vec_min(node.min, prim[0])
        node.max = vec_max(node.max, prim[1])
    }
}

@(require_results)
_update_node_bounds_with_mid_bounds :: proc(bvh: ^BVH, node: ^Node) -> (mid_min, mid_max: [3]f32) #no_bounds_check {
    node.min = max(f32)
    node.max = min(f32)
    mid_min = max(f32)
    mid_max = min(f32)

    for i in 0..<int(node.len) {
        prim_index := bvh.indices[int(node.first) + i]
        prim := bvh.prims[prim_index]
        node.min = vec_min(node.min, prim[0])
        node.max = vec_max(node.max, prim[1])
        mid := (prim[0] + prim[1]) * 0.5
        mid_min = vec_min(mid_min, mid)
        mid_max = vec_max(mid_max, mid)
    }

    EPS :: 1e-6

    return mid_min - EPS, mid_max + EPS
}

@(require_results)
_update_node_bounds_with_mean :: proc(bvh: ^BVH, node: ^Node) -> (mean: [3]f32) #no_bounds_check {
    node.min = max(f32)
    node.max = min(f32)

    for i in 0..<int(node.len) {
        prim_index := bvh.indices[int(node.first) + i]
        prim := bvh.prims[prim_index]
        node.min = vec_min(node.min, prim[0])
        node.max = vec_max(node.max, prim[1])
        mean += prim[0] + prim[1]
    }

    return mean / f32(2 * node.len)
}


@(require_results)
vec_min :: proc "contextless" (a, b: [3]f32) -> [3]f32 {
    return {
        min(a.x, b.x),
        min(a.y, b.y),
        min(a.z, b.z),
    }
}

@(require_results)
vec_max :: proc "contextless" (a, b: [3]f32) -> [3]f32 {
    return {
        max(a.x, b.x),
        max(a.y, b.y),
        max(a.z, b.z),
    }
}

@(require_results)
surface_area :: proc(min, max: [3]f32) -> f32 {
    e := max - min
    return e.x*e.y + e.y*e.z + e.z*e.x
}
