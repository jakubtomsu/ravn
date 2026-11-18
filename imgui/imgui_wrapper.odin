package imgui

import "core:fmt"

@(deferred_none = End)
window :: proc(name: cstring, p_open: ^bool = nil, flags: WindowFlags = {}) -> bool {
    return Begin(name, p_open, flags)    
}

text :: proc(format: string, args: ..any) {
    Text("%s", fmt.ctprintf(format, args = args))
}

dump :: proc(val: any, name := #caller_expression(val)) {
    text("%s = %#v", name, val)
}

@(deferred_none = EndMainMenuBar)
main_menu_bar :: proc() -> bool {
    return BeginMainMenuBar()
}

@(deferred_none = EndDisabled)
disabled :: proc(disabled := true) -> bool {
    BeginDisabled(disabled)
    return true
}

combo_enum :: proc(label: cstring, val: ^$T, flags: ComboFlags = {}) -> (change: bool) where intrinsics.type_is_enum(T) {
    if BeginCombo(label, fmt.ctprint(val^), flags = flags) {
        defer EndCombo()
        for x in T {
            if Selectable(fmt.ctprint(x), x == val^) {
                val^ = x
                change = true
            }
        }
    }
    return change
}

tooltip :: proc(format: string, args: ..any) {
    if BeginItemTooltip() {
        defer EndTooltip()

        text := fmt.ctprintf(format, args = args)
        Text("%s", text)
    }
}

@(deferred_out = _tree_pop)
tree :: proc(label: cstring, flags: TreeNodeFlags = {}) -> bool {
    return TreeNodeEx(label, flags)
}

@(deferred_out = _tree_pop)
tree_str :: proc(id: cstring, str: cstring, flags: TreeNodeFlags = {}) -> bool {
    return TreeNodeExStr(id, flags, "%s", str)
}

_tree_pop :: proc(ok: bool) {
    if ok do TreePop()
}

@(deferred_out = _popup_end)
popup :: proc(id: cstring, flags: WindowFlags = {}) -> bool {
    return BeginPopup(id, flags)
}

_popup_end :: proc(ok: bool) {
    if ok do EndPopup()
}

@(deferred_none = PopID)
id_int :: proc(#any_int x: i32) {
    PushIDInt(x)
}

@(deferred_none = PopID)
id_cstr :: proc(str: cstring) {
    PushID(str)
}

@(deferred_none = PopID)
id_str :: proc(str: string) {
    PushIDStr(transmute(cstring)raw_data(str), transmute(cstring)(uintptr(raw_data(str)) + uintptr(len(str)) - 1))
}

@(deferred_none = PopID)
id_ptr :: proc(ptr: rawptr) {
    PushIDPtr(ptr)
}
