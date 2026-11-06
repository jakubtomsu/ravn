// https://github.com/Capati/odin-imgui
package imgui

when ODIN_OS == .Linux {
	@(require) foreign import stdcpp "system:stdc++"
} else when ODIN_OS == .Darwin {
	@(require) foreign import stdcpp "system:c++"
}

when ODIN_OS == .Windows {
	when ODIN_ARCH == .amd64 {
		@export
		foreign import imguilib "imgui_windows_x86_64.lib"
	} else {
		@export
		foreign import imguilib "imgui_windows_arm64.lib"
	}
} else when ODIN_OS == .Linux {
	when ODIN_ARCH == .amd64 {
		@export
		foreign import imguilib "libimgui_linux_x86_64.a"
	} else {
		@export
		foreign import imguilib "libimgui_linux_arm64.a"
	}
} else when ODIN_OS == .Darwin {
	when ODIN_ARCH == .amd64 {
		@export
		foreign import imguilib "libimgui_macosx_x86_64.a"
	} else {
		@export
		foreign import imguilib "libimgui_macosx_arm64.a"
	}
}

// Verify ABI compatibility between caller code and compiled version of Dear ImGui.
// This helps detects some build issues.
CHECKVERSION :: proc() {
	ensure(
		DebugCheckVersionAndDataLayout(
			VERSION,
			size_of(IO),
			size_of(Style),
			size_of(Vec2),
			size_of(Vec4),
			size_of(DrawVert),
			size_of(DrawIdx),
		),
	)
}

VERSION :: "1.92.9b"
VERSION_NUM :: 19291
TextureID_Invalid :: TextureID(0)
PAYLOAD_TYPE_COLOR_3F :: "_COL3F" // float[3]: Standard type for colors, without alpha. User code may use this type.
PAYLOAD_TYPE_COLOR_4F :: "_COL4F" // float[4]: Standard type for colors. User code may use this type.
UNICODE_CODEPOINT_INVALID :: 0xFFFD // Invalid Unicode code point (standard value).
UNICODE_CODEPOINT_MAX :: 0xFFFF // Maximum Unicode code point supported by this build.
COL32_R_SHIFT :: 0
COL32_G_SHIFT :: 8
COL32_B_SHIFT :: 16
COL32_A_SHIFT :: 24
COL32_A_MASK :: 0xFF000000
DRAWLIST_TEX_LINES_WIDTH_MAX :: 32
FontAtlasRectId_Invalid :: -1

// Flags for ImGui::Begin()
// (Those are per-window flags. There are shared flags in ImGuiIO: io.ConfigWindowsResizeFromEdges and io.ConfigWindowsMoveFromTitleBarOnly)
WindowFlags :: bit_set[WindowFlag; i32]
WindowFlag :: enum i32 {
	NoTitleBar = 0, // Disable title-bar
	NoResize = 1, // Disable user resizing with the lower-right grip
	NoMove = 2, // Disable user moving the window
	NoScrollbar = 3, // Disable scrollbars (window can still scroll with mouse or programmatically)
	NoScrollWithMouse = 4, // Disable user vertically scrolling with mouse wheel. On child window, mouse wheel will be forwarded to the parent unless NoScrollbar is also set.
	NoCollapse = 5, // Disable user collapsing window by double-clicking on it. Also referred to as Window Menu Button (e.g. within a docking node).
	AlwaysAutoResize = 6, // Resize every window to its content every frame
	NoBackground = 7, // Disable drawing background color (WindowBg, etc.) and outside border. Similar as using SetNextWindowBgAlpha(0.0f).
	NoSavedSettings = 8, // Never load/save settings in .ini file
	NoMouseInputs = 9, // Disable catching mouse, hovering test with pass through.
	MenuBar = 10, // Has a menu-bar
	HorizontalScrollbar = 11, // Allow horizontal scrollbar to appear (off by default). You may use SetNextWindowContentSize(ImVec2(width,0.0f)); prior to calling Begin() to specify width. Read code in imgui_demo in the "Horizontal Scrolling" section.
	NoFocusOnAppearing = 12, // Disable taking focus when transitioning from hidden to visible state
	NoBringToFrontOnFocus = 13, // Disable bringing window to front when taking focus (e.g. clicking on it or programmatically giving it focus)
	AlwaysVerticalScrollbar = 14, // Always show vertical scrollbar (even if ContentSize.y < Size.y)
	AlwaysHorizontalScrollbar = 15, // Always show horizontal scrollbar (even if ContentSize.x < Size.x)
	NoNavInputs = 16, // No keyboard/gamepad navigation within the window
	NoNavFocus = 17, // No focusing toward this window with keyboard/gamepad navigation (e.g. skipped by Ctrl+Tab)
	UnsavedDocument = 18, // Display a dot next to the title. When used in a tab/docking context, tab is selected when clicking the X + closure is not assumed (will wait for user to stop submitting the tab). Otherwise closure is assumed when pressing the X, so if you keep submitting the tab may reappear at end of tab bar.
	NoDocking = 19, // Disable docking of this window
}

WINDOW_FLAGS_NO_NAV :: WindowFlags{.NoNavInputs, .NoNavFocus}
WINDOW_FLAGS_NO_DECORATION :: WindowFlags{.NoTitleBar, .NoResize, .NoScrollbar, .NoCollapse}
WINDOW_FLAGS_NO_INPUTS :: WindowFlags{.NoMouseInputs, .NoNavInputs, .NoNavFocus}

// Flags for ImGui::BeginChild()
// (Legacy: bit 0 must always correspond to ImGuiChildFlags_Borders to be backward compatible with old API using 'bool border = false'.)
// About using AutoResizeX/AutoResizeY flags:
// - May be combined with SetNextWindowSizeConstraints() to set a min/max size for each axis (see "Demo->Child->Auto-resize with Constraints").
// - Size measurement for a given axis is only performed when the child window is within visible boundaries, or is just appearing.
//   - This allows BeginChild() to return false when not within boundaries (e.g. when scrolling), which is more optimal. BUT it won't update its auto-size while clipped.
//     While not perfect, it is a better default behavior as the always-on performance gain is more valuable than the occasional "resizing after becoming visible again" glitch.
//   - You may also use ImGuiChildFlags_AlwaysAutoResize to force an update even when child window is not in view.
//     HOWEVER PLEASE UNDERSTAND THAT DOING SO WILL PREVENT BeginChild() FROM EVER RETURNING FALSE, disabling benefits of coarse clipping.
ChildFlags :: bit_set[ChildFlag; i32]
ChildFlag :: enum i32 {
	Borders = 0, // Show an outer border and enable WindowPadding. (IMPORTANT: this is always == 1 == true for legacy reason)
	AlwaysUseWindowPadding = 1, // Pad with style.WindowPadding even if no border are drawn (no padding by default for non-bordered child windows because it makes more sense)
	ResizeX = 2, // Allow resize from right border (layout direction). Enable .ini saving (unless ImGuiWindowFlags_NoSavedSettings passed to window flags)
	ResizeY = 3, // Allow resize from bottom border (layout direction). "
	AutoResizeX = 4, // Enable auto-resizing width. Read "IMPORTANT: Size measurement" details above.
	AutoResizeY = 5, // Enable auto-resizing height. Read "IMPORTANT: Size measurement" details above.
	AlwaysAutoResize = 6, // Combined with AutoResizeX/AutoResizeY. Always measure size even when child is hidden, always return true, always disable clipping optimization! NOT RECOMMENDED.
	FrameStyle = 7, // Style the child window like a framed item: use FrameBg, FrameRounding, FrameBorderSize, FramePadding instead of ChildBg, ChildRounding, ChildBorderSize, WindowPadding.
	NavFlattened = 8, // [BETA] Share focus scope, allow keyboard/gamepad navigation to cross over parent border to this child or between sibling child windows.
}

// Flags for ImGui::PushItemFlag()
// (Those are shared by all submitted items)
ItemFlags :: bit_set[ItemFlag; i32]
ItemFlag :: enum i32 {
	NoTabStop = 0, // false    // Disable keyboard tabbing. This is a "lighter" version of ImGuiItemFlags_NoNav.
	NoNav = 1, // false    // Disable any form of focusing: keyboard/gamepad directional navigation and SetKeyboardFocusHere() calls.
	NoNavDefaultFocus = 2, // false    // Disable item being a candidate for default focus (e.g. used by title bar items).
	ButtonRepeat = 3, // false    // Any button-like behavior will have repeat mode enabled (based on io.KeyRepeatDelay and io.KeyRepeatRate values). Note that you can also call IsItemActive() after any button to tell if it is being held.
	AutoClosePopups = 4, // true     // MenuItem()/Selectable() automatically close their parent popup window.
	AllowDuplicateId = 5, // false    // Allow submitting an item with the same identifier as an item already submitted this frame without triggering a warning tooltip if io.ConfigDebugHighlightIdConflicts is set.
	Disabled = 6, // false    // [Internal] Disable interactions. DOES NOT affect visuals. This is used by BeginDisabled()/EndDisabled() and only provided here so you can read back via GetItemFlags().
	LiveEditOnInputText = 7, // true     // InputText: apply keyboard edits to backing value while typing. Otherwise, edits are applied when validating, tabbing out or losing focus.
	LiveEditOnInputScalar = 8, // false    // DragXXX, SliderXXX, InputScalar: apply keyboard edits to backing value while typing. Otherwise, edits are applied when validating, tabbing out or losing focus.
}

ITEM_FLAGS_LIVE_EDIT_ON_INPUT :: ItemFlags{.LiveEditOnInputText, .LiveEditOnInputScalar}

// Flags for ImGui::InputText()
// (Those are per-item flags. There are shared flags in ImGuiIO: io.ConfigInputTextCursorBlink and io.ConfigInputTextEnterKeepActive)
InputTextFlags :: bit_set[InputTextFlag; i32]
InputTextFlag :: enum i32 {
	CharsDecimal = 0, // Allow 0123456789.+-*/
	CharsHexadecimal = 1, // Allow 0123456789ABCDEFabcdef
	CharsScientific = 2, // Allow 0123456789.+-*/eE (Scientific notation input)
	CharsUppercase = 3, // Turn a..z into A..Z
	CharsNoBlank = 4, // Filter out spaces, tabs
	AllowTabInput = 5, // Pressing TAB input a '\t' character into the text field
	EnterReturnsTrue = 6, // Return 'true' when Enter is pressed (as opposed to every time the value was modified). Consider disabling LiveEdit! or using IsItemDeactivatedAfterEdit() instead!
	EscapeClearsAll = 7, // Escape key clears content if not empty, and deactivate otherwise (contrast to default behavior of Escape to revert)
	CtrlEnterForNewLine = 8, // In multi-line mode: validate with Enter, add new line with Ctrl+Enter (default is opposite: validate with Ctrl+Enter, add line with Enter). Note that Shift+Enter always enter a new line either way.
	ReadOnly = 9, // Read-only mode
	Password = 10, // Password mode, display all characters as '*', disable copy
	AlwaysOverwrite = 11, // Overwrite mode
	AutoSelectAll = 12, // Select entire text when first taking mouse focus
	ParseEmptyRefVal = 13, // InputFloat(), InputInt(), InputScalar() etc. only: parse empty string as zero value.
	DisplayEmptyRefVal = 14, // InputFloat(), InputInt(), InputScalar() etc. only: when value is zero, do not display it. Generally used with ImGuiInputTextFlags_ParseEmptyRefVal.
	NoHorizontalScroll = 15, // Disable following the cursor horizontally
	NoUndoRedo = 16, // Disable undo/redo. Note that input text owns the text data while active, if you want to provide your own undo/redo stack you need e.g. to call ClearActiveID().
	ElideLeft = 17, // When text doesn't fit, elide left side to ensure right side stays visible. Useful for path/filenames. Single-line only!
	CallbackCompletion = 18, // Callback on pressing TAB (for completion handling)
	CallbackHistory = 19, // Callback on pressing Up/Down arrows (for history handling)
	CallbackAlways = 20, // Callback on each iteration. User code may query cursor position, modify text buffer.
	CallbackCharFilter = 21, // Callback on character inputs to replace or discard them. Modify 'EventChar' to replace or discard, or return 1 in callback to discard.
	CallbackResize = 22, // Callback on buffer capacity changes request (beyond 'buf_size' parameter value), allowing the string to grow. Notify when the string wants to be resized (for string types which hold a cache of their Size). You will be provided a new BufSize in the callback and NEED to honor it. (see misc/cpp/imgui_stdlib.h for an example of using this)
	CallbackEdit = 23, // Callback on any edit. Note that InputText() already returns true on edit + you can always use IsItemEdited(). The callback is useful to manipulate the underlying buffer while focus is active.
	WordWrap = 24, // InputTextMultiline(): word-wrap lines that are too long.
}

// Flags for ImGui::TreeNodeEx(), ImGui::CollapsingHeader*()
TreeNodeFlags :: bit_set[TreeNodeFlag; i32]
TreeNodeFlag :: enum i32 {
	Selected = 0, // Draw as selected
	Framed = 1, // Draw frame with background (e.g. for CollapsingHeader)
	AllowOverlap = 2, // Hit testing will allow subsequent widgets to overlap this one. Require previous frame HoveredId to match before being usable. Shortcut to calling SetNextItemAllowOverlap().
	NoTreePushOnOpen = 3, // Don't do a TreePush() when open (e.g. for CollapsingHeader) = no extra indent nor pushing on ID stack
	NoAutoOpenOnLog = 4, // Don't automatically and temporarily open node when Logging is active (by default logging will automatically open tree nodes)
	DefaultOpen = 5, // Default node to be open
	OpenOnDoubleClick = 6, // Open on double-click instead of simple click (default for multi-select unless any _OpenOnXXX behavior is set explicitly). Both behaviors may be combined.
	OpenOnArrow = 7, // Open when clicking on the arrow part (default for multi-select unless any _OpenOnXXX behavior is set explicitly). Both behaviors may be combined.
	Leaf = 8, // No collapsing, no arrow (use as a convenience for leaf nodes). Note: will always open a tree/id scope and return true. If you never use that scope, add ImGuiTreeNodeFlags_NoTreePushOnOpen.
	Bullet = 9, // Display a bullet instead of arrow. IMPORTANT: node can still be marked open/close if you don't set the _Leaf flag!
	FramePadding = 10, // Use FramePadding (even for an unframed text node) to vertically align text baseline to regular widget height. Equivalent to calling AlignTextToFramePadding() before the node.
	SpanAvailWidth = 11, // Extend hit box to the right-most edge, even if not framed. This is not the default in order to allow adding other items on the same line without using AllowOverlap mode.
	SpanFullWidth = 12, // Extend hit box to the left-most and right-most edges (cover the indent area).
	SpanLabelWidth = 13, // Narrow hit box + narrow hovering highlight, will only cover the label text.
	SpanAllColumns = 14, // Frame will span all columns of its container table (label will still fit in current column)
	LabelSpanAllColumns = 15, // Label will span all columns of its container table
	NavLeftJumpsToParent = 17, // Nav: left arrow moves back to parent. This is processed in TreePop() when there's an unfulfilled Left nav request remaining.
	DrawLinesNone = 18, // No lines drawn
	DrawLinesFull = 19, // Horizontal lines to child nodes. Vertical line drawn down to TreePop() position: cover full contents. Faster (for large trees).
	DrawLinesToNodes = 20, // Horizontal lines to child nodes. Vertical line drawn down to bottom-most child node. Slower (for large trees).
}

TREE_NODE_FLAGS_COLLAPSING_HEADER :: TreeNodeFlags{.Framed, .NoTreePushOnOpen, .NoAutoOpenOnLog}

// Flags for OpenPopup*(), BeginPopupContext*(), IsPopupOpen() functions.
// - IMPORTANT: If you ever used the left mouse button with BeginPopupContextXXX() helpers before 1.92.6: Read "API BREAKING CHANGES" 2026/01/07 (1.92.6) entry in imgui.cpp or GitHub topic #9157.
// - Multiple buttons currently cannot be combined/or-ed in those functions (we could allow it later).
PopupFlags :: bit_set[PopupFlag; i32]
PopupFlag :: enum i32 {
	MouseButtonLeft = 2, // For BeginPopupContext*(): open on Left Mouse release. Only one button allowed!
	MouseButtonRight = 3, // For BeginPopupContext*(): open on Right Mouse release. Only one button allowed! (default)
	MouseButtonMiddle = 2, // For BeginPopupContext*(): open on Middle Mouse release. Only one button allowed!
	NoReopen = 5, // For OpenPopup*(), BeginPopupContext*(): don't reopen same popup if already open (won't reposition, won't reinitialize navigation)
	NoOpenOverExistingPopup = 7, // For OpenPopup*(), BeginPopupContext*(): don't open if there's already a popup at the same level of the popup stack
	NoOpenOverItems = 8, // For BeginPopupContextWindow(): don't return true when hovering items, only when hovering empty space
	AnyPopupId = 10, // For IsPopupOpen(): ignore the ImGuiID parameter and test for any popup.
	AnyPopupLevel = 11, // For IsPopupOpen(): search/test at any level of the popup stack (default test in the current level)
}

POPUP_FLAGS_ANY_POPUP :: PopupFlags{.AnyPopupId, .AnyPopupLevel}

// Flags for ImGui::Selectable()
SelectableFlags :: bit_set[SelectableFlag; i32]
SelectableFlag :: enum i32 {
	NoAutoClosePopups = 0, // Clicking this doesn't close parent popup window (overrides ImGuiItemFlags_AutoClosePopups)
	SpanAllColumns = 1, // Frame will span all columns of its container table (text will still fit in current column)
	AllowDoubleClick = 2, // Generate press events on double clicks too
	Disabled = 3, // Cannot be selected, display grayed out text
	AllowOverlap = 4, // Hit testing will allow subsequent widgets to overlap this one. Require previous frame HoveredId to match before being usable. Shortcut to calling SetNextItemAllowOverlap().
	Highlight = 5, // Make the item be displayed as if it is hovered
	SelectOnNav = 6, // Auto-select when moved into, unless Ctrl is held. Automatic when in a BeginMultiSelect() block.
}

// Flags for ImGui::BeginCombo()
ComboFlags :: bit_set[ComboFlag; i32]
ComboFlag :: enum i32 {
	PopupAlignLeft = 0, // Align the popup toward the left by default
	HeightSmall = 1, // Max ~4 items visible. Tip: If you want your combo popup to be a specific size you can use SetNextWindowSizeConstraints() prior to calling BeginCombo()
	HeightRegular = 2, // Max ~8 items visible (default)
	HeightLarge = 3, // Max ~20 items visible
	HeightLargest = 4, // As many fitting items as possible
	NoArrowButton = 5, // Display on the preview box without the square arrow button
	NoPreview = 6, // Display only a square arrow button
	WidthFitPreview = 7, // Width dynamically calculated from preview contents
}

// Flags for ImGui::BeginTabBar()
TabBarFlags :: bit_set[TabBarFlag; i32]
TabBarFlag :: enum i32 {
	Reorderable = 0, // Allow manually dragging tabs to re-order them + New tabs are appended at the end of list
	AutoSelectNewTabs = 1, // Automatically select new tabs when they appear
	TabListPopupButton = 2, // Disable buttons to open the tab list popup
	NoCloseWithMiddleMouseButton = 3, // Disable behavior of closing tabs (that are submitted with p_open != NULL) with middle mouse button. You may handle this behavior manually on user's side with if (IsItemHovered() && IsMouseClicked(2)) *p_open = false.
	NoTabListScrollingButtons = 4, // Disable scrolling buttons (apply when fitting policy is ImGuiTabBarFlags_FittingPolicyScroll)
	NoTooltip = 5, // Disable tooltips when hovering a tab
	DrawSelectedOverline = 6, // Draw selected overline markers over selected tab
	FittingPolicyMixed = 7, // Shrink down tabs when they don't fit, until width is style.TabMinWidthShrink, then enable scrolling. Setting TabMinWidthShrink to FLT_MAX makes this behave like ImGuiTabBarFlags_FittingPolicyScroll.
	FittingPolicyShrink = 8, // Shrink down tabs when they don't fit
	FittingPolicyScroll = 9, // Enable scrolling buttons when tabs don't fit
}

// Flags for ImGui::BeginTabItem()
TabItemFlags :: bit_set[TabItemFlag; i32]
TabItemFlag :: enum i32 {
	UnsavedDocument = 0, // Display a dot next to the title + set ImGuiTabItemFlags_NoAssumedClosure.
	SetSelected = 1, // Trigger flag to programmatically make the tab selected when calling BeginTabItem()
	NoCloseWithMiddleMouseButton = 2, // Disable behavior of closing tabs (that are submitted with p_open != NULL) with middle mouse button. You may handle this behavior manually on user's side with if (IsItemHovered() && IsMouseClicked(2)) *p_open = false.
	NoPushId = 3, // Don't call PushID()/PopID() on BeginTabItem()/EndTabItem()
	NoTooltip = 4, // Disable tooltip for the given tab
	NoReorder = 5, // Disable reordering this tab or having another tab cross over this tab
	Leading = 6, // Enforce the tab position to the left of the tab bar (after the tab list popup button)
	Trailing = 7, // Enforce the tab position to the right of the tab bar (before the scrolling buttons)
	NoAssumedClosure = 8, // Tab is selected when trying to close + closure is not immediately assumed (will wait for user to stop submitting the tab). Otherwise closure is assumed when pressing the X, so if you keep submitting the tab may reappear at end of tab bar.
}

// Flags for ImGui::IsWindowFocused()
FocusedFlags :: bit_set[FocusedFlag; i32]
FocusedFlag :: enum i32 {
	ChildWindows = 0, // Return true if any children of the window is focused
	RootWindow = 1, // Test from root window (top most parent of the current hierarchy)
	AnyWindow = 2, // Return true if any window is focused. Important: If you are trying to tell how to dispatch your low-level inputs, do NOT use this. Use 'io.WantCaptureMouse' instead! Please read the FAQ!
	NoPopupHierarchy = 3, // Do not consider popup hierarchy (do not treat popup emitter as parent of popup) (when used with _ChildWindows or _RootWindow)
	DockHierarchy = 4, // Consider docking hierarchy (treat dockspace host as parent of docked window) (when used with _ChildWindows or _RootWindow)
}

FOCUSED_FLAGS_ROOT_AND_CHILD_WINDOWS :: FocusedFlags{.RootWindow, .ChildWindows}

// Flags for ImGui::IsItemHovered(), ImGui::IsWindowHovered()
// Note: if you are trying to check whether your mouse should be dispatched to Dear ImGui or to your app, you should use 'io.WantCaptureMouse' instead! Please read the FAQ!
// Note: windows with the ImGuiWindowFlags_NoInputs flag are ignored by IsWindowHovered() calls.
HoveredFlags :: bit_set[HoveredFlag; i32]
HoveredFlag :: enum i32 {
	ChildWindows = 0, // IsWindowHovered() only: Return true if any children of the window is hovered
	RootWindow = 1, // IsWindowHovered() only: Test from root window (top most parent of the current hierarchy)
	AnyWindow = 2, // IsWindowHovered() only: Return true if any window is hovered
	NoPopupHierarchy = 3, // IsWindowHovered() only: Do not consider popup hierarchy (do not treat popup emitter as parent of popup) (when used with _ChildWindows or _RootWindow)
	DockHierarchy = 4, // IsWindowHovered() only: Consider docking hierarchy (treat dockspace host as parent of docked window) (when used with _ChildWindows or _RootWindow)
	AllowWhenBlockedByPopup = 5, // Return true even if a popup window is normally blocking access to this item/window
	AllowWhenBlockedByActiveItem = 7, // Return true even if an active item is blocking access to this item/window. Useful for Drag and Drop patterns.
	AllowWhenOverlappedByItem = 8, // IsItemHovered() only: Return true even if the item uses AllowOverlap mode and is overlapped by another hoverable item.
	AllowWhenOverlappedByWindow = 9, // IsItemHovered() only: Return true even if the position is obstructed or overlapped by another window.
	AllowWhenDisabled = 10, // IsItemHovered() only: Return true even if the item is disabled
	NoNavOverride = 11, // IsItemHovered() only: Disable using keyboard/gamepad navigation state when active, always query mouse
	ForTooltip = 12, // Shortcut for standard flags when using IsItemHovered() + SetTooltip() sequence.
	Stationary = 13, // Require mouse to be stationary for style.HoverStationaryDelay (~0.15 sec) _at least one time_. After this, can move on same item/window. Using the stationary test tends to reduces the need for a long delay.
	DelayNone = 14, // IsItemHovered() only: Return true immediately (default). As this is the default you generally ignore this.
	DelayShort = 15, // IsItemHovered() only: Return true after style.HoverDelayShort elapsed (~0.15 sec) (shared between items) + requires mouse to be stationary for style.HoverStationaryDelay (once per item).
	DelayNormal = 16, // IsItemHovered() only: Return true after style.HoverDelayNormal elapsed (~0.40 sec) (shared between items) + requires mouse to be stationary for style.HoverStationaryDelay (once per item).
	NoSharedDelay = 17, // IsItemHovered() only: Disable shared delay system where moving from one item to the next keeps the previous timer for a short time (standard for tooltips with long delays)
}

HOVERED_FLAGS_ALLOW_WHEN_OVERLAPPED :: HoveredFlags{.AllowWhenOverlappedByItem, .AllowWhenOverlappedByWindow}
HOVERED_FLAGS_RECT_ONLY :: HoveredFlags{.AllowWhenBlockedByPopup, .AllowWhenBlockedByActiveItem, .AllowWhenOverlappedByItem, .AllowWhenOverlappedByWindow, }
HOVERED_FLAGS_ROOT_AND_CHILD_WINDOWS :: HoveredFlags{.RootWindow, .ChildWindows}

// Flags for ImGui::DockSpace(), shared/inherited by child nodes.
// (Some flags can be applied to individual nodes directly)
// FIXME-DOCK: Also see ImGuiDockNodeFlagsPrivate_ which may involve using the WIP and internal DockBuilder api.
DockNodeFlags :: bit_set[DockNodeFlag; i32]
DockNodeFlag :: enum i32 {
	KeepAliveOnly = 0, //       // Don't display the dockspace node but keep it alive. Windows docked into this dockspace node won't be undocked.
	NoDockingOverCentralNode = 2, //       // Disable docking over the Central Node, which will be always kept empty.
	PassthruCentralNode = 3, //       // Enable passthru dockspace: 1) DockSpace() will render a ImGuiCol_WindowBg background covering everything excepted the Central Node when empty. Meaning the host window should probably use SetNextWindowBgAlpha(0.0f) prior to Begin() when using this. 2) When Central Node is empty: let inputs pass-through + won't display a DockingEmptyBg background. See demo for details.
	NoDockingSplit = 4, //       // Disable other windows/nodes from splitting this node.
	NoResize = 5, // Saved // Disable resizing node using the splitter/separators. Useful with programmatically setup dockspaces.
	AutoHideTabBar = 6, //       // Tab bar will automatically hide when there is a single window in the dock node.
	NoUndocking = 7, //       // Disable undocking this node.
}

// Flags for ImGui::BeginDragDropSource(), ImGui::AcceptDragDropPayload()
DragDropFlags :: bit_set[DragDropFlag; i32]
DragDropFlag :: enum i32 {
	SourceNoPreviewTooltip = 0, // Disable preview tooltip. By default, a successful call to BeginDragDropSource opens a tooltip so you can display a preview or description of the source contents. This flag disables this behavior.
	SourceNoDisableHover = 1, // By default, when dragging we clear data so that IsItemHovered() will return false, to avoid subsequent user code submitting tooltips. This flag disables this behavior so you can still call IsItemHovered() on the source item.
	SourceNoHoldToOpenOthers = 2, // Disable the behavior that allows to open tree nodes and collapsing header by holding over them while dragging a source item.
	SourceAllowNullID = 3, // Allow items such as Text(), Image() that have no unique identifier to be used as drag source, by manufacturing a temporary identifier based on their window-relative position. This is extremely unusual within the dear imgui ecosystem and so we made it explicit.
	SourceExtern = 4, // External source (from outside of dear imgui), won't attempt to read current item/window info. Will always return true. Only one Extern source can be active simultaneously.
	PayloadAutoExpire = 5, // Automatically expire the payload if the source cease to be submitted (otherwise payloads are persisting while being dragged)
	PayloadNoCrossContext = 6, // Hint to specify that the payload may not be copied outside current dear imgui context.
	PayloadNoCrossProcess = 7, // Hint to specify that the payload may not be copied outside current process.
	AcceptBeforeDelivery = 10, // AcceptDragDropPayload() will returns true even before the mouse button is released. You can then call IsDelivery() to test if the payload needs to be delivered.
	AcceptNoDrawDefaultRect = 11, // Do not draw the default highlight rectangle when hovering over target.
	AcceptNoPreviewTooltip = 12, // Request hiding the BeginDragDropSource tooltip from the BeginDragDropTarget site.
	AcceptDrawAsHovered = 13, // Accepting item will render as if hovered. Useful for e.g. a Button() used as a drop target.
}

DRAG_DROP_FLAGS_ACCEPT_PEEK_ONLY :: DragDropFlags{.AcceptBeforeDelivery, .AcceptNoDrawDefaultRect}

// A primary data type
DataType :: enum i32 {
	S8 = 0, // signed char / char (with sensible compilers)
	U8 = 1, // unsigned char
	S16 = 2, // short
	U16 = 3, // unsigned short
	S32 = 4, // int
	U32 = 5, // unsigned int
	S64 = 6, // long long / __int64
	U64 = 7, // unsigned long long / unsigned __int64
	Float = 8, // float
	Double = 9, // double
	Bool = 10, // bool (provided for user convenience, not supported by scalar widgets)
	String = 11, // char* (provided for user convenience, not supported by scalar widgets)
}

DATA_TYPE_COUNT :: 12

// A cardinal direction
Dir :: enum i32 {
	None = -1,
	Left = 0,
	Right = 1,
	Up = 2,
	Down = 3,
}

DIR_COUNT :: 4

// A sorting direction
SortDirection :: enum i32 {
	None = 0,
	Ascending = 1, // Ascending = 0->9, A->Z etc.
	Descending = 2, // Descending = 9->0, Z->A etc.
}

// A key identifier (ImGuiKey_XXX or ImGuiMod_XXX value): can represent Keyboard, Mouse and Gamepad values.
// All our named keys are >= 512. Keys value 0 to 511 are left unused and were legacy native/opaque key values (< 1.87).
// Support for legacy keys was completely removed in 1.91.5.
// Read details about the 1.87+ transition : https://github.com/ocornut/imgui/issues/4921
// Note that "Keys" related to physical keys and are not the same concept as input "Characters", the latter are submitted via io.AddInputCharacter().
// The keyboard key enum values are named after the keys on a standard US keyboard, and on other keyboard types the keys reported may not match the keycaps.
Key :: enum i32 {
	None = 0,
	NamedKey_BEGIN = 512, // First valid key value (other than 0)
	Tab = 512, // == ImGuiKey_NamedKey_BEGIN
	LeftArrow = 513,
	RightArrow = 514,
	UpArrow = 515,
	DownArrow = 516,
	PageUp = 517,
	PageDown = 518,
	Home = 519,
	End = 520,
	Insert = 521,
	Delete = 522,
	Backspace = 523,
	Space = 524,
	Enter = 525,
	Escape = 526,
	LeftCtrl = 527,
	LeftShift = 528,
	LeftAlt = 529,
	LeftSuper = 530, // Also see ImGuiMod_Ctrl, ImGuiMod_Shift, ImGuiMod_Alt, ImGuiMod_Super below!
	RightCtrl = 531,
	RightShift = 532,
	RightAlt = 533,
	RightSuper = 534,
	Menu = 535,
	_0 = 536,
	_1 = 537,
	_2 = 538,
	_3 = 539,
	_4 = 540,
	_5 = 541,
	_6 = 542,
	_7 = 543,
	_8 = 544,
	_9 = 545,
	A = 546,
	B = 547,
	C = 548,
	D = 549,
	E = 550,
	F = 551,
	G = 552,
	H = 553,
	I = 554,
	J = 555,
	K = 556,
	L = 557,
	M = 558,
	N = 559,
	O = 560,
	P = 561,
	Q = 562,
	R = 563,
	S = 564,
	T = 565,
	U = 566,
	V = 567,
	W = 568,
	X = 569,
	Y = 570,
	Z = 571,
	F1 = 572,
	F2 = 573,
	F3 = 574,
	F4 = 575,
	F5 = 576,
	F6 = 577,
	F7 = 578,
	F8 = 579,
	F9 = 580,
	F10 = 581,
	F11 = 582,
	F12 = 583,
	F13 = 584,
	F14 = 585,
	F15 = 586,
	F16 = 587,
	F17 = 588,
	F18 = 589,
	F19 = 590,
	F20 = 591,
	F21 = 592,
	F22 = 593,
	F23 = 594,
	F24 = 595,
	Apostrophe = 596, // '
	Comma = 597, // ,
	Minus = 598, // -
	Period = 599, // .
	Slash = 600, // /
	Semicolon = 601, // ;
	Equal = 602, // =
	LeftBracket = 603, // [
	Backslash = 604, // \ (this text inhibit multiline comment caused by backslash)
	RightBracket = 605, // ]
	GraveAccent = 606, // `
	CapsLock = 607,
	ScrollLock = 608,
	NumLock = 609,
	PrintScreen = 610,
	Pause = 611,
	Keypad0 = 612,
	Keypad1 = 613,
	Keypad2 = 614,
	Keypad3 = 615,
	Keypad4 = 616,
	Keypad5 = 617,
	Keypad6 = 618,
	Keypad7 = 619,
	Keypad8 = 620,
	Keypad9 = 621,
	KeypadDecimal = 622,
	KeypadDivide = 623,
	KeypadMultiply = 624,
	KeypadSubtract = 625,
	KeypadAdd = 626,
	KeypadEnter = 627,
	KeypadEqual = 628,
	AppBack = 629, // Available on some keyboard/mouses. Often referred as "Browser Back"
	AppForward = 630,
	Oem102 = 631, // Non-US backslash.
	GamepadStart = 632, // Menu        | +       | Options  |
	GamepadBack = 633, // View        | -       | Share    |
	GamepadFaceLeft = 634, // X           | Y       | Square   | Toggle Menu. Hold for Windowing mode (Focus/Move/Resize windows)
	GamepadFaceRight = 635, // B           | A       | Circle   | Cancel / Close / Exit
	GamepadFaceUp = 636, // Y           | X       | Triangle | Open Context Menu
	GamepadFaceDown = 637, // A           | B       | Cross    | Activate / Open / Toggle. Hold for 0.60f to Activate in Text Input mode (e.g. wired to an on-screen keyboard).
	GamepadDpadLeft = 638, // D-pad Left  | "       | "        | Move / Tweak / Resize Window (in Windowing mode)
	GamepadDpadRight = 639, // D-pad Right | "       | "        | Move / Tweak / Resize Window (in Windowing mode)
	GamepadDpadUp = 640, // D-pad Up    | "       | "        | Move / Tweak / Resize Window (in Windowing mode)
	GamepadDpadDown = 641, // D-pad Down  | "       | "        | Move / Tweak / Resize Window (in Windowing mode)
	GamepadL1 = 642, // L Bumper    | L       | L1       | Tweak Slower / Focus Previous (in Windowing mode)
	GamepadR1 = 643, // R Bumper    | R       | R1       | Tweak Faster / Focus Next (in Windowing mode)
	GamepadL2 = 644, // L Trigger   | ZL      | L2       | [Analog]
	GamepadR2 = 645, // R Trigger   | ZR      | R2       | [Analog]
	GamepadL3 = 646, // L Stick     | L3      | L3       |
	GamepadR3 = 647, // R Stick     | R3      | R3       |
	GamepadLStickLeft = 648, //             |         |          | [Analog] Move Window (in Windowing mode)
	GamepadLStickRight = 649, //             |         |          | [Analog] Move Window (in Windowing mode)
	GamepadLStickUp = 650, //             |         |          | [Analog] Move Window (in Windowing mode)
	GamepadLStickDown = 651, //             |         |          | [Analog] Move Window (in Windowing mode)
	GamepadRStickLeft = 652, //             |         |          | [Analog]
	GamepadRStickRight = 653, //             |         |          | [Analog]
	GamepadRStickUp = 654, //             |         |          | [Analog]
	GamepadRStickDown = 655, //             |         |          | [Analog]
	MouseLeft = 656,
	MouseRight = 657,
	MouseMiddle = 658,
	MouseX1 = 659,
	MouseX2 = 660,
	MouseWheelX = 661,
	MouseWheelY = 662,
	ReservedForModCtrl = 663,
	ReservedForModShift = 664,
	ReservedForModAlt = 665,
	ReservedForModSuper = 666,
	NamedKey_END = 667,
}

KEY_NAMED_KEY_COUNT :: 155
KEY_MOD_NONE :: 0
KEY_MOD_CTRL :: 4096
KEY_MOD_SHIFT :: 8192
KEY_MOD_ALT :: 16384
KEY_MOD_SUPER :: 32768
KEY_MOD_MASK :: 61440

// Flags for Shortcut(), SetNextItemShortcut(),
// (and for upcoming extended versions of IsKeyPressed(), IsMouseClicked(), Shortcut(), SetKeyOwner(), SetItemKeyOwner() that are still in imgui_internal.h)
// Don't mistake with ImGuiInputTextFlags! (which is for ImGui::InputText() function)
InputFlags :: bit_set[InputFlag; i32]
InputFlag :: enum i32 {
	Repeat = 0, // Enable repeat. Return true on successive repeats. Default for legacy IsKeyPressed(). NOT Default for legacy IsMouseClicked(). MUST BE == 1.
	RouteActive = 10, // Route to active item only.
	RouteFocused = 11, // Route to windows in the focus stack (DEFAULT). Deep-most focused window takes inputs. Active item takes inputs over deep-most focused window.
	RouteGlobal = 12, // Global route (unless a focused window or active item registered the route).
	RouteAlways = 13, // Do not register route, poll keys directly.
	RouteOverFocused = 14, // Option: global route: higher priority than focused route (unless active item in focused route).
	RouteOverActive = 15, // Option: global route: higher priority than active item. Unlikely you need to use that: will interfere with every active items, e.g. Ctrl+A registered by InputText will be overridden by this. May not be fully honored as user/internal code is likely to always assume they can access keys when active.
	RouteUnlessBgFocused = 16, // Option: global route: will not be applied if underlying background/void is focused (== no Dear ImGui windows are focused). Useful for overlay applications.
	RouteFromRootWindow = 17, // Option: route evaluated from the point of view of root window rather than current window.
	Tooltip = 18, // Automatically display a tooltip when hovering item [BETA] Unsure of right api (opt-in/opt-out)
}

// Configuration flags stored in io.ConfigFlags. Set by user/application.
// Note that nowadays most of our configuration options are in other ImGuiIO fields, e.g. io.ConfigWindowsMoveFromTitleBarOnly.
ConfigFlags :: bit_set[ConfigFlag; i32]
ConfigFlag :: enum i32 {
	NavEnableKeyboard = 0, // Master keyboard navigation enable flag. Enable full Tabbing + directional arrows + Space/Enter to activate. Note: some features such as basic Tabbing and CtrL+Tab are enabled by regardless of this flag (and may be disabled via other means, see #4828, #9218).
	NavEnableGamepad = 1, // Master gamepad navigation enable flag. Backend also needs to set ImGuiBackendFlags_HasGamepad.
	NoMouse = 4, // Instruct dear imgui to disable mouse inputs and interactions.
	NoMouseCursorChange = 5, // Instruct backend to not alter mouse cursor shape and visibility. Use if the backend cursor changes are interfering with yours and you don't want to use SetMouseCursor() to change mouse cursor. You may want to honor requests from imgui by reading GetMouseCursor() yourself instead.
	NoKeyboard = 6, // Instruct dear imgui to disable keyboard inputs and interactions. This is done by ignoring keyboard events and clearing existing states.
	DockingEnable = 7, // Docking enable flags.
	ViewportsEnable = 10, // Viewport enable flags (require both ImGuiBackendFlags_PlatformHasViewports + ImGuiBackendFlags_RendererHasViewports set by the respective backends)
	IsSRGB = 20, // Application is SRGB-aware.
	IsTouchScreen = 21, // Application is using a touch screen instead of a mouse.
}

// Backend capabilities flags stored in io.BackendFlags. Set by imgui_impl_xxx or custom backend.
BackendFlags :: bit_set[BackendFlag; i32]
BackendFlag :: enum i32 {
	HasGamepad = 0, // Backend Platform supports gamepad and currently has one connected.
	HasMouseCursors = 1, // Backend Platform supports honoring GetMouseCursor() value to change the OS cursor shape.
	HasSetMousePos = 2, // Backend Platform supports io.WantSetMousePos requests to reposition the OS mouse position (only used if io.ConfigNavMoveSetMousePos is set).
	RendererHasVtxOffset = 3, // Backend Renderer supports ImDrawCmd::VtxOffset. This enables output of large meshes (64K+ vertices) while still using 16-bit indices.
	RendererHasTextures = 4, // Backend Renderer supports ImTextureData requests to create/update/destroy textures. This enables incremental texture updates and texture reloads. See https://github.com/ocornut/imgui/blob/master/docs/BACKENDS.md for instructions on how to upgrade your custom backend.
	RendererHasViewports = 10, // Backend Renderer supports multiple viewports.
	PlatformHasViewports = 11, // Backend Platform supports multiple viewports.
	HasMouseHoveredViewport = 12, // Backend Platform supports calling io.AddMouseViewportEvent() with the viewport under the mouse. IF POSSIBLE, ignore viewports with the ImGuiViewportFlags_NoInputs flag (Win32 backend, GLFW 3.30+ backend can do this, SDL backend cannot). If this cannot be done, Dear ImGui needs to use a flawed heuristic to find the viewport under.
	HasParentViewport = 13, // Backend Platform supports honoring viewport->ParentViewport/ParentViewportId value, by applying the corresponding parent/child relationship at the Platform level. Child windows always appear in front of their parent window.
}

// Enumeration for PushStyleColor() / PopStyleColor()
Col :: enum i32 {
	Text = 0,
	TextDisabled = 1,
	WindowBg = 2, // Background of normal windows
	ChildBg = 3, // Background of child windows
	PopupBg = 4, // Background of popups, menus, tooltips windows
	Border = 5,
	BorderShadow = 6,
	FrameBg = 7, // Background of checkbox, radio button, plot, slider, text input
	FrameBgHovered = 8,
	FrameBgActive = 9,
	TitleBg = 10, // Title bar
	TitleBgActive = 11, // Title bar when focused
	TitleBgCollapsed = 12, // Title bar when collapsed
	MenuBarBg = 13,
	ScrollbarBg = 14,
	ScrollbarGrab = 15,
	ScrollbarGrabHovered = 16,
	ScrollbarGrabActive = 17,
	CheckMark = 18, // Checkbox tick and RadioButton circle
	CheckboxSelectedBg = 19, // Checkbox background when Selected, otherwise use FrameBg
	SliderGrab = 20,
	SliderGrabActive = 21,
	Button = 22,
	ButtonHovered = 23,
	ButtonActive = 24,
	Header = 25, // Header* colors are used for CollapsingHeader, TreeNode, Selectable, MenuItem
	HeaderHovered = 26,
	HeaderActive = 27,
	Separator = 28,
	SeparatorHovered = 29,
	SeparatorActive = 30,
	ResizeGrip = 31, // Resize grip in lower-right and lower-left corners of windows.
	ResizeGripHovered = 32,
	ResizeGripActive = 33,
	InputTextCursor = 34, // InputText cursor/caret
	TabHovered = 35, // Tab background, when hovered
	Tab = 36, // Tab background, when tab-bar is focused & tab is unselected
	TabSelected = 37, // Tab background, when tab-bar is focused & tab is selected
	TabSelectedOverline = 38, // Tab horizontal overline, when tab-bar is focused & tab is selected
	TabDimmed = 39, // Tab background, when tab-bar is unfocused & tab is unselected
	TabDimmedSelected = 40, // Tab background, when tab-bar is unfocused & tab is selected
	TabDimmedSelectedOverline = 41, //..horizontal overline, when tab-bar is unfocused & tab is selected
	DockingPreview = 42, // Preview overlay color when about to docking something
	DockingEmptyBg = 43, // Background color for empty node (e.g. CentralNode with no window docked into it)
	PlotLines = 44,
	PlotLinesHovered = 45,
	PlotHistogram = 46,
	PlotHistogramHovered = 47,
	TableHeaderBg = 48, // Table header background
	TableBorderStrong = 49, // Table outer and header borders (prefer using Alpha=1.0 here)
	TableBorderLight = 50, // Table inner borders (prefer using Alpha=1.0 here)
	TableRowBg = 51, // Table row background (even rows)
	TableRowBgAlt = 52, // Table row background (odd rows)
	TextLink = 53, // Hyperlink color
	TextSelectedBg = 54, // Selected text inside an InputText
	TreeLines = 55, // Tree node hierarchy outlines when using ImGuiTreeNodeFlags_DrawLines
	DragDropTarget = 56, // Rectangle border highlighting a drop target
	DragDropTargetBg = 57, // Rectangle background highlighting a drop target
	UnsavedMarker = 58, // Unsaved Document marker (in window title and tabs)
	NavCursor = 59, // Color of keyboard/gamepad navigation cursor/rectangle, when visible
	NavWindowingHighlight = 60, // Highlight window when using Ctrl+Tab
	NavWindowingDimBg = 61, // Darken/colorize entire screen behind the Ctrl+Tab window list, when active
	ModalWindowDimBg = 62, // Darken/colorize entire screen behind a modal window, when one is active
}

COL_COUNT :: 63

// Enumeration for PushStyleVar() / PopStyleVar() to temporarily modify the ImGuiStyle structure.
// - The enum only refers to fields of ImGuiStyle which makes sense to be pushed/popped inside UI code.
//   During initialization or between frames, feel free to just poke into ImGuiStyle directly.
// - Tip: Use your programming IDE navigation facilities on the names in the _second column_ below to find the actual members and their description.
//   - In Visual Studio: Ctrl+Comma ("Edit.GoToAll") can follow symbols inside comments, whereas Ctrl+F12 ("Edit.GoToImplementation") cannot.
//   - In Visual Studio w/ Visual Assist installed: Alt+G ("VAssistX.GoToImplementation") can also follow symbols inside comments.
//   - In VS Code, CLion, etc.: Ctrl+Click can follow symbols inside comments.
// - When changing this enum, you need to update the associated internal table GStyleVarInfo[] accordingly. This is where we link enum values to members offset/type.
StyleVar :: enum i32 {
	Alpha = 0, // float     Alpha
	DisabledAlpha = 1, // float     DisabledAlpha
	WindowPadding = 2, // ImVec2    WindowPadding
	WindowRounding = 3, // float     WindowRounding
	WindowBorderSize = 4, // float     WindowBorderSize
	WindowMinSize = 5, // ImVec2    WindowMinSize
	WindowTitleAlign = 6, // ImVec2    WindowTitleAlign
	ChildRounding = 7, // float     ChildRounding
	ChildBorderSize = 8, // float     ChildBorderSize
	PopupRounding = 9, // float     PopupRounding
	PopupBorderSize = 10, // float     PopupBorderSize
	FramePadding = 11, // ImVec2    FramePadding
	FrameRounding = 12, // float     FrameRounding
	FrameBorderSize = 13, // float     FrameBorderSize
	ItemSpacing = 14, // ImVec2    ItemSpacing
	ItemInnerSpacing = 15, // ImVec2    ItemInnerSpacing
	IndentSpacing = 16, // float     IndentSpacing
	CellPadding = 17, // ImVec2    CellPadding
	ScrollbarSize = 18, // float     ScrollbarSize
	ScrollbarRounding = 19, // float     ScrollbarRounding
	ScrollbarPadding = 20, // float     ScrollbarPadding
	GrabMinSize = 21, // float     GrabMinSize
	GrabRounding = 22, // float     GrabRounding
	ImageRounding = 23, // float     ImageRounding
	ImageBorderSize = 24, // float     ImageBorderSize
	TabRounding = 25, // float     TabRounding
	TabBorderSize = 26, // float     TabBorderSize
	TabMinWidthBase = 27, // float     TabMinWidthBase
	TabMinWidthShrink = 28, // float     TabMinWidthShrink
	TabBarBorderSize = 29, // float     TabBarBorderSize
	TabBarOverlineSize = 30, // float     TabBarOverlineSize
	TableAngledHeadersAngle = 31, // float     TableAngledHeadersAngle
	TableAngledHeadersTextAlign = 32, // ImVec2  TableAngledHeadersTextAlign
	TreeLinesSize = 33, // float     TreeLinesSize
	TreeLinesRounding = 34, // float     TreeLinesRounding
	MenuItemRounding = 35, // float     MenuItemRounding
	SelectableRounding = 36, // float     SelectableRounding
	DragDropTargetRounding = 37, // float     DragDropTargetRounding
	ButtonTextAlign = 38, // ImVec2    ButtonTextAlign
	SelectableTextAlign = 39, // ImVec2    SelectableTextAlign
	SeparatorSize = 40, // float     SeparatorSize
	SeparatorTextBorderSize = 41, // float     SeparatorTextBorderSize
	SeparatorTextAlign = 42, // ImVec2    SeparatorTextAlign
	SeparatorTextPadding = 43, // ImVec2    SeparatorTextPadding
	DockingSeparatorSize = 44, // float     DockingSeparatorSize
}

STYLE_VAR_COUNT :: 45

// Flags for InvisibleButton() [extended in imgui_internal.h]
ButtonFlags :: bit_set[ButtonFlag; i32]
ButtonFlag :: enum i32 {
	MouseButtonLeft = 0, // React on left mouse button (default)
	MouseButtonRight = 1, // React on right mouse button
	MouseButtonMiddle = 2, // React on center mouse button
	EnableNav = 3, // InvisibleButton(): do not disable navigation/tabbing. Otherwise disabled by default.
	AllowOverlap = 12, // Hit testing will allow subsequent widgets to overlap this one. Require previous frame HoveredId to match before being usable. Shortcut to calling SetNextItemAllowOverlap().
}

// Flags for ColorEdit3() / ColorEdit4() / ColorPicker3() / ColorPicker4() / ColorButton()
ColorEditFlags :: bit_set[ColorEditFlag; i32]
ColorEditFlag :: enum i32 {
	NoAlpha = 1, //              // ColorEdit, ColorPicker, ColorButton: ignore Alpha component (will only read 3 components from the input pointer).
	NoPicker = 2, //              // ColorEdit: disable picker when clicking on color square.
	NoOptions = 3, //              // ColorEdit: disable toggling options menu when right-clicking on inputs/small preview.
	NoSmallPreview = 4, //              // ColorEdit, ColorPicker: disable color square preview next to the inputs. (e.g. to show only the inputs)
	NoInputs = 5, //              // ColorEdit, ColorPicker: disable inputs sliders/text widgets (e.g. to show only the small preview color square).
	NoTooltip = 6, //              // ColorEdit, ColorPicker, ColorButton: disable tooltip when hovering the preview.
	NoLabel = 7, //              // ColorEdit, ColorPicker: disable display of inline text label (the label is still forwarded to the tooltip and picker).
	NoSidePreview = 8, //              // ColorPicker: disable bigger color preview on right side of the picker, use small color square preview instead.
	NoDragDrop = 9, //              // ColorEdit: disable drag and drop target/source. ColorButton: disable drag and drop source.
	NoBorder = 10, //              // ColorButton: disable border (which is enforced by default)
	NoColorMarkers = 11, //              // ColorEdit: disable rendering R/G/B/A color marker. May also be disabled globally by setting style.ColorMarkerSize = 0.
	AlphaOpaque = 12, //              // ColorEdit, ColorPicker, ColorButton: disable alpha in the preview,. Contrary to _NoAlpha it may still be edited when calling ColorEdit4()/ColorPicker4(). For ColorButton() this does the same as _NoAlpha.
	AlphaNoBg = 13, //              // ColorEdit, ColorPicker, ColorButton: disable rendering a checkerboard background behind transparent color.
	AlphaPreviewHalf = 14, //              // ColorEdit, ColorPicker, ColorButton: display half opaque / half transparent preview.
	AlphaBar = 18, //              // ColorEdit, ColorPicker: show vertical alpha bar/gradient in picker.
	HDR = 19, //              // (WIP) ColorEdit: Currently only disable 0.0f..1.0f limits in RGBA edition (note: you probably want to use ImGuiColorEditFlags_Float flag as well).
	DisplayRGB = 20, // [Display]    // ColorEdit: override _display_ type among RGB/HSV/Hex. ColorPicker: select any combination using one or more of RGB/HSV/Hex.
	DisplayHSV = 21, // [Display]    // "
	DisplayHex = 22, // [Display]    // "
	Uint8 = 23, // [DataType]   // ColorEdit, ColorPicker, ColorButton: _display_ values formatted as 0..255.
	Float = 24, // [DataType]   // ColorEdit, ColorPicker, ColorButton: _display_ values formatted as 0.0f..1.0f floats instead of 0..255 integers. No round-trip of value via integers.
	PickerHueBar = 25, // [Picker]     // ColorPicker: bar for Hue, rectangle for Sat/Value.
	PickerHueWheel = 26, // [Picker]     // ColorPicker: wheel for Hue, triangle for Sat/Value.
	PickerNoRotate = 27, // [Picker]     // ColorPicker: disable rotating Sat/Value triangle. Best set in io.ConfigColorEditFlags once.
	InputRGB = 28, // [Input]      // ColorEdit, ColorPicker: input and output data in RGB format.
	InputHSV = 29, // [Input]      // ColorEdit, ColorPicker: input and output data in HSV format.
}

// Flags for DragFloat(), DragInt(), SliderFloat(), SliderInt() etc.
// We use the same sets of flags for DragXXX() and SliderXXX() functions as the features are the same and it makes it easier to swap them.
// (Those are per-item flags. There is shared behavior flag too: ImGuiIO: io.ConfigDragClickToInputText)
SliderFlags :: bit_set[SliderFlag; i32]
SliderFlag :: enum i32 {
	Logarithmic = 5, // Make the widget logarithmic (linear otherwise). Consider using ImGuiSliderFlags_NoRoundToFormat with this if using a format-string with small amount of digits.
	NoRoundToFormat = 6, // Disable rounding underlying value to match precision of the display format string (e.g. %.3f values are rounded to those 3 digits).
	NoInput = 7, // Disable Ctrl+Click or Enter key allowing to input text directly into the widget.
	WrapAround = 8, // Enable wrapping around from max to min and from min to max. Only supported by DragXXX() functions for now.
	ClampOnInput = 9, // Clamp value to min/max bounds when input manually with Ctrl+Click. By default Ctrl+Click allows going out of bounds.
	ClampZeroRange = 10, // Clamp even if min==max==0.0f. Otherwise due to legacy reason DragXXX functions don't clamp with those values. When your clamping limits are dynamic you almost always want to use it.
	NoSpeedTweaks = 11, // Disable keyboard modifiers altering tweak speed. Useful if you want to alter tweak speed yourself based on your own logic.
	ColorMarkers = 12, // DragScalarN(), SliderScalarN(): Draw R/G/B/A color markers on each component.
}

SLIDER_FLAGS_ALWAYS_CLAMP :: SliderFlags{.ClampOnInput, .ClampZeroRange}

// Identify a mouse button.
// Those values are guaranteed to be stable and we frequently use 0/1 directly. Named enums provided for convenience.
MouseButton :: enum i32 {
	Left = 0,
	Right = 1,
	Middle = 2,
}

MOUSE_BUTTON_COUNT :: 5

// Enumeration for GetMouseCursor()
// User code may request backend to display given cursor by calling SetMouseCursor(), which is why we have some cursors that are marked unused here
MouseCursor :: enum i32 {
	None = -1,
	Arrow = 0,
	TextInput = 1, // When hovering over InputText, etc.
	ResizeAll = 2, // (Unused by Dear ImGui functions)
	ResizeNS = 3, // When hovering over a horizontal border
	ResizeEW = 4, // When hovering over a vertical border or a column
	ResizeNESW = 5, // When hovering over the bottom-left corner of a window
	ResizeNWSE = 6, // When hovering over the bottom-right corner of a window
	Hand = 7, // (Unused by Dear ImGui functions. Use for e.g. hyperlinks)
	Wait = 8, // When waiting for something to process/load.
	Progress = 9, // When waiting for something to process/load, but application is still interactive.
	NotAllowed = 10, // When hovering something with disallowed interaction. Usually a crossed circle.
}

MOUSE_CURSOR_COUNT :: 11

// Enumeration for AddMouseSourceEvent() actual source of Mouse Input data.
// Historically we use "Mouse" terminology everywhere to indicate pointer data, e.g. MousePos, IsMousePressed(), io.AddMousePosEvent()
// But that "Mouse" data can come from different source which occasionally may be useful for application to know about.
// You can submit a change of pointer type using io.AddMouseSourceEvent().
MouseSource :: enum i32 {
	Mouse = 0, // Input is coming from an actual mouse.
	TouchScreen = 1, // Input is coming from a touch screen (no hovering prior to initial press, less precise initial press aiming, dual-axis wheeling possible).
	Pen = 2, // Input is coming from a pressure/magnetic pen (often used in conjunction with high-sampling rates).
}

MOUSE_SOURCE_COUNT :: 3

// Enumeration for ImGui::SetNextWindow***(), SetWindow***(), SetNextItem***() functions
// Represent a condition.
// Important: Treat as a regular enum! Do NOT combine multiple values using binary operators! All the functions above treat 0 as a shortcut to ImGuiCond_Always.
Cond :: enum i32 {
	None = 0, // No condition (always set the variable), same as _Always
	Always = 1, // No condition (always set the variable), same as _None
	Once = 2, // Set the variable once per runtime session (only the first call will succeed)
	FirstUseEver = 4, // Set the variable if the object/window has no persistently saved data (no entry in .ini file)
	Appearing = 8, // Set the variable if the object/window is appearing after being hidden/inactive (or the first time)
}

// Flags for ImGui::BeginTable()
// - Important! Sizing policies have complex and subtle side effects, much more so than you would expect.
//   Read comments/demos carefully + experiment with live demos to get acquainted with them.
// - The DEFAULT sizing policies are:
//    - Default to ImGuiTableFlags_SizingFixedFit    if ScrollX is on, or if host window has ImGuiWindowFlags_AlwaysAutoResize.
//    - Default to ImGuiTableFlags_SizingStretchSame if ScrollX is off.
// - When ScrollX is off:
//    - Table defaults to ImGuiTableFlags_SizingStretchSame -> all Columns defaults to ImGuiTableColumnFlags_WidthStretch with same weight.
//    - Columns sizing policy allowed: Stretch (default), Fixed/Auto.
//    - Fixed Columns (if any) will generally obtain their requested width (unless the table cannot fit them all).
//    - Stretch Columns will share the remaining width according to their respective weight.
//    - Mixed Fixed/Stretch columns is possible but has various side-effects on resizing behaviors.
//      The typical use of mixing sizing policies is: any number of LEADING Fixed columns, followed by one or two TRAILING Stretch columns.
//      (this is because the visible order of columns have subtle but necessary effects on how they react to manual resizing).
// - When ScrollX is on:
//    - Table defaults to ImGuiTableFlags_SizingFixedFit -> all Columns defaults to ImGuiTableColumnFlags_WidthFixed
//    - Columns sizing policy allowed: Fixed/Auto mostly.
//    - Fixed Columns can be enlarged as needed. Table will show a horizontal scrollbar if needed.
//    - When using auto-resizing (non-resizable) fixed columns, querying the content width to use item right-alignment e.g. SetNextItemWidth(-FLT_MIN) doesn't make sense, would create a feedback loop.
//    - Using Stretch columns OFTEN DOES NOT MAKE SENSE if ScrollX is on, UNLESS you have specified a value for 'inner_width' in BeginTable().
//      If you specify a value for 'inner_width' then effectively the scrolling space is known and Stretch or mixed Fixed/Stretch columns become meaningful again.
// - Read on documentation at the top of imgui_tables.cpp for details.
TableFlags :: bit_set[TableFlag; i32]
TableFlag :: enum i32 {
	Resizable = 0, // Enable resizing columns.
	Reorderable = 1, // Enable reordering columns in header row. (Need calling TableSetupColumn() + TableHeadersRow() to display headers, or using ImGuiTableFlags_ContextMenuInBody to access context-menu without headers).
	Hideable = 2, // Enable hiding/disabling columns in context menu.
	Sortable = 3, // Enable sorting. Call TableGetSortSpecs() to obtain sort specs. Also see ImGuiTableFlags_SortMulti and ImGuiTableFlags_SortTristate.
	NoSavedSettings = 4, // Disable persisting columns order, width, visibility and sort settings in the .ini file.
	ContextMenuInBody = 5, // Right-click on columns body/contents will also display table context menu. By default it is available in TableHeadersRow().
	RowBg = 6, // Set each RowBg color with ImGuiCol_TableRowBg or ImGuiCol_TableRowBgAlt (equivalent of calling TableSetBgColor with ImGuiTableBgFlags_RowBg0 on each row manually)
	BordersInnerH = 7, // Draw horizontal borders between rows.
	BordersOuterH = 8, // Draw horizontal borders at the top and bottom.
	BordersInnerV = 9, // Draw vertical borders between columns.
	BordersOuterV = 10, // Draw vertical borders on the left and right sides.
	NoBordersInBody = 11, // [ALPHA] Disable vertical borders in columns Body (borders will always appear in Headers). -> May move to style
	NoBordersInBodyUntilResize = 12, // [ALPHA] Disable vertical borders in columns Body until hovered for resize (borders will always appear in Headers). -> May move to style
	SizingFixedFit = 13, // Columns default to _WidthFixed or _WidthAuto (if resizable or not resizable), matching contents width.
	SizingFixedSame = 14, // Columns default to _WidthFixed or _WidthAuto (if resizable or not resizable), matching the maximum contents width of all columns. Implicitly enable ImGuiTableFlags_NoKeepColumnsVisible.
	SizingStretchProp = 13, // Columns default to _WidthStretch with default weights proportional to each columns contents widths.
	SizingStretchSame = 15, // Columns default to _WidthStretch with default weights all equal, unless overridden by TableSetupColumn().
	NoHostExtendX = 16, // Make outer width auto-fit to columns, overriding outer_size.x value. Only available when ScrollX/ScrollY are disabled and Stretch columns are not used.
	NoHostExtendY = 17, // Make outer height stop exactly at outer_size.y (prevent auto-extending table past the limit). Only available when ScrollX/ScrollY are disabled. Data below the limit will be clipped and not visible.
	NoKeepColumnsVisible = 18, // Disable keeping column always minimally visible when ScrollX is off and table gets too small. Not recommended if columns are resizable.
	PreciseWidths = 19, // Disable distributing remainder width to stretched columns (width allocation on a 100-wide table with 3 columns: Without this flag: 33,33,34. With this flag: 33,33,33). With larger number of columns, resizing will appear to be less smooth.
	NoClip = 20, // Disable clipping rectangle for every individual columns (reduce draw command count, items will be able to overflow into other columns). Generally incompatible with TableSetupScrollFreeze().
	PadOuterX = 21, // Default if BordersOuterV is on. Enable outermost padding. Generally desirable if you have headers.
	NoPadOuterX = 22, // Default if BordersOuterV is off. Disable outermost padding.
	NoPadInnerX = 23, // Disable inner padding between columns (double inner padding if BordersOuterV is on, single inner padding if BordersOuterV is off).
	ScrollX = 24, // Enable horizontal scrolling. Require 'outer_size' parameter of BeginTable() to specify the container size. Changes default sizing policy. Because this creates a child window, ScrollY is currently generally recommended when using ScrollX.
	ScrollY = 25, // Enable vertical scrolling. Require 'outer_size' parameter of BeginTable() to specify the container size.
	SortMulti = 26, // Hold shift when clicking headers to sort on multiple column. TableGetSortSpecs() may return specs where (SpecsCount > 1).
	SortTristate = 27, // Allow no sorting, disable default sorting. TableGetSortSpecs() may return specs where (SpecsCount == 0).
	HighlightHoveredColumn = 28, // Highlight column headers when hovered (may evolve into a fuller highlight)
}

TABLE_FLAGS_BORDERS_H :: TableFlags{.BordersInnerH, .BordersOuterH}
TABLE_FLAGS_BORDERS_V :: TableFlags{.BordersInnerV, .BordersOuterV}
TABLE_FLAGS_BORDERS_INNER :: TableFlags{.BordersInnerV, .BordersInnerH}
TABLE_FLAGS_BORDERS_OUTER :: TableFlags{.BordersOuterV, .BordersOuterH}
TABLE_FLAGS_BORDERS :: TableFlags{.BordersInnerV, .BordersInnerH, .BordersOuterV, .BordersOuterH, }

// Flags for ImGui::TableSetupColumn()
TableColumnFlags :: bit_set[TableColumnFlag; i32]
TableColumnFlag :: enum i32 {
	Disabled = 0, // Overriding/master disable flag: hide column, won't show in context menu (unlike calling TableSetColumnEnabled() which manipulates the user accessible state)
	DefaultHide = 1, // Default as a hidden/disabled column.
	DefaultSort = 2, // Default as a sorting column.
	WidthStretch = 3, // Column will stretch. Preferable with horizontal scrolling disabled (default if table sizing policy is _SizingStretchSame or _SizingStretchProp).
	WidthFixed = 4, // Column will not stretch. Preferable with horizontal scrolling enabled (default if table sizing policy is _SizingFixedFit and table is resizable).
	NoResize = 5, // Disable manual resizing.
	NoReorder = 6, // Disable manual reordering this column, this will also prevent other columns from crossing over this column.
	NoHide = 7, // Disable ability to hide/disable this column.
	NoClip = 8, // Disable clipping for this column (all NoClip columns will render in a same draw command).
	NoSort = 9, // Disable ability to sort on this field (even if ImGuiTableFlags_Sortable is set on the table).
	NoSortAscending = 10, // Disable ability to sort in the ascending direction.
	NoSortDescending = 11, // Disable ability to sort in the descending direction.
	NoHeaderLabel = 12, // TableHeadersRow() will submit an empty label for this column. Convenient for some small columns. Name will still appear in context menu or in angled headers. You may append into this cell by calling TableSetColumnIndex() right after the TableHeadersRow() call.
	NoHeaderWidth = 13, // Disable header text width contribution to automatic column width.
	PreferSortAscending = 14, // Make the initial sort direction Ascending when first sorting on this column (default).
	PreferSortDescending = 15, // Make the initial sort direction Descending when first sorting on this column.
	IndentEnable = 16, // Use current Indent value when entering cell (default for column 0).
	IndentDisable = 17, // Ignore current Indent value when entering cell (default for columns > 0). Indentation changes _within_ the cell will still be honored.
	AngledHeader = 18, // TableHeadersRow() will submit an angled header row for this column. Note this will add an extra row.
	IsEnabled = 24, // Status: is enabled == not hidden by user/api (referred to as "Hide" in _DefaultHide and _NoHide) flags.
	IsVisible = 25, // Status: is visible == is enabled AND not clipped by scrolling.
	IsSorted = 26, // Status: is currently part of the sort specs
	IsHovered = 27, // Status: is hovered by mouse
}

// Flags for ImGui::TableNextRow()
TableRowFlags :: bit_set[TableRowFlag; i32]
TableRowFlag :: enum i32 {
	Headers = 0, // Identify header row (set default background color + width of its contents accounted differently for auto column width)
}

// Enum for ImGui::TableSetBgColor()
// Background colors are rendering in 3 layers:
//  - Layer 0: draw with RowBg0 color if set, otherwise draw with ColumnBg0 if set.
//  - Layer 1: draw with RowBg1 color if set, otherwise draw with ColumnBg1 if set.
//  - Layer 2: draw with CellBg color if set.
// The purpose of the two row/columns layers is to let you decide if a background color change should override or blend with the existing color.
// When using ImGuiTableFlags_RowBg on the table, each row has the RowBg0 color automatically set for odd/even rows.
// If you set the color of RowBg0 target, your color will override the existing RowBg0 color.
// If you set the color of RowBg1 or ColumnBg1 target, your color will blend over the RowBg0 color.
TableBgTarget :: enum i32 {
	None = 0,
	RowBg0 = 1, // Set row background color 0 (generally used for background, automatically set when ImGuiTableFlags_RowBg is used)
	RowBg1 = 2, // Set row background color 1 (generally used for selection marking)
	CellBg = 3, // Set cell background color (top-most color)
}

// Flags for ImGuiListClipper (currently not fully exposed in function calls: a future refactor will likely add this to ImGuiListClipper::Begin function equivalent)
ListClipperFlags :: bit_set[ListClipperFlag; i32]
ListClipperFlag :: enum i32 {
	NoSetTableRowCounters = 0, // [Internal] Disabled modifying table row counters. Avoid assumption that 1 clipper item == 1 table row.
}

// Flags for BeginMultiSelect()
MultiSelectFlags :: bit_set[MultiSelectFlag; i32]
MultiSelectFlag :: enum i32 {
	SingleSelect = 0, // Disable selecting more than one item. This is available to allow single-selection code to share same code/logic if desired. It essentially disables the main purpose of BeginMultiSelect() tho!
	NoSelectAll = 1, // Disable Ctrl+A shortcut to select all.
	NoRangeSelect = 2, // Disable Shift+selection mouse/keyboard support (useful for unordered 2D selection). With BoxSelect is also ensure contiguous SetRange requests are not combined into one. This allows not handling interpolation in SetRange requests.
	NoAutoSelect = 3, // Disable selecting items when navigating (useful for e.g. supporting range-select in a list of checkboxes).
	NoAutoClear = 4, // Disable clearing selection when navigating or selecting another one (generally used with ImGuiMultiSelectFlags_NoAutoSelect. useful for e.g. supporting range-select in a list of checkboxes).
	NoAutoClearOnReselect = 5, // Disable clearing selection when clicking/selecting an already selected item.
	BoxSelect1d = 6, // Enable box-selection with same width and same x pos items (e.g. full row Selectable()). Box-selection works better with little bit of spacing between items hit-box in order to be able to aim at empty space.
	BoxSelect2d = 7, // Enable box-selection with varying width or varying x pos items support (e.g. different width labels, or 2D layout/grid). This is slower: alters clipping logic so that e.g. horizontal movements will update selection of normally clipped items.
	BoxSelectNoScroll = 8, // Disable scrolling when box-selecting and moving mouse near edges of scope.
	ClearOnEscape = 9, // Clear selection when pressing Escape while scope is focused.
	ClearOnClickVoid = 10, // Clear selection when clicking on empty location within scope.
	ScopeWindow = 11, // Scope for _BoxSelect and _ClearOnClickVoid is whole window (Default). Use if BeginMultiSelect() covers a whole window or used a single time in same window.
	ScopeRect = 12, // Scope for _BoxSelect and _ClearOnClickVoid is rectangle encompassing BeginMultiSelect()/EndMultiSelect(). Use if BeginMultiSelect() is called multiple times in same window.
	SelectOnAuto = 13, // Apply selection on mouse down when clicking on unselected item, on mouse up when clicking on selected item. (Default)
	SelectOnClickAlways = 14, // Apply selection on mouse down when clicking on any items. Prevents Drag and Drop from being used on multiple-selection, but allows e.g. BoxSelect to always reselect even when clicking inside an existing selection. (Excel style behavior)
	SelectOnClickRelease = 15, // Apply selection on mouse release when clicking an unselected item. Allow dragging an unselected item without altering selection.
	NavWrapX = 16, // [Temporary] Enable navigation wrapping on X axis. Provided as a convenience because we don't have a design for the general Nav API for this yet. When the more general feature be public we may obsolete this flag in favor of new one.
	NoSelectOnRightClick = 17, // Disable default right-click processing, which selects item on mouse down, and is designed for context-menus.
}

// Selection request type
SelectionRequestType :: enum i32 {
	None = 0,
	SetAll = 1, // Request app to clear selection (if Selected==false) or select all items (if Selected==true). We cannot set RangeFirstItem/RangeLastItem as its contents is entirely up to user (not necessarily an index)
	SetRange = 2, // Request app to select/unselect [RangeFirstItem..RangeLastItem] items (inclusive) based on value of Selected. Only EndMultiSelect() request this, app code can read after BeginMultiSelect() and it will always be false.
}

// Flags for ImDrawList functions
DrawFlags :: bit_set[DrawFlag; i32]
DrawFlag :: enum i32 {
	RoundCornersTopLeft = 4, // Round top-left corner only (when rounding > 0.0f, we default to all corners).
	RoundCornersTopRight = 5, // Round top-right corner only (when rounding > 0.0f, we default to all corners).
	RoundCornersBottomLeft = 6, // Round bottom-left corner only (when rounding > 0.0f, we default to all corners).
	RoundCornersBottomRight = 7, // Round bottom-right corner only (when rounding > 0.0f, we default to all corners).
	RoundCornersNone = 8, // Disable rounding even if `float rounding > 0.0f`. This is NOT zero, NOT an implicit flag!
	Closed = 9, // PathStroke(), AddPolyline(): specify that shape should be closed.
}

DRAW_FLAGS_ROUND_CORNERS_ALL :: DrawFlags{.RoundCornersTopLeft, .RoundCornersTopRight, .RoundCornersBottomLeft, .RoundCornersBottomRight}
DRAW_FLAGS_ROUND_CORNERS_TOP :: DrawFlags{.RoundCornersTopLeft, .RoundCornersTopRight}
DRAW_FLAGS_ROUND_CORNERS_BOTTOM :: DrawFlags{.RoundCornersBottomLeft, .RoundCornersBottomRight}
DRAW_FLAGS_ROUND_CORNERS_LEFT :: DrawFlags{.RoundCornersBottomLeft, .RoundCornersTopLeft}
DRAW_FLAGS_ROUND_CORNERS_RIGHT :: DrawFlags{.RoundCornersBottomRight, .RoundCornersTopRight}

// Flags for ImDrawList instance. Those are set automatically by ImGui:: functions from ImGuiIO settings, and generally not manipulated directly.
// It is however possible to temporarily alter flags between calls to ImDrawList:: functions.
DrawListFlags :: bit_set[DrawListFlag; i32]
DrawListFlag :: enum i32 {
	AntiAliasedLines = 0, // Enable anti-aliased lines/borders (*2 the number of triangles for 1.0f wide line or lines thin enough to be drawn using textures, otherwise *3 the number of triangles)
	AntiAliasedLinesUseTex = 1, // Enable anti-aliased lines/borders using textures when possible. Require backend to render with bilinear filtering (NOT point/nearest filtering).
	AntiAliasedFill = 2, // Enable anti-aliased edge around filled shapes (rounded rectangles, circles).
	AllowVtxOffset = 3, // Can emit 'VtxOffset > 0' to allow large meshes. Set when 'ImGuiBackendFlags_RendererHasVtxOffset' is enabled.
	TextNoPixelSnap = 4, // Disable automatically snapping AddText() calls to pixel boundaries.
}

// Most standard backends only support RGBA32 but we provide a single channel option for low-resource/embedded systems.
TextureFormat :: enum i32 {
	RGBA32 = 0, // 4 components per pixel, each is unsigned 8-bit. Total size = TexWidth * TexHeight * 4
	Alpha8 = 1, // 1 component per pixel, each is unsigned 8-bit. Total size = TexWidth * TexHeight
}

// Status of a texture to communicate with Renderer Backend.
TextureStatus :: enum i32 {
	OK = 0,
	Destroyed = 1, // Backend destroyed the texture.
	WantCreate = 2, // Requesting backend to create the texture. Set status OK when done.
	WantUpdates = 3, // Requesting backend to update specific blocks of pixels (write to texture portions which have never been used before). Set status OK when done.
	WantDestroy = 4, // Requesting backend to destroy the texture. Set status to Destroyed when done.
}

// Flags for ImFontAtlas build
FontAtlasFlags :: bit_set[FontAtlasFlag; i32]
FontAtlasFlag :: enum i32 {
	NoPowerOfTwoHeight = 0, // Don't round the height to next power of two
	NoMouseCursors = 1, // Don't build software mouse cursors into the atlas (save a little texture memory)
	NoBakedLines = 2, // Don't build thick line textures into the atlas (save a little texture memory, allow support for point/nearest filtering). The AntiAliasedLinesUseTex features uses them, otherwise they will be rendered using polygons (more expensive for CPU/GPU).
}

// Font flags
// (in future versions as we redesign font loading API, this will become more important and better documented. for now please consider this as internal/advanced use)
FontFlags :: bit_set[FontFlag; i32]
FontFlag :: enum i32 {
	NoLoadError = 1, // Disable throwing an error/assert when calling AddFontXXX() with missing file/data. Calling code is expected to check AddFontXXX() return value.
	NoLoadGlyphs = 2, // [Internal] Disable loading new glyphs.
	LockBakedSizes = 3, // [Internal] Disable loading new baked sizes, disable garbage collecting current ones. e.g. if you want to lock a font to a single size. Important: if you use this to preload given sizes, consider the possibility of multiple font density used on Retina display.
	ImplicitRefSize = 4, // [Internal] Reference size was not set explicitly.
}

// Flags stored in ImGuiViewport::Flags, giving indications to the platform backends.
ViewportFlags :: bit_set[ViewportFlag; i32]
ViewportFlag :: enum i32 {
	IsPlatformWindow = 0, // Represent a Platform Window
	IsPlatformMonitor = 1, // Represent a Platform Monitor (unused yet)
	OwnedByApp = 2, // Platform Window: Is created/managed by the user application? (rather than our backend)
	NoDecoration = 3, // Platform Window: Disable platform decorations: title bar, borders, etc. (generally set all windows, but if ImGuiConfigFlags_ViewportsDecoration is set we only set this on popups/tooltips)
	NoTaskBarIcon = 4, // Platform Window: Disable platform task bar icon (generally set on popups/tooltips, or all windows if ImGuiConfigFlags_ViewportsNoTaskBarIcon is set)
	NoFocusOnAppearing = 5, // Platform Window: Don't take focus when created.
	NoFocusOnClick = 6, // Platform Window: Don't take focus when clicked on.
	NoInputs = 7, // Platform Window: Make mouse pass through so we can drag this window while peaking behind it.
	NoRendererClear = 8, // Platform Window: Renderer doesn't need to clear the framebuffer ahead (because we will fill it entirely).
	NoAutoMerge = 9, // Platform Window: Avoid merging this window into another host window. This can only be set via ImGuiWindowClass viewport flags override (because we need to now ahead if we are going to create a viewport in the first place!).
	TopMost = 10, // Platform Window: Display on top (for tooltips only).
	CanHostOtherWindows = 11, // Viewport can host multiple imgui windows (secondary viewports are associated to a single window). // FIXME: In practice there's still probably code making the assumption that this is always and only on the MainViewport. Will fix once we add support for "no main viewport".
	IsMinimized = 12, // Platform Window: Window is minimized, can skip render. When minimized we tend to avoid using the viewport pos/size for clipping window or testing if they are contained in the viewport.
	IsFocused = 13, // Platform Window: Window is focused (last call to Platform_GetWindowFocus() returned true)
}

DrawIdx :: u16
ID :: u32
DrawTextFlags :: i32
KeyChord :: i32
Wchar32 :: u32
Wchar16 :: u16
Wchar :: Wchar16
SelectionUserData :: i64
InputTextCallback :: #type proc(data: ^InputTextCallbackData) -> i32
SizeCallback :: #type proc(data: ^SizeCallbackData)
MemAllocFunc :: #type proc(sz: uint, user_data: rawptr) -> rawptr
MemFreeFunc :: #type proc(ptr: rawptr, user_data: rawptr)
TextureID :: u64
DrawCallback :: #type proc(parent_list: ^DrawList, cmd: ^DrawCmd)
FontAtlasRectId :: i32
FontAtlasCustomRect :: FontAtlasRect

DrawListSharedData :: struct {}

FontAtlasBuilder :: struct {}

FontLoader :: struct {}

// Forward declarations: ImGui layer
Context :: struct {}

Vec2 :: [2]f32

// ImVec4: 4D vector used to store clipping rectangles, colors etc. [Compile-time configurable type]
Vec4 :: [4]f32

TextureRef :: struct {
	_TexData: ^TextureData, //      A texture, generally owned by a ImFontAtlas. Will convert to ImTextureID during render loop, after texture has been uploaded.
	_TexID: TextureID, // _OR_ Low-level backend texture identifier, if already uploaded or created by user/app. Generally provided to e.g. ImGui::Image() calls.
}

// Sorting specifications for a table (often handling sort specs for a single column, occasionally more)
// Obtained by calling TableGetSortSpecs().
// When 'SpecsDirty == true' you can sort your data. It will be true with sorting specs have changed since last call, or the first time.
// Make sure to set 'SpecsDirty = false' after sorting, else you may wastefully sort your data every frame!
TableSortSpecs :: struct {
	Specs: ^TableColumnSortSpecs, // Pointer to sort spec array.
	SpecsCount: i32, // Sort spec count. Most often 1. May be > 1 when ImGuiTableFlags_SortMulti is enabled. May be == 0 when ImGuiTableFlags_SortTristate is enabled.
	SpecsDirty: bool, // Set to true when specs have changed since last time! Use this to sort again, then clear the flag.
}

// Sorting specification for one column of a table (sizeof == 12 bytes)
TableColumnSortSpecs :: struct {
	ColumnUserID: ID, // User data for the column (if specified by a TableSetupColumn() call in the 'ImGuiID user_data' field). FIXME: Should be called 'UserData'..
	ColumnIndex: i16, // Index of the column
	SortOrder: i16, // Index within parent ImGuiTableSortSpecs (always stored in order starting from 0, tables sorted on a single criteria will always have a 0 here)
	SortDirection: SortDirection, // ImGuiSortDirection_Ascending or ImGuiSortDirection_Descending
}

Vector_TextRange :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]TextFilter_TextRange,
}

Vector_char :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]u8,
}

Vector_StoragePair :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]StoragePair,
}

Vector_SelectionRequest :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]SelectionRequest,
}

Vector_DrawChannel :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]DrawChannel,
}

Vector_DrawCmd :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]DrawCmd,
}

Vector_DrawIdx :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]DrawIdx,
}

Vector_DrawVert :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]DrawVert,
}

Vector_Vec2 :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]Vec2,
}

Vector_Vec4 :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]Vec4,
}

Vector_TextureRef :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]TextureRef,
}

Vector_U8 :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]u8,
}

Vector_DrawListPtr :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]^DrawList,
}

Vector_TextureRect :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]TextureRect,
}

Vector_U32 :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]u32,
}

Vector_Wchar :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]Wchar,
}

Vector_FontPtr :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]^Font,
}

Vector_FontConfig :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]FontConfig,
}

Vector_DrawListSharedDataPtr :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]^DrawListSharedData,
}

Vector_float :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]f32,
}

Vector_U16 :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]u16,
}

Vector_FontGlyph :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]FontGlyph,
}

Vector_FontConfigPtr :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]^FontConfig,
}

Vector_PlatformMonitor :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]PlatformMonitor,
}

Vector_TextureDataPtr :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]^TextureData,
}

Vector_ViewportPtr :: struct {
	Size: i32,
	Capacity: i32,
	Data: [^]^Viewport,
}

Style :: struct {
	FontSizeBase: f32, // Current base font size before external global factors are applied. Use PushFont(NULL, size) to modify. Use ImGui::GetFontSize() to obtain scaled value.
	FontScaleMain: f32, // Main global scale factor. May be set by application once, or exposed to end-user.
	FontScaleDpi: f32, // Additional global scale factor from viewport/monitor contents scale. In docking branch: when io.ConfigDpiScaleFonts is enabled, this is automatically overwritten when changing monitor DPI.
	Alpha: f32, // Global alpha applies to everything in Dear ImGui.
	DisabledAlpha: f32, // Additional alpha multiplier applied by BeginDisabled(). Multiply over current value of Alpha.
	WindowPadding: Vec2, // Padding within a window.
	WindowRounding: f32, // Radius of window corners rounding. Set to 0.0f to have rectangular windows. Large values tend to lead to variety of artifacts and are not recommended.
	WindowBorderSize: f32, // Thickness of border around windows. Generally set to 0.0f or 1.0f. (Other values are not well tested and more CPU/GPU costly).
	WindowBorderHoverPadding: f32, // Hit-testing extent outside/inside resizing border. Also extend determination of hovered window. Generally meaningfully larger than WindowBorderSize to make it easy to reach borders.
	WindowMinSize: Vec2, // Minimum window size. This is a global setting. If you want to constrain individual windows, use SetNextWindowSizeConstraints().
	WindowTitleAlign: Vec2, // Alignment for title bar text. Defaults to (0.0f,0.5f) for left-aligned,vertically centered.
	WindowMenuButtonPosition: Dir, // Side of the collapsing/docking button in the title bar (None/Left/Right). Defaults to ImGuiDir_Left.
	ChildRounding: f32, // Radius of child window corners rounding. Set to 0.0f to have rectangular windows.
	ChildBorderSize: f32, // Thickness of border around child windows. Generally set to 0.0f or 1.0f. (Other values are not well tested and more CPU/GPU costly).
	PopupRounding: f32, // Radius of popup window corners rounding. (Note that tooltip windows use WindowRounding)
	PopupBorderSize: f32, // Thickness of border around popup/tooltip windows. Generally set to 0.0f or 1.0f. (Other values are not well tested and more CPU/GPU costly).
	FramePadding: Vec2, // Padding within a framed rectangle (used by most widgets).
	FrameRounding: f32, // Radius of frame corners rounding. Set to 0.0f to have rectangular frame (used by most widgets).
	FrameBorderSize: f32, // Thickness of border around frames. Generally set to 0.0f or 1.0f. (Other values are not well tested and more CPU/GPU costly).
	ItemSpacing: Vec2, // Horizontal and vertical spacing between widgets/lines.
	ItemInnerSpacing: Vec2, // Horizontal and vertical spacing between within elements of a composed widget (e.g. a slider and its label).
	CellPadding: Vec2, // Padding within a table cell. Cellpadding.x is locked for entire table. CellPadding.y may be altered between different rows.
	TouchExtraPadding: Vec2, // Expand reactive bounding box for touch-based system where touch position is not accurate enough. Unfortunately we don't sort widgets so priority on overlap will always be given to the first widget. So don't grow this too much!
	IndentSpacing: f32, // Horizontal indentation when e.g. entering a tree node. Generally == (FontSize + FramePadding.x*2).
	ColumnsMinSpacing: f32, // Minimum horizontal spacing between two columns. Preferably > (FramePadding.x + 1).
	ScrollbarSize: f32, // Width of the vertical scrollbar, Height of the horizontal scrollbar.
	ScrollbarRounding: f32, // Radius of grab corners for scrollbar.
	ScrollbarPadding: f32, // Padding of scrollbar grab within its frame (same for both axes).
	GrabMinSize: f32, // Minimum width/height of a grab box for slider/scrollbar.
	GrabRounding: f32, // Radius of grabs corners rounding. Set to 0.0f to have rectangular slider grabs.
	LogSliderDeadzone: f32, // The size in pixels of the dead-zone around zero on logarithmic sliders that cross zero.
	ImageRounding: f32, // Rounding of Image() calls.
	ImageBorderSize: f32, // Thickness of border around Image() calls.
	TabRounding: f32, // Radius of upper corners of a tab. Set to 0.0f to have rectangular tabs.
	TabBorderSize: f32, // Thickness of border around tabs.
	TabMinWidthBase: f32, // Minimum tab width, to make tabs larger than their contents. TabBar buttons are not affected.
	TabMinWidthShrink: f32, // Minimum tab width after shrinking, when using ImGuiTabBarFlags_FittingPolicyMixed policy.
	TabCloseButtonMinWidthSelected: f32, // -1: always visible. 0.0f: visible when hovered. >0.0f: visible when hovered if minimum width. FLT_MAX: never shrink, will behave like ImGuiTabBarFlags_FittingPolicyScroll.
	TabCloseButtonMinWidthUnselected: f32, // -1: always visible. 0.0f: visible when hovered. >0.0f: visible when hovered if minimum width. FLT_MAX: never show close button when unselected.
	TabBarBorderSize: f32, // Thickness of tab-bar separator, which takes on the tab active color to denote focus.
	TabBarOverlineSize: f32, // Thickness of tab-bar overline, which highlights the selected tab-bar.
	TableAngledHeadersAngle: f32, // Angle of angled headers (supported values range from -50.0f degrees to +50.0f degrees).
	TableAngledHeadersTextAlign: Vec2, // Alignment of angled headers within the cell
	TreeLinesFlags: TreeNodeFlags, // Default way to draw lines connecting TreeNode hierarchy. ImGuiTreeNodeFlags_DrawLinesNone or ImGuiTreeNodeFlags_DrawLinesFull or ImGuiTreeNodeFlags_DrawLinesToNodes.
	TreeLinesSize: f32, // Thickness of outlines when using ImGuiTreeNodeFlags_DrawLines.
	TreeLinesRounding: f32, // Radius of lines connecting child nodes to the vertical line.
	MenuItemRounding: f32, // Radius of MenuItem, BeginMenu rounding.
	SelectableRounding: f32, // Radius of Selectable rounding. MODIFYING THIS IS DISCOURAGED. CONTIGUOUS SELECTIONS WILL NOT LOOK RIGHT. (#7589)
	DragDropTargetRounding: f32, // Radius of the drag and drop target frame. When <0.0f: use FrameRounding.
	DragDropTargetBorderSize: f32, // Thickness of the drag and drop target border.
	DragDropTargetPadding: f32, // Size to expand the drag and drop target from actual target item size.
	ColorMarkerSize: f32, // Size of R/G/B/A color markers for ColorEdit4() and for Drags/Sliders when using ImGuiSliderFlags_ColorMarkers.
	ColorButtonPosition: Dir, // Side of the color button in the ColorEdit4 widget (left/right). Defaults to ImGuiDir_Right.
	ButtonTextAlign: Vec2, // Alignment of button text when button is larger than text. Defaults to (0.5f, 0.5f) (centered).
	SelectableTextAlign: Vec2, // Alignment of selectable text. Defaults to (0.0f, 0.0f) (top-left aligned). It's generally important to keep this left-aligned if you want to lay multiple items on a same line.
	InputTextCursorSize: f32, // Thickness of cursor/caret in InputText().
	SeparatorSize: f32, // Thickness of border in Separator(). Must be >= 1.0f.
	SeparatorTextBorderSize: f32, // Thickness of border in SeparatorText()
	SeparatorTextAlign: Vec2, // Alignment of text within the separator. Defaults to (0.0f, 0.5f) (left aligned, center).
	SeparatorTextPadding: Vec2, // Horizontal offset of text from each edge of the separator + spacing on other axis. Generally small values. .y is recommended to be == FramePadding.y.
	DisplayWindowPadding: Vec2, // Apply to regular windows: amount which we enforce to keep visible when moving near edges of your screen.
	DisplaySafeAreaPadding: Vec2, // Apply to every windows, menus, popups, tooltips: amount where we avoid displaying contents. Adjust if you cannot see the edges of your screen (e.g. on a TV where scaling has not been configured).
	DockingNodeHasCloseButton: bool, // Docking node has their own CloseButton() to close all docked windows.
	DockingSeparatorSize: f32, // Thickness of resizing border between docked windows
	MouseCursorScale: f32, // Scale software rendered mouse cursor (when io.MouseDrawCursor is enabled). We apply per-monitor DPI scaling over this scale. May be removed later.
	AntiAliasedLines: bool, // Enable anti-aliased lines/borders. Disable if you are really tight on CPU/GPU. Latched at the beginning of the frame (copied to ImDrawList).
	AntiAliasedLinesUseTex: bool, // Enable anti-aliased lines/borders using textures where possible. Require backend to render with bilinear filtering (NOT point/nearest filtering). Latched at the beginning of the frame (copied to ImDrawList).
	AntiAliasedFill: bool, // Enable anti-aliased edges around filled shapes (rounded rectangles, circles, etc.). Disable if you are really tight on CPU/GPU. Latched at the beginning of the frame (copied to ImDrawList).
	CurveTessellationTol: f32, // Tessellation tolerance when using PathBezierCurveTo() without a specific number of segments. Decrease for highly tessellated curves (higher quality, more polygons), increase to reduce quality.
	CircleTessellationMaxError: f32, // Maximum error (in pixels) allowed when using AddCircle()/AddCircleFilled() or drawing rounded corner rectangles with no explicit segment count specified. Decrease for higher quality but more geometry.
	Colors: [COL_COUNT]Vec4,
	HoverStationaryDelay: f32, // Delay for IsItemHovered(ImGuiHoveredFlags_Stationary). Time required to consider mouse stationary.
	HoverDelayShort: f32, // Delay for IsItemHovered(ImGuiHoveredFlags_DelayShort). Usually used along with HoverStationaryDelay.
	HoverDelayNormal: f32, // Delay for IsItemHovered(ImGuiHoveredFlags_DelayNormal). "
	HoverFlagsForTooltipMouse: HoveredFlags, // Default flags when using IsItemHovered(ImGuiHoveredFlags_ForTooltip) or BeginItemTooltip()/SetItemTooltip() while using mouse.
	HoverFlagsForTooltipNav: HoveredFlags, // Default flags when using IsItemHovered(ImGuiHoveredFlags_ForTooltip) or BeginItemTooltip()/SetItemTooltip() while using keyboard/gamepad.
	_MainScale: f32, // FIXME-WIP: Reference scale, as applied by ScaleAllSizes(). PLEASE DO NOT USE THIS FOR NOW.
	_NextFrameFontSizeBase: f32, // FIXME: Temporary hack until we finish remaining work.
}

// [Internal] Storage used by IsKeyDown(), IsKeyPressed() etc functions.
// If prior to 1.87 you used io.KeysDownDuration[] (which was marked as internal), you should use GetKeyData(key)->DownDuration and *NOT* io.KeysData[key]->DownDuration.
KeyData :: struct {
	Down: bool, // True for if key is down
	DownDuration: f32, // Duration the key has been down (<0.0f: not pressed, 0.0f: just pressed, >0.0f: time held)
	DownDurationPrev: f32, // Last frame duration the key has been down
	AnalogValue: f32, // 0.0f..1.0f for gamepad values
}

IO :: struct {
	ConfigFlags: ConfigFlags, // = 0              // See ImGuiConfigFlags_ enum. Set by user/application. Keyboard/Gamepad navigation options, etc.
	BackendFlags: BackendFlags, // = 0              // See ImGuiBackendFlags_ enum. Set by backend (imgui_impl_xxx files or custom backend) to communicate features supported by the backend.
	DisplaySize: Vec2, // <unset>          // Main display size, in pixels (== GetMainViewport()->Size). May change every frame.
	DisplayFramebufferScale: Vec2, // = (1, 1)         // Main display density. For retina display where window coordinates are different from framebuffer coordinates. This will affect font density + will end up in ImDrawData::FramebufferScale.
	DeltaTime: f32, // = 1.0f/60.0f     // Time elapsed since last frame, in seconds. May change every frame.
	IniSavingRate: f32, // = 5.0f           // Minimum time between saving positions/sizes to .ini file, in seconds.
	IniFilename: cstring, // = "imgui.ini"    // Path to .ini file (important: default "imgui.ini" is relative to current working dir!). Set NULL to disable automatic .ini loading/saving or if you want to manually call LoadIniSettingsXXX() / SaveIniSettingsXXX() functions.
	LogFilename: cstring, // = "imgui_log.txt"// Path to .log file (default parameter to ImGui::LogToFile when no file is specified).
	UserData: rawptr, // = NULL           // Store your own data.
	Fonts: ^FontAtlas, // <auto>           // Font atlas: load, rasterize and pack one or more fonts into a single texture.
	FontDefault: ^Font, // = NULL           // Font to use on NewFrame(). Use NULL to uses Fonts->Fonts[0].
	FontAllowUserScaling: bool, // = false          // Allow user scaling text of individual window with Ctrl+Wheel.
	ConfigNavSwapGamepadButtons: bool, // = false          // Swap Activate<>Cancel (A<>B) buttons, matching typical "Nintendo/Japanese style" gamepad layout.
	ConfigNavMoveSetMousePos: bool, // = false          // Directional/tabbing navigation teleports the mouse cursor. May be useful on TV/console systems where moving a virtual mouse is difficult. Will update io.MousePos and set io.WantSetMousePos=true.
	ConfigNavCaptureKeyboard: bool, // = true           // Sets io.WantCaptureKeyboard when io.NavActive is set.
	ConfigNavEscapeClearFocusItem: bool, // = true           // Pressing Escape can clear focused item + navigation id/highlight. Set to false if you want to always keep highlight on.
	ConfigNavEscapeClearFocusWindow: bool, // = false          // Pressing Escape can clear focused window as well (super set of io.ConfigNavEscapeClearFocusItem).
	ConfigNavCursorVisibleAuto: bool, // = true           // Using directional navigation key makes the cursor visible. Mouse click hides the cursor.
	ConfigNavCursorVisibleAlways: bool, // = false          // Navigation cursor is always visible.
	ConfigDockingNoSplit: bool, // = false          // Simplified docking mode: disable window splitting, so docking is limited to merging multiple windows together into tab-bars.
	ConfigDockingNoDockingOver: bool, // = false          // Simplified docking mode: disable window merging into a same tab-bar, so docking is limited to splitting windows.
	ConfigDockingWithShift: bool, // = false          // Enable docking with holding Shift key (reduce visual noise, allows dropping in wider space)
	ConfigDockingAlwaysTabBar: bool, // = false          // [BETA] [FIXME: This currently creates regression with auto-sizing and general overhead] Make every single floating window display within a docking node.
	ConfigDockingTransparentPayload: bool, // = false          // [BETA] Make window or viewport transparent when docking and only display docking boxes on the target viewport. Useful if rendering of multiple viewport cannot be synced. Best used with ConfigViewportsNoAutoMerge.
	ConfigViewportsNoAutoMerge: bool, // = false;         // Set to make all floating imgui windows always create their own viewport. Otherwise, they are merged into the main host viewports when overlapping it. May also set ImGuiViewportFlags_NoAutoMerge on individual viewport.
	ConfigViewportsNoTaskBarIcon: bool, // = false          // Disable default OS task bar icon flag for secondary viewports. When a viewport doesn't want a task bar icon, ImGuiViewportFlags_NoTaskBarIcon will be set on it.
	ConfigViewportsNoDecoration: bool, // = true           // Disable default OS window decoration flag for secondary viewports. When a viewport doesn't want window decorations, ImGuiViewportFlags_NoDecoration will be set on it. Enabling decoration can create subsequent issues at OS levels (e.g. minimum window size).
	ConfigViewportsNoDefaultParent: bool, // = true           // Disable setting OS window parent to main viewport by default. The platform backend is expected to honor `viewport->ParentViewportID` to setup a parent/child relationship between the OS windows (supported if ImGuiBackendFlags_HasParentViewport is set). When parented: child windows always appear in front of their parent. Set to false if you want viewports to automatically be parent of main viewport, otherwise all viewports will be top-level OS windows. Parent/child relationship may be set on a per-window basis using ImGuiWindowClass.
	ConfigViewportsPlatformFocusSetsImGuiFocus: bool, //= true // When a platform window is focused (e.g. using Alt+Tab, clicking Platform Title Bar), apply corresponding focus on imgui windows (may clear focus/active id from imgui windows location in other platform windows). In principle this is better enabled but we provide an opt-out, because some Linux window managers tend to eagerly focus windows (e.g. on mouse hover, or even a simple window pos/size change).
	ConfigDpiScaleFonts: bool, // = false          // [EXPERIMENTAL] Automatically overwrite style.FontScaleDpi when Monitor DPI changes. This will scale fonts but _NOT_ scale sizes/padding for now.
	ConfigDpiScaleViewports: bool, // = false          // [EXPERIMENTAL] Scale Dear ImGui and Platform Windows when Monitor DPI changes.
	ConfigMacOSXBehaviors: bool, // = defined(__APPLE__) // Swap Cmd<>Ctrl keys + OS X style text editing cursor movement using Alt instead of Ctrl, Shortcuts using Cmd/Super instead of Ctrl, Line/Text Start and End using Cmd+Arrows instead of Home/End, Double click selects by word instead of selecting whole text, Multi-selection in lists uses Cmd/Super instead of Ctrl.
	ConfigInputTrickleEventQueue: bool, // = true           // Enable input queue trickling: some types of events submitted during the same frame (e.g. button down + up) will be spread over multiple frames, improving interactions with low framerates.
	ConfigInputTextCursorBlink: bool, // = true           // Enable blinking cursor (optional as some users consider it to be distracting).
	ConfigInputTextEnterKeepActive: bool, // = false          // [BETA] Pressing Enter will reactivate item and select all text (single-line only). Ctrl+Enter or Shift+Enter will deactivate normally.
	ConfigColorEditFlags: ColorEditFlags, // = <defaults>     // Current settings for ColorEdit/ColorPicker widgets. Must have one bit of ImGuiColorEditFlags_DisplayMask_, one bit of ImGuiColorEditFlags_DataTypeMask_, one bit of ImGuiColorEditFlags_PickerMask_, one bit of ImGuiColorEditFlags_InputMask_. Defaults to ImGuiColorEditFlags_DefaultOptions_. May be further edited by users, unless you also set ImGuiColorEditFlags_NoOptions.
	ConfigDragClickToInputText: bool, // = false          // [BETA] Enable turning DragXXX widgets into text input with a simple mouse click-release (without moving). Not desirable on devices without a keyboard.
	ConfigWindowsResizeFromEdges: bool, // = true           // Enable resizing of windows from their edges and from the lower-left corner. This requires ImGuiBackendFlags_HasMouseCursors for better mouse cursor feedback. (This used to be a per-window ImGuiWindowFlags_ResizeFromAnySide flag)
	ConfigWindowsMoveFromTitleBarOnly: bool, // = false      // Enable allowing to move windows only when clicking on their title bar. Does not apply to windows without a title bar.
	ConfigWindowsCopyContentsWithCtrlC: bool, // = false      // [EXPERIMENTAL] Ctrl+C copy the contents of focused window into the clipboard. Experimental because: (1) has known issues with nested Begin/End pairs (2) text output quality varies (3) text output is in submission order rather than spatial order.
	ConfigScrollbarScrollByPage: bool, // = true           // Enable scrolling page by page when clicking outside the scrollbar grab. When disabled, always scroll to clicked location. When enabled, Shift+Click scrolls to clicked location.
	ConfigIniSettingsSaveLastUsedDate: bool, // = true         // Enable loading/saving last used day (YYYYMMDD) in some .ini struct, making things easier to audit and allowing custom tools to cleanup old data.
	ConfigIniSettingsAutoDiscardMonths: i32, // = 0          // [BETA] Set number of months after which unused .ini entries are discarded on load. Require platform_io.Platform_SessionDate to be set. For systems supporting the feature, .ini entries without a LastUsed field will always be discarded! Please report if you are using this.
	ConfigDebugIniSettings: bool, // = false          // Save .ini data with extra comments (particularly helpful for Docking, but makes saving slower)
	MouseDrawCursor: bool, // = false          // Request ImGui to draw a mouse cursor for you (if you are on a platform without a mouse cursor). Cannot be easily renamed to 'io.ConfigXXX' because this is frequently used by backend implementations.
	ConfigMemoryCompactTimer: f32, // = 60.0f          // Timer (in seconds) to free transient windows/tables memory buffers when unused. Set to -1.0f to disable.
	MouseDoubleClickTime: f32, // = 0.30f          // Time for consecutive clicks to account as a double-click, in seconds.
	MouseDoubleClickMaxDist: f32, // = 6.0f           // Distance threshold to stay in to validate a double-click or multiple clicks, in pixels.
	MouseSingleClickDelay: f32, // = 0.60f          // Time for a delayed click when using GetItemClickedCountWithSingleClickDelay() or IsMouseReleasedWithDelay(), in seconds. Must be > io.MouseDoubleClickTime.
	MouseDragThreshold: f32, // = 6.0f           // Distance threshold before considering we are dragging.
	KeyRepeatDelay: f32, // = 0.275f         // When holding a key/button, time before it starts repeating, in seconds (for buttons in Repeat mode, etc.).
	KeyRepeatRate: f32, // = 0.050f         // When holding a key/button, rate at which it repeats, in seconds.
	ConfigErrorRecovery: bool, // = true       // Enable error recovery support. Some errors won't be detected and lead to direct crashes if recovery is disabled.
	ConfigErrorRecoveryEnableAssert: bool, // = true       // Enable asserts on recoverable error. By default call IM_ASSERT() when returning from a failing IM_ASSERT_USER_ERROR()
	ConfigErrorRecoveryEnableDebugLog: bool, // = true       // Enable debug log output on recoverable errors.
	ConfigErrorRecoveryEnableTooltip: bool, // = true       // Enable tooltip on recoverable errors. The tooltip include a way to enable asserts if they were disabled.
	ConfigDebugIsDebuggerPresent: bool, // = false          // Enable various tools calling IM_DEBUG_BREAK().
	ConfigDebugHighlightIdConflicts: bool, // = true           // Highlight and show an error message popup when multiple items have conflicting identifiers.
	ConfigDebugHighlightIdConflictsShowItemPicker: bool, //=true // Show "Item Picker" button in aforementioned popup.
	ConfigDebugBeginReturnValueOnce: bool, // = false          // First-time calls to Begin()/BeginChild() will return false. NEEDS TO BE SET AT APPLICATION BOOT TIME if you don't want to miss windows.
	ConfigDebugBeginReturnValueLoop: bool, // = false          // Some calls to Begin()/BeginChild() will return false. Will cycle through window depths then repeat. Suggested use: add "io.ConfigDebugBeginReturnValue = io.KeyShift" in your main loop then occasionally press SHIFT. Windows should be flickering while running.
	ConfigDebugIgnoreFocusLoss: bool, // = false          // Ignore io.AddFocusEvent(false), consequently not calling io.ClearInputKeys()/io.ClearInputMouse() in input processing.
	BackendPlatformName: cstring, // = NULL
	BackendRendererName: cstring, // = NULL
	BackendPlatformUserData: rawptr, // = NULL           // User data for platform backend
	BackendRendererUserData: rawptr, // = NULL           // User data for renderer backend
	BackendLanguageUserData: rawptr, // = NULL           // User data for non C++ programming language backend
	WantCaptureMouse: bool, // Set when Dear ImGui will use mouse inputs, in this case do not dispatch them to your main game/application (either way, always pass on mouse inputs to imgui). (e.g. unclicked mouse is hovering over an imgui window, widget is active, mouse was clicked over an imgui window, etc.).
	WantCaptureKeyboard: bool, // Set when Dear ImGui will use keyboard inputs, in this case do not dispatch them to your main game/application (either way, always pass keyboard inputs to imgui). (e.g. InputText active, or an imgui window is focused and navigation is enabled, etc.).
	WantTextInput: bool, // Mobile/console: when set, you may display an on-screen keyboard. This is set by Dear ImGui when it wants textual keyboard input to happen (e.g. when a InputText widget is active).
	WantSetMousePos: bool, // MousePos has been altered, backend should reposition mouse on next frame. Rarely used! Set only when io.ConfigNavMoveSetMousePos is enabled.
	WantSaveIniSettings: bool, // When manual .ini load/save is active (io.IniFilename == NULL), this will be set to notify your application that you can call SaveIniSettingsToMemory() and save yourself. Important: clear io.WantSaveIniSettings yourself after saving!
	NavActive: bool, // Keyboard/Gamepad navigation is currently allowed (will handle ImGuiKey_NavXXX events) = a window is focused and it doesn't use the ImGuiWindowFlags_NoNavInputs flag.
	NavVisible: bool, // Keyboard/Gamepad navigation highlight is visible and allowed (will handle ImGuiKey_NavXXX events).
	Framerate: f32, // Estimate of application framerate (rolling average over 60 frames, based on io.DeltaTime), in frame per second. Solely for convenience. Slow applications may not want to use a moving average or may want to reset underlying buffers occasionally.
	MetricsRenderVertices: i32, // Vertices output during last call to Render()
	MetricsRenderIndices: i32, // Indices output during last call to Render() = number of triangles * 3
	MetricsRenderWindows: i32, // Number of visible windows
	MetricsActiveWindows: i32, // Number of active windows
	MouseDelta: Vec2, // Mouse delta. Note that this is zero if either current or previous position are invalid (-FLT_MAX,-FLT_MAX), so a disappearing/reappearing mouse won't have a huge delta.
	Ctx: ^Context, // Parent UI context (needs to be set explicitly by parent).
	MousePos: Vec2, // Mouse position, in pixels. Set to ImVec2(-FLT_MAX, -FLT_MAX) if mouse is unavailable (on another screen, etc.)
	MouseDown: [5]bool, // Mouse buttons: 0=left, 1=right, 2=middle + extras (ImGuiMouseButton_COUNT == 5). Dear ImGui mostly uses left and right buttons. Other buttons allow us to track if the mouse is being used by your application + available to user as a convenience via IsMouse** API.
	MouseWheel: f32, // Mouse wheel Vertical: 1 unit scrolls about 5 lines text. >0 scrolls Up, <0 scrolls Down. Hold Shift to turn vertical scroll into horizontal scroll.
	MouseWheelH: f32, // Mouse wheel Horizontal. >0 scrolls Left, <0 scrolls Right. Most users don't have a mouse with a horizontal wheel, may not be filled by all backends.
	MouseSource: MouseSource, // Mouse actual input peripheral (Mouse/TouchScreen/Pen).
	MouseHoveredViewport: ID, // (Optional) Modify using io.AddMouseViewportEvent(). With multi-viewports: viewport the OS mouse is hovering. If possible _IGNORING_ viewports with the ImGuiViewportFlags_NoInputs flag is much better (few backends can handle that). Set io.BackendFlags |= ImGuiBackendFlags_HasMouseHoveredViewport if you can provide this info. If you don't imgui will infer the value using the rectangles and last focused time of the viewports it knows about (ignoring other OS windows).
	KeyCtrl: bool, // Keyboard modifier down: Ctrl (non-macOS), Cmd (macOS)
	KeyShift: bool, // Keyboard modifier down: Shift
	KeyAlt: bool, // Keyboard modifier down: Alt
	KeySuper: bool, // Keyboard modifier down: Windows/Super (non-macOS), Ctrl (macOS)
	KeyMods: KeyChord, // Key mods flags (any of ImGuiMod_Ctrl/ImGuiMod_Shift/ImGuiMod_Alt/ImGuiMod_Super flags, same as io.KeyCtrl/KeyShift/KeyAlt/KeySuper but merged into flags). Read-only, updated by NewFrame()
	KeysData: [KEY_NAMED_KEY_COUNT]KeyData, // Key state for all known keys. MUST use 'key - ImGuiKey_NamedKey_BEGIN' as index. Use IsKeyXXX() functions to access this.
	WantCaptureMouseUnlessPopupClose: bool, // Alternative to WantCaptureMouse: (WantCaptureMouse == true && WantCaptureMouseUnlessPopupClose == false) when a click over void is expected to close a popup.
	MousePosPrev: Vec2, // Previous mouse position (note that MouseDelta is not necessary == MousePos-MousePosPrev, in case either position is invalid)
	MouseClickedPos: [5]Vec2, // Position at time of clicking
	MouseClickedTime: [5]f64, // Time of last click (used to figure out double-click)
	MouseClicked: [5]bool, // Mouse button went from !Down to Down (same as MouseClickedCount[x] != 0)
	MouseDoubleClicked: [5]bool, // Has mouse button been double-clicked? (same as MouseClickedCount[x] == 2)
	MouseClickedCount: [5]u16, // == 0 (not clicked), == 1 (same as MouseClicked[]), == 2 (double-clicked), == 3 (triple-clicked) etc. when going from !Down to Down
	MouseClickedLastCount: [5]u16, // Count successive number of clicks. Stays valid after mouse release. Reset after another click is done.
	MouseReleased: [5]bool, // Mouse button went from Down to !Down
	MouseReleasedTime: [5]f64, // Time of last released (rarely used! but useful to handle delayed single-click when trying to disambiguate them from double-click).
	MouseDownOwned: [5]bool, // Track if button was clicked inside a dear imgui window or over void blocked by a popup. We don't request mouse capture from the application if click started outside ImGui bounds.
	MouseDownOwnedUnlessPopupClose: [5]bool, // Track if button was clicked inside a dear imgui window.
	MouseWheelRequestAxisSwap: bool, // On a non-Mac system, holding Shift requests WheelY to perform the equivalent of a WheelX event. On a Mac system this is already enforced by the system.
	MouseCtrlLeftAsRightClick: bool, // (OSX) Set to true when the current click was a Ctrl+Click that spawned a simulated right click
	MouseDownDuration: [5]f32, // Duration the mouse button has been down (0.0f == just clicked)
	MouseDownDurationPrev: [5]f32, // Previous time the mouse button has been down
	MouseDragMaxDistanceAbs: [5]Vec2, // Maximum distance, absolute, on each axis, of how much mouse has traveled from the clicking point
	MouseDragMaxDistanceSqr: [5]f32, // Squared maximum distance of how much mouse has traveled from the clicking point (used for moving thresholds)
	PenPressure: f32, // Touch/Pen pressure (0.0f to 1.0f, should be >0.0f only when MouseDown[0] == true). Helper storage currently unused by Dear ImGui.
	AppFocusLost: bool, // Only modify via AddFocusEvent()
	AppAcceptingEvents: bool, // Only modify via SetAppAcceptingEvents()
	InputQueueSurrogate: Wchar16, // For AddInputCharacterUTF16()
	InputQueueCharacters: Vector_Wchar, // Queue of _characters_ input (obtained by platform backend). Fill using AddInputCharacter() helper.
}

// Shared state of InputText(), passed as an argument to your callback when a ImGuiInputTextFlags_Callback* flag is used.
// The callback function should return 0 by default.
// Callbacks (follow a flag name and see comments in ImGuiInputTextFlags_ declarations for more details)
// - ImGuiInputTextFlags_CallbackEdit:        Callback on buffer edit. Note that InputText() already returns true on edit + you can always use IsItemEdited(). The callback is useful to manipulate the underlying buffer while focus is active.
// - ImGuiInputTextFlags_CallbackAlways:      Callback on each iteration
// - ImGuiInputTextFlags_CallbackCompletion:  Callback on pressing TAB
// - ImGuiInputTextFlags_CallbackHistory:     Callback on pressing Up/Down arrows
// - ImGuiInputTextFlags_CallbackCharFilter:  Callback on character inputs to replace or discard them. Modify 'EventChar' to replace or discard, or return 1 in callback to discard.
// - ImGuiInputTextFlags_CallbackResize:      Callback on buffer capacity changes request (beyond 'buf_size' parameter value), allowing the string to grow.
InputTextCallbackData :: struct {
	Ctx: ^Context, // Parent UI context
	EventFlag: InputTextFlags, // One ImGuiInputTextFlags_Callback*    // Read-only
	Flags: InputTextFlags, // What user passed to InputText()      // Read-only
	UserData: rawptr, // What user passed to InputText()      // Read-only
	id: ID, // Widget ID                            // Read-only
	EventKey: Key, // Key pressed (Up/Down/TAB)            // Read-only    // [Completion,History]
	EventChar: Wchar, // Character input                      // Read-write   // [CharFilter] Replace character with another one, or set to zero to drop. return 1 is equivalent to setting EventChar=0;
	EventActivated: bool, // Input field just got activated       // Read-only    // [Always]
	BufDirty: bool, // Set if you modify Buf/BufTextLen!    // Write        // [Completion,History,Always]
	Buf: cstring, // Text buffer                          // Read-write   // [Resize] Can replace pointer / [Completion,History,Always] Only write to pointed data, don't replace the actual pointer!
	BufTextLen: i32, // Text length (in bytes)               // Read-write   // [Resize,Completion,History,Always] Exclude zero-terminator storage. In C land: == strlen(some_text), in C++ land: string.length()
	BufSize: i32, // Buffer size (in bytes) = capacity+1  // Read-only    // [Resize,Completion,History,Always] Include zero-terminator storage. In C land: == ARRAYSIZE(my_char_array), in C++ land: string.capacity()+1
	CursorPos: i32, //                                      // Read-write   // [Completion,History,Always,CharFilter]
	SelectionStart: i32, //                                      // Read-write   // [Completion,History,Always,CharFilter] == to SelectionEnd when no selection
	SelectionEnd: i32, //                                      // Read-write   // [Completion,History,Always,CharFilter]
}

// Resizing callback data to apply custom constraint. As enabled by SetNextWindowSizeConstraints(). Callback is called during the next Begin().
// NB: For basic min/max size constraint on each axis you don't need to use the callback! The SetNextWindowSizeConstraints() parameters are enough.
SizeCallbackData :: struct {
	UserData: rawptr, // Read-only.   What user passed to SetNextWindowSizeConstraints(). Generally store an integer or float in here (need reinterpret_cast<>).
	Pos: Vec2, // Read-only.   Window position, for reference.
	CurrentSize: Vec2, // Read-only.   Current window size.
	DesiredSize: Vec2, // Read-write.  Desired size, based on user's mouse position. Write to this field to restrain resizing.
}

// [ALPHA] Rarely used / very advanced uses only. Use with SetNextWindowClass() and DockSpace() functions.
// Important: the content of this class is still highly WIP and likely to change and be refactored
// before we stabilize Docking features. Please be mindful if using this.
// Provide hints:
// - To the platform backend via altered viewport flags (enable/disable OS decoration, OS task bar icons, etc.)
// - To the platform backend for OS level parent/child relationships of viewport (otherwise: default is configured via io.ConfigViewportsNoDefaultParent)
// - To the docking system for various options and filtering.
WindowClass :: struct {
	ClassId: ID, // User data. 0 = Default class (unclassed). Windows of different classes cannot be docked with each others.
	ParentViewportId: ID, // Hint for the platform backend. -1: use default. 0: request platform backend to not parent the platform. != 0: request platform backend to create a parent<>child relationship between the platform windows. Not conforming backends are free to e.g. parent every viewport to the main viewport or not.
	FocusRouteParentWindowId: ID, // ID of parent window for shortcut focus route evaluation, e.g. Shortcut() call from Parent Window will succeed when this window is focused.
	ViewportFlagsOverrideSet: ViewportFlags, // Viewport flags to set when a window of this class owns a viewport. This allows you to enforce OS decoration or task bar icon, override the defaults on a per-window basis.
	ViewportFlagsOverrideClear: ViewportFlags, // Viewport flags to clear when a window of this class owns a viewport. This allows you to enforce OS decoration or task bar icon, override the defaults on a per-window basis.
	TabItemFlagsOverrideSet: TabItemFlags, // [EXPERIMENTAL] TabItem flags to set when a window of this class gets submitted into a dock node tab bar. May use with ImGuiTabItemFlags_Leading or ImGuiTabItemFlags_Trailing.
	DockNodeFlagsOverrideSet: DockNodeFlags, // [EXPERIMENTAL] Dock node flags to set when a window of this class is hosted by a dock node (it doesn't have to be selected!)
	DockingAlwaysTabBar: bool, // Set to true to enforce single floating windows of this class always having their own docking node (equivalent of setting the global io.ConfigDockingAlwaysTabBar)
	DockingAllowUnclassed: bool, // Set to true to allow windows of this class to be docked/merged with an unclassed window. // FIXME-DOCK: Move to DockNodeFlags override?
	PlatformIconData: rawptr, // [EXPERIMENTAL] Pass opaque data for Platform backend to handle.
}

// Data payload for Drag and Drop operations: AcceptDragDropPayload(), GetDragDropPayload()
Payload :: struct {
	Data: rawptr, // Data (copied and owned by dear imgui)
	DataSize: i32, // Data size
	SourceId: ID, // Source item id
	SourceParentId: ID, // Source parent id (if available)
	DataFrameCount: i32, // Data timestamp
	DataType: [32+1]u8, // Data type tag (short user-supplied string, 32 characters max)
	Preview: bool, // Set when AcceptDragDropPayload() was called and mouse has been hovering the target item (nb: handle overlapping drag targets)
	Delivery: bool, // Set when AcceptDragDropPayload() was called and mouse button is released over the target item.
}

// [Internal]
TextFilter_TextRange :: struct {
	b: cstring,
	e: cstring,
}

// Helper: Parse and apply text filters. In format "aaaaa[,bbbb][,ccccc]"
TextFilter :: struct {
	InputBuf: [256]u8,
	Filters: Vector_TextRange,
	CountGrep: i32,
}

// Helper: Growable text buffer for logging/accumulating text
// (this could be called 'ImGuiTextBuilder' / 'ImGuiStringBuilder')
TextBuffer :: struct {
	Buf: Vector_char,
}

// [Internal] Key+Value for ImGuiStorage
StoragePair :: struct {
	key: ID,
	__anonymous_type0: __anonymous_type0,
}

__anonymous_type0 :: struct {
	val_i: i32,
	val_f: f32,
	val_p: rawptr,
}

// Helper: Key->Value storage
// Typically you don't have to worry about this since a storage is held within each Window.
// We use it to e.g. store collapse state for a tree (Int 0/1)
// This is optimized for efficient lookup (dichotomy into a contiguous buffer) and rare insertion (typically tied to user interactions aka max once a frame)
// You can use it as custom user storage for temporary values. Declare your own storage if, for example:
// - You want to manipulate the open/close state of a particular sub-tree in your interface (tree node uses Int 0/1 to store their state).
// - You want to store custom debug data easily without adding or editing structures in your code (probably not efficient, but convenient)
// Types are NOT stored, so it is up to you to make sure your Key don't collide with different types.
Storage :: struct {
	Data: Vector_StoragePair,
}

// Helper: Manually clip large list of items.
// If you have lots evenly spaced items and you have random access to the list, you can perform coarse
// clipping based on visibility to only submit items that are in view.
// The clipper calculates the range of visible items and advance the cursor to compensate for the non-visible items we have skipped.
// (Dear ImGui already clip items based on their bounds but: it needs to first layout the item to do so, and generally
//  fetching/submitting your own data incurs additional cost. Coarse clipping using ImGuiListClipper allows you to easily
//  scale using lists with tens of thousands of items without a problem)
// Usage:
//   ImGuiListClipper clipper;
//   clipper.Begin(1000);         // We have 1000 elements, evenly spaced.
//   while (clipper.Step())
//       for (int i = clipper.DisplayStart; i < clipper.DisplayEnd; i++)
//           ImGui::Text("line number %d", i);
// Generally what happens is:
// - Clipper lets you process the first element (DisplayStart = 0, DisplayEnd = 1) regardless of it being visible or not.
// - User code submit that one element.
// - Clipper can measure the height of the first element
// - Clipper calculate the actual range of elements to display based on the current clipping rectangle, position the cursor before the first visible element.
// - User code submit visible elements.
// - The clipper also handles various subtleties related to keyboard/gamepad navigation, wrapping etc.
ListClipper :: struct {
	DisplayStart: i32, // First item to display, updated by each call to Step()
	DisplayEnd: i32, // End of items to display (exclusive)
	UserIndex: i32, // Helper storage for user convenience/code. Optional, and otherwise unused if you don't use it.
	ItemsCount: i32, // [Internal] Number of items
	ItemsHeight: f32, // [Internal] Height of item after a first step and item submission can calculate it
	Flags: ListClipperFlags, // [Internal] Flags, currently not yet well exposed.
	StartPosY: f64, // [Internal] Cursor position at the time of Begin() or after table frozen rows are all processed
	StartSeekOffsetY: f64, // [Internal] Account for frozen rows in a table and initial loss of precision in very large windows.
	Ctx: ^Context, // [Internal] Parent UI context
	TempData: rawptr, // [Internal] Internal data
}

// Helper: ImColor() implicitly converts colors to either ImU32 (packed 4x1 byte) or ImVec4 (4x1 float)
// Prefer using IM_COL32() macros if you want a guaranteed compile-time ImU32 for usage with ImDrawList API.
// **Avoid storing ImColor! Store either u32 of ImVec4. This is not a full-featured color class. MAY OBSOLETE.
// **None of the ImGui API are using ImColor directly but you can use it as a convenience to pass colors in either ImU32 or ImVec4 formats. Explicitly cast to ImU32 or ImVec4 if needed.
Color :: struct {
	Value: Vec4,
}

// Main IO structure returned by BeginMultiSelect()/EndMultiSelect().
// This mainly contains a list of selection requests.
// - Use 'Demo->Tools->Debug Log->Selection' to see requests as they happen.
// - Some fields are only useful if your list is dynamic and allows deletion (getting post-deletion focus/state right is shown in the demo)
// - Below: who reads/writes each fields? 'r'=read, 'w'=write, 'ms'=multi-select code, 'app'=application/user code.
MultiSelectIO :: struct {
	Requests: Vector_SelectionRequest, //  ms:w, app:r     /  ms:w  app:r   // Requests to apply to your selection data.
	RangeSrcItem: SelectionUserData, //  ms:w  app:r     /                // (If using clipper) Begin: Source item (often the first selected item) must never be clipped: use clipper.IncludeItemByIndex() to ensure it is submitted.
	NavIdItem: SelectionUserData, //  ms:w, app:r     /                // (If using deletion) Last known SetNextItemSelectionUserData() value for NavId (if part of submitted items).
	NavIdSelected: bool, //  ms:w, app:r     /        app:r   // (If using deletion) Last known selection state for NavId (if part of submitted items).
	RangeSrcReset: bool, //        app:w     /  ms:r          // (If using deletion) Set before EndMultiSelect() to reset ResetSrcItem (e.g. if deleted selection).
	ItemsCount: i32, //  ms:w, app:r     /        app:r   // 'int items_count' parameter to BeginMultiSelect() is copied here for convenience, allowing simpler calls to your ApplyRequests handler. Not used internally.
}

// Selection request item
SelectionRequest :: struct {
	Type: SelectionRequestType, //  ms:w, app:r     /  ms:w, app:r   // Request type. You'll most often receive 1 Clear + 1 SetRange with a single-item range.
	Selected: bool, //  ms:w, app:r     /  ms:w, app:r   // Parameter for SetAll/SetRange requests (true = select, false = unselect)
	RangeDirection: i8, //                  /  ms:w  app:r   // Parameter for SetRange request: +1 when RangeFirstItem comes before RangeLastItem, -1 otherwise. Useful if you want to preserve selection order on a backward Shift+Click.
	RangeFirstItem: SelectionUserData, //                  /  ms:w, app:r   // Parameter for SetRange request (this is generally == RangeSrcItem when shift selecting from top to bottom).
	RangeLastItem: SelectionUserData, //                  /  ms:w, app:r   // Parameter for SetRange request (this is generally == RangeSrcItem when shift selecting from bottom to top). Inclusive!
}

// Optional helper to store multi-selection state + apply multi-selection requests.
// - Used by our demos and provided as a convenience to easily implement basic multi-selection.
// - Iterate selection with 'void* it = NULL; ImGuiID id; while (selection.GetNextSelectedItem(&it, &id)) { ... }'
//   Or you can check 'if (Contains(id)) { ... }' for each possible object if their number is not too high to iterate.
// - USING THIS IS NOT MANDATORY. This is only a helper and not a required API.
// To store a multi-selection, in your application you could:
// - Use this helper as a convenience. We use our simple key->value ImGuiStorage as a std::set<ImGuiID> replacement.
// - Use your own external storage: e.g. std::set<MyObjectId>, std::vector<MyObjectId>, interval trees, intrusively stored selection etc.
// In ImGuiSelectionBasicStorage we:
// - always use indices in the multi-selection API (passed to SetNextItemSelectionUserData(), retrieved in ImGuiMultiSelectIO)
// - use the AdapterIndexToStorageId() indirection layer to abstract how persistent selection data is derived from an index.
// - use decently optimized logic to allow queries and insertion of very large selection sets.
// - do not preserve selection order.
// Many combinations are possible depending on how you prefer to store your items and how you prefer to store your selection.
// Large applications are likely to eventually want to get rid of this indirection layer and do their own thing.
// See https://github.com/ocornut/imgui/wiki/Multi-Select for details and pseudo-code using this helper.
SelectionBasicStorage :: struct {
	Size: i32, //          // Number of selected items, maintained by this helper.
	PreserveOrder: bool, // = false  // GetNextSelectedItem() will return ordered selection (currently implemented by two additional sorts of selection. Could be improved)
	UserData: rawptr, // = NULL   // User data for use by adapter function        // e.g. selection.UserData = (void*)my_items;
	AdapterIndexToStorageId: proc "c" (self: ^SelectionBasicStorage, idx: i32) -> ID,
	_SelectionOrder: i32, // [Internal] Increasing counter to store selection order
	_Storage: Storage, // [Internal] Selection set. Think of this as similar to e.g. std::set<ImGuiID>. Prefer not accessing directly: iterate with GetNextSelectedItem().
}

// Optional helper to apply multi-selection requests to existing randomly accessible storage.
// Convenient if you want to quickly wire multi-select API on e.g. an array of bool or items storing their own selection state.
SelectionExternalStorage :: struct {
	UserData: rawptr, // User data for use by adapter function                                // e.g. selection.UserData = (void*)my_items;
	AdapterSetItemSelected: proc "c" (self: ^SelectionExternalStorage, idx: i32, selected: bool),
}

// Typically, 1 command = 1 GPU draw call (unless command is a callback)
// - VtxOffset: When 'io.BackendFlags & ImGuiBackendFlags_RendererHasVtxOffset' is enabled,
//   this fields allow us to render meshes larger than 64K vertices while keeping 16-bit indices.
//   Backends made for <1.71. will typically ignore the VtxOffset fields.
// - The ClipRect/TexRef/VtxOffset fields must be contiguous as we memcmp() them together (this is asserted for).
DrawCmd :: struct {
	ClipRect: Vec4, // 4*4  // Clipping rectangle (x1, y1, x2, y2). Subtract ImDrawData->DisplayPos to get clipping rectangle in "viewport" coordinates
	TexRef: TextureRef, // 16   // Reference to a font/texture atlas (where backend called ImTextureData::SetTexID()) or to a user-provided texture ID (via e.g. ImGui::Image() calls). Both will lead to a ImTextureID value.
	VtxOffset: u32, // 4    // Start offset in vertex buffer. ImGuiBackendFlags_RendererHasVtxOffset: always 0, otherwise may be >0 to support meshes larger than 64K vertices with 16-bit indices.
	IdxOffset: u32, // 4    // Start offset in index buffer.
	ElemCount: u32, // 4    // Number of indices (multiple of 3) to be rendered as triangles. Vertices are stored in the callee ImDrawList's vtx_buffer[] array, indices in idx_buffer[].
	UserCallback: DrawCallback, // 4-8  // If != NULL, call the function instead of rendering the vertices. clip_rect and texture_id will be set normally.
	UserCallbackData: rawptr, // 4-8  // Callback user data (when UserCallback != NULL). If called AddCallback() with size == 0, this is a copy of the AddCallback() argument. If called AddCallback() with size > 0, this is pointing to a buffer where data is stored.
	UserCallbackDataSize: i32, // 4 // Size of callback user data when using storage, otherwise 0.
	UserCallbackDataOffset: i32, // 4 // [Internal] Offset of callback user data when using storage, otherwise -1.
}

DrawVert :: struct {
	pos: Vec2,
	uv: Vec2,
	col: u32,
}

// [Internal] For use by ImDrawList
DrawCmdHeader :: struct {
	ClipRect: Vec4,
	TexRef: TextureRef,
	VtxOffset: u32,
}

// [Internal] For use by ImDrawListSplitter
DrawChannel :: struct {
	_CmdBuffer: Vector_DrawCmd,
	_IdxBuffer: Vector_DrawIdx,
}

// Split/Merge functions are used to split the draw list into different layers which can be drawn into out of order.
// This is used by the Columns/Tables API, so items of each column can be batched together in a same draw call.
DrawListSplitter :: struct {
	_Current: i32, // Current channel number (0)
	_Count: i32, // Number of active channels (1+)
	_Channels: Vector_DrawChannel, // Draw channels (not resized down so _Count might be < Channels.Size)
}

// Draw command list
// This is the low-level list of polygons that ImGui:: functions are filling. At the end of the frame,
// all command lists are passed to your ImGuiIO::RenderDrawListFn function for rendering.
// Each dear imgui window contains its own ImDrawList. You can use ImGui::GetWindowDrawList() to
// access the current window draw list and draw custom primitives.
// You can interleave normal ImGui:: calls and adding primitives to the current draw list.
// In single viewport mode, top-left is == GetMainViewport()->Pos (generally 0,0), bottom-right is == GetMainViewport()->Pos+Size (generally io.DisplaySize).
// You are totally free to apply whatever transformation matrix you want to the data (depending on the use of the transformation you may want to apply it to ClipRect as well!)
// Important: Primitives are always added to the list and not culled (culling is done at higher-level by ImGui:: functions), if you use this API a lot consider coarse culling your drawn objects.
DrawList :: struct {
	CmdBuffer: Vector_DrawCmd, // Draw commands. Typically 1 command = 1 GPU draw call, unless the command is a callback.
	IdxBuffer: Vector_DrawIdx, // Index buffer. Each command consume ImDrawCmd::ElemCount of those
	VtxBuffer: Vector_DrawVert, // Vertex buffer.
	Flags: DrawListFlags, // Flags, you may poke into these to adjust anti-aliasing settings per-primitive.
	_VtxCurrentIdx: u32, // [Internal] generally == VtxBuffer.Size unless we are past 64K vertices, in which case this gets reset to 0.
	_Data: ^DrawListSharedData, // Pointer to shared draw data (you can use ImGui::GetDrawListSharedData() to get the one from current ImGui context)
	_VtxWritePtr: ^DrawVert, // [Internal] point within VtxBuffer.Data after each add command (to avoid using the ImVector<> operators too much)
	_IdxWritePtr: ^DrawIdx, // [Internal] point within IdxBuffer.Data after each add command (to avoid using the ImVector<> operators too much)
	_Path: Vector_Vec2, // [Internal] current path building
	_CmdHeader: DrawCmdHeader, // [Internal] template of active commands. Fields should match those of CmdBuffer.back().
	_Splitter: DrawListSplitter, // [Internal] for channels api (note: prefer using your own persistent instance of ImDrawListSplitter!)
	_ClipRectStack: Vector_Vec4, // [Internal]
	_TextureStack: Vector_TextureRef, // [Internal]
	_CallbacksDataBuf: Vector_U8, // [Internal]
	_FringeScale: f32, // [Internal] anti-alias fringe is scaled by this value, this helps to keep things sharp while zooming at vertex buffer content
	_OwnerName: cstring, // Pointer to owner window's name for debugging
}

// All draw data to render a Dear ImGui frame
// (NB: the style and the naming convention here is a little inconsistent, we currently preserve them for backward compatibility purpose,
// as this is one of the oldest structure exposed by the library! Basically, ImDrawList == CmdList)
DrawData :: struct {
	Valid: bool, // Only valid after Render() is called and before the next NewFrame() is called.
	FrameCount: i32, // Frame counter of the emitter context. Mostly for debugging purpose.
	TotalIdxCount: i32, // For convenience, sum of all ImDrawList's IdxBuffer.Size
	TotalVtxCount: i32, // For convenience, sum of all ImDrawList's VtxBuffer.Size
	CmdLists: Vector_DrawListPtr, // Array of ImDrawList* to render. The ImDrawLists are owned by ImGuiContext and only pointed to from here.
	DisplayPos: Vec2, // Top-left position of the viewport to render (== top-left of the orthogonal projection matrix to use) (== GetMainViewport()->Pos for the main viewport, == (0.0) in most single-viewport applications)
	DisplaySize: Vec2, // Size of the viewport to render (== GetMainViewport()->Size for the main viewport, == io.DisplaySize in most single-viewport applications)
	FramebufferScale: Vec2, // Amount of pixels for each unit of DisplaySize. Copied from viewport->FramebufferScale (== io.DisplayFramebufferScale for main viewport). Generally (1,1) on normal display, (2,2) on OSX with Retina display.
	OwnerViewport: ^Viewport, // Viewport carrying the ImDrawData instance, might be of use to the renderer (generally not).
	Textures: ^Vector_TextureDataPtr, // List of textures to update. Most of the times the list is shared by all ImDrawData, has only 1 texture and it doesn't need any update. This almost always points to ImGui::GetPlatformIO().Textures[]. May be overridden or set to NULL if you want to manually update textures.
}

// Coordinates of a rectangle within a texture.
// When a texture is in ImTextureStatus_WantUpdates state, we provide a list of individual rectangles to copy to the graphics system.
// You may use ImTextureData::Updates[] for the list, or ImTextureData::UpdateBox for a single bounding box.
TextureRect :: struct {
	x: u16, // Upper-left coordinates of rectangle to update, within the parent Pixels[] array.
	y: u16, // Upper-left coordinates of rectangle to update, within the parent Pixels[] array.
	w: u16, // Size of rectangle to update (in pixels)
	h: u16, // Size of rectangle to update (in pixels)
}

// Specs and pixel storage for a texture used by Dear ImGui.
// This is only useful for (1) core library and (2) backends. End-user/applications do not need to care about this.
// Renderer Backends will create a GPU-side version of this.
// Why does we store two identifiers: TexID and BackendUserData?
// - ImTextureID    TexID           = lower-level identifier stored in ImDrawCmd. ImDrawCmd can refer to textures not created by the backend, and for which there's no ImTextureData.
// - void*          BackendUserData = higher-level opaque storage for backend own book-keeping. Some backends may have enough with TexID and not need both.
// In columns below: who reads/writes each fields? 'r'=read, 'w'=write, 'core'=main library, 'backend'=renderer backend
TextureData :: struct {
	UniqueID: i32, // w    -   // [DEBUG] Sequential index to facilitate identifying a texture when debugging/printing. Unique per atlas.
	Status: TextureStatus, // rw   rw  // ImTextureStatus_OK/_WantCreate/_WantUpdates/_WantDestroy. Always use SetStatus() to modify!
	BackendUserData: rawptr, // -    rw  // Convenience storage for backend. Some backends may have enough with TexID.
	QueueUserData: rawptr, // r    -   // Convenience storage for a staged/multi-threaded rendering texture queue (e.g. imgui_threaded_rendering.h. See #8597). When != NULL, core assumes the texture is referenced by the queue.
	TexID: TextureID, // r    w   // Backend-specific texture identifier. Always use SetTexID() to modify! The identifier will stored in ImDrawCmd::GetTexID() and passed to backend's RenderDrawData function.
	Format: TextureFormat, // w    r   // ImTextureFormat_RGBA32 (default) or ImTextureFormat_Alpha8
	Width: i32, // w    r   // Texture width
	Height: i32, // w    r   // Texture height
	BytesPerPixel: i32, // w    r   // 4 or 1
	Pixels: [^]u8, // w    r   // Pointer to whole texture buffer holding 'Width*Height' pixels and 'Width*Height*BytesPerPixels' bytes.
	UsedRect: TextureRect, // w    r   // Bounding box encompassing all past and queued Updates[].
	UpdateRect: TextureRect, // w    r   // Bounding box encompassing all queued Updates[].
	Updates: Vector_TextureRect, // w    r   // Array of individual updates.
	UnusedFrames: i32, // w    r   // In order to facilitate handling Status==WantDestroy in some backend: this is a count successive frames where the texture was not used. Always >0 when Status==WantDestroy.
	RefCount: u16, // w    r   // Number of contexts using this texture. Used during backend shutdown.
	UseColors: bool, // w    r   // Tell whether our texture data is known to use colors (rather than just white + alpha).
	WantDestroyNextFrame: bool, // rw   -   // [Internal] Queued to set ImTextureStatus_WantDestroy next frame. May still be used in the current frame.
}

// A font input/source (we may rename this to ImFontSource in the future)
FontConfig :: struct {
	Name: [40]u8, // <auto>   // Name (strictly to ease debugging, hence limited size buffer)
	FontData: rawptr, //          // TTF/OTF data
	FontDataSize: i32, //          // TTF/OTF data size
	FontDataOwnedByAtlas: bool, // true     // TTF/OTF data ownership taken by the owner ImFontAtlas (will delete memory itself). SINCE 1.92, THE DATA NEEDS TO PERSIST FOR WHOLE DURATION OF ATLAS.
	MergeMode: bool, // false    // Merge into previous ImFont, so you can combine multiple inputs font into one ImFont (e.g. ASCII font + icons + Japanese glyphs). You may want to use GlyphOffset.y when merge font of different heights.
	PixelSnapH: bool, // false    // Align every glyph AdvanceX to pixel boundaries. Prevents fractional font size from working correctly! Useful e.g. if you are merging a non-pixel aligned font with the default font. If enabled, OversampleH/V will default to 1.
	OversampleH: i8, // 0 (2)    // Rasterize at higher quality for sub-pixel positioning. 0 == auto == 1 or 2 depending on size. Note the difference between 2 and 3 is minimal. You can reduce this to 1 for large glyphs save memory. Read https://github.com/nothings/stb/blob/master/tests/oversample/README.md for details.
	OversampleV: i8, // 0 (1)    // Rasterize at higher quality for sub-pixel positioning. 0 == auto == 1. This is not really useful as we don't use sub-pixel positions on the Y axis.
	EllipsisChar: Wchar, // 0        // Explicitly specify Unicode codepoint of ellipsis character. When fonts are being merged first specified ellipsis will be used.
	SizePixels: f32, //          // Output size in pixels for rasterizer (more or less maps to the resulting font height).
	GlyphRanges: ^Wchar, // NULL     // *LEGACY* THE ARRAY DATA NEEDS TO PERSIST AS LONG AS THE FONT IS ALIVE. Pointer to a user-provided list of Unicode range (2 value per range, values are inclusive, zero-terminated list).
	GlyphExcludeRanges: ^Wchar, // NULL     // Pointer to a small user-provided list of Unicode ranges (2 value per range, values are inclusive, zero-terminated list). This is very close to GlyphRanges[] but designed to exclude ranges from a font source, when merging fonts with overlapping glyphs. Use "Input Glyphs Overlap Detection Tool" to find about your overlapping ranges.
	GlyphOffset: Vec2, // 0, 0     // Offset (in pixels) all glyphs from this font input. Absolute value for default size, other sizes will scale this value.
	GlyphMinAdvanceX: f32, // 0        // Minimum AdvanceX for glyphs, set Min to align font icons, set both Min/Max to enforce mono-space font. Absolute value for default size, other sizes will scale this value.
	GlyphMaxAdvanceX: f32, // FLT_MAX  // Maximum AdvanceX for glyphs
	GlyphExtraAdvanceX: f32, // 0        // Extra spacing (in pixels) between glyphs. Please contact us if you are using this. // FIXME-NEWATLAS: Intentionally unscaled
	FontNo: u32, // 0        // Index of font within TTF/OTF file
	FontLoaderFlags: u32, // 0        // Settings for custom font builder. THIS IS BUILDER IMPLEMENTATION DEPENDENT. Leave as zero if unsure.
	RasterizerMultiply: f32, // 1.0f     // Linearly brighten (>1.0f) or darken (<1.0f) font output. Brightening small fonts may be a good workaround to make them more readable. This is a silly thing we may remove in the future.
	RasterizerDensity: f32, // 1.0f     // [LEGACY: this only makes sense when ImGuiBackendFlags_RendererHasTextures is not supported] DPI scale multiplier for rasterization. Not altering other font metrics: makes it easy to swap between e.g. a 100% and a 400% fonts for a zooming display, or handle Retina screen. IMPORTANT: If you change this it is expected that you increase/decrease font scale roughly to the inverse of this, otherwise quality may look lowered.
	ExtraSizeScale: f32, // 1.0f     // Extra rasterizer scale over SizePixels.
	Flags: FontFlags, // Font flags (don't use just yet, will be exposed in upcoming 1.92.X updates)
	DstFont: ^Font, // Target font (as we merging fonts, multiple ImFontConfig may target the same font)
	FontLoader: ^FontLoader, // Custom font backend for this source (default source is the one stored in ImFontAtlas)
	FontLoaderData: rawptr, // Font loader opaque storage (per font config)
}

// Hold rendering data for one glyph.
// (Note: some language parsers may fail to convert the bitfield members, in this case maybe drop store a single u32 or we can rework this)
FontGlyph :: struct {
	Colored: u32, // Flag to indicate glyph is colored and should generally ignore tinting (make it usable with no shift on little-endian as this is used in loops)
	Visible: u32, // Flag to indicate glyph has no visible pixels (e.g. space). Allow early out when rendering.
	SourceIdx: u32, // Index of source in parent font
	Codepoint: u32, // 0x0000..0x10FFFF
	AdvanceX: f32, // Horizontal distance to advance cursor/layout position.
	X0: f32, // Glyph corners. Offsets from current cursor/layout position.
	Y0: f32, // Glyph corners. Offsets from current cursor/layout position.
	X1: f32, // Glyph corners. Offsets from current cursor/layout position.
	Y1: f32, // Glyph corners. Offsets from current cursor/layout position.
	U0: f32, // Texture coordinates for the current value of ImFontAtlas->TexRef. Cached equivalent of calling GetCustomRect() with PackId.
	V0: f32, // Texture coordinates for the current value of ImFontAtlas->TexRef. Cached equivalent of calling GetCustomRect() with PackId.
	U1: f32, // Texture coordinates for the current value of ImFontAtlas->TexRef. Cached equivalent of calling GetCustomRect() with PackId.
	V1: f32, // Texture coordinates for the current value of ImFontAtlas->TexRef. Cached equivalent of calling GetCustomRect() with PackId.
	PackId: i32, // [Internal] ImFontAtlasRectId value (FIXME: Cold data, could be moved elsewhere?)
}

// Helper to build glyph ranges from text/string data. Feed your application strings/characters to it then call BuildRanges().
// This is essentially a tightly packed of vector of 64k booleans = 8KB storage.
FontGlyphRangesBuilder :: struct {
	UsedChars: Vector_U32, // Store 1-bit per Unicode code point (0=unused, 1=used)
}

// Output of ImFontAtlas::GetCustomRect() when using custom rectangles.
// Those values may not be cached/stored as they are only valid for the current value of atlas->TexRef
// (this is in theory derived from ImTextureRect but we use separate structures for reasons)
FontAtlasRect :: struct {
	x: u16, // Position (in current texture)
	y: u16, // Position (in current texture)
	w: u16, // Size
	h: u16, // Size
	uv0: Vec2, // UV coordinates (in current texture)
	uv1: Vec2, // UV coordinates (in current texture)
}

// Load and rasterize multiple TTF/OTF fonts into a same texture. The font atlas will build a single texture holding:
//  - One or more fonts.
//  - Custom graphics data needed to render the shapes needed by Dear ImGui.
//  - Mouse cursor shapes for software cursor rendering (unless setting 'Flags |= ImFontAtlasFlags_NoMouseCursors' in the font atlas).
//  - If you don't call any AddFont*** functions, the default font embedded in the code will be loaded for you.
// It is the rendering backend responsibility to upload texture into your graphics API:
//  - ImGui_ImplXXXX_RenderDrawData() functions generally iterate platform_io->Textures[] to create/update/destroy each ImTextureData instance.
//  - Backend then set ImTextureData's TexID and BackendUserData.
//  - Texture id are passed back to you during rendering to identify the texture. Read FAQ entry about ImTextureID/ImTextureRef for more details.
// Legacy path:
//  - Call Build() + GetTexDataAsAlpha8() or GetTexDataAsRGBA32() to build and retrieve pixels data.
//  - Call SetTexID(my_tex_id); and pass the pointer/identifier to your texture in a format natural to your graphics API.
// Common pitfalls:
// - If you pass a 'glyph_ranges' array to AddFont*** functions, you need to make sure that your array persists up until the
//   atlas is build (when calling GetTexData*** or Build()). We only copy the pointer, not the data.
// - Important: By default, AddFontFromMemoryTTF() takes ownership of the data. Even though we are not writing to it, we will free the pointer on destruction.
//   You can set font_cfg->FontDataOwnedByAtlas=false to keep ownership of your data and it won't be freed,
// - Even though many functions are suffixed with "TTF", OTF data is supported just as well.
// - This is an old API and it is currently awkward for those and various other reasons! We will address them in the future!
FontAtlas :: struct {
	Flags: FontAtlasFlags, // Build flags (see ImFontAtlasFlags_)
	TexDesiredFormat: TextureFormat, // Desired texture format (default to ImTextureFormat_RGBA32 but may be changed to ImTextureFormat_Alpha8).
	TexGlyphPadding: i32, // FIXME: Should be called "TexPackPadding". Padding between glyphs within texture in pixels. Defaults to 1. If your rendering method doesn't rely on bilinear filtering you may set this to 0 (will also need to set AntiAliasedLinesUseTex = false).
	TexMinWidth: i32, // Minimum desired texture width. Must be a power of two. Default to 512.
	TexMinHeight: i32, // Minimum desired texture height. Must be a power of two. Default to 128.
	TexMaxWidth: i32, // Maximum desired texture width. Must be a power of two. Default to 8192.
	TexMaxHeight: i32, // Maximum desired texture height. Must be a power of two. Default to 8192.
	UserData: rawptr, // Store your own atlas related user-data (if e.g. you have multiple font atlas).
	TexRef: TextureRef, // Latest texture identifier == TexData->GetTexRef().
	TexData: ^TextureData, // Latest texture.
	TexList: Vector_TextureDataPtr, // Texture list (most often TexList.Size == 1). TexData is always == TexList.back(). DO NOT USE DIRECTLY, USE GetDrawData().Textures[]/GetPlatformIO().Textures[] instead!
	Locked: bool, // Marked as locked during ImGui::NewFrame()..EndFrame() scope if TexUpdates are not supported. Any attempt to modify the atlas will assert.
	RendererHasTextures: bool, // Copy of (BackendFlags & ImGuiBackendFlags_RendererHasTextures) from supporting context.
	TexIsBuilt: bool, // Set when texture was built matching current font input. Mostly useful for legacy IsBuilt() call.
	TexPixelsUseColors: bool, // Tell whether our texture data is known to use colors (rather than just alpha channel), in order to help backend select a format or conversion process.
	TexUvScale: Vec2, // = (1.0f/TexData->TexWidth, 1.0f/TexData->TexHeight). May change as new texture gets created.
	TexUvWhitePixel: Vec2, // Texture coordinates to a white pixel. May change as new texture gets created.
	Fonts: Vector_FontPtr, // Hold all the fonts returned by AddFont*. Fonts[0] is the default font upon calling ImGui::NewFrame(), use ImGui::PushFont()/PopFont() to change the current font.
	Sources: Vector_FontConfig, // Source/configuration data
	TexUvLines: [DRAWLIST_TEX_LINES_WIDTH_MAX+1]Vec4, // UVs for baked anti-aliased lines
	TexNextUniqueID: i32, // Next value to be stored in TexData->UniqueID
	FontNextUniqueID: i32, // Next value to be stored in ImFont->FontID
	DrawListSharedDatas: Vector_DrawListSharedDataPtr, // List of users for this atlas. Typically one per Dear ImGui context.
	Builder: ^FontAtlasBuilder, // Opaque interface to our data that doesn't need to be public and may be discarded when rebuilding.
	FontLoader: ^FontLoader, // Font loader opaque interface (default to use FreeType when IMGUI_ENABLE_FREETYPE is defined, otherwise default to use stb_truetype). Use SetFontLoader() to change this at runtime.
	FontLoaderName: cstring, // Font loader name (for display e.g. in About box) == FontLoader->Name
	FontLoaderData: rawptr, // Font backend opaque storage
	FontLoaderFlags: u32, // Shared flags (for all fonts) for font loader. THIS IS BUILD IMPLEMENTATION DEPENDENT (e.g. Per-font override is also available in ImFontConfig).
	RefCount: i32, // Number of contexts using this atlas
	OwnerContext: ^Context, // Context which own the atlas will be in charge of updating and destroying it.
}

__anonymous_type1 :: struct {
}

// Font runtime data for a given size
// Important: pointers to ImFontBaked are only valid for the current frame.
FontBaked :: struct {
	IndexAdvanceX: Vector_float, // 12-16 // out // Sparse. Glyphs->AdvanceX in a directly indexable way (cache-friendly for CalcTextSize functions which only this info, and are often bottleneck in large UI).
	FallbackAdvanceX: f32, // 4     // out // FindGlyph(FallbackChar)->AdvanceX
	Size: f32, // 4     // in  // Height of characters/line, set during loading (doesn't change after loading)
	RasterizerDensity: f32, // 4     // in  // Density this is baked at
	IndexLookup: Vector_U16, // 12-16 // out // Sparse. Index glyphs by Unicode code-point.
	Glyphs: Vector_FontGlyph, // 12-16 // out // All glyphs.
	FallbackGlyphIndex: i32, // 4     // out // Index of FontFallbackChar
	Ascent: f32, // 4+4   // out // Ascent: distance from top to bottom of e.g. 'A' [0..FontSize] (unscaled)
	Descent: f32, // 4+4   // out // Ascent: distance from top to bottom of e.g. 'A' [0..FontSize] (unscaled)
	MetricsTotalSurface: u32, // 3  // out // Total surface in pixels to get an idea of the font rasterization/texture cost (not exact, we approximate the cost of padding between glyphs)
	WantDestroy: u32, // 0  //     // Queued for destroy
	LoadNoFallback: u32, // 0  //     // Disable loading fallback in lower-level calls.
	LoadNoRenderOnLayout: u32, // 0  //     // Enable a two-steps mode where CalcTextSize() calls will load AdvanceX *without* rendering/packing glyphs. Only advantageous if you know that the glyph is unlikely to actually be rendered, otherwise it is slower because we'd do one query on the first CalcTextSize and one query on the first Draw.
	LastUsedFrame: i32, // 4  //     // Record of that time this was bounds
	BakedId: ID, // 4     //     // Unique ID for this baked storage
	OwnerFont: ^Font, // 4-8   // in  // Parent font
	FontLoaderDatas: rawptr, // 4-8   //     // Font loader opaque storage (per baked font * sources): single contiguous buffer allocated by imgui, passed to loader.
}

// Font runtime data and rendering
// - ImFontAtlas automatically loads a default embedded font for you if you didn't load one manually.
// - Since 1.92.0 a font may be rendered as any size! Therefore a font doesn't have one specific size.
// - Use 'font->GetFontBaked(size)' to retrieve the ImFontBaked* corresponding to a given size.
// - If you used g.Font + g.FontSize (which is frequent from the ImGui layer), you can use g.FontBaked as a shortcut, as g.FontBaked == g.Font->GetFontBaked(g.FontSize).
Font :: struct {
	LastBaked: ^FontBaked, // 4-8   // Cache last bound baked. NEVER USE DIRECTLY. Use GetFontBaked().
	OwnerAtlas: ^FontAtlas, // 4-8   // What we have been loaded into.
	Flags: FontFlags, // 4     // Font flags.
	CurrentRasterizerDensity: f32, // Current rasterizer density. This is a varying state of the font.
	FontId: ID, // Unique identifier for the font
	LegacySize: f32, // 4     // in  // Font size passed to AddFont(). Use for old code calling PushFont() expecting to use that size. (use ImGui::GetFontBaked() to get font baked at current bound size).
	Sources: Vector_FontConfigPtr, // 16    // in  // List of sources. Pointers within OwnerAtlas->Sources[]
	EllipsisChar: Wchar, // 2-4   // out // Character used for ellipsis rendering ('...'). If you ever want to temporarily swap this for an alternative/dummy char, make sure to clear EllipsisAutoBake.
	FallbackChar: Wchar, // 2-4   // out // Character used if a glyph isn't found (U+FFFD, '?')
	Used8kPagesMap: [(UNICODE_CODEPOINT_MAX +1)/8192/8]u8, // 1 bytes if ImWchar=ImWchar16, 17 bytes if ImWchar==ImWchar32. Store 1-bit for each block of 8K codepoints that has one active glyph. This is mainly used to facilitate iterations across all used codepoints.
	EllipsisAutoBake: bool, // 1     //     // Mark when the "..." glyph (== EllipsisChar) needs to be generated by combining multiple '.'.
	RemapPairs: Storage, // 16    //     // Remapping pairs when using AddRemapChar(), otherwise empty.
}

// - Currently represents the Platform Window created by the application which is hosting our Dear ImGui windows.
// - With multi-viewport enabled, we extend this concept to have multiple active viewports.
// - In the future we will extend this concept further to also represent Platform Monitor and support a "no main platform window" operation mode.
// - About Main Area vs Work Area:
//   - Main Area = entire viewport.
//   - Work Area = entire viewport minus sections used by main menu bars (for platform windows), or by task bar (for platform monitor).
//   - Windows are generally trying to stay within the Work Area of their host viewport.
Viewport :: struct {
	id: ID, // Unique identifier for the viewport
	Flags: ViewportFlags, // See ImGuiViewportFlags_
	Pos: Vec2, // Main Area: Position of the viewport (Dear ImGui coordinates are the same as OS desktop/native coordinates)
	Size: Vec2, // Main Area: Size of the viewport.
	FramebufferScale: Vec2, // Density of the viewport for Retina display (always 1,1 on Windows, may be 2,2 etc on macOS/iOS). This will affect font rasterizer density.
	WorkPos: Vec2, // Work Area: Position of the viewport minus task bars, menus bars, status bars (>= Pos)
	WorkSize: Vec2, // Work Area: Size of the viewport minus task bars, menu bars, status bars (<= Size)
	DpiScale: f32, // 1.0f = 96 DPI = No extra scale.
	ParentViewportId: ID, // (Advanced) 0: no parent. Instruct the platform backend to setup a parent/child relationship between platform windows.
	ParentViewport: ^Viewport, // (Advanced) Direct shortcut to ImGui::FindViewportByID(ParentViewportId). NULL: no parent.
	DrawData: ^DrawData, // The ImDrawData corresponding to this viewport. Valid after Render() and until the next call to NewFrame().
	RendererUserData: rawptr, // void* to hold custom data structure for the renderer (e.g. swap chain, framebuffers etc.). generally set by your Renderer_CreateWindow function.
	PlatformUserData: rawptr, // void* to hold custom data structure for the OS / platform (e.g. windowing info, render context). generally set by your Platform_CreateWindow function.
	PlatformIconData: rawptr, // void* to hold custom data structure for the OS / platform to specify an icon. Currently unused for exposed to allow experiments.
	PlatformHandle: rawptr, // void* to hold higher-level, platform window handle (e.g. HWND for Win32 backend, Uint32 WindowID for SDL, GLFWWindow* for GLFW), for FindViewportByPlatformHandle().
	PlatformHandleRaw: rawptr, // void* to hold lower-level, platform-native window handle (always HWND on Win32 platform, unused for other platforms).
	PlatformWindowCreated: bool, // Platform window has been created (Platform_CreateWindow() has been called). This is false during the first frame where a viewport is being created.
	PlatformRequestMove: bool, // Platform window requested move (e.g. window was moved by the OS / host window manager, authoritative position will be OS window position)
	PlatformRequestResize: bool, // Platform window requested resize (e.g. window was resized by the OS / host window manager, authoritative size will be OS window size)
	PlatformRequestClose: bool, // Platform window requested closure (e.g. window was moved by the OS / host window manager, e.g. pressing ALT-F4)
}

// Access via ImGui::GetPlatformIO()
PlatformIO :: struct {
	PlatformGetClipboardTextFn: proc "c" (ctx: ^Context) -> cstring,
	PlatformSetClipboardTextFn: proc "c" (ctx: ^Context, text: cstring),
	Platform_ClipboardUserData: rawptr,
	PlatformOpenInShellFn: proc "c" (ctx: ^Context, path: cstring) -> bool,
	Platform_OpenInShellUserData: rawptr,
	PlatformSetImeDataFn: proc "c" (ctx: ^Context, viewport: ^Viewport, data: ^PlatformeData),
	Platform_ImeUserData: rawptr,
	Platform_LocaleDecimalPoint: Wchar, // '.'
	Platform_SessionDate: i32, // Integer storing YYYYMMDD e.g. 20261231 corresponding to the beginning of application session.
	Renderer_TextureMaxWidth: i32,
	Renderer_TextureMaxHeight: i32,
	Renderer_RenderState: rawptr,
	DrawCallback_ResetRenderState: DrawCallback, // Request to reset the graphics/render state.
	DrawCallback_SetSamplerLinear: DrawCallback, // Request backend to set texture sampling to Linear.
	DrawCallback_SetSamplerNearest: DrawCallback, // Request backend to set texture sampling to Nearest/Point.
	PlatformCreateWindow: proc "c" (vp: ^Viewport),
	PlatformDestroyWindow: proc "c" (vp: ^Viewport),
	PlatformShowWindow: proc "c" (vp: ^Viewport),
	PlatformSetWindowPos: proc "c" (vp: ^Viewport, pos: Vec2),
	PlatformGetWindowPos: proc "c" (vp: ^Viewport) -> Vec2,
	PlatformSetWindowSize: proc "c" (vp: ^Viewport, size: Vec2),
	PlatformGetWindowSize: proc "c" (vp: ^Viewport) -> Vec2,
	PlatformGetWindowFramebufferScale: proc "c" (vp: ^Viewport) -> Vec2,
	PlatformSetWindowFocus: proc "c" (vp: ^Viewport),
	PlatformGetWindowFocus: proc "c" (vp: ^Viewport) -> bool,
	PlatformGetWindowMinimized: proc "c" (vp: ^Viewport) -> bool,
	PlatformSetWindowTitle: proc "c" (vp: ^Viewport, str: cstring),
	PlatformSetWindowAlpha: proc "c" (vp: ^Viewport, alpha: f32),
	PlatformUpdateWindow: proc "c" (vp: ^Viewport),
	PlatformRenderWindow: proc "c" (vp: ^Viewport, render_arg: rawptr),
	PlatformSwapBuffers: proc "c" (vp: ^Viewport, render_arg: rawptr),
	PlatformGetWindowDpiScale: proc "c" (vp: ^Viewport) -> f32,
	PlatformOnChangedViewport: proc "c" (vp: ^Viewport),
	PlatformGetWindowWorkAreaInsets: proc "c" (vp: ^Viewport) -> Vec4,
	PlatformCreateVkSurface: proc "c" (vp: ^Viewport, vk_inst: u64, vk_allocators: rawptr, out_vk_surface: ^u64) -> i32,
	RendererCreateWindow: proc "c" (vp: ^Viewport),
	RendererDestroyWindow: proc "c" (vp: ^Viewport),
	RendererSetWindowSize: proc "c" (vp: ^Viewport, size: Vec2),
	RendererRenderWindow: proc "c" (vp: ^Viewport, render_arg: rawptr),
	RendererSwapBuffers: proc "c" (vp: ^Viewport, render_arg: rawptr),
	Monitors: Vector_PlatformMonitor,
	Textures: Vector_TextureDataPtr, // List of textures used by Dear ImGui (most often 1) + contents of external texture list is automatically appended into this.
	Viewports: Vector_ViewportPtr, // Main viewports, followed by all secondary viewports.
}

// (Optional) This is required when enabling multi-viewport. Represent the bounds of each connected monitor/display and their DPI.
// We use this information for multiple DPI support + clamping the position of popups and tooltips so they don't straddle multiple monitors.
PlatformMonitor :: struct {
	MainPos: Vec2, // Coordinates of the area displayed on this monitor (Min = upper left, Max = bottom right)
	MainSize: Vec2, // Coordinates of the area displayed on this monitor (Min = upper left, Max = bottom right)
	WorkPos: Vec2, // Coordinates without task bars / side bars / menu bars. Used to avoid positioning popups/tooltips inside this region. If you don't have this info, please copy the value for MainPos/MainSize.
	WorkSize: Vec2, // Coordinates without task bars / side bars / menu bars. Used to avoid positioning popups/tooltips inside this region. If you don't have this info, please copy the value for MainPos/MainSize.
	DpiScale: f32, // 1.0f = 96 DPI
	PlatformHandle: rawptr, // Backend dependant data (e.g. HMONITOR, GLFWmonitor*, SDL Display Index, NSScreen*)
}

// (Optional) Support for IME (Input Method Editor) via the platform_io.Platform_SetImeDataFn() function. Handler is called during EndFrame().
PlatformeData :: struct {
	WantVisible: bool, // A widget wants the IME to be visible.
	WantTextInput: bool, // A widget wants text input, not necessarily IME to be visible. This is automatically set to the upcoming value of io.WantTextInput.
	InputPos: Vec2, // Position of input cursor (for IME).
	InputLineHeight: f32, // Line height (for IME).
	ViewportId: ID, // ID of platform window/viewport.
}

@(default_calling_convention = "c")
foreign imguilib {
	// == (_TexData ? _TexData->TexID : _TexID) // Implemented below in the file.
	@(link_name = "ImTextureRef_GetTexID")
	TextureRef_GetTexID :: proc(
		self: ^TextureRef) -> TextureID ---
	// Context creation and access
	// - Each context create its own ImFontAtlas by default. You may instance one yourself and pass it to CreateContext() to share a font atlas between contexts.
	// - DLL users: heaps and globals are not shared across DLL boundaries! You will need to call SetCurrentContext() + SetAllocatorFunctions()
	//   for each static/DLL boundary you are calling from. Read "Context and Memory Allocators" section of imgui.cpp for details.
	@(link_name = "ImGui_CreateContext")
	CreateContext :: proc(
		shared_font_atlas: ^FontAtlas = nil) -> ^Context ---
	// NULL = destroy current context
	@(link_name = "ImGui_DestroyContext")
	DestroyContext :: proc(
		ctx: ^Context = nil) ---
	@(link_name = "ImGui_GetCurrentContext")
	GetCurrentContext :: proc() -> ^Context ---
	@(link_name = "ImGui_SetCurrentContext")
	SetCurrentContext :: proc(
		ctx: ^Context) ---
	// Main
	// access the ImGuiIO structure (mouse/keyboard/gamepad inputs, time, various configuration options/flags)
	@(link_name = "ImGui_GetIO")
	GetIO :: proc() -> ^IO ---
	// access the ImGuiPlatformIO structure (mostly hooks/functions to connect to platform/renderer and OS Clipboard, IME etc.)
	@(link_name = "ImGui_GetPlatformIO")
	GetPlatformIO :: proc() -> ^PlatformIO ---
	// access the Style structure (colors, sizes). Always use PushStyleColor(), PushStyleVar() to modify style mid-frame!
	@(link_name = "ImGui_GetStyle")
	GetStyle :: proc() -> ^Style ---
	// start a new Dear ImGui frame, you can submit any command from this point until Render()/EndFrame().
	@(link_name = "ImGui_NewFrame")
	NewFrame :: proc() ---
	// ends the Dear ImGui frame. automatically called by Render(). If you don't need to render data (skipping rendering) you may call EndFrame() without Render()... but you'll have wasted CPU already! If you don't need to render, better to not create any windows and not call NewFrame() at all!
	@(link_name = "ImGui_EndFrame")
	EndFrame :: proc() ---
	// ends the Dear ImGui frame, finalize the draw data. You can then get call GetDrawData().
	@(link_name = "ImGui_Render")
	Render :: proc() ---
	// valid after Render() and until the next call to NewFrame(). Call ImGui_ImplXXXX_RenderDrawData() function in your Renderer Backend to render.
	@(link_name = "ImGui_GetDrawData")
	GetDrawData :: proc() -> ^DrawData ---
	// Demo, Debug, Information
	// create Demo window. demonstrate most ImGui features. call this to learn about the library! try to make it always available in your application!
	@(link_name = "ImGui_ShowDemoWindow")
	ShowDemoWindow :: proc(
		p_open: ^bool = nil) ---
	// create Metrics/Debugger window. display Dear ImGui internals: windows, draw commands, various internal state, etc.
	@(link_name = "ImGui_ShowMetricsWindow")
	ShowMetricsWindow :: proc(
		p_open: ^bool = nil) ---
	// create Debug Log window. display a simplified log of important dear imgui events.
	@(link_name = "ImGui_ShowDebugLogWindow")
	ShowDebugLogWindow :: proc(
		p_open: ^bool = nil) ---
	// create Stack Tool window. hover items with mouse to query information about the source of their unique ID.
	@(link_name = "ImGui_ShowIDStackToolWindow")
	ShowIDStackToolWindow :: proc(
		p_open: ^bool = nil) ---
	// create About window. display Dear ImGui version, credits and build/system information.
	@(link_name = "ImGui_ShowAboutWindow")
	ShowAboutWindow :: proc(
		p_open: ^bool = nil) ---
	// add style editor block (not a window). you can pass in a reference ImGuiStyle structure to compare to, revert to and save to (else it uses the default style)
	@(link_name = "ImGui_ShowStyleEditor")
	ShowStyleEditor :: proc(
		ref: ^Style = nil) ---
	// add style selector block (not a window), essentially a combo listing the default styles.
	@(link_name = "ImGui_ShowStyleSelector")
	ShowStyleSelector :: proc(
		label: cstring) -> bool ---
	// add font selector block (not a window), essentially a combo listing the loaded fonts.
	@(link_name = "ImGui_ShowFontSelector")
	ShowFontSelector :: proc(
		label: cstring) ---
	// add basic help/info block (not a window): how to manipulate ImGui as an end-user (mouse/keyboard controls).
	@(link_name = "ImGui_ShowUserGuide")
	ShowUserGuide :: proc() ---
	// get the compiled version string e.g. "1.80 WIP" (essentially the value for IMGUI_VERSION from the compiled version of imgui.cpp)
	@(link_name = "ImGui_GetVersion")
	GetVersion :: proc() -> cstring ---
	// Styles
	// new, recommended style (default)
	@(link_name = "ImGui_StyleColorsDark")
	StyleColorsDark :: proc(
		dst: ^Style = nil) ---
	// best used with borders and a custom, thicker font
	@(link_name = "ImGui_StyleColorsLight")
	StyleColorsLight :: proc(
		dst: ^Style = nil) ---
	// classic imgui style
	@(link_name = "ImGui_StyleColorsClassic")
	StyleColorsClassic :: proc(
		dst: ^Style = nil) ---
	// Windows
	// - Begin() = push window to the stack and start appending to it. End() = pop window from the stack.
	// - Passing 'bool* p_open != NULL' shows a window-closing widget in the upper-right corner of the window,
	//   which clicking will set the boolean to false when clicked.
	// - You may append multiple times to the same window during the same frame by calling Begin()/End() pairs multiple times.
	//   Some information such as 'flags' or 'p_open' will only be considered by the first call to Begin().
	// - Begin() return false to indicate the window is collapsed or fully clipped, so you may early out and omit submitting
	//   anything to the window. Always call a matching End() for each Begin() call, regardless of its return value!
	//   [Important: due to legacy reason, Begin/End and BeginChild/EndChild are inconsistent with all other functions
	//    such as BeginMenu/EndMenu, BeginPopup/EndPopup, etc. where the EndXXX call should only be called if the corresponding
	//    BeginXXX function returned true. Begin and BeginChild are the only odd ones out. Will be fixed in a future update.]
	// - Note that the bottom of window stack always contains a window called "Debug".
	@(link_name = "ImGui_Begin")
	Begin :: proc(
		name: cstring,
		p_open: ^bool = nil,
		flags: WindowFlags = {}) -> bool ---
	@(link_name = "ImGui_End")
	End :: proc() ---
	// Child Windows
	// - Use child windows to begin into a self-contained independent scrolling/clipping regions within a host window. Child windows can embed their own child.
	// - Before 1.90 (November 2023), the "ImGuiChildFlags child_flags = 0" parameter was "bool border = false".
	//   This API is backward compatible with old code, as we guarantee that ImGuiChildFlags_Borders == true.
	//   Consider updating your old code:
	//      BeginChild("Name", size, false)   -> Begin("Name", size, 0); or Begin("Name", size, ImGuiChildFlags_None);
	//      BeginChild("Name", size, true)    -> Begin("Name", size, ImGuiChildFlags_Borders);
	// - Manual sizing (each axis can use a different setting e.g. ImVec2(0.0f, 400.0f)):
	//     == 0.0f: use remaining parent window size for this axis.
	//      > 0.0f: use specified size for this axis.
	//      < 0.0f: right/bottom-align to specified distance from available content boundaries.
	// - Specifying ImGuiChildFlags_AutoResizeX or ImGuiChildFlags_AutoResizeY makes the sizing automatic based on child contents.
	//   Combining both ImGuiChildFlags_AutoResizeX _and_ ImGuiChildFlags_AutoResizeY defeats purpose of a scrolling region and is NOT recommended.
	// - BeginChild() returns false to indicate the window is collapsed or fully clipped, so you may early out and omit submitting
	//   anything to the window. Always call a matching EndChild() for each BeginChild() call, regardless of its return value.
	//   [Important: due to legacy reason, Begin/End and BeginChild/EndChild are inconsistent with all other functions
	//    such as BeginMenu/EndMenu, BeginPopup/EndPopup, etc. where the EndXXX call should only be called if the corresponding
	//    BeginXXX function returned true. Begin and BeginChild are the only odd ones out. Will be fixed in a future update.]
	@(link_name = "ImGui_BeginChild")
	BeginChild :: proc(
		str_id: cstring,
		size: Vec2 = Vec2{0, 0},
		child_flags: ChildFlags = {},
		window_flags: WindowFlags = {}) -> bool ---
	@(link_name = "ImGui_BeginChildID")
	BeginChildID :: proc(
		id: ID,
		size: Vec2 = Vec2{0, 0},
		child_flags: ChildFlags = {},
		window_flags: WindowFlags = {}) -> bool ---
	@(link_name = "ImGui_EndChild")
	EndChild :: proc() ---
	// Windows Utilities
	// - 'current window' = the window we are appending into while inside a Begin()/End() block. 'next window' = next window we will Begin() into.
	@(link_name = "ImGui_IsWindowAppearing")
	IsWindowAppearing :: proc() -> bool ---
	@(link_name = "ImGui_IsWindowCollapsed")
	IsWindowCollapsed :: proc() -> bool ---
	// is current window focused? or its root/child, depending on flags. see flags for options.
	@(link_name = "ImGui_IsWindowFocused")
	IsWindowFocused :: proc(
		flags: FocusedFlags = {}) -> bool ---
	// is current window hovered and hoverable (e.g. not blocked by a popup/modal)? See ImGuiHoveredFlags_ for options. IMPORTANT: If you are trying to check whether your mouse should be dispatched to Dear ImGui or to your underlying app, you should not use this function! Use the 'io.WantCaptureMouse' boolean for that! Refer to FAQ entry "How can I tell whether to dispatch mouse/keyboard to Dear ImGui or my application?" for details.
	@(link_name = "ImGui_IsWindowHovered")
	IsWindowHovered :: proc(
		flags: HoveredFlags = {}) -> bool ---
	// get draw list associated to the current window, to append your own drawing primitives
	@(link_name = "ImGui_GetWindowDrawList")
	GetWindowDrawList :: proc() -> ^DrawList ---
	// get DPI scale currently associated to the current window's viewport.
	@(link_name = "ImGui_GetWindowDpiScale")
	GetWindowDpiScale :: proc() -> f32 ---
	// get current window position in screen space (IT IS UNLIKELY YOU EVER NEED TO USE THIS. Consider always using GetCursorScreenPos() and GetContentRegionAvail() instead)
	@(link_name = "ImGui_GetWindowPos")
	GetWindowPos :: proc() -> Vec2 ---
	// get current window size (IT IS UNLIKELY YOU EVER NEED TO USE THIS. Consider always using GetCursorScreenPos() and GetContentRegionAvail() instead)
	@(link_name = "ImGui_GetWindowSize")
	GetWindowSize :: proc() -> Vec2 ---
	// get current window width (IT IS UNLIKELY YOU EVER NEED TO USE THIS). Shortcut for GetWindowSize().x.
	@(link_name = "ImGui_GetWindowWidth")
	GetWindowWidth :: proc() -> f32 ---
	// get current window height (IT IS UNLIKELY YOU EVER NEED TO USE THIS). Shortcut for GetWindowSize().y.
	@(link_name = "ImGui_GetWindowHeight")
	GetWindowHeight :: proc() -> f32 ---
	// get viewport currently associated to the current window.
	@(link_name = "ImGui_GetWindowViewport")
	GetWindowViewport :: proc() -> ^Viewport ---
	// Window manipulation
	// - Prefer using SetNextXXX functions (before Begin) rather that SetXXX functions (after Begin).
	// set next window position. call before Begin(). use pivot=(0.5f,0.5f) to center on given point, etc.
	@(link_name = "ImGui_SetNextWindowPos")
	SetNextWindowPos :: proc(
		pos: Vec2,
		cond: Cond = {},
		pivot: Vec2 = Vec2{0, 0}) ---
	// set next window size. set axis to 0.0f to force an auto-fit on this axis. call before Begin()
	@(link_name = "ImGui_SetNextWindowSize")
	SetNextWindowSize :: proc(
		size: Vec2,
		cond: Cond = {}) ---
	// set next window size limits. use 0.0f or FLT_MAX if you don't want limits. Use -1 for both min and max of same axis to preserve current size (which itself is a constraint). Use callback to apply non-trivial programmatic constraints.
	@(link_name = "ImGui_SetNextWindowSizeConstraints")
	SetNextWindowSizeConstraints :: proc(
		size_min: Vec2,
		size_max: Vec2,
		custom_callback: SizeCallback = nil,
		custom_callback_data: rawptr = nil) ---
	// set next window content size (~ scrollable client area, which enforce the range of scrollbars). Not including window decorations (title bar, menu bar, etc.) nor WindowPadding. set an axis to 0.0f to leave it automatic. call before Begin()
	@(link_name = "ImGui_SetNextWindowContentSize")
	SetNextWindowContentSize :: proc(
		size: Vec2) ---
	// set next window collapsed state. call before Begin()
	@(link_name = "ImGui_SetNextWindowCollapsed")
	SetNextWindowCollapsed :: proc(
		collapsed: bool,
		cond: Cond = {}) ---
	// set next window to be focused / top-most. call before Begin()
	@(link_name = "ImGui_SetNextWindowFocus")
	SetNextWindowFocus :: proc() ---
	// set next window scrolling value (use < 0.0f to not affect a given axis).
	@(link_name = "ImGui_SetNextWindowScroll")
	SetNextWindowScroll :: proc(
		scroll: Vec2) ---
	// set next window background color alpha. helper to easily override the Alpha component of ImGuiCol_WindowBg/ChildBg/PopupBg. you may also use ImGuiWindowFlags_NoBackground.
	@(link_name = "ImGui_SetNextWindowBgAlpha")
	SetNextWindowBgAlpha :: proc(
		alpha: f32) ---
	// set next window viewport
	@(link_name = "ImGui_SetNextWindowViewport")
	SetNextWindowViewport :: proc(
		viewport_id: ID) ---
	// (not recommended) set current window position - call within Begin()/End(). prefer using SetNextWindowPos(), as this may incur tearing and side-effects.
	@(link_name = "ImGui_SetWindowPos")
	SetWindowPos :: proc(
		pos: Vec2,
		cond: Cond = {}) ---
	// (not recommended) set current window size - call within Begin()/End(). set to ImVec2(0, 0) to force an auto-fit. prefer using SetNextWindowSize(), as this may incur tearing and minor side-effects.
	@(link_name = "ImGui_SetWindowSize")
	SetWindowSize :: proc(
		size: Vec2,
		cond: Cond = {}) ---
	// (not recommended) set current window collapsed state. prefer using SetNextWindowCollapsed().
	@(link_name = "ImGui_SetWindowCollapsed")
	SetWindowCollapsed :: proc(
		collapsed: bool,
		cond: Cond = {}) ---
	// (not recommended) set current window to be focused / top-most. prefer using SetNextWindowFocus().
	@(link_name = "ImGui_SetWindowFocus")
	SetWindowFocus :: proc() ---
	// set named window position.
	@(link_name = "ImGui_SetWindowPosStr")
	SetWindowPosStr :: proc(
		name: cstring,
		pos: Vec2,
		cond: Cond = {}) ---
	// set named window size. set axis to 0.0f to force an auto-fit on this axis.
	@(link_name = "ImGui_SetWindowSizeStr")
	SetWindowSizeStr :: proc(
		name: cstring,
		size: Vec2,
		cond: Cond = {}) ---
	// set named window collapsed state
	@(link_name = "ImGui_SetWindowCollapsedStr")
	SetWindowCollapsedStr :: proc(
		name: cstring,
		collapsed: bool,
		cond: Cond = {}) ---
	// set named window to be focused / top-most. use NULL to remove focus.
	@(link_name = "ImGui_SetWindowFocusStr")
	SetWindowFocusStr :: proc(
		name: cstring) ---
	// Windows Scrolling
	// - Any change of Scroll will be applied at the beginning of next frame in the first call to Begin().
	// - You may instead use SetNextWindowScroll() prior to calling Begin() to avoid this delay, as an alternative to using SetScrollX()/SetScrollY().
	// get scrolling amount [0 .. GetScrollMaxX()]
	@(link_name = "ImGui_GetScrollX")
	GetScrollX :: proc() -> f32 ---
	// get scrolling amount [0 .. GetScrollMaxY()]
	@(link_name = "ImGui_GetScrollY")
	GetScrollY :: proc() -> f32 ---
	// set scrolling amount [0 .. GetScrollMaxX()]
	@(link_name = "ImGui_SetScrollX")
	SetScrollX :: proc(
		scroll_x: f32) ---
	// set scrolling amount [0 .. GetScrollMaxY()]
	@(link_name = "ImGui_SetScrollY")
	SetScrollY :: proc(
		scroll_y: f32) ---
	// get maximum scrolling amount ~~ ContentSize.x - WindowSize.x - DecorationsSize.x
	@(link_name = "ImGui_GetScrollMaxX")
	GetScrollMaxX :: proc() -> f32 ---
	// get maximum scrolling amount ~~ ContentSize.y - WindowSize.y - DecorationsSize.y
	@(link_name = "ImGui_GetScrollMaxY")
	GetScrollMaxY :: proc() -> f32 ---
	// adjust scrolling amount to make current cursor position visible. center_x_ratio=0.0: left, 0.5: center, 1.0: right. When using to make a "default/current item" visible, consider using SetItemDefaultFocus() instead.
	@(link_name = "ImGui_SetScrollHereX")
	SetScrollHereX :: proc(
		center_x_ratio: f32 = 0.5) ---
	// adjust scrolling amount to make current cursor position visible. center_y_ratio=0.0: top, 0.5: center, 1.0: bottom. When using to make a "default/current item" visible, consider using SetItemDefaultFocus() instead.
	@(link_name = "ImGui_SetScrollHereY")
	SetScrollHereY :: proc(
		center_y_ratio: f32 = 0.5) ---
	// adjust scrolling amount to make given position visible. Generally GetCursorStartPos() + offset to compute a valid position.
	@(link_name = "ImGui_SetScrollFromPosX")
	SetScrollFromPosX :: proc(
		local_x: f32,
		center_x_ratio: f32 = 0.5) ---
	// adjust scrolling amount to make given position visible. Generally GetCursorStartPos() + offset to compute a valid position.
	@(link_name = "ImGui_SetScrollFromPosY")
	SetScrollFromPosY :: proc(
		local_y: f32,
		center_y_ratio: f32 = 0.5) ---
	// Parameters stacks (font)
	//  - PushFont(font, 0.0f)                       // Change font and keep current size
	//  - PushFont(NULL, 20.0f)                      // Keep font and change current size
	//  - PushFont(font, 20.0f)                      // Change font and set size to 20.0f
	//  - PushFont(font, style.FontSizeBase * 2.0f)  // Change font and set size to be twice bigger than current size.
	//  - PushFont(font, font->LegacySize)           // Change font and set size to size passed to AddFontXXX() function. Same as pre-1.92 behavior.
	// *IMPORTANT* before 1.92, fonts had a single size. They can now be dynamically be adjusted.
	//  - In 1.92 we have REMOVED the single parameter version of PushFont() because it seems like the easiest way to provide an error-proof transition.
	//  - PushFont(font) before 1.92 = PushFont(font, font->LegacySize) after 1.92          // Use default font size as passed to AddFontXXX() function.
	// *IMPORTANT* global scale factors are applied over the provided size.
	//  - Global scale factors are: 'style.FontScaleMain', 'style.FontScaleDpi' and maybe more.
	// -  If you want to apply a factor to the _current_ font size:
	//  - CORRECT:   PushFont(NULL, style.FontSizeBase)         // use current unscaled size    == does nothing
	//  - CORRECT:   PushFont(NULL, style.FontSizeBase * 2.0f)  // use current unscaled size x2 == make text twice bigger
	//  - INCORRECT: PushFont(NULL, GetFontSize())              // INCORRECT! using size after global factors already applied == GLOBAL SCALING FACTORS WILL APPLY TWICE!
	//  - INCORRECT: PushFont(NULL, GetFontSize() * 2.0f)       // INCORRECT! using size after global factors already applied == GLOBAL SCALING FACTORS WILL APPLY TWICE!
	// Use NULL as a shortcut to keep current font. Use 0.0f to keep current size.
	@(link_name = "ImGui_PushFontFloat")
	PushFontFloat :: proc(
		font: ^Font,
		font_size_base_unscaled: f32) ---
	@(link_name = "ImGui_PopFont")
	PopFont :: proc() ---
	// get current font
	@(link_name = "ImGui_GetFont")
	GetFont :: proc() -> ^Font ---
	// get current scaled font size (= height in pixels). AFTER global scale factors applied. *IMPORTANT* DO NOT PASS THIS VALUE TO PushFont()! Use ImGui::GetStyle().FontSizeBase to get value before global scale factors.
	@(link_name = "ImGui_GetFontSize")
	GetFontSize :: proc() -> f32 ---
	// get current font bound at current size // == GetFont()->GetFontBaked(GetFontSize())
	@(link_name = "ImGui_GetFontBaked")
	GetFontBaked :: proc() -> ^FontBaked ---
	// Parameters stacks (shared)
	// modify a style color. always use this if you modify the style after NewFrame().
	@(link_name = "ImGui_PushStyleColor")
	PushStyleColor :: proc(
		idx: Col,
		col: u32) ---
	@(link_name = "ImGui_PushStyleColorImVec4")
	PushStyleColorVec4 :: proc(
		idx: Col,
		col: Vec4) ---
	@(link_name = "ImGui_PopStyleColor")
	PopStyleColor :: proc(
		count: i32 = 1) ---
	// modify a style float variable. always use this if you modify the style after NewFrame()!
	@(link_name = "ImGui_PushStyleVar")
	PushStyleVar :: proc(
		idx: StyleVar,
		val: f32) ---
	// modify a style ImVec2 variable. "
	@(link_name = "ImGui_PushStyleVarImVec2")
	PushStyleVarVec2 :: proc(
		idx: StyleVar,
		val: Vec2) ---
	// modify X component of a style ImVec2 variable. "
	@(link_name = "ImGui_PushStyleVarX")
	PushStyleVarX :: proc(
		idx: StyleVar,
		val_x: f32) ---
	// modify Y component of a style ImVec2 variable. "
	@(link_name = "ImGui_PushStyleVarY")
	PushStyleVarY :: proc(
		idx: StyleVar,
		val_y: f32) ---
	@(link_name = "ImGui_PopStyleVar")
	PopStyleVar :: proc(
		count: i32 = 1) ---
	// modify specified shared item flag, e.g. PushItemFlag(ImGuiItemFlags_NoTabStop, true)
	@(link_name = "ImGui_PushItemFlag")
	PushItemFlag :: proc(
		option: ItemFlags,
		enabled: bool) ---
	@(link_name = "ImGui_PopItemFlag")
	PopItemFlag :: proc() ---
	// Parameters stacks (current window)
	// push width of items for common large "item+label" widgets. >0.0f: width in pixels, <0.0f align xx pixels to the right of window (so -FLT_MIN always align width to the right side).
	@(link_name = "ImGui_PushItemWidth")
	PushItemWidth :: proc(
		item_width: f32) ---
	@(link_name = "ImGui_PopItemWidth")
	PopItemWidth :: proc() ---
	// set width of the _next_ common large "item+label" widget. >0.0f: width in pixels, <0.0f align xx pixels to the right of window (so -FLT_MIN always align width to the right side)
	@(link_name = "ImGui_SetNextItemWidth")
	SetNextItemWidth :: proc(
		item_width: f32) ---
	// width of item given pushed settings and current cursor position. NOT necessarily the width of last item unlike most 'Item' functions.
	@(link_name = "ImGui_CalcItemWidth")
	CalcItemWidth :: proc() -> f32 ---
	// push word-wrapping position for Text*() commands. < 0.0f: no wrapping; 0.0f: wrap to end of window (or column); > 0.0f: wrap at 'wrap_pos_x' position in window local space
	@(link_name = "ImGui_PushTextWrapPos")
	PushTextWrapPos :: proc(
		wrap_local_pos_x: f32 = 0.0) ---
	@(link_name = "ImGui_PopTextWrapPos")
	PopTextWrapPos :: proc() ---
	// Style read access
	// - Use the ShowStyleEditor() function to interactively see/edit the colors.
	// get UV coordinate for a white pixel, useful to draw custom shapes via the ImDrawList API
	@(link_name = "ImGui_GetFontTexUvWhitePixel")
	GetFontTexUvWhitePixel :: proc() -> Vec2 ---
	// retrieve given style color with style alpha applied and optional extra alpha multiplier, packed as a 32-bit value suitable for ImDrawList
	@(link_name = "ImGui_GetColorU32")
	GetColorU32 :: proc(
		idx: Col,
		alpha_mul: f32 = 1.0) -> u32 ---
	// retrieve given color with style alpha applied, packed as a 32-bit value suitable for ImDrawList
	@(link_name = "ImGui_GetColorU32ImVec4")
	GetColorU32Vec4 :: proc(
		col: Vec4) -> u32 ---
	// retrieve given color with style alpha applied, packed as a 32-bit value suitable for ImDrawList
	@(link_name = "ImGui_GetColorU32ImU32")
	GetColorU32U32 :: proc(
		col: u32,
		alpha_mul: f32 = 1.0) -> u32 ---
	// retrieve style color as stored in ImGuiStyle structure. use to feed back into PushStyleColor(), otherwise use GetColorU32() to get style color with style alpha baked in.
	@(link_name = "ImGui_GetStyleColorVec4")
	GetStyleColorVec4 :: proc(
		idx: Col) -> ^Vec4 ---
	// Layout cursor positioning
	// - By "cursor" we mean the current output position.
	// - The typical widget behavior is to output themselves at the current cursor position, then move the cursor one line down.
	// - You can call SameLine() between widgets to undo the last carriage return and output at the right of the preceding widget.
	// - YOU CAN DO 99% OF WHAT YOU NEED WITH ONLY GetCursorScreenPos() and GetContentRegionAvail().
	// - Attention! We currently have inconsistencies between window-local and absolute positions we will aim to fix with future API:
	//    - Absolute coordinate:        GetCursorScreenPos(), SetCursorScreenPos(), all ImDrawList:: functions. -> this is the preferred way forward.
	//    - Window-local coordinates:   SameLine(offset), GetCursorPos(), SetCursorPos(), GetCursorStartPos(), PushTextWrapPos()
	//    - Window-local coordinates:   GetContentRegionMax(), GetWindowContentRegionMin(), GetWindowContentRegionMax() --> all obsoleted. YOU DON'T NEED THEM.
	// - GetCursorScreenPos() = GetCursorPos() + GetWindowPos(). GetWindowPos() is almost only ever useful to convert from window-local to absolute coordinates. Try not to use it.
	// cursor position, absolute coordinates. THIS IS YOUR BEST FRIEND (prefer using this rather than GetCursorPos(), also more useful to work with ImDrawList API).
	@(link_name = "ImGui_GetCursorScreenPos")
	GetCursorScreenPos :: proc() -> Vec2 ---
	// cursor position, absolute coordinates. THIS IS YOUR BEST FRIEND.
	@(link_name = "ImGui_SetCursorScreenPos")
	SetCursorScreenPos :: proc(
		pos: Vec2) ---
	// available space from current position. THIS IS YOUR BEST FRIEND.
	@(link_name = "ImGui_GetContentRegionAvail")
	GetContentRegionAvail :: proc() -> Vec2 ---
	// [window-local] cursor position in window-local coordinates. This is not your best friend.
	@(link_name = "ImGui_GetCursorPos")
	GetCursorPos :: proc() -> Vec2 ---
	// [window-local] "
	@(link_name = "ImGui_GetCursorPosX")
	GetCursorPosX :: proc() -> f32 ---
	// [window-local] "
	@(link_name = "ImGui_GetCursorPosY")
	GetCursorPosY :: proc() -> f32 ---
	// [window-local] "
	@(link_name = "ImGui_SetCursorPos")
	SetCursorPos :: proc(
		local_pos: Vec2) ---
	// [window-local] "
	@(link_name = "ImGui_SetCursorPosX")
	SetCursorPosX :: proc(
		local_x: f32) ---
	// [window-local] "
	@(link_name = "ImGui_SetCursorPosY")
	SetCursorPosY :: proc(
		local_y: f32) ---
	// [window-local] initial cursor position, in window-local coordinates. Call GetCursorScreenPos() after Begin() to get the absolute coordinates version.
	@(link_name = "ImGui_GetCursorStartPos")
	GetCursorStartPos :: proc() -> Vec2 ---
	// Other layout functions
	// separator, generally horizontal. inside a menu bar or in horizontal layout mode, this becomes a vertical separator.
	@(link_name = "ImGui_Separator")
	Separator :: proc() ---
	// call between widgets or groups to layout them horizontally. X position given in window coordinates.
	@(link_name = "ImGui_SameLine")
	SameLine :: proc(
		offset_from_start_x: f32 = 0.0,
		spacing: f32 = -1.0) ---
	// undo a SameLine() or force a new line when in a horizontal-layout context.
	@(link_name = "ImGui_NewLine")
	NewLine :: proc() ---
	// add vertical spacing.
	@(link_name = "ImGui_Spacing")
	Spacing :: proc() ---
	// add a dummy item of given size. unlike InvisibleButton(), Dummy() won't take the mouse click or be navigable into.
	@(link_name = "ImGui_Dummy")
	Dummy :: proc(
		size: Vec2) ---
	// move content position toward the right, by indent_w, or style.IndentSpacing if indent_w <= 0
	@(link_name = "ImGui_Indent")
	Indent :: proc(
		indent_w: f32 = 0.0) ---
	// move content position back to the left, by indent_w, or style.IndentSpacing if indent_w <= 0
	@(link_name = "ImGui_Unindent")
	Unindent :: proc(
		indent_w: f32 = 0.0) ---
	// lock horizontal starting position
	@(link_name = "ImGui_BeginGroup")
	BeginGroup :: proc() ---
	// unlock horizontal starting position + capture the whole group bounding box into one "item" (so you can use IsItemHovered() or layout primitives such as SameLine() on whole group, etc.)
	@(link_name = "ImGui_EndGroup")
	EndGroup :: proc() ---
	// vertically align upcoming text baseline to FramePadding.y so that it will align properly to regularly framed items (call if you have text on a line before a framed item)
	@(link_name = "ImGui_AlignTextToFramePadding")
	AlignTextToFramePadding :: proc() ---
	// ~ FontSize
	@(link_name = "ImGui_GetTextLineHeight")
	GetTextLineHeight :: proc() -> f32 ---
	// ~ FontSize + style.ItemSpacing.y (distance in pixels between 2 consecutive lines of text)
	@(link_name = "ImGui_GetTextLineHeightWithSpacing")
	GetTextLineHeightWithSpacing :: proc() -> f32 ---
	// ~ FontSize + style.FramePadding.y * 2
	@(link_name = "ImGui_GetFrameHeight")
	GetFrameHeight :: proc() -> f32 ---
	// ~ FontSize + style.FramePadding.y * 2 + style.ItemSpacing.y (distance in pixels between 2 consecutive lines of framed widgets)
	@(link_name = "ImGui_GetFrameHeightWithSpacing")
	GetFrameHeightWithSpacing :: proc() -> f32 ---
	// ID stack/scopes
	// Read the FAQ (docs/FAQ.md or http://dearimgui.com/faq) for more details about how ID are handled in dear imgui.
	// - Those questions are answered and impacted by understanding of the ID stack system:
	//   - "Q: Why is my widget not reacting when I click on it?"
	//   - "Q: How can I have widgets with an empty label?"
	//   - "Q: How can I have multiple widgets with the same label?"
	// - Short version: ID are hashes of the entire ID stack. If you are creating widgets in a loop you most likely
	//   want to push a unique identifier (e.g. object pointer, loop index) to uniquely differentiate them.
	// - You can also use the "Label##foobar" syntax within widget label to distinguish them from each others.
	// - In this header file we use the "label"/"name" terminology to denote a string that will be displayed + used as an ID,
	//   whereas "str_id" denote a string that is only used as an ID and not normally displayed.
	// push string into the ID stack (will hash string).
	@(link_name = "ImGui_PushID")
	PushID :: proc(
		str_id: cstring) ---
	// push string into the ID stack (will hash string).
	@(link_name = "ImGui_PushIDStr")
	PushIDStr :: proc(
		str_id_begin: cstring,
		str_id_end: cstring) ---
	// push pointer into the ID stack (will hash pointer).
	@(link_name = "ImGui_PushIDPtr")
	PushIDPtr :: proc(
		ptr_id: rawptr) ---
	// push integer into the ID stack (will hash integer).
	@(link_name = "ImGui_PushIDInt")
	PushIDInt :: proc(
		int_id: i32) ---
	// pop from the ID stack.
	@(link_name = "ImGui_PopID")
	PopID :: proc() ---
	// calculate unique ID (hash of whole ID stack + given parameter). e.g. if you want to query into ImGuiStorage yourself
	@(link_name = "ImGui_GetID")
	GetID :: proc(
		str_id: cstring) -> ID ---
	@(link_name = "ImGui_GetIDStr")
	GetIDStr :: proc(
		str_id_begin: cstring,
		str_id_end: cstring) -> ID ---
	@(link_name = "ImGui_GetIDPtr")
	GetIDPtr :: proc(
		ptr_id: rawptr) -> ID ---
	@(link_name = "ImGui_GetIDInt")
	GetIDInt :: proc(
		int_id: i32) -> ID ---
	// Widgets: Text
	// - Note that all functions taking format strings in the API may be passed ("%s", text) or ("%.*s", text_len, text): which will automatically bypass the formatter.
	// raw text without formatting. Practically equivalent to 'Text("%s", text)' but doesn't require null terminated string if 'text_end' is specified.
	@(link_name = "ImGui_TextUnformatted")
	TextUnformatted :: proc(
		text: cstring,
		text_end: cstring = nil) ---
	// formatted text
	@(link_name = "ImGui_Text")
	Text :: proc(
		fmt: cstring,
		#c_vararg args: ..any) ---
	// shortcut for PushStyleColor(ImGuiCol_Text, col); Text(fmt, ...); PopStyleColor();
	@(link_name = "ImGui_TextColored")
	TextColored :: proc(
		col: Vec4,
		fmt: cstring,
		#c_vararg args: ..any) ---
	// shortcut for PushStyleColor(ImGuiCol_Text, style.Colors[ImGuiCol_TextDisabled]); Text(fmt, ...); PopStyleColor();
	@(link_name = "ImGui_TextDisabled")
	TextDisabled :: proc(
		fmt: cstring,
		#c_vararg args: ..any) ---
	// shortcut for PushTextWrapPos(0.0f); Text(fmt, ...); PopTextWrapPos();. Note that this won't work on an auto-resizing window if there's no other widgets to extend the window width, yoy may need to set a size using SetNextWindowSize().
	@(link_name = "ImGui_TextWrapped")
	TextWrapped :: proc(
		fmt: cstring,
		#c_vararg args: ..any) ---
	// display text+label aligned the same way as value+label widgets
	@(link_name = "ImGui_LabelText")
	LabelText :: proc(
		label: cstring,
		fmt: cstring,
		#c_vararg args: ..any) ---
	// shortcut for Bullet()+Text()
	@(link_name = "ImGui_BulletText")
	BulletText :: proc(
		fmt: cstring,
		#c_vararg args: ..any) ---
	// currently: formatted text with a horizontal line
	@(link_name = "ImGui_SeparatorText")
	SeparatorText :: proc(
		label: cstring) ---
	// Widgets: Main
	// - Most widgets return true when the value has been changed or when pressed/selected
	// - You may also use one of the many IsItemXXX functions (e.g. IsItemActive, IsItemHovered, etc.) to query widget state.
	// button
	@(link_name = "ImGui_Button")
	Button :: proc(
		label: cstring,
		size: Vec2 = Vec2{0, 0}) -> bool ---
	// button with (FramePadding.y == 0) to easily embed within text
	@(link_name = "ImGui_SmallButton")
	SmallButton :: proc(
		label: cstring) -> bool ---
	// flexible button behavior without the visuals, frequently useful to build custom behaviors using the public api (along with IsItemActive, IsItemHovered, etc.)
	@(link_name = "ImGui_InvisibleButton")
	InvisibleButton :: proc(
		str_id: cstring,
		size: Vec2,
		flags: ButtonFlags = {}) -> bool ---
	// square button with an arrow shape
	@(link_name = "ImGui_ArrowButton")
	ArrowButton :: proc(
		str_id: cstring,
		dir: Dir) -> bool ---
	@(link_name = "ImGui_Checkbox")
	Checkbox :: proc(
		label: cstring,
		v: ^bool) -> bool ---
	@(link_name = "ImGui_CheckboxFlagsIntPtr")
	CheckboxFlagsIntPtr :: proc(
		label: cstring,
		flags: ^i32,
		flags_value: i32) -> bool ---
	@(link_name = "ImGui_CheckboxFlagsUintPtr")
	CheckboxFlagsUintPtr :: proc(
		label: cstring,
		flags: ^u32,
		flags_value: u32) -> bool ---
	// use with e.g. if (RadioButton("one", my_value==1)) { my_value = 1; }
	@(link_name = "ImGui_RadioButton")
	RadioButton :: proc(
		label: cstring,
		active: bool) -> bool ---
	// shortcut to handle the above pattern when value is an integer
	@(link_name = "ImGui_RadioButtonIntPtr")
	RadioButtonIntPtr :: proc(
		label: cstring,
		v: ^i32,
		v_button: i32) -> bool ---
	@(link_name = "ImGui_ProgressBar")
	ProgressBar :: proc(
		fraction: f32,
		size_arg: Vec2 = Vec2{-min(f32), 0},
		overlay: cstring = nil) ---
	// draw a small circle + keep the cursor on the same line. advance cursor x position by GetTreeNodeToLabelSpacing(), same distance that TreeNode() uses
	@(link_name = "ImGui_Bullet")
	Bullet :: proc() ---
	// hyperlink text button, return true when clicked
	@(link_name = "ImGui_TextLink")
	TextLink :: proc(
		label: cstring) -> bool ---
	// hyperlink text button, automatically open file/url when clicked
	@(link_name = "ImGui_TextLinkOpenURL")
	TextLinkOpenURL :: proc(
		label: cstring,
		url: cstring = nil) -> bool ---
	// Widgets: Images
	// - Read about ImTextureID/ImTextureRef  here: https://github.com/ocornut/imgui/wiki/Image-Loading-and-Displaying-Examples
	// - 'uv0' and 'uv1' are texture coordinates. Read about them from the same link above.
	// - Image() adds style.ImageBorderSize on each side, ImageButton() adds style.FramePadding on each side.
	// - ImageButton() draws a background based on regular Button() color + optionally an inner background if specified.
	// - An obsolete version of Image(), before 1.91.9 (March 2025), had a 'tint_col' parameter which is now supported by the ImageWithBg() function.
	@(link_name = "ImGui_Image")
	Image :: proc(
		tex_ref: TextureRef,
		image_size: Vec2,
		uv0: Vec2 = Vec2{0, 0},
		uv1: Vec2 = Vec2{1, 1}) ---
	@(link_name = "ImGui_ImageWithBg")
	ImageWithBg :: proc(
		tex_ref: TextureRef,
		image_size: Vec2,
		uv0: Vec2 = Vec2{0, 0},
		uv1: Vec2 = Vec2{1, 1},
		bg_col: Vec4 = Vec4{0, 0, 0, 0},
		tint_col: Vec4 = Vec4{1, 1, 1, 1}) ---
	@(link_name = "ImGui_ImageButton")
	ImageButton :: proc(
		str_id: cstring,
		tex_ref: TextureRef,
		image_size: Vec2,
		uv0: Vec2 = Vec2{0, 0},
		uv1: Vec2 = Vec2{1, 1},
		bg_col: Vec4 = Vec4{0, 0, 0, 0},
		tint_col: Vec4 = Vec4{1, 1, 1, 1}) -> bool ---
	// Widgets: Combo Box (Dropdown)
	// - The BeginCombo()/EndCombo() api allows you to manage your contents and selection state however you want it, by creating e.g. Selectable() items.
	// - The old Combo() api are helpers over BeginCombo()/EndCombo() which are kept available for convenience purpose. This is analogous to how ListBox are created.
	@(link_name = "ImGui_BeginCombo")
	BeginCombo :: proc(
		label: cstring,
		preview_value: cstring,
		flags: ComboFlags = {}) -> bool ---
	// only call EndCombo() if BeginCombo() returns true!
	@(link_name = "ImGui_EndCombo")
	EndCombo :: proc() ---
	@(link_name = "ImGui_ComboChar")
	ComboChar :: proc(
		label: cstring,
		current_item: ^i32,
		items: [^]cstring,
		items_count: i32,
		popup_max_height_in_items: i32 = -1) -> bool ---
	// Separate items with \0 within a string, end item-list with \0\0. e.g. "One\0Two\0Three\0"
	@(link_name = "ImGui_Combo")
	Combo :: proc(
		label: cstring,
		current_item: ^i32,
		items_separated_by_zeros: cstring,
		popup_max_height_in_items: i32 = -1) -> bool ---
	@(link_name = "ImGui_ComboCallback")
	ComboCallback :: proc(
		label: cstring,
		current_item: ^i32,
		getter: proc "c" (user_data: rawptr, idx: i32) -> cstring,
		user_data: rawptr,
		items_count: i32,
		popup_max_height_in_items: i32 = -1) -> bool ---
	// Widgets: Drag Sliders
	// - Ctrl+Click on any drag box to turn them into an input box. Manually input values aren't clamped by default and can go off-bounds. Use ImGuiSliderFlags_AlwaysClamp to always clamp.
	// - For all the Float2/Float3/Float4/Int2/Int3/Int4 versions of every function, note that a 'float v[X]' function argument is the same as 'float* v',
	//   the array syntax is just a way to document the number of elements that are expected to be accessible. You can pass address of your first element out of a contiguous set, e.g. &myvector.x
	// - Adjust format string to decorate the value with a prefix, a suffix, or adapt the editing and display precision e.g. "%.3f" -> 1.234; "%5.2f secs" -> 01.23 secs; "Biscuit: %.0f" -> Biscuit: 1; etc.
	// - Format string may also be set to NULL or use the default format ("%f" or "%d").
	// - Speed are per-pixel of mouse movement (v_speed=0.2f: mouse needs to move by 5 pixels to increase value by 1). For keyboard/gamepad navigation, minimum speed is Max(v_speed, minimum_step_at_given_precision).
	// - Use v_min < v_max to clamp edits to given limits. Note that Ctrl+Click manual input can override those limits if ImGuiSliderFlags_AlwaysClamp is not used.
	// - Use v_max = FLT_MAX / INT_MAX etc to avoid clamping to a maximum, same with v_min = -FLT_MAX / INT_MIN to avoid clamping to a minimum.
	// - We use the same sets of flags for DragXXX() and SliderXXX() functions as the features are the same and it makes it easier to swap them.
	// - Legacy: Pre-1.78 there are DragXXX() function signatures that take a final `float power=1.0f' argument instead of the `ImGuiSliderFlags flags=0' argument.
	//   If you get a warning converting a float to ImGuiSliderFlags, read https://github.com/ocornut/imgui/issues/3361
	// If v_min >= v_max we have no bound
	@(link_name = "ImGui_DragFloat")
	DragFloat :: proc(
		label: cstring,
		v: ^f32,
		v_speed: f32 = 1.0,
		v_min: f32 = 0.0,
		v_max: f32 = 0.0,
		format: cstring = "%.3f",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_DragFloat2")
	DragFloat2 :: proc(
		label: cstring,
		v: ^[2]f32,
		v_speed: f32 = 1.0,
		v_min: f32 = 0.0,
		v_max: f32 = 0.0,
		format: cstring = "%.3f",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_DragFloat3")
	DragFloat3 :: proc(
		label: cstring,
		v: ^[3]f32,
		v_speed: f32 = 1.0,
		v_min: f32 = 0.0,
		v_max: f32 = 0.0,
		format: cstring = "%.3f",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_DragFloat4")
	DragFloat4 :: proc(
		label: cstring,
		v: ^[4]f32,
		v_speed: f32 = 1.0,
		v_min: f32 = 0.0,
		v_max: f32 = 0.0,
		format: cstring = "%.3f",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_DragFloatRange2")
	DragFloatRange2 :: proc(
		label: cstring,
		v_current_min: ^f32,
		v_current_max: ^f32,
		v_speed: f32 = 1.0,
		v_min: f32 = 0.0,
		v_max: f32 = 0.0,
		format: cstring = "%.3f",
		format_max: cstring = nil,
		flags: SliderFlags = {}) -> bool ---
	// If v_min >= v_max we have no bound
	@(link_name = "ImGui_DragInt")
	DragInt :: proc(
		label: cstring,
		v: ^i32,
		v_speed: f32 = 1.0,
		v_min: i32 = 0,
		v_max: i32 = 0,
		format: cstring = "%d",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_DragInt2")
	DragInt2 :: proc(
		label: cstring,
		v: ^[2]i32,
		v_speed: f32 = 1.0,
		v_min: i32 = 0,
		v_max: i32 = 0,
		format: cstring = "%d",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_DragInt3")
	DragInt3 :: proc(
		label: cstring,
		v: ^[3]i32,
		v_speed: f32 = 1.0,
		v_min: i32 = 0,
		v_max: i32 = 0,
		format: cstring = "%d",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_DragInt4")
	DragInt4 :: proc(
		label: cstring,
		v: ^[4]i32,
		v_speed: f32 = 1.0,
		v_min: i32 = 0,
		v_max: i32 = 0,
		format: cstring = "%d",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_DragIntRange2")
	DragIntRange2 :: proc(
		label: cstring,
		v_current_min: ^i32,
		v_current_max: ^i32,
		v_speed: f32 = 1.0,
		v_min: i32 = 0,
		v_max: i32 = 0,
		format: cstring = "%d",
		format_max: cstring = nil,
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_DragScalar")
	DragScalar :: proc(
		label: cstring,
		data_type: DataType,
		p_data: rawptr,
		v_speed: f32 = 1.0,
		p_min: rawptr = nil,
		p_max: rawptr = nil,
		format: cstring = nil,
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_DragScalarN")
	DragScalarN :: proc(
		label: cstring,
		data_type: DataType,
		p_data: rawptr,
		components: i32,
		v_speed: f32 = 1.0,
		p_min: rawptr = nil,
		p_max: rawptr = nil,
		format: cstring = nil,
		flags: SliderFlags = {}) -> bool ---
	// Widgets: Regular Sliders
	// - Ctrl+Click on any slider to turn them into an input box. Manually input values aren't clamped by default and can go off-bounds. Use ImGuiSliderFlags_AlwaysClamp to always clamp.
	// - Adjust format string to decorate the value with a prefix, a suffix, or adapt the editing and display precision e.g. "%.3f" -> 1.234; "%5.2f secs" -> 01.23 secs; "Biscuit: %.0f" -> Biscuit: 1; etc.
	// - Format string may also be set to NULL or use the default format ("%f" or "%d").
	// - Legacy: Pre-1.78 there are SliderXXX() function signatures that take a final `float power=1.0f' argument instead of the `ImGuiSliderFlags flags=0' argument.
	//   If you get a warning converting a float to ImGuiSliderFlags, read https://github.com/ocornut/imgui/issues/3361
	// adjust format to decorate the value with a prefix or a suffix for in-slider labels or unit display.
	@(link_name = "ImGui_SliderFloat")
	SliderFloat :: proc(
		label: cstring,
		v: ^f32,
		v_min: f32,
		v_max: f32,
		format: cstring = "%.3f",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_SliderFloat2")
	SliderFloat2 :: proc(
		label: cstring,
		v: ^[2]f32,
		v_min: f32,
		v_max: f32,
		format: cstring = "%.3f",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_SliderFloat3")
	SliderFloat3 :: proc(
		label: cstring,
		v: ^[3]f32,
		v_min: f32,
		v_max: f32,
		format: cstring = "%.3f",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_SliderFloat4")
	SliderFloat4 :: proc(
		label: cstring,
		v: ^[4]f32,
		v_min: f32,
		v_max: f32,
		format: cstring = "%.3f",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_SliderAngle")
	SliderAngle :: proc(
		label: cstring,
		v_rad: ^f32,
		v_degrees_min: f32 = -360.0,
		v_degrees_max: f32 = +360.0,
		format: cstring = "%.0f deg",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_SliderInt")
	SliderInt :: proc(
		label: cstring,
		v: ^i32,
		v_min: i32,
		v_max: i32,
		format: cstring = "%d",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_SliderInt2")
	SliderInt2 :: proc(
		label: cstring,
		v: ^[2]i32,
		v_min: i32,
		v_max: i32,
		format: cstring = "%d",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_SliderInt3")
	SliderInt3 :: proc(
		label: cstring,
		v: ^[3]i32,
		v_min: i32,
		v_max: i32,
		format: cstring = "%d",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_SliderInt4")
	SliderInt4 :: proc(
		label: cstring,
		v: ^[4]i32,
		v_min: i32,
		v_max: i32,
		format: cstring = "%d",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_SliderScalar")
	SliderScalar :: proc(
		label: cstring,
		data_type: DataType,
		p_data: rawptr,
		p_min: rawptr,
		p_max: rawptr,
		format: cstring = nil,
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_SliderScalarN")
	SliderScalarN :: proc(
		label: cstring,
		data_type: DataType,
		p_data: rawptr,
		components: i32,
		p_min: rawptr,
		p_max: rawptr,
		format: cstring = nil,
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_VSliderFloat")
	VSliderFloat :: proc(
		label: cstring,
		size: Vec2,
		v: ^f32,
		v_min: f32,
		v_max: f32,
		format: cstring = "%.3f",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_VSliderInt")
	VSliderInt :: proc(
		label: cstring,
		size: Vec2,
		v: ^i32,
		v_min: i32,
		v_max: i32,
		format: cstring = "%d",
		flags: SliderFlags = {}) -> bool ---
	@(link_name = "ImGui_VSliderScalar")
	VSliderScalar :: proc(
		label: cstring,
		size: Vec2,
		data_type: DataType,
		p_data: rawptr,
		p_min: rawptr,
		p_max: rawptr,
		format: cstring = nil,
		flags: SliderFlags = {}) -> bool ---
	// Widgets: Input with Keyboard
	// - If you want to use InputText() with std::string or any custom dynamic string type, use the wrapper in misc/cpp/imgui_stdlib.h/.cpp!
	// - Most of the ImGuiInputTextFlags flags are only useful for InputText() and not for InputFloatX, InputIntX, InputDouble etc.
	@(link_name = "ImGui_InputText")
	InputText :: proc(
		label: cstring,
		buf: cstring,
		buf_size: uint,
		flags: InputTextFlags = {},
		callback: InputTextCallback = nil,
		user_data: rawptr = nil) -> bool ---
	@(link_name = "ImGui_InputTextMultiline")
	InputTextMultiline :: proc(
		label: cstring,
		buf: cstring,
		buf_size: uint,
		size: Vec2 = Vec2{0, 0},
		flags: InputTextFlags = {},
		callback: InputTextCallback = nil,
		user_data: rawptr = nil) -> bool ---
	@(link_name = "ImGui_InputTextWithHint")
	InputTextWithHint :: proc(
		label: cstring,
		hint: cstring,
		buf: cstring,
		buf_size: uint,
		flags: InputTextFlags = {},
		callback: InputTextCallback = nil,
		user_data: rawptr = nil) -> bool ---
	@(link_name = "ImGui_InputFloat")
	InputFloat :: proc(
		label: cstring,
		v: ^f32,
		step: f32 = 0.0,
		step_fast: f32 = 0.0,
		format: cstring = "%.3f",
		flags: InputTextFlags = {}) -> bool ---
	@(link_name = "ImGui_InputFloat2")
	InputFloat2 :: proc(
		label: cstring,
		v: ^[2]f32,
		format: cstring = "%.3f",
		flags: InputTextFlags = {}) -> bool ---
	@(link_name = "ImGui_InputFloat3")
	InputFloat3 :: proc(
		label: cstring,
		v: ^[3]f32,
		format: cstring = "%.3f",
		flags: InputTextFlags = {}) -> bool ---
	@(link_name = "ImGui_InputFloat4")
	InputFloat4 :: proc(
		label: cstring,
		v: ^[4]f32,
		format: cstring = "%.3f",
		flags: InputTextFlags = {}) -> bool ---
	@(link_name = "ImGui_InputInt")
	InputInt :: proc(
		label: cstring,
		v: ^i32,
		step: i32 = 1,
		step_fast: i32 = 100,
		flags: InputTextFlags = {}) -> bool ---
	@(link_name = "ImGui_InputInt2")
	InputInt2 :: proc(
		label: cstring,
		v: ^[2]i32,
		flags: InputTextFlags = {}) -> bool ---
	@(link_name = "ImGui_InputInt3")
	InputInt3 :: proc(
		label: cstring,
		v: ^[3]i32,
		flags: InputTextFlags = {}) -> bool ---
	@(link_name = "ImGui_InputInt4")
	InputInt4 :: proc(
		label: cstring,
		v: ^[4]i32,
		flags: InputTextFlags = {}) -> bool ---
	@(link_name = "ImGui_InputDouble")
	InputDouble :: proc(
		label: cstring,
		v: ^f64,
		step: f64 = 0.0,
		step_fast: f64 = 0.0,
		format: cstring = "%.6f",
		flags: InputTextFlags = {}) -> bool ---
	@(link_name = "ImGui_InputScalar")
	InputScalar :: proc(
		label: cstring,
		data_type: DataType,
		p_data: rawptr,
		p_step: rawptr = nil,
		p_step_fast: rawptr = nil,
		format: cstring = nil,
		flags: InputTextFlags = {}) -> bool ---
	@(link_name = "ImGui_InputScalarN")
	InputScalarN :: proc(
		label: cstring,
		data_type: DataType,
		p_data: rawptr,
		components: i32,
		p_step: rawptr = nil,
		p_step_fast: rawptr = nil,
		format: cstring = nil,
		flags: InputTextFlags = {}) -> bool ---
	// Widgets: Color Editor/Picker (tip: the ColorEdit* functions have a little color square that can be left-clicked to open a picker, and right-clicked to open an option menu.)
	// - Note that in C++ a 'float v[X]' function argument is the _same_ as 'float* v', the array syntax is just a way to document the number of elements that are expected to be accessible.
	// - You can pass the address of a first float element out of a contiguous structure, e.g. &myvector.x
	@(link_name = "ImGui_ColorEdit3")
	ColorEdit3 :: proc(
		label: cstring,
		col: ^[3]f32,
		flags: ColorEditFlags = {}) -> bool ---
	@(link_name = "ImGui_ColorEdit4")
	ColorEdit4 :: proc(
		label: cstring,
		col: ^[4]f32,
		flags: ColorEditFlags = {}) -> bool ---
	@(link_name = "ImGui_ColorPicker3")
	ColorPicker3 :: proc(
		label: cstring,
		col: ^[3]f32,
		flags: ColorEditFlags = {}) -> bool ---
	@(link_name = "ImGui_ColorPicker4")
	ColorPicker4 :: proc(
		label: cstring,
		col: ^[4]f32,
		flags: ColorEditFlags = {},
		ref_col: ^f32 = nil) -> bool ---
	// display a color square/button, hover for details, return true when pressed.
	@(link_name = "ImGui_ColorButton")
	ColorButton :: proc(
		desc_id: cstring,
		col: Vec4,
		flags: ColorEditFlags = {},
		size: Vec2 = Vec2{0, 0}) -> bool ---
	// Widgets: Trees
	// - TreeNode functions return true when the node is open, in which case you need to also call TreePop() when you are finished displaying the tree node contents.
	@(link_name = "ImGui_TreeNode")
	TreeNode :: proc(
		label: cstring) -> bool ---
	// helper variation to easily decorrelate the id from the displayed string. Read the FAQ about why and how to use ID. to align arbitrary text at the same level as a TreeNode() you can use Bullet().
	@(link_name = "ImGui_TreeNodeStr")
	TreeNodeStr :: proc(
		str_id: cstring,
		fmt: cstring,
		#c_vararg args: ..any) -> bool ---
	// "
	@(link_name = "ImGui_TreeNodePtr")
	TreeNodePtr :: proc(
		ptr_id: rawptr,
		fmt: cstring,
		#c_vararg args: ..any) -> bool ---
	@(link_name = "ImGui_TreeNodeEx")
	TreeNodeEx :: proc(
		label: cstring,
		flags: TreeNodeFlags = {}) -> bool ---
	@(link_name = "ImGui_TreeNodeExStr")
	TreeNodeExStr :: proc(
		str_id: cstring,
		flags: TreeNodeFlags,
		fmt: cstring,
		#c_vararg args: ..any) -> bool ---
	@(link_name = "ImGui_TreeNodeExPtr")
	TreeNodeExPtr :: proc(
		ptr_id: rawptr,
		flags: TreeNodeFlags,
		fmt: cstring,
		#c_vararg args: ..any) -> bool ---
	// ~ Indent()+PushID(). Already called by TreeNode() when returning true, but you can call TreePush/TreePop yourself if desired.
	@(link_name = "ImGui_TreePush")
	TreePush :: proc(
		str_id: cstring) ---
	// "
	@(link_name = "ImGui_TreePushPtr")
	TreePushPtr :: proc(
		ptr_id: rawptr) ---
	// ~ Unindent()+PopID()
	@(link_name = "ImGui_TreePop")
	TreePop :: proc() ---
	// horizontal distance preceding label when using TreeNode*() or Bullet() == (g.FontSize + style.FramePadding.x*2) for a regular unframed TreeNode
	@(link_name = "ImGui_GetTreeNodeToLabelSpacing")
	GetTreeNodeToLabelSpacing :: proc() -> f32 ---
	// if returning 'true' the header is open. doesn't indent nor push on ID stack. user doesn't have to call TreePop().
	@(link_name = "ImGui_CollapsingHeader")
	CollapsingHeader :: proc(
		label: cstring,
		flags: TreeNodeFlags = {}) -> bool ---
	// when 'p_visible != NULL': if '*p_visible==true' display an additional small close button on upper right of the header which will set the bool to false when clicked, if '*p_visible==false' don't display the header.
	@(link_name = "ImGui_CollapsingHeaderBoolPtr")
	CollapsingHeaderBoolPtr :: proc(
		label: cstring,
		p_visible: ^bool,
		flags: TreeNodeFlags = {}) -> bool ---
	// set next TreeNode/CollapsingHeader open state.
	@(link_name = "ImGui_SetNextItemOpen")
	SetNextItemOpen :: proc(
		is_open: bool,
		cond: Cond = {}) ---
	// set id to use for open/close storage (default to same as item id).
	@(link_name = "ImGui_SetNextItemStorageID")
	SetNextItemStorageID :: proc(
		storage_id: ID) ---
	// retrieve tree node open/close state.
	@(link_name = "ImGui_TreeNodeGetOpen")
	TreeNodeGetOpen :: proc(
		storage_id: ID) -> bool ---
	// Widgets: Selectables
	// - A selectable highlights when hovered, and can display another color when selected.
	// - Neighbors selectable extend their highlight bounds in order to leave no gap between them. This is so a series of selected Selectable appear contiguous.
	// "bool selected" carry the selection state (read-only). Selectable() is clicked is returns true so you can modify your selection state. size.x==0.0: use remaining width, size.x>0.0: specify width. size.y==0.0: use label height, size.y>0.0: specify height
	@(link_name = "ImGui_Selectable")
	Selectable :: proc(
		label: cstring,
		selected: bool = false,
		flags: SelectableFlags = {},
		size: Vec2 = Vec2{0, 0}) -> bool ---
	// "bool* p_selected" point to the selection state (read-write), as a convenient helper.
	@(link_name = "ImGui_SelectableBoolPtr")
	SelectableBoolPtr :: proc(
		label: cstring,
		p_selected: ^bool,
		flags: SelectableFlags = {},
		size: Vec2 = Vec2{0, 0}) -> bool ---
	// Multi-selection system for Selectable(), Checkbox(), TreeNode() functions [BETA]
	// - This enables standard multi-selection/range-selection idioms (Ctrl+Mouse/Keyboard, Shift+Mouse/Keyboard, etc.) in a way that also allow a clipper to be used.
	// - ImGuiSelectionUserData is often used to store your item index within the current view (but may store something else).
	// - Read comments near ImGuiMultiSelectIO for instructions/details and see 'Demo->Widgets->Selection State & Multi-Select' for demo.
	// - TreeNode() is technically supported but... using this correctly is more complicated. You need some sort of linear/random access to your tree,
	//   which is suited to advanced trees setups already implementing filters and clipper. We will work simplifying the current demo.
	// - 'selection_size' and 'items_count' parameters are optional and used by a few features. If they are costly for you to compute, you may avoid them.
	@(link_name = "ImGui_BeginMultiSelect")
	BeginMultiSelect :: proc(
		flags: MultiSelectFlags,
		selection_size: i32 = -1,
		items_count: i32 = -1) -> ^MultiSelectIO ---
	@(link_name = "ImGui_EndMultiSelect")
	EndMultiSelect :: proc() -> ^MultiSelectIO ---
	@(link_name = "ImGui_SetNextItemSelectionUserData")
	SetNextItemSelectionUserData :: proc(
		selection_user_data: SelectionUserData) ---
	// Was the last item selection state toggled? Useful if you need the per-item information _before_ reaching EndMultiSelect(). We only returns toggle _event_ in order to handle clipping correctly.
	@(link_name = "ImGui_IsItemToggledSelection")
	IsItemToggledSelection :: proc() -> bool ---
	// Widgets: List Boxes
	// - This is essentially a thin wrapper to using BeginChild/EndChild with the ImGuiChildFlags_FrameStyle flag for stylistic changes + displaying a label.
	// - If you don't need a label you can probably simply use BeginChild() with the ImGuiChildFlags_FrameStyle flag for the same result.
	// - You can submit contents and manage your selection state however you want it, by creating e.g. Selectable() or any other items.
	// - The simplified/old ListBox() api are helpers over BeginListBox()/EndListBox() which are kept available for convenience purpose. This is analogous to how Combos are created.
	// - Choose frame width:   size.x > 0.0f: custom  /  size.x < 0.0f or -FLT_MIN: right-align   /  size.x = 0.0f (default): use current ItemWidth
	// - Choose frame height:  size.y > 0.0f: custom  /  size.y < 0.0f or -FLT_MIN: bottom-align  /  size.y = 0.0f (default): arbitrary default height which can fit ~7 items
	// open a framed scrolling region
	@(link_name = "ImGui_BeginListBox")
	BeginListBox :: proc(
		label: cstring,
		size: Vec2 = Vec2{0, 0}) -> bool ---
	// only call EndListBox() if BeginListBox() returned true!
	@(link_name = "ImGui_EndListBox")
	EndListBox :: proc() ---
	@(link_name = "ImGui_ListBox")
	ListBox :: proc(
		label: cstring,
		current_item: ^i32,
		items: [^]cstring,
		items_count: i32,
		height_in_items: i32 = -1) -> bool ---
	@(link_name = "ImGui_ListBoxCallback")
	ListBoxCallback :: proc(
		label: cstring,
		current_item: ^i32,
		getter: proc "c" (user_data: rawptr, idx: i32) -> cstring,
		user_data: rawptr,
		items_count: i32,
		height_in_items: i32 = -1) -> bool ---
	// Widgets: Data Plotting
	// - Consider using ImPlot (https://github.com/epezent/implot) which is much better!
	@(link_name = "ImGui_PlotLines")
	PlotLines :: proc(
		label: cstring,
		values: ^f32,
		values_count: i32,
		values_offset: i32 = 0,
		overlay_text: cstring = nil,
		scale_min: f32 = max(f32),
		scale_max: f32 = max(f32),
		graph_size: Vec2 = Vec2{0, 0},
		stride: i32 = size_of(f32)) ---
	@(link_name = "ImGui_PlotLinesCallback")
	PlotLinesCallback :: proc(
		label: cstring,
		values_getter: proc "c" (data: rawptr, idx: i32) -> f32,
		data: rawptr,
		values_count: i32,
		values_offset: i32 = 0,
		overlay_text: cstring = nil,
		scale_min: f32 = max(f32),
		scale_max: f32 = max(f32),
		graph_size: Vec2 = Vec2{0, 0}) ---
	@(link_name = "ImGui_PlotHistogram")
	PlotHistogram :: proc(
		label: cstring,
		values: ^f32,
		values_count: i32,
		values_offset: i32 = 0,
		overlay_text: cstring = nil,
		scale_min: f32 = max(f32),
		scale_max: f32 = max(f32),
		graph_size: Vec2 = Vec2{0, 0},
		stride: i32 = size_of(f32)) ---
	@(link_name = "ImGui_PlotHistogramCallback")
	PlotHistogramCallback :: proc(
		label: cstring,
		values_getter: proc "c" (data: rawptr, idx: i32) -> f32,
		data: rawptr,
		values_count: i32,
		values_offset: i32 = 0,
		overlay_text: cstring = nil,
		scale_min: f32 = max(f32),
		scale_max: f32 = max(f32),
		graph_size: Vec2 = Vec2{0, 0}) ---
	// Widgets: Menus
	// - Use BeginMenuBar() on a window ImGuiWindowFlags_MenuBar to append to its menu bar.
	// - Use BeginMainMenuBar() to create a menu bar at the top of the screen and append to it.
	// - Use BeginMenu() to create a menu. You can call BeginMenu() multiple time with the same identifier to append more items to it.
	// - Note that MenuItem() keyboard shortcuts are displayed as a convenience but _not processed_ by Dear ImGui at the moment.
	// append to menu-bar of current window (requires ImGuiWindowFlags_MenuBar flag set on parent window).
	@(link_name = "ImGui_BeginMenuBar")
	BeginMenuBar :: proc() -> bool ---
	// only call EndMenuBar() if BeginMenuBar() returns true!
	@(link_name = "ImGui_EndMenuBar")
	EndMenuBar :: proc() ---
	// create and append to a full screen menu-bar.
	@(link_name = "ImGui_BeginMainMenuBar")
	BeginMainMenuBar :: proc() -> bool ---
	// only call EndMainMenuBar() if BeginMainMenuBar() returns true!
	@(link_name = "ImGui_EndMainMenuBar")
	EndMainMenuBar :: proc() ---
	// create a sub-menu entry. only call EndMenu() if this returns true!
	@(link_name = "ImGui_BeginMenu")
	BeginMenu :: proc(
		label: cstring,
		enabled: bool = true) -> bool ---
	// only call EndMenu() if BeginMenu() returns true!
	@(link_name = "ImGui_EndMenu")
	EndMenu :: proc() ---
	// return true when activated.
	@(link_name = "ImGui_MenuItem")
	MenuItem :: proc(
		label: cstring,
		shortcut: cstring = nil,
		selected: bool = false,
		enabled: bool = true) -> bool ---
	// return true when activated + toggle (*p_selected) if p_selected != NULL
	@(link_name = "ImGui_MenuItemBoolPtr")
	MenuItemBoolPtr :: proc(
		label: cstring,
		shortcut: cstring,
		p_selected: ^bool,
		enabled: bool = true) -> bool ---
	// Tooltips
	// - Tooltips are windows following the mouse. They do not take focus away.
	// - A tooltip window can contain items of any types.
	// - SetTooltip() is more or less a shortcut for the 'if (BeginTooltip()) { Text(...); EndTooltip(); }' idiom (with a subtlety that it discard any previously submitted tooltip)
	// begin/append a tooltip window.
	@(link_name = "ImGui_BeginTooltip")
	BeginTooltip :: proc() -> bool ---
	// only call EndTooltip() if BeginTooltip()/BeginItemTooltip() returns true!
	@(link_name = "ImGui_EndTooltip")
	EndTooltip :: proc() ---
	// set a text-only tooltip. Often used after a ImGui::IsItemHovered() check. Override any previous call to SetTooltip().
	@(link_name = "ImGui_SetTooltip")
	SetTooltip :: proc(
		fmt: cstring,
		#c_vararg args: ..any) ---
	// Tooltips: helpers for showing a tooltip when hovering an item
	// - BeginItemTooltip() is a shortcut for the 'if (IsItemHovered(ImGuiHoveredFlags_ForTooltip) && BeginTooltip())' idiom.
	// - SetItemTooltip() is a shortcut for the 'if (IsItemHovered(ImGuiHoveredFlags_ForTooltip)) { SetTooltip(...); }' idiom.
	// - Where 'ImGuiHoveredFlags_ForTooltip' itself is a shortcut to use 'style.HoverFlagsForTooltipMouse' or 'style.HoverFlagsForTooltipNav' depending on active input type. For mouse it defaults to 'ImGuiHoveredFlags_Stationary | ImGuiHoveredFlags_DelayShort'.
	// begin/append a tooltip window if preceding item was hovered.
	@(link_name = "ImGui_BeginItemTooltip")
	BeginItemTooltip :: proc() -> bool ---
	// set a text-only tooltip if preceding item was hovered. override any previous call to SetTooltip().
	@(link_name = "ImGui_SetItemTooltip")
	SetItemTooltip :: proc(
		fmt: cstring,
		#c_vararg args: ..any) ---
	// Popups, Modals
	//  - They block normal mouse hovering detection (and therefore most mouse interactions) behind them.
	//  - If not modal: they can be closed by clicking anywhere outside them, or by pressing Escape (call 'Shortcut(ImGuiKey_Escape)' to claim a higher-priority shortcut).
	//  - Their visibility state (~bool) is held internally instead of being held by the programmer as we are used to with regular Begin*() calls.
	//  - The 3 properties above are related: we need to retain popup visibility state in the library because popups may be closed as any time.
	//  - You can bypass the hovering restriction by using ImGuiHoveredFlags_AllowWhenBlockedByPopup when calling IsItemHovered() or IsWindowHovered().
	//  - IMPORTANT: Popup identifiers are relative to the current ID stack, so OpenPopup and BeginPopup generally needs to be at the same level of the stack.
	//    This is sometimes leading to confusing mistakes. May rework this in the future.
	//  - BeginPopup(): query popup state, if open start appending into the window. Call EndPopup() afterwards if returned true. ImGuiWindowFlags are forwarded to the window.
	//  - BeginPopupModal(): block every interaction behind the window, cannot be closed by user, add a dimming background, has a title bar.
	// return true if the popup is open, and you can start outputting to it.
	@(link_name = "ImGui_BeginPopup")
	BeginPopup :: proc(
		str_id: cstring,
		flags: WindowFlags = {}) -> bool ---
	// return true if the modal is open, and you can start outputting to it.
	@(link_name = "ImGui_BeginPopupModal")
	BeginPopupModal :: proc(
		name: cstring,
		p_open: ^bool = nil,
		flags: WindowFlags = {}) -> bool ---
	// only call EndPopup() if BeginPopupXXX() returns true!
	@(link_name = "ImGui_EndPopup")
	EndPopup :: proc() ---
	// Popups: open/close functions
	//  - OpenPopup(): set popup state to open (unless one of the specified ImGuiPopupFlags prevent opening).
	//  - OpenPopupXXX() functions return true when the popup is toggled open, which allows you to capture local state if needed.
	//    You may also call IsWindowAppearing() inside the later BeginPopup() scope if you need to prepare/compute data for the popup.
	//  - If not modal: they can be closed by clicking anywhere outside them, or by pressing ESCAPE.
	//  - CloseCurrentPopup(): use inside the BeginPopup()/EndPopup() scope to close manually.
	//  - CloseCurrentPopup() is called by default by Selectable()/MenuItem() when activated (FIXME: need some options).
	//  - Use ImGuiPopupFlags_NoOpenOverExistingPopup to avoid opening a popup if there's already one at the same level. This is equivalent to e.g. testing for !IsAnyPopupOpen() prior to OpenPopup().
	//  - Use IsWindowAppearing() after BeginPopup() to tell if a window just opened.
	// call to mark popup as open (don't call every frame!).
	@(link_name = "ImGui_OpenPopup")
	OpenPopup :: proc(
		str_id: cstring,
		popup_flags: PopupFlags = {}) -> bool ---
	// id overload to facilitate calling from nested stacks
	@(link_name = "ImGui_OpenPopupID")
	OpenPopupID :: proc(
		id: ID,
		popup_flags: PopupFlags = {}) -> bool ---
	// helper to open popup when clicked on last item. Default to ImGuiPopupFlags_MouseButtonRight == 1. (note: actually triggers on the mouse _released_ event to be consistent with popup behaviors)
	@(link_name = "ImGui_OpenPopupOnItemClick")
	OpenPopupOnItemClick :: proc(
		str_id: cstring = nil,
		popup_flags: PopupFlags = {}) -> bool ---
	// manually close the popup we have begin-ed into.
	@(link_name = "ImGui_CloseCurrentPopup")
	CloseCurrentPopup :: proc() ---
	// Popups: Open+Begin popup combined functions helpers to create context menus.
	//  - Helpers to do OpenPopup+BeginPopup where the Open action is triggered by e.g. hovering an item and right-clicking.
	//  - IMPORTANT: Notice that BeginPopupContextXXX takes ImGuiPopupFlags just like OpenPopup() and unlike BeginPopup(). For full consistency, we may add ImGuiWindowFlags to the BeginPopupContextXXX functions in the future.
	//  - IMPORTANT: If you ever used the left mouse button with BeginPopupContextXXX() helpers before 1.92.6:
	//    - Before this version, OpenPopupOnItemClick(), BeginPopupContextItem(), BeginPopupContextWindow(), BeginPopupContextVoid() had 'a ImGuiPopupFlags popup_flags = 1' default value in their function signature.
	//    - Before: Explicitly passing a literal 0 meant ImGuiPopupFlags_MouseButtonLeft. The default = 1 meant ImGuiPopupFlags_MouseButtonRight.
	//    - After: The default = 0 means ImGuiPopupFlags_MouseButtonRight. Explicitly passing a literal 1 also means ImGuiPopupFlags_MouseButtonRight (if legacy behavior are enabled) or will assert (if legacy behavior are disabled).
	//    - TL;DR: if you don't want to use right mouse button for popups, always specify it explicitly using a named ImGuiPopupFlags_MouseButtonXXXX value.
	//    - Read "API BREAKING CHANGES" 2026/01/07 (1.92.6) entry in imgui.cpp or GitHub topic #9157 for all details.
	// open+begin popup when clicked on last item. Use str_id==NULL to associate the popup to previous item. If you want to use that on a non-interactive item such as Text() you need to pass in an explicit ID here. read comments in .cpp!
	@(link_name = "ImGui_BeginPopupContextItem")
	BeginPopupContextItem :: proc(
		str_id: cstring = nil,
		popup_flags: PopupFlags = {}) -> bool ---
	// open+begin popup when clicked on current window.
	@(link_name = "ImGui_BeginPopupContextWindow")
	BeginPopupContextWindow :: proc(
		str_id: cstring = nil,
		popup_flags: PopupFlags = {}) -> bool ---
	// open+begin popup when clicked in void (where there are no windows).
	@(link_name = "ImGui_BeginPopupContextVoid")
	BeginPopupContextVoid :: proc(
		str_id: cstring = nil,
		popup_flags: PopupFlags = {}) -> bool ---
	// Popups: query functions
	//  - IsPopupOpen(): return true if the popup is open at the current BeginPopup() level of the popup stack.
	//  - IsPopupOpen() with ImGuiPopupFlags_AnyPopupId: return true if any popup is open at the current BeginPopup() level of the popup stack.
	//  - IsPopupOpen() with ImGuiPopupFlags_AnyPopupId + ImGuiPopupFlags_AnyPopupLevel: return true if any popup is open.
	// return true if the popup is open.
	@(link_name = "ImGui_IsPopupOpen")
	IsPopupOpen :: proc(
		str_id: cstring,
		flags: PopupFlags = {}) -> bool ---
	// Tables
	// - Full-featured replacement for old Columns API.
	// - See Demo->Tables for demo code. See top of imgui_tables.cpp for general commentary.
	// - See ImGuiTableFlags_ and ImGuiTableColumnFlags_ enums for a description of available flags.
	// The typical call flow is:
	// - 1. Call BeginTable(), early out if returning false.
	// - 2. Optionally call TableSetupColumn() to submit column name/flags/defaults.
	// - 3. Optionally call TableSetupScrollFreeze() to request scroll freezing of columns/rows.
	// - 4. Optionally call TableHeadersRow() to submit a header row. Names are pulled from TableSetupColumn() data.
	// - 5. Populate contents:
	//    - In most situations you can use TableNextRow() + TableSetColumnIndex(N) to start appending into a column.
	//    - If you are using tables as a sort of grid, where every column is holding the same type of contents,
	//      you may prefer using TableNextColumn() instead of TableNextRow() + TableSetColumnIndex().
	//      TableNextColumn() will automatically wrap-around into the next row if needed.
	//    - IMPORTANT: Comparatively to the old Columns() API, we need to call TableNextColumn() for the first column!
	//    - Summary of possible call flow:
	//        - TableNextRow() -> TableSetColumnIndex(0) -> Text("Hello 0") -> TableSetColumnIndex(1) -> Text("Hello 1")  // OK
	//        - TableNextRow() -> TableNextColumn()      -> Text("Hello 0") -> TableNextColumn()      -> Text("Hello 1")  // OK
	//        -                   TableNextColumn()      -> Text("Hello 0") -> TableNextColumn()      -> Text("Hello 1")  // OK: TableNextColumn() automatically gets to next row!
	//        - TableNextRow()                           -> Text("Hello 0")                                               // Not OK! Missing TableSetColumnIndex() or TableNextColumn()! Text will not appear!
	// - 5. Call EndTable()
	@(link_name = "ImGui_BeginTable")
	BeginTable :: proc(
		str_id: cstring,
		columns: i32,
		flags: TableFlags = {},
		outer_size: Vec2 = Vec2{0.0, 0.0},
		inner_width: f32 = 0.0) -> bool ---
	// only call EndTable() if BeginTable() returns true!
	@(link_name = "ImGui_EndTable")
	EndTable :: proc() ---
	// append into the first cell of a new row. 'min_row_height' include the minimum top and bottom padding aka CellPadding.y * 2.0f.
	@(link_name = "ImGui_TableNextRow")
	TableNextRow :: proc(
		row_flags: TableRowFlags = {},
		min_row_height: f32 = 0.0) ---
	// append into the next column (or first column of next row if currently in last column). Return true when column is visible.
	@(link_name = "ImGui_TableNextColumn")
	TableNextColumn :: proc() -> bool ---
	// append into the specified column. Return true when column is visible.
	@(link_name = "ImGui_TableSetColumnIndex")
	TableSetColumnIndex :: proc(
		column_n: i32) -> bool ---
	// Tables: Headers & Columns declaration
	// - Use TableSetupColumn() to specify label, resizing policy, default width/weight, various other flags etc.
	//   (the trailing 'ImGuiID user_data', which used to be referred to as 'ImGuiID user_id', is merely user data that is blindly copied in ImGuiTableColumnSortSpecs).
	// - Use TableHeadersRow() to create a header row and automatically submit a TableHeader() for each column.
	//   Headers are required to perform: reordering, sorting, and opening the context menu.
	//   The context menu can also be made available in columns body using ImGuiTableFlags_ContextMenuInBody.
	// - You may manually submit headers using TableNextRow() + TableHeader() calls, but this is only useful in
	//   some advanced use cases (e.g. adding custom widgets in header row).
	// - Use TableSetupScrollFreeze() to lock columns/rows so they stay visible when scrolled. When freezing columns you would usually also use ImGuiTableColumnFlags_NoHide on them.
	@(link_name = "ImGui_TableSetupColumn")
	TableSetupColumn :: proc(
		label: cstring,
		flags: TableColumnFlags = {},
		init_width_or_weight: f32 = 0.0,
		user_data: ID = {}) ---
	// lock columns/rows so they stay visible when scrolled.
	@(link_name = "ImGui_TableSetupScrollFreeze")
	TableSetupScrollFreeze :: proc(
		cols: i32,
		rows: i32) ---
	// submit one header cell manually (rarely used)
	@(link_name = "ImGui_TableHeader")
	TableHeader :: proc(
		label: cstring) ---
	// submit a row with headers cells based on data provided to TableSetupColumn() + submit context menu
	@(link_name = "ImGui_TableHeadersRow")
	TableHeadersRow :: proc() ---
	// submit a row with angled headers for every column with the ImGuiTableColumnFlags_AngledHeader flag. MUST BE FIRST ROW.
	@(link_name = "ImGui_TableAngledHeadersRow")
	TableAngledHeadersRow :: proc() ---
	// Tables: Sorting & Miscellaneous functions
	// - Sorting: call TableGetSortSpecs() to retrieve latest sort specs for the table. NULL when not sorting.
	//   When 'sort_specs->SpecsDirty == true' you should sort your data. It will be true when sorting specs have
	//   changed since last call, or the first time. Make sure to set 'SpecsDirty = false' after sorting,
	//   else you may wastefully sort your data every frame!
	// - Functions args 'int column_n' treat the default value of -1 as the same as passing the current column index.
	// get latest sort specs for the table (NULL if not sorting).  Lifetime: don't hold on this pointer over multiple frames or past any subsequent call to BeginTable().
	@(link_name = "ImGui_TableGetSortSpecs")
	TableGetSortSpecs :: proc() -> ^TableSortSpecs ---
	// return number of columns (value passed to BeginTable)
	@(link_name = "ImGui_TableGetColumnCount")
	TableGetColumnCount :: proc() -> i32 ---
	// return current column index.
	@(link_name = "ImGui_TableGetColumnIndex")
	TableGetColumnIndex :: proc() -> i32 ---
	// return current row index (header rows are accounted for)
	@(link_name = "ImGui_TableGetRowIndex")
	TableGetRowIndex :: proc() -> i32 ---
	// return "" if column didn't have a name declared by TableSetupColumn(). Pass -1 to use current column.
	@(link_name = "ImGui_TableGetColumnName")
	TableGetColumnName :: proc(
		column_n: i32 = -1) -> cstring ---
	// return column flags so you can query their Enabled/Visible/Sorted/Hovered status flags. Pass -1 to use current column.
	@(link_name = "ImGui_TableGetColumnFlags")
	TableGetColumnFlags :: proc(
		column_n: i32 = -1) -> TableColumnFlags ---
	// change user accessible enabled/disabled state of a column. Set to false to hide the column. User can use the context menu to change this themselves (right-click in headers, or right-click in columns body with ImGuiTableFlags_ContextMenuInBody)
	@(link_name = "ImGui_TableSetColumnEnabled")
	TableSetColumnEnabled :: proc(
		column_n: i32,
		v: bool) ---
	// return hovered column. return -1 when table is not hovered. return columns_count if the unused space at the right of visible columns is hovered. Can also use (TableGetColumnFlags() & ImGuiTableColumnFlags_IsHovered) instead.
	@(link_name = "ImGui_TableGetHoveredColumn")
	TableGetHoveredColumn :: proc() -> i32 ---
	// change the color of a cell, row, or column. See ImGuiTableBgTarget_ flags for details.
	@(link_name = "ImGui_TableSetBgColor")
	TableSetBgColor :: proc(
		target: TableBgTarget,
		color: u32,
		column_n: i32 = -1) ---
	// Legacy Columns API (prefer using Tables!)
	// - You can also use SameLine(pos_x) to mimic simplified columns.
	@(link_name = "ImGui_Columns")
	Columns :: proc(
		count: i32 = 1,
		id: cstring = nil,
		borders: bool = true) ---
	// next column, defaults to current row or next row if the current row is finished
	@(link_name = "ImGui_NextColumn")
	NextColumn :: proc() ---
	// get current column index
	@(link_name = "ImGui_GetColumnIndex")
	GetColumnIndex :: proc() -> i32 ---
	// get column width (in pixels). pass -1 to use current column
	@(link_name = "ImGui_GetColumnWidth")
	GetColumnWidth :: proc(
		column_index: i32 = -1) -> f32 ---
	// set column width (in pixels). pass -1 to use current column
	@(link_name = "ImGui_SetColumnWidth")
	SetColumnWidth :: proc(
		column_index: i32,
		width: f32) ---
	// get position of column line (in pixels, from the left side of the contents region). pass -1 to use current column, otherwise 0..GetColumnsCount() inclusive. column 0 is typically 0.0f
	@(link_name = "ImGui_GetColumnOffset")
	GetColumnOffset :: proc(
		column_index: i32 = -1) -> f32 ---
	// set position of column line (in pixels, from the left side of the contents region). pass -1 to use current column
	@(link_name = "ImGui_SetColumnOffset")
	SetColumnOffset :: proc(
		column_index: i32,
		offset_x: f32) ---
	@(link_name = "ImGui_GetColumnsCount")
	GetColumnsCount :: proc() -> i32 ---
	// Tab Bars, Tabs
	// - Note: Tabs are automatically created by the docking system (when in 'docking' branch). Use this to create tab bars/tabs yourself.
	// create and append into a TabBar
	@(link_name = "ImGui_BeginTabBar")
	BeginTabBar :: proc(
		str_id: cstring,
		flags: TabBarFlags = {}) -> bool ---
	// only call EndTabBar() if BeginTabBar() returns true!
	@(link_name = "ImGui_EndTabBar")
	EndTabBar :: proc() ---
	// create a Tab. Returns true if the Tab is selected.
	@(link_name = "ImGui_BeginTabItem")
	BeginTabItem :: proc(
		label: cstring,
		p_open: ^bool = nil,
		flags: TabItemFlags = {}) -> bool ---
	// only call EndTabItem() if BeginTabItem() returns true!
	@(link_name = "ImGui_EndTabItem")
	EndTabItem :: proc() ---
	// create a Tab behaving like a button. return true when clicked. cannot be selected in the tab bar.
	@(link_name = "ImGui_TabItemButton")
	TabItemButton :: proc(
		label: cstring,
		flags: TabItemFlags = {}) -> bool ---
	// notify TabBar or Docking system of a closed tab/window ahead (useful to reduce visual flicker on reorderable tab bars). For tab-bar: call after BeginTabBar() and before Tab submissions. Otherwise call with a window name.
	@(link_name = "ImGui_SetTabItemClosed")
	SetTabItemClosed :: proc(
		tab_or_docked_window_label: cstring) ---
	// Docking
	// - Read https://github.com/ocornut/imgui/wiki/Docking for details.
	// - Enable with io.ConfigFlags |= ImGuiConfigFlags_DockingEnable.
	// - You can use many Docking facilities without calling any API.
	//   - Drag from window title bar or their tab to dock/undock. Hold SHIFT to disable docking.
	//   - Drag from window menu button (upper-left button) to undock an entire node (all windows).
	//   - When io.ConfigDockingWithShift == true, you instead need to hold SHIFT to enable docking.
	// - DockSpaceOverViewport:
	//   - This is a helper to create an invisible window covering a viewport, then submit a DockSpace() into it.
	//   - Most applications can simply call DockSpaceOverViewport() once to allow docking windows into e.g. the edge of your screen.
	//     e.g. ImGui::NewFrame(); ImGui::DockSpaceOverViewport();                                                   // Create a dockspace in main viewport.
	//      or: ImGui::NewFrame(); ImGui::DockSpaceOverViewport(0, nullptr, ImGuiDockNodeFlags_PassthruCentralNode); // Create a dockspace in main viewport, central node is transparent.
	// - Dockspaces:
	//   - A dockspace is an explicit dock node within an existing window.
	//   - IMPORTANT: Dockspaces need to be submitted _before_ any window they can host. Submit them early in your frame!
	//   - IMPORTANT: Dockspaces need to be kept alive if hidden, otherwise windows docked into it will be undocked.
	//     If you have e.g. multiple tabs with a dockspace inside each tab: submit the non-visible dockspaces with ImGuiDockNodeFlags_KeepAliveOnly.
	//   - See 'Demo->Examples->Dockspace' or 'Demo->Examples->Documents' for more detailed demos.
	// - Programmatic docking:
	//   - There is no public API yet other than the very limited SetNextWindowDockID() function. Sorry for that!
	//   - Read https://github.com/ocornut/imgui/wiki/Docking for examples of how to use current internal API.
	@(link_name = "ImGui_DockSpace")
	DockSpace :: proc(
		dockspace_id: ID,
		size: Vec2 = Vec2{0, 0},
		flags: DockNodeFlags = {},
		window_class: ^WindowClass = nil) -> ID ---
	@(link_name = "ImGui_DockSpaceOverViewport")
	DockSpaceOverViewport :: proc(
		dockspace_id: ID = {},
		viewport: ^Viewport = nil,
		flags: DockNodeFlags = {},
		window_class: ^WindowClass = nil) -> ID ---
	// set next window dock id
	@(link_name = "ImGui_SetNextWindowDockID")
	SetNextWindowDockID :: proc(
		dock_id: ID,
		cond: Cond = {}) ---
	// set next window class (control docking compatibility + provide hints to platform backend via custom viewport flags and platform parent/child relationship)
	@(link_name = "ImGui_SetNextWindowClass")
	SetNextWindowClass :: proc(
		window_class: ^WindowClass) ---
	// get dock id of current window, or 0 if not associated to any docking node.
	@(link_name = "ImGui_GetWindowDockID")
	GetWindowDockID :: proc() -> ID ---
	// is current window docked into another window?
	@(link_name = "ImGui_IsWindowDocked")
	IsWindowDocked :: proc() -> bool ---
	// Logging/Capture
	// - All text output from the interface can be captured into tty/file/clipboard. By default, tree nodes are automatically opened during logging.
	// start logging to tty (stdout)
	@(link_name = "ImGui_LogToTTY")
	LogToTTY :: proc(
		auto_open_depth: i32 = -1) ---
	// start logging to file
	@(link_name = "ImGui_LogToFile")
	LogToFile :: proc(
		auto_open_depth: i32 = -1,
		filename: cstring = nil) ---
	// start logging to OS clipboard
	@(link_name = "ImGui_LogToClipboard")
	LogToClipboard :: proc(
		auto_open_depth: i32 = -1) ---
	// stop logging (close file, etc.)
	@(link_name = "ImGui_LogFinish")
	LogFinish :: proc() ---
	// helper to display buttons for logging to tty/file/clipboard
	@(link_name = "ImGui_LogButtons")
	LogButtons :: proc() ---
	// pass text data straight to log (without being displayed)
	@(link_name = "ImGui_LogText")
	LogText :: proc(
		fmt: cstring,
		#c_vararg args: ..any) ---
	// Drag and Drop
	// - On source items, call BeginDragDropSource(), if it returns true also call SetDragDropPayload() + EndDragDropSource().
	// - On target candidates, call BeginDragDropTarget(), if it returns true also call AcceptDragDropPayload() + EndDragDropTarget().
	// - If you stop calling BeginDragDropSource() the payload is preserved however it won't have a preview tooltip (we currently display a fallback "..." tooltip, see #1725)
	// - An item can be both drag source and drop target.
	// call after submitting an item which may be dragged. when this return true, you can call SetDragDropPayload() + EndDragDropSource()
	@(link_name = "ImGui_BeginDragDropSource")
	BeginDragDropSource :: proc(
		flags: DragDropFlags = {}) -> bool ---
	// type is a user defined string of maximum 32 characters. Strings starting with '_' are reserved for dear imgui internal types. Data is copied and held by imgui. Return true when payload has been accepted.
	@(link_name = "ImGui_SetDragDropPayload")
	SetDragDropPayload :: proc(
		type: cstring,
		data: rawptr,
		sz: uint,
		cond: Cond = {}) -> bool ---
	// only call EndDragDropSource() if BeginDragDropSource() returns true!
	@(link_name = "ImGui_EndDragDropSource")
	EndDragDropSource :: proc() ---
	// call after submitting an item that may receive a payload. If this returns true, you can call AcceptDragDropPayload() + EndDragDropTarget()
	@(link_name = "ImGui_BeginDragDropTarget")
	BeginDragDropTarget :: proc() -> bool ---
	// accept contents of a given type. If ImGuiDragDropFlags_AcceptBeforeDelivery is set you can peek into the payload before the mouse button is released.
	@(link_name = "ImGui_AcceptDragDropPayload")
	AcceptDragDropPayload :: proc(
		type: cstring,
		flags: DragDropFlags = {}) -> ^Payload ---
	// only call EndDragDropTarget() if BeginDragDropTarget() returns true!
	@(link_name = "ImGui_EndDragDropTarget")
	EndDragDropTarget :: proc() ---
	// peek directly into the current payload from anywhere. returns NULL when drag and drop is finished or inactive. use ImGuiPayload::IsDataType() to test for the payload type.
	@(link_name = "ImGui_GetDragDropPayload")
	GetDragDropPayload :: proc() -> ^Payload ---
	// Disabling [BETA API]
	// - Disable all user interactions and dim items visuals (applying style.DisabledAlpha over current colors)
	// - Those can be nested but it cannot be used to enable an already disabled section (a single BeginDisabled(true) in the stack is enough to keep everything disabled)
	// - Tooltips windows are automatically opted out of disabling. Note that IsItemHovered() by default returns false on disabled items, unless using ImGuiHoveredFlags_AllowWhenDisabled.
	// - BeginDisabled(false)/EndDisabled() essentially does nothing but is provided to facilitate use of boolean expressions (as a micro-optimization: if you have tens of thousands of BeginDisabled(false)/EndDisabled() pairs, you might want to reformulate your code to avoid making those calls)
	@(link_name = "ImGui_BeginDisabled")
	BeginDisabled :: proc(
		disabled: bool = true) ---
	@(link_name = "ImGui_EndDisabled")
	EndDisabled :: proc() ---
	// Clipping
	// - Mouse hovering is affected by ImGui::PushClipRect() calls, unlike direct calls to ImDrawList::PushClipRect() which are render only.
	@(link_name = "ImGui_PushClipRect")
	PushClipRect :: proc(
		clip_rect_min: Vec2,
		clip_rect_max: Vec2,
		intersect_with_current_clip_rect: bool) ---
	@(link_name = "ImGui_PopClipRect")
	PopClipRect :: proc() ---
	// Focus, Activation
	// make last item the default focused item of a newly appearing window.
	@(link_name = "ImGui_SetItemDefaultFocus")
	SetItemDefaultFocus :: proc() ---
	// focus keyboard on the next widget. Use positive 'offset' to access sub components of a multiple component widget. Use -1 to access previous widget.
	@(link_name = "ImGui_SetKeyboardFocusHere")
	SetKeyboardFocusHere :: proc(
		offset: i32 = 0) ---
	// Keyboard/Gamepad Navigation
	// alter visibility of keyboard/gamepad cursor. by default: show when using an arrow key, hide when clicking with mouse.
	@(link_name = "ImGui_SetNavCursorVisible")
	SetNavCursorVisible :: proc(
		visible: bool) ---
	// Overlapping mode
	// allow next item to be overlapped by a subsequent item. Typically useful with InvisibleButton(), Selectable(), TreeNode() covering an area where subsequent items may need to be added. Note that both Selectable() and TreeNode() have dedicated flags doing this.
	@(link_name = "ImGui_SetNextItemAllowOverlap")
	SetNextItemAllowOverlap :: proc() ---
	// Item/Widgets Utilities and Query Functions
	// - Most of the functions are referring to the previous Item that has been submitted.
	// - See Demo Window under "Widgets->Querying Status" for an interactive visualization of most of those functions.
	// is the last item hovered? (and usable, aka not blocked by a popup, etc.). See ImGuiHoveredFlags for more options.
	@(link_name = "ImGui_IsItemHovered")
	IsItemHovered :: proc(
		flags: HoveredFlags = {}) -> bool ---
	// is the last item active? (e.g. button being held, text field being edited. This will continuously return true while holding mouse button on an item. Items that don't interact will always return false)
	@(link_name = "ImGui_IsItemActive")
	IsItemActive :: proc() -> bool ---
	// is the last item focused for keyboard/gamepad navigation?
	@(link_name = "ImGui_IsItemFocused")
	IsItemFocused :: proc() -> bool ---
	// is the last item hovered and mouse clicked on? (**)  == IsMouseClicked(mouse_button) && IsItemHovered()Important. (**) this is NOT equivalent to the behavior of e.g. Button(). Read comments in function definition.
	@(link_name = "ImGui_IsItemClicked")
	IsItemClicked :: proc(
		mouse_button: MouseButton = {}) -> bool ---
	// is the last item visible? (items may be out of sight because of clipping/scrolling)
	@(link_name = "ImGui_IsItemVisible")
	IsItemVisible :: proc() -> bool ---
	// did the last item modify its underlying value this frame? or was pressed? This is generally the same as the "bool" return value of many widgets.
	@(link_name = "ImGui_IsItemEdited")
	IsItemEdited :: proc() -> bool ---
	// was the last item just made active (item was previously inactive).
	@(link_name = "ImGui_IsItemActivated")
	IsItemActivated :: proc() -> bool ---
	// was the last item just made inactive (item was previously active). Useful for Undo/Redo patterns with widgets that require continuous editing.
	@(link_name = "ImGui_IsItemDeactivated")
	IsItemDeactivated :: proc() -> bool ---
	// was the last item just made inactive and made a value change when it was active? (e.g. Slider/Drag moved). Useful for Undo/Redo patterns with widgets that require continuous editing. Note that you may get false positives (some widgets such as Combo()/ListBox()/Selectable() will return true even when clicking an already selected item).
	@(link_name = "ImGui_IsItemDeactivatedAfterEdit")
	IsItemDeactivatedAfterEdit :: proc() -> bool ---
	// was the last item open state toggled? set by TreeNode().
	@(link_name = "ImGui_IsItemToggledOpen")
	IsItemToggledOpen :: proc() -> bool ---
	// is any item hovered?
	@(link_name = "ImGui_IsAnyItemHovered")
	IsAnyItemHovered :: proc() -> bool ---
	// is any item active?
	@(link_name = "ImGui_IsAnyItemActive")
	IsAnyItemActive :: proc() -> bool ---
	// is any item focused?
	@(link_name = "ImGui_IsAnyItemFocused")
	IsAnyItemFocused :: proc() -> bool ---
	// get ID of last item (~~ often same ImGui::GetID(label) beforehand)
	@(link_name = "ImGui_GetItemID")
	GetItemID :: proc() -> ID ---
	// get upper-left bounding rectangle of the last item (screen space)
	@(link_name = "ImGui_GetItemRectMin")
	GetItemRectMin :: proc() -> Vec2 ---
	// get lower-right bounding rectangle of the last item (screen space)
	@(link_name = "ImGui_GetItemRectMax")
	GetItemRectMax :: proc() -> Vec2 ---
	// get size of last item
	@(link_name = "ImGui_GetItemRectSize")
	GetItemRectSize :: proc() -> Vec2 ---
	// get generic flags of last item
	@(link_name = "ImGui_GetItemFlags")
	GetItemFlags :: proc() -> ItemFlags ---
	// [BETA] building block for disambiguation between single-click and double-click. Returns 1 on single-click but delayed by io.MouseSingleClickDelay after mouse release. Returns 2+ on double-click or repeated clicks.
	@(link_name = "ImGui_GetItemClickedCountWithSingleClickDelay")
	GetItemClickedCountWithSingleClickDelay :: proc(
		mouse_button: MouseButton = {},
		delay: f32 = -1.0) -> i32 ---
	// Viewports
	// - Currently represents the Platform Window created by the application which is hosting our Dear ImGui windows.
	// - In 'docking' branch with multi-viewport enabled, we extend this concept to have multiple active viewports.
	// - In the future we will extend this concept further to also represent Platform Monitor and support a "no main platform window" operation mode.
	// return primary/default viewport. This can never be NULL.
	@(link_name = "ImGui_GetMainViewport")
	GetMainViewport :: proc() -> ^Viewport ---
	// Background/Foreground Draw Lists
	// get background draw list for the given viewport or viewport associated to the current window. this draw list will be the first rendering one. Useful to quickly draw shapes/text behind dear imgui contents.
	@(link_name = "ImGui_GetBackgroundDrawList")
	GetBackgroundDrawList :: proc(
		viewport: ^Viewport = nil) -> ^DrawList ---
	// get foreground draw list for the given viewport or viewport associated to the current window. this draw list will be the top-most rendered one. Useful to quickly draw shapes/text over dear imgui contents.
	@(link_name = "ImGui_GetForegroundDrawList")
	GetForegroundDrawList :: proc(
		viewport: ^Viewport = nil) -> ^DrawList ---
	// Miscellaneous Utilities
	// test if rectangle (of given size, starting from cursor position) is visible / not clipped.
	@(link_name = "ImGui_IsRectVisibleBySize")
	IsRectVisibleBySize :: proc(
		size: Vec2) -> bool ---
	// test if rectangle (in screen space) is visible / not clipped. to perform coarse clipping on user's side.
	@(link_name = "ImGui_IsRectVisible")
	IsRectVisible :: proc(
		rect_min: Vec2,
		rect_max: Vec2) -> bool ---
	// get global imgui time. incremented by io.DeltaTime every frame.
	@(link_name = "ImGui_GetTime")
	GetTime :: proc() -> f64 ---
	// get global imgui frame count. incremented by 1 every frame.
	@(link_name = "ImGui_GetFrameCount")
	GetFrameCount :: proc() -> i32 ---
	// you may use this when creating your own ImDrawList instances.
	@(link_name = "ImGui_GetDrawListSharedData")
	GetDrawListSharedData :: proc() -> ^DrawListSharedData ---
	// get a string corresponding to the enum value (for display, saving, etc.).
	@(link_name = "ImGui_GetStyleColorName")
	GetStyleColorName :: proc(
		idx: Col) -> cstring ---
	// replace current window storage with our own (if you want to manipulate it yourself, typically clear subsection of it)
	@(link_name = "ImGui_SetStateStorage")
	SetStateStorage :: proc(
		storage: ^Storage) ---
	@(link_name = "ImGui_GetStateStorage")
	GetStateStorage :: proc() -> ^Storage ---
	// Text Utilities
	@(link_name = "ImGui_CalcTextSize")
	CalcTextSize :: proc(
		text: cstring,
		text_end: cstring = nil,
		hide_text_after_double_hash: bool = false,
		wrap_width: f32 = -1.0) -> Vec2 ---
	// Color Utilities
	@(link_name = "ImGui_ColorConvertU32ToFloat4")
	ColorConvertU32ToFloat4 :: proc(
		_in: u32) -> Vec4 ---
	@(link_name = "ImGui_ColorConvertFloat4ToU32")
	ColorConvertFloat4ToU32 :: proc(
		_in: Vec4) -> u32 ---
	@(link_name = "ImGui_ColorConvertRGBtoHSV")
	ColorConvertRGBtoHSV :: proc(
		r: f32,
		g: f32,
		b: f32,
		out_h: ^f32,
		out_s: ^f32,
		out_v: ^f32) ---
	@(link_name = "ImGui_ColorConvertHSVtoRGB")
	ColorConvertHSVtoRGB :: proc(
		h: f32,
		s: f32,
		v: f32,
		out_r: ^f32,
		out_g: ^f32,
		out_b: ^f32) ---
	// Inputs Utilities: Raw Keyboard/Mouse/Gamepad Access
	// - Consider using the Shortcut() function instead of IsKeyPressed()/IsKeyChordPressed()! Shortcut() is easier to use and better featured (can do focus routing check).
	// - the ImGuiKey enum contains all possible keyboard, mouse and gamepad inputs (e.g. ImGuiKey_A, ImGuiKey_MouseLeft, ImGuiKey_GamepadDpadUp...).
	// - (legacy: before v1.87 (2022-02), we used ImGuiKey < 512 values to carry native/user indices as defined by each backends. This was obsoleted in 1.87 (2022-02) and completely removed in 1.91.5 (2024-11). See https://github.com/ocornut/imgui/issues/4921)
	// is key being held.
	@(link_name = "ImGui_IsKeyDown")
	IsKeyDown :: proc(
		key: Key) -> bool ---
	// was key pressed (went from !Down to Down)? Repeat rate uses io.KeyRepeatDelay / KeyRepeatRate.
	@(link_name = "ImGui_IsKeyPressed")
	IsKeyPressed :: proc(
		key: Key,
		repeat: bool = true) -> bool ---
	// was key released (went from Down to !Down)?
	@(link_name = "ImGui_IsKeyReleased")
	IsKeyReleased :: proc(
		key: Key) -> bool ---
	// was key chord (mods + key) pressed, e.g. you can pass 'ImGuiMod_Ctrl | ImGuiKey_S' as a key-chord. This doesn't do any routing or focus check, please consider using Shortcut() function instead.
	@(link_name = "ImGui_IsKeyChordPressed")
	IsKeyChordPressed :: proc(
		key_chord: KeyChord) -> bool ---
	// uses provided repeat rate/delay. return a count, most often 0 or 1 but might be >1 if RepeatRate is small enough that DeltaTime > RepeatRate
	@(link_name = "ImGui_GetKeyPressedAmount")
	GetKeyPressedAmount :: proc(
		key: Key,
		repeat_delay: f32,
		rate: f32) -> i32 ---
	// [DEBUG] returns English name of the key. Those names are provided for debugging purpose and are not meant to be saved persistently nor compared.
	@(link_name = "ImGui_GetKeyName")
	GetKeyName :: proc(
		key: Key) -> cstring ---
	// Override io.WantCaptureKeyboard flag next frame (said flag is left for your application to handle, typically when true it instructs your app to ignore inputs). e.g. force capture keyboard when your widget is being hovered. This is equivalent to setting "io.WantCaptureKeyboard = want_capture_keyboard"; after the next NewFrame() call.
	@(link_name = "ImGui_SetNextFrameWantCaptureKeyboard")
	SetNextFrameWantCaptureKeyboard :: proc(
		want_capture_keyboard: bool) ---
	// Inputs Utilities: Shortcut Testing & Routing
	// - Typical use is e.g.: 'if (ImGui::Shortcut(ImGuiMod_Ctrl | ImGuiKey_S)) { ... }'.
	// - Flags: Default route use ImGuiInputFlags_RouteFocused, but see ImGuiInputFlags_RouteGlobal and other options in ImGuiInputFlags_!
	// - Flags: Use ImGuiInputFlags_Repeat to support repeat.
	// - ImGuiKeyChord = a ImGuiKey + optional ImGuiMod_Alt/ImGuiMod_Ctrl/ImGuiMod_Shift/ImGuiMod_Super.
	//       ImGuiKey_C                          // Accepted by functions taking ImGuiKey or ImGuiKeyChord arguments
	//       ImGuiMod_Ctrl | ImGuiKey_C          // Accepted by functions taking ImGuiKeyChord arguments
	//   only ImGuiMod_XXX values are legal to combine with an ImGuiKey. You CANNOT combine two ImGuiKey values.
	// - The general idea is that several callers may register interest in a shortcut, and only one owner gets it.
	//      Parent   -> call Shortcut(Ctrl+S)    // When Parent is focused, Parent gets the shortcut.
	//        Child1 -> call Shortcut(Ctrl+S)    // When Child1 is focused, Child1 gets the shortcut (Child1 overrides Parent shortcuts)
	//        Child2 -> no call                  // When Child2 is focused, Parent gets the shortcut.
	//   The whole system is order independent, so if Child1 makes its calls before Parent, results will be identical.
	//   This is an important property as it facilitate working with foreign code or larger codebase.
	// - To understand the difference:
	//   - IsKeyChordPressed() compares mods and call IsKeyPressed()
	//     -> the function has no side-effect.
	//   - Shortcut() submits a route, routes are resolved, if it currently can be routed it calls IsKeyChordPressed()
	//     -> the function has (desirable) side-effects as it can prevents another call from getting the route.
	// - Visualize registered routes in 'Metrics/Debugger->Inputs'.
	@(link_name = "ImGui_Shortcut")
	Shortcut :: proc(
		key_chord: KeyChord,
		flags: InputFlags = {}) -> bool ---
	@(link_name = "ImGui_SetNextItemShortcut")
	SetNextItemShortcut :: proc(
		key_chord: KeyChord,
		flags: InputFlags = {}) ---
	// Inputs Utilities: Key/Input Ownership [BETA]
	// - One common use case would be to allow your items to disable standard inputs behaviors such
	//   as Tab or Alt key handling, Mouse Wheel scrolling, etc.
	//   e.g. `Button(...); if (SetItemKeyOwner(ImGuiKey_MouseWheelY)) { ... }` to make hovering/activating a button disable wheel for scrolling.
	// - Reminder ImGuiKey enum include access to mouse buttons and gamepad, so key ownership can apply to them.
	// - The return value of SetItemKeyOwner() says if ownership has been requested for the item, which is a shortcut to calling yet non-public TestKeyOwner() function.
	// - Many related features are still in imgui_internal.h. For instance, most IsKeyXXX()/IsMouseXXX() functions have an owner-id-aware version.
	// Set key owner to last item ID if it is hovered or active. Return true when ownership has been set. Roughly equivalent to 'if (TestKeyOwner(key, GetItemID()) && (IsItemHovered() || IsItemActive())) { SetKeyOwner(key, GetItemID());'.
	@(link_name = "ImGui_SetItemKeyOwner")
	SetItemKeyOwner :: proc(
		key: Key) -> bool ---
	// Inputs Utilities: Mouse
	// - To refer to a mouse button, you may use named enums in your code e.g. ImGuiMouseButton_Left, ImGuiMouseButton_Right.
	// - You can also use regular integer: it is forever guaranteed that 0=Left, 1=Right, 2=Middle.
	// - Dragging operations are only reported after mouse has moved a certain distance away from the initial clicking position (see 'lock_threshold' and 'io.MouseDraggingThreshold')
	// is mouse button held?
	@(link_name = "ImGui_IsMouseDown")
	IsMouseDown :: proc(
		button: MouseButton) -> bool ---
	// did mouse button clicked? (went from !Down to Down). Same as GetMouseClickedCount() == 1.
	@(link_name = "ImGui_IsMouseClicked")
	IsMouseClicked :: proc(
		button: MouseButton,
		repeat: bool = false) -> bool ---
	// did mouse button released? (went from Down to !Down)
	@(link_name = "ImGui_IsMouseReleased")
	IsMouseReleased :: proc(
		button: MouseButton) -> bool ---
	// did mouse button double-clicked? Same as GetMouseClickedCount() == 2. (note that a double-click will also report IsMouseClicked() == true)
	@(link_name = "ImGui_IsMouseDoubleClicked")
	IsMouseDoubleClicked :: proc(
		button: MouseButton) -> bool ---
	// delayed mouse release. Use sparingly. Prefer higher-level helper GetItemClickedCountWithSingleClickDelay(). Generally used with 'delay >= io.MouseDoubleClickTime' + combined with a 'io.MouseClickedLastCount==1' test.
	@(link_name = "ImGui_IsMouseReleasedWithDelay")
	IsMouseReleasedWithDelay :: proc(
		button: MouseButton,
		delay: f32 = -1.) -> bool ---
	// return the number of successive mouse-clicks at the time where a click happen (otherwise 0).
	@(link_name = "ImGui_GetMouseClickedCount")
	GetMouseClickedCount :: proc(
		button: MouseButton) -> i32 ---
	// is mouse hovering given bounding rect (in screen space). clipped by current clipping settings, but disregarding of other consideration of focus/window ordering/popup-block.
	@(link_name = "ImGui_IsMouseHoveringRect")
	IsMouseHoveringRect :: proc(
		r_min: Vec2,
		r_max: Vec2,
		clip: bool = true) -> bool ---
	// by convention we use (-FLT_MAX,-FLT_MAX) to denote that there is no mouse available
	@(link_name = "ImGui_IsMousePosValid")
	IsMousePosValid :: proc(
		mouse_pos: ^Vec2 = nil) -> bool ---
	// [WILL OBSOLETE] is any mouse button held? This was designed for backends, but prefer having backend maintain a mask of held mouse buttons, because upcoming input queue system will make this invalid.
	@(link_name = "ImGui_IsAnyMouseDown")
	IsAnyMouseDown :: proc() -> bool ---
	// shortcut to ImGui::GetIO().MousePos provided by user, to be consistent with other calls
	@(link_name = "ImGui_GetMousePos")
	GetMousePos :: proc() -> Vec2 ---
	// retrieve mouse position at the time of opening popup we have BeginPopup() into (helper to avoid user backing that value themselves)
	@(link_name = "ImGui_GetMousePosOnOpeningCurrentPopup")
	GetMousePosOnOpeningCurrentPopup :: proc() -> Vec2 ---
	// is mouse dragging? (uses io.MouseDraggingThreshold if lock_threshold < 0.0f)
	@(link_name = "ImGui_IsMouseDragging")
	IsMouseDragging :: proc(
		button: MouseButton,
		lock_threshold: f32 = -1.0) -> bool ---
	// return the delta from the initial clicking position while the mouse button is pressed or was just released. This is locked and return 0.0f until the mouse moves past a distance threshold at least once (uses io.MouseDraggingThreshold if lock_threshold < 0.0f)
	@(link_name = "ImGui_GetMouseDragDelta")
	GetMouseDragDelta :: proc(
		button: MouseButton = {},
		lock_threshold: f32 = -1.0) -> Vec2 ---
	//
	@(link_name = "ImGui_ResetMouseDragDelta")
	ResetMouseDragDelta :: proc(
		button: MouseButton = {}) ---
	// get desired mouse cursor shape. Important: reset in ImGui::NewFrame(), this is updated during the frame. valid before Render(). If you use software rendering by setting io.MouseDrawCursor ImGui will render those for you
	@(link_name = "ImGui_GetMouseCursor")
	GetMouseCursor :: proc() -> MouseCursor ---
	// set desired mouse cursor shape
	@(link_name = "ImGui_SetMouseCursor")
	SetMouseCursor :: proc(
		cursor_type: MouseCursor) ---
	// Override io.WantCaptureMouse flag next frame (said flag is left for your application to handle, typical when true it instructs your app to ignore inputs). This is equivalent to setting "io.WantCaptureMouse = want_capture_mouse;" after the next NewFrame() call.
	@(link_name = "ImGui_SetNextFrameWantCaptureMouse")
	SetNextFrameWantCaptureMouse :: proc(
		want_capture_mouse: bool) ---
	// Clipboard Utilities
	// - Also see the LogToClipboard() function to capture GUI into clipboard, or easily output text data to the clipboard.
	@(link_name = "ImGui_GetClipboardText")
	GetClipboardText :: proc() -> cstring ---
	@(link_name = "ImGui_SetClipboardText")
	SetClipboardText :: proc(
		text: cstring) ---
	// Settings/.Ini Utilities
	// - The disk functions are automatically called if io.IniFilename != NULL (default is "imgui.ini").
	// - Set io.IniFilename to NULL to load/save manually. Read io.WantSaveIniSettings description about handling .ini saving manually.
	// - Important: default value "imgui.ini" is relative to current working dir! Most apps will want to lock this to an absolute path (e.g. same path as executables).
	// call after CreateContext() and before the first call to NewFrame(). NewFrame() automatically calls LoadIniSettingsFromDisk(io.IniFilename).
	@(link_name = "ImGui_LoadIniSettingsFromDisk")
	LoadIniSettingsFromDisk :: proc(
		ini_filename: cstring) ---
	// call after CreateContext() and before the first call to NewFrame() to provide .ini data from your own data source.
	@(link_name = "ImGui_LoadIniSettingsFromMemory")
	LoadIniSettingsFromMemory :: proc(
		ini_data: cstring,
		ini_size: uint = {}) ---
	// this is automatically called (if io.IniFilename is not empty) a few seconds after any modification that should be reflected in the .ini file (and also by DestroyContext).
	@(link_name = "ImGui_SaveIniSettingsToDisk")
	SaveIniSettingsToDisk :: proc(
		ini_filename: cstring) ---
	// return a zero-terminated string with the .ini data which you can save by your own mean. call when io.WantSaveIniSettings is set, then save data by your own mean and clear io.WantSaveIniSettings.
	@(link_name = "ImGui_SaveIniSettingsToMemory")
	SaveIniSettingsToMemory :: proc(
		out_ini_size: ^uint = nil) -> cstring ---
	// Debug Utilities
	// - Your main debugging friend is the ShowMetricsWindow() function.
	// - Interactive tools are all accessible from the 'Dear ImGui Demo->Tools' menu.
	// - Read https://github.com/ocornut/imgui/wiki/Debug-Tools for a description of all available debug tools.
	@(link_name = "ImGui_DebugTextEncoding")
	DebugTextEncoding :: proc(
		text: cstring) ---
	@(link_name = "ImGui_DebugFlashStyleColor")
	DebugFlashStyleColor :: proc(
		idx: Col) ---
	@(link_name = "ImGui_DebugStartItemPicker")
	DebugStartItemPicker :: proc() ---
	// This is called by IMGUI_CHECKVERSION() macro.
	@(link_name = "ImGui_DebugCheckVersionAndDataLayout")
	DebugCheckVersionAndDataLayout :: proc(
		version_str: cstring,
		sz_io: uint,
		sz_style: uint,
		sz_vec2: uint,
		sz_vec4: uint,
		sz_drawvert: uint,
		sz_drawidx: uint) -> bool ---
	// Call via IMGUI_DEBUG_LOG() for maximum stripping in caller code!
	@(link_name = "ImGui_DebugLog")
	DebugLog :: proc(
		fmt: cstring,
		#c_vararg args: ..any) ---
	// Memory Allocators
	// - Those functions are not reliant on the current context.
	// - DLL users: heaps and globals are not shared across DLL boundaries! You will need to call SetCurrentContext() + SetAllocatorFunctions()
	//   for each static/DLL boundary you are calling from. Read "Context and Memory Allocators" section of imgui.cpp for more details.
	@(link_name = "ImGui_SetAllocatorFunctions")
	SetAllocatorFunctions :: proc(
		alloc_func: MemAllocFunc,
		free_func: MemFreeFunc,
		user_data: rawptr = nil) ---
	@(link_name = "ImGui_GetAllocatorFunctions")
	GetAllocatorFunctions :: proc(
		p_alloc_func: ^MemAllocFunc,
		p_free_func: ^MemFreeFunc,
		p_user_data: ^rawptr) ---
	@(link_name = "ImGui_MemAlloc")
	MemAlloc :: proc(
		size: uint) -> rawptr ---
	@(link_name = "ImGui_MemFree")
	MemFree :: proc(
		ptr: rawptr) ---
	// (Optional) Platform/OS interface for multi-viewport support
	// Read comments around the ImGuiPlatformIO structure for more details.
	// Note: You may use GetWindowViewport() to get the current viewport of the current window.
	// call in main loop. will call CreateWindow/ResizeWindow/etc. platform functions for each secondary viewport, and DestroyWindow for each inactive viewport.
	@(link_name = "ImGui_UpdatePlatformWindows")
	UpdatePlatformWindows :: proc() ---
	// call in main loop. will call RenderWindow/SwapBuffers platform functions for each secondary viewport which doesn't have the ImGuiViewportFlags_Minimized flag set. May be reimplemented by user for custom rendering needs.
	@(link_name = "ImGui_RenderPlatformWindowsDefault")
	RenderPlatformWindowsDefault :: proc(
		platform_render_arg: rawptr = nil,
		renderer_render_arg: rawptr = nil) ---
	// call DestroyWindow platform functions for all viewports. call from backend Shutdown() if you need to close platform windows before imgui shutdown. otherwise will be called by DestroyContext().
	@(link_name = "ImGui_DestroyPlatformWindows")
	DestroyPlatformWindows :: proc() ---
	// this is a helper for backends.
	@(link_name = "ImGui_FindViewportByID")
	FindViewportByID :: proc(
		viewport_id: ID) -> ^Viewport ---
	// this is a helper for backends. the type platform_handle is decided by the backend (e.g. HWND, MyWindow*, GLFWwindow* etc.)
	@(link_name = "ImGui_FindViewportByPlatformHandle")
	FindViewportByPlatformHandle :: proc(
		platform_handle: rawptr) -> ^Viewport ---
	// Construct a zero-size ImVector<> (of any type). This is primarily useful when calling ImFontGlyphRangesBuilder_BuildRanges()
	@(link_name = "ImVector_Construct")
	Vector_Construct :: proc(
		vector: rawptr) ---
	// Destruct an ImVector<> (of any type). Important: Frees the vector memory but does not call destructors on contained objects (if they have them)
	@(link_name = "ImVector_Destruct")
	Vector_Destruct :: proc(
		vector: rawptr) ---
	// Set ImGuiPlatformIO::Platform_GetWindowWorkAreaInsets in a C-compatible mannner
	@(link_name = "ImGuiPlatformIO_SetPlatform_GetWindowWorkAreaInsets")
	PlatformIO_SetPlatform_GetWindowWorkAreaInsets :: proc(
		getWindowWorkAreaInsetsFunc: proc "c" (vp: ^Viewport, result: ^Vec4)) ---
	// Set ImGuiPlatformIO::Platform_GetWindowFramebufferScale in a C-compatible mannner
	@(link_name = "ImGuiPlatformIO_SetPlatform_GetWindowFramebufferScale")
	PlatformIO_SetPlatform_GetWindowFramebufferScale :: proc(
		getWindowFramebufferScaleFunc: proc "c" (vp: ^Viewport, result: ^Vec2)) ---
	// Set ImGuiPlatformIO::Platform_GetWindowPos in a C-compatible mannner
	@(link_name = "ImGuiPlatformIO_SetPlatform_GetWindowPos")
	PlatformIO_SetPlatform_GetWindowPos :: proc(
		getWindowPosFunc: proc "c" (vp: ^Viewport, result: ^Vec2)) ---
	// Set ImGuiPlatformIO::Platform_GetWindowSize in a C-compatible mannner
	@(link_name = "ImGuiPlatformIO_SetPlatform_GetWindowSize")
	PlatformIO_SetPlatform_GetWindowSize :: proc(
		getWindowSizeFunc: proc "c" (vp: ^Viewport, result: ^Vec2)) ---
	// Scale all spacing/padding/thickness values. Do not scale fonts. See comments in definition. Consider not calling this if your initial scale factor if <1.0.
	@(link_name = "ImGuiStyle_ScaleAllSizes")
	Style_ScaleAllSizes :: proc(
		self: ^Style,
		scale_factor: f32) ---
	// Input Functions
	// Queue a new key down/up event. Key should be "translated" (as in, generally ImGuiKey_A matches the key end-user would use to emit an 'A' character)
	@(link_name = "ImGuiIO_AddKeyEvent")
	IO_AddKeyEvent :: proc(
		self: ^IO,
		key: Key,
		down: bool) ---
	// Queue a new key down/up event for analog values (e.g. ImGuiKey_Gamepad_ values). Dead-zones should be handled by the backend.
	@(link_name = "ImGuiIO_AddKeyAnalogEvent")
	IO_AddKeyAnalogEvent :: proc(
		self: ^IO,
		key: Key,
		down: bool,
		v: f32) ---
	// Queue a mouse position update. Use -FLT_MAX,-FLT_MAX to signify no mouse (e.g. app not focused and not hovered)
	@(link_name = "ImGuiIO_AddMousePosEvent")
	IO_AddMousePosEvent :: proc(
		self: ^IO,
		x: f32,
		y: f32) ---
	// Queue a mouse button change
	@(link_name = "ImGuiIO_AddMouseButtonEvent")
	IO_AddMouseButtonEvent :: proc(
		self: ^IO,
		button: i32,
		down: bool) ---
	// Queue a mouse wheel update. wheel_y<0: scroll down, wheel_y>0: scroll up, wheel_x<0: scroll right, wheel_x>0: scroll left.
	@(link_name = "ImGuiIO_AddMouseWheelEvent")
	IO_AddMouseWheelEvent :: proc(
		self: ^IO,
		wheel_x: f32,
		wheel_y: f32) ---
	// Queue a mouse source change (Mouse/TouchScreen/Pen)
	@(link_name = "ImGuiIO_AddMouseSourceEvent")
	IO_AddMouseSourceEvent :: proc(
		self: ^IO,
		source: MouseSource) ---
	// Queue a mouse hovered viewport. Requires backend to set ImGuiBackendFlags_HasMouseHoveredViewport to call this (for multi-viewport support).
	@(link_name = "ImGuiIO_AddMouseViewportEvent")
	IO_AddMouseViewportEvent :: proc(
		self: ^IO,
		id: ID) ---
	// Queue a gain/loss of focus for the application (generally based on OS/platform focus of your window)
	@(link_name = "ImGuiIO_AddFocusEvent")
	IO_AddFocusEvent :: proc(
		self: ^IO,
		focused: bool) ---
	// Queue a new character input
	@(link_name = "ImGuiIO_AddInputCharacter")
	IO_AddInputCharacter :: proc(
		self: ^IO,
		c: u32) ---
	// Queue a new character input from a UTF-16 character, it can be a surrogate
	@(link_name = "ImGuiIO_AddInputCharacterUTF16")
	IO_AddInputCharacterUTF16 :: proc(
		self: ^IO,
		c: Wchar16) ---
	// Queue a new characters input from a UTF-8 string
	@(link_name = "ImGuiIO_AddInputCharactersUTF8")
	IO_AddInputCharactersUTF8 :: proc(
		self: ^IO,
		str: cstring) ---
	// [Optional] Specify index for legacy <1.87 IsKeyXXX() functions with native indices + specify native keycode, scancode.
	@(link_name = "ImGuiIO_SetKeyEventNativeData")
	IO_SetKeyEventNativeData :: proc(
		self: ^IO,
		key: Key,
		native_keycode: i32,
		native_scancode: i32,
		native_legacy_index: i32 = -1) ---
	// Set master flag for accepting key/mouse/text events (default to true). Useful if you have native dialog boxes that are interrupting your application loop/refresh, and you want to disable events being queued while your app is frozen.
	@(link_name = "ImGuiIO_SetAppAcceptingEvents")
	IO_SetAppAcceptingEvents :: proc(
		self: ^IO,
		accepting_events: bool) ---
	// Clear all incoming events.
	@(link_name = "ImGuiIO_ClearEventsQueue")
	IO_ClearEventsQueue :: proc(
		self: ^IO) ---
	// Clear current keyboard/gamepad state + current frame text input buffer. Equivalent to releasing all keys/buttons.
	@(link_name = "ImGuiIO_ClearInputKeys")
	IO_ClearInputKeys :: proc(
		self: ^IO) ---
	// Clear current mouse state.
	@(link_name = "ImGuiIO_ClearInputMouse")
	IO_ClearInputMouse :: proc(
		self: ^IO) ---
	@(link_name = "ImGuiInputTextCallbackData_DeleteChars")
	InputTextCallbackData_DeleteChars :: proc(
		self: ^InputTextCallbackData,
		pos: i32,
		bytes_count: i32) ---
	@(link_name = "ImGuiInputTextCallbackData_InsertChars")
	InputTextCallbackData_InsertChars :: proc(
		self: ^InputTextCallbackData,
		pos: i32,
		text: cstring,
		text_end: cstring = nil) ---
	@(link_name = "ImGuiInputTextCallbackData_SelectAll")
	InputTextCallbackData_SelectAll :: proc(
		self: ^InputTextCallbackData) ---
	@(link_name = "ImGuiInputTextCallbackData_SetSelection")
	InputTextCallbackData_SetSelection :: proc(
		self: ^InputTextCallbackData,
		s: i32,
		e: i32) ---
	@(link_name = "ImGuiInputTextCallbackData_ClearSelection")
	InputTextCallbackData_ClearSelection :: proc(
		self: ^InputTextCallbackData) ---
	@(link_name = "ImGuiInputTextCallbackData_HasSelection")
	InputTextCallbackData_HasSelection :: proc(
		self: ^InputTextCallbackData) -> bool ---
	@(link_name = "ImGuiPayload_Clear")
	Payload_Clear :: proc(
		self: ^Payload) ---
	@(link_name = "ImGuiPayload_IsDataType")
	Payload_IsDataType :: proc(
		self: ^Payload,
		type: cstring) -> bool ---
	@(link_name = "ImGuiPayload_IsPreview")
	Payload_IsPreview :: proc(
		self: ^Payload) -> bool ---
	@(link_name = "ImGuiPayload_IsDelivery")
	Payload_IsDelivery :: proc(
		self: ^Payload) -> bool ---
	@(link_name = "ImGuiTextFilter_ImGuiTextRange_empty")
	TextFilter_TextRange_empty :: proc(
		self: ^TextFilter_TextRange) -> bool ---
	@(link_name = "ImGuiTextFilter_ImGuiTextRange_split")
	TextFilter_TextRange_split :: proc(
		self: ^TextFilter_TextRange,
		separator: u8,
		out: ^Vector_TextRange) ---
	// Helper calling InputText+Build
	@(link_name = "ImGuiTextFilter_Draw")
	TextFilter_Draw :: proc(
		self: ^TextFilter,
		label: cstring = "Filter (inc,-exc)",
		width: f32 = 0.0) -> bool ---
	@(link_name = "ImGuiTextFilter_PassFilter")
	TextFilter_PassFilter :: proc(
		self: ^TextFilter,
		text: cstring,
		text_end: cstring = nil) -> bool ---
	@(link_name = "ImGuiTextFilter_Build")
	TextFilter_Build :: proc(
		self: ^TextFilter) ---
	@(link_name = "ImGuiTextFilter_Clear")
	TextFilter_Clear :: proc(
		self: ^TextFilter) ---
	@(link_name = "ImGuiTextFilter_IsActive")
	TextFilter_IsActive :: proc(
		self: ^TextFilter) -> bool ---
	@(link_name = "ImGuiTextBuffer_begin")
	TextBuffer_begin :: proc(
		self: ^TextBuffer) -> cstring ---
	// Buf is zero-terminated, so end() will point on the zero-terminator
	@(link_name = "ImGuiTextBuffer_end")
	TextBuffer_end :: proc(
		self: ^TextBuffer) -> cstring ---
	@(link_name = "ImGuiTextBuffer_size")
	TextBuffer_size :: proc(
		self: ^TextBuffer) -> i32 ---
	@(link_name = "ImGuiTextBuffer_empty")
	TextBuffer_empty :: proc(
		self: ^TextBuffer) -> bool ---
	@(link_name = "ImGuiTextBuffer_clear")
	TextBuffer_clear :: proc(
		self: ^TextBuffer) ---
	// Similar to resize(0) on ImVector: empty string but don't free buffer.
	@(link_name = "ImGuiTextBuffer_resize")
	TextBuffer_resize :: proc(
		self: ^TextBuffer,
		size: i32) ---
	@(link_name = "ImGuiTextBuffer_reserve")
	TextBuffer_reserve :: proc(
		self: ^TextBuffer,
		capacity: i32) ---
	@(link_name = "ImGuiTextBuffer_c_str")
	TextBuffer_c_str :: proc(
		self: ^TextBuffer) -> cstring ---
	@(link_name = "ImGuiTextBuffer_append")
	TextBuffer_append :: proc(
		self: ^TextBuffer,
		str: cstring,
		str_end: cstring = nil) ---
	@(link_name = "ImGuiTextBuffer_appendf")
	TextBuffer_appendf :: proc(
		self: ^TextBuffer,
		fmt: cstring,
		#c_vararg args: ..any) ---
	// - Get***() functions find pair, never add/allocate. Pairs are sorted so a query is O(log N)
	// - Set***() functions find pair, insertion on demand if missing.
	// - Sorted insertion is costly, paid once. A typical frame shouldn't need to insert any new pair.
	@(link_name = "ImGuiStorage_Clear")
	Storage_Clear :: proc(
		self: ^Storage) ---
	@(link_name = "ImGuiStorage_GetInt")
	Storage_GetInt :: proc(
		self: ^Storage,
		key: ID,
		default_val: i32 = 0) -> i32 ---
	@(link_name = "ImGuiStorage_SetInt")
	Storage_SetInt :: proc(
		self: ^Storage,
		key: ID,
		val: i32) ---
	@(link_name = "ImGuiStorage_GetBool")
	Storage_GetBool :: proc(
		self: ^Storage,
		key: ID,
		default_val: bool = false) -> bool ---
	@(link_name = "ImGuiStorage_SetBool")
	Storage_SetBool :: proc(
		self: ^Storage,
		key: ID,
		val: bool) ---
	@(link_name = "ImGuiStorage_GetFloat")
	Storage_GetFloat :: proc(
		self: ^Storage,
		key: ID,
		default_val: f32 = 0.0) -> f32 ---
	@(link_name = "ImGuiStorage_SetFloat")
	Storage_SetFloat :: proc(
		self: ^Storage,
		key: ID,
		val: f32) ---
	// default_val is NULL
	@(link_name = "ImGuiStorage_GetVoidPtr")
	Storage_GetVoidPtr :: proc(
		self: ^Storage,
		key: ID) -> rawptr ---
	@(link_name = "ImGuiStorage_SetVoidPtr")
	Storage_SetVoidPtr :: proc(
		self: ^Storage,
		key: ID,
		val: rawptr) ---
	// - Get***Ref() functions finds pair, insert on demand if missing, return pointer. Useful if you intend to do Get+Set.
	// - References are only valid until a new value is added to the storage. Calling a Set***() function or a Get***Ref() function invalidates the pointer.
	// - A typical use case where this is convenient for quick hacking (e.g. add storage during a live Edit&Continue session if you can't modify existing struct)
	//      float* pvar = ImGui::GetFloatRef(key); ImGui::SliderFloat("var", pvar, 0, 100.0f); some_var += *pvar;
	@(link_name = "ImGuiStorage_GetIntRef")
	Storage_GetIntRef :: proc(
		self: ^Storage,
		key: ID,
		default_val: i32 = 0) -> ^i32 ---
	@(link_name = "ImGuiStorage_GetBoolRef")
	Storage_GetBoolRef :: proc(
		self: ^Storage,
		key: ID,
		default_val: bool = false) -> ^bool ---
	@(link_name = "ImGuiStorage_GetFloatRef")
	Storage_GetFloatRef :: proc(
		self: ^Storage,
		key: ID,
		default_val: f32 = 0.0) -> ^f32 ---
	@(link_name = "ImGuiStorage_GetVoidPtrRef")
	Storage_GetVoidPtrRef :: proc(
		self: ^Storage,
		key: ID,
		default_val: rawptr = nil) -> ^rawptr ---
	// Advanced: for quicker full rebuild of a storage (instead of an incremental one), you may add all your contents and then sort once.
	@(link_name = "ImGuiStorage_BuildSortByKey")
	Storage_BuildSortByKey :: proc(
		self: ^Storage) ---
	// Obsolete: use on your own storage if you know only integer are being stored (open/close all tree nodes)
	@(link_name = "ImGuiStorage_SetAllInt")
	Storage_SetAllInt :: proc(
		self: ^Storage,
		val: i32) ---
	@(link_name = "ImGuiListClipper_Begin")
	ListClipper_Begin :: proc(
		self: ^ListClipper,
		items_count: i32,
		items_height: f32 = -1.0) ---
	// Automatically called on the last call of Step() that returns false.
	@(link_name = "ImGuiListClipper_End")
	ListClipper_End :: proc(
		self: ^ListClipper) ---
	// Call until it returns false. The DisplayStart/DisplayEnd fields will be set and you can process/draw those items.
	@(link_name = "ImGuiListClipper_Step")
	ListClipper_Step :: proc(
		self: ^ListClipper) -> bool ---
	// Call IncludeItemByIndex() or IncludeItemsByIndex() *BEFORE* first call to Step() if you need a range of items to not be clipped, regardless of their visibility.
	// (Due to alignment / padding of certain items it is possible that an extra item may be included on either end of the display range).
	@(link_name = "ImGuiListClipper_IncludeItemByIndex")
	ListClipper_IncludeItemByIndex :: proc(
		self: ^ListClipper,
		item_index: i32) ---
	// item_end is exclusive e.g. use (42, 42+1) to make item 42 never clipped.
	@(link_name = "ImGuiListClipper_IncludeItemsByIndex")
	ListClipper_IncludeItemsByIndex :: proc(
		self: ^ListClipper,
		item_begin: i32,
		item_end: i32) ---
	// Seek cursor toward given item. This is automatically called while stepping.
	// - The only reason to call this is: you can use ImGuiListClipper::Begin(INT_MAX) if you don't know item count ahead of time.
	// - In this case, after all steps are done, you'll want to call SeekCursorForItem(item_count).
	@(link_name = "ImGuiListClipper_SeekCursorForItem")
	ListClipper_SeekCursorForItem :: proc(
		self: ^ListClipper,
		item_index: i32) ---
	// FIXME-OBSOLETE: May need to obsolete/cleanup those helpers.
	@(link_name = "ImColor_SetHSV")
	Color_SetHSV :: proc(
		self: ^Color,
		h: f32,
		s: f32,
		v: f32,
		a: f32 = 1.0) ---
	@(link_name = "ImColor_HSV")
	Color_HSV :: proc(
		h: f32,
		s: f32,
		v: f32,
		a: f32 = 1.0) -> Color ---
	// Apply selection requests coming from BeginMultiSelect() and EndMultiSelect() functions. It uses 'items_count' passed to BeginMultiSelect()
	@(link_name = "ImGuiSelectionBasicStorage_ApplyRequests")
	SelectionBasicStorage_ApplyRequests :: proc(
		self: ^SelectionBasicStorage,
		ms_io: ^MultiSelectIO) ---
	// Query if an item id is in selection.
	@(link_name = "ImGuiSelectionBasicStorage_Contains")
	SelectionBasicStorage_Contains :: proc(
		self: ^SelectionBasicStorage,
		id: ID) -> bool ---
	// Clear selection
	@(link_name = "ImGuiSelectionBasicStorage_Clear")
	SelectionBasicStorage_Clear :: proc(
		self: ^SelectionBasicStorage) ---
	// Swap two selections
	@(link_name = "ImGuiSelectionBasicStorage_Swap")
	SelectionBasicStorage_Swap :: proc(
		self: ^SelectionBasicStorage,
		r: ^SelectionBasicStorage) ---
	// Add/remove an item from selection (generally done by ApplyRequests() function)
	@(link_name = "ImGuiSelectionBasicStorage_SetItemSelected")
	SelectionBasicStorage_SetItemSelected :: proc(
		self: ^SelectionBasicStorage,
		id: ID,
		selected: bool) ---
	// Iterate selection with 'void* it = NULL; ImGuiID id; while (selection.GetNextSelectedItem(&it, &id)) { ... }'
	@(link_name = "ImGuiSelectionBasicStorage_GetNextSelectedItem")
	SelectionBasicStorage_GetNextSelectedItem :: proc(
		self: ^SelectionBasicStorage,
		opaque_it: ^rawptr,
		out_id: ^ID) -> bool ---
	// Convert index to item id based on provided adapter.
	@(link_name = "ImGuiSelectionBasicStorage_GetStorageIdFromIndex")
	SelectionBasicStorage_GetStorageIdFromIndex :: proc(
		self: ^SelectionBasicStorage,
		idx: i32) -> ID ---
	// Apply selection requests by using AdapterSetItemSelected() calls
	@(link_name = "ImGuiSelectionExternalStorage_ApplyRequests")
	SelectionExternalStorage_ApplyRequests :: proc(
		self: ^SelectionExternalStorage,
		ms_io: ^MultiSelectIO) ---
	// Since 1.83: returns ImTextureID associated with this draw call. Warning: DO NOT assume this is always same as 'TextureId' (we will change this function for an upcoming feature)
	// Since 1.92: removed ImDrawCmd::TextureId field, the getter function must be used!
	// == (TexRef._TexData ? TexRef._TexData->TexID : TexRef._TexID)
	@(link_name = "ImDrawCmd_GetTexID")
	DrawCmd_GetTexID :: proc(
		self: ^DrawCmd) -> TextureID ---
	// Do not clear Channels[] so our allocations are reused next frame
	@(link_name = "ImDrawListSplitter_Clear")
	DrawListSplitter_Clear :: proc(
		self: ^DrawListSplitter) ---
	@(link_name = "ImDrawListSplitter_ClearFreeMemory")
	DrawListSplitter_ClearFreeMemory :: proc(
		self: ^DrawListSplitter) ---
	@(link_name = "ImDrawListSplitter_Split")
	DrawListSplitter_Split :: proc(
		self: ^DrawListSplitter,
		draw_list: ^DrawList,
		count: i32) ---
	@(link_name = "ImDrawListSplitter_Merge")
	DrawListSplitter_Merge :: proc(
		self: ^DrawListSplitter,
		draw_list: ^DrawList) ---
	@(link_name = "ImDrawListSplitter_SetCurrentChannel")
	DrawListSplitter_SetCurrentChannel :: proc(
		self: ^DrawListSplitter,
		draw_list: ^DrawList,
		channel_idx: i32) ---
	// Render-level scissoring. This is passed down to your render function but not used for CPU-side coarse clipping. Prefer using higher-level ImGui::PushClipRect() to affect logic (hit-testing and widget culling)
	@(link_name = "ImDrawList_PushClipRect")
	DrawList_PushClipRect :: proc(
		self: ^DrawList,
		clip_rect_min: Vec2,
		clip_rect_max: Vec2,
		intersect_with_current_clip_rect: bool = false) ---
	@(link_name = "ImDrawList_PushClipRectFullScreen")
	DrawList_PushClipRectFullScreen :: proc(
		self: ^DrawList) ---
	@(link_name = "ImDrawList_PopClipRect")
	DrawList_PopClipRect :: proc(
		self: ^DrawList) ---
	@(link_name = "ImDrawList_PushTexture")
	DrawList_PushTexture :: proc(
		self: ^DrawList,
		tex_ref: TextureRef) ---
	@(link_name = "ImDrawList_PopTexture")
	DrawList_PopTexture :: proc(
		self: ^DrawList) ---
	@(link_name = "ImDrawList_GetClipRectMin")
	DrawList_GetClipRectMin :: proc(
		self: ^DrawList) -> Vec2 ---
	@(link_name = "ImDrawList_GetClipRectMax")
	DrawList_GetClipRectMax :: proc(
		self: ^DrawList) -> Vec2 ---
	// Primitives
	// - Filled shapes must always use clockwise winding order. The anti-aliasing fringe depends on it. Counter-clockwise shapes will have "inward" anti-aliasing.
	// - For rectangular primitives, "p_min" and "p_max" represent the upper-left and lower-right corners.
	// - For circle primitives, use "num_segments == 0" to automatically calculate tessellation (preferred).
	//   In older versions (until Dear ImGui 1.77) the AddCircle functions defaulted to num_segments == 12.
	//   In future versions we will use textures to provide cheaper and higher-quality circles.
	//   Use AddNgon() and AddNgonFilled() functions if you need to guarantee a specific number of sides.
	@(link_name = "ImDrawList_AddLine")
	DrawList_AddLine :: proc(
		self: ^DrawList,
		p1: Vec2,
		p2: Vec2,
		col: u32,
		thickness: f32 = 1.0) ---
	@(link_name = "ImDrawList_AddLineH")
	DrawList_AddLineH :: proc(
		self: ^DrawList,
		min_x: f32,
		max_x: f32,
		y: f32,
		col: u32,
		thickness: f32 = 1.0) ---
	@(link_name = "ImDrawList_AddLineV")
	DrawList_AddLineV :: proc(
		self: ^DrawList,
		x: f32,
		min_y: f32,
		max_y: f32,
		col: u32,
		thickness: f32 = 1.0) ---
	// a: upper-left, b: lower-right (== upper-left + size)
	@(link_name = "ImDrawList_AddRect")
	DrawList_AddRect :: proc(
		self: ^DrawList,
		p_min: Vec2,
		p_max: Vec2,
		col: u32,
		rounding: f32 = 0.0,
		thickness: f32 = 1.0,
		flags: DrawFlags = {}) ---
	// a: upper-left, b: lower-right (== upper-left + size)
	@(link_name = "ImDrawList_AddRectFilled")
	DrawList_AddRectFilled :: proc(
		self: ^DrawList,
		p_min: Vec2,
		p_max: Vec2,
		col: u32,
		rounding: f32 = 0.0,
		flags: DrawFlags = {}) ---
	@(link_name = "ImDrawList_AddRectFilledMultiColor")
	DrawList_AddRectFilledMultiColor :: proc(
		self: ^DrawList,
		p_min: Vec2,
		p_max: Vec2,
		col_upr_left: u32,
		col_upr_right: u32,
		col_bot_right: u32,
		col_bot_left: u32) ---
	@(link_name = "ImDrawList_AddQuad")
	DrawList_AddQuad :: proc(
		self: ^DrawList,
		p1: Vec2,
		p2: Vec2,
		p3: Vec2,
		p4: Vec2,
		col: u32,
		thickness: f32 = 1.0) ---
	@(link_name = "ImDrawList_AddQuadFilled")
	DrawList_AddQuadFilled :: proc(
		self: ^DrawList,
		p1: Vec2,
		p2: Vec2,
		p3: Vec2,
		p4: Vec2,
		col: u32) ---
	@(link_name = "ImDrawList_AddTriangle")
	DrawList_AddTriangle :: proc(
		self: ^DrawList,
		p1: Vec2,
		p2: Vec2,
		p3: Vec2,
		col: u32,
		thickness: f32 = 1.0) ---
	@(link_name = "ImDrawList_AddTriangleFilled")
	DrawList_AddTriangleFilled :: proc(
		self: ^DrawList,
		p1: Vec2,
		p2: Vec2,
		p3: Vec2,
		col: u32) ---
	@(link_name = "ImDrawList_AddCircle")
	DrawList_AddCircle :: proc(
		self: ^DrawList,
		center: Vec2,
		radius: f32,
		col: u32,
		num_segments: i32 = 0,
		thickness: f32 = 1.0) ---
	@(link_name = "ImDrawList_AddCircleFilled")
	DrawList_AddCircleFilled :: proc(
		self: ^DrawList,
		center: Vec2,
		radius: f32,
		col: u32,
		num_segments: i32 = 0) ---
	@(link_name = "ImDrawList_AddNgon")
	DrawList_AddNgon :: proc(
		self: ^DrawList,
		center: Vec2,
		radius: f32,
		col: u32,
		num_segments: i32,
		thickness: f32 = 1.0) ---
	@(link_name = "ImDrawList_AddNgonFilled")
	DrawList_AddNgonFilled :: proc(
		self: ^DrawList,
		center: Vec2,
		radius: f32,
		col: u32,
		num_segments: i32) ---
	@(link_name = "ImDrawList_AddEllipse")
	DrawList_AddEllipse :: proc(
		self: ^DrawList,
		center: Vec2,
		radius: Vec2,
		col: u32,
		rot: f32 = 0.0,
		num_segments: i32 = 0,
		thickness: f32 = 1.0) ---
	@(link_name = "ImDrawList_AddEllipseFilled")
	DrawList_AddEllipseFilled :: proc(
		self: ^DrawList,
		center: Vec2,
		radius: Vec2,
		col: u32,
		rot: f32 = 0.0,
		num_segments: i32 = 0) ---
	@(link_name = "ImDrawList_AddText")
	DrawList_AddText :: proc(
		self: ^DrawList,
		pos: Vec2,
		col: u32,
		text_begin: cstring,
		text_end: cstring = nil) ---
	@(link_name = "ImDrawList_AddTextImFontPtr")
	DrawList_AddTextFontPtr :: proc(
		self: ^DrawList,
		font: ^Font,
		font_size: f32,
		pos: Vec2,
		col: u32,
		text_begin: cstring,
		text_end: cstring = nil,
		wrap_width: f32 = 0.0,
		cpu_fine_clip_rect: ^Vec4 = nil) ---
	// Cubic Bezier (4 control points)
	@(link_name = "ImDrawList_AddBezierCubic")
	DrawList_AddBezierCubic :: proc(
		self: ^DrawList,
		p1: Vec2,
		p2: Vec2,
		p3: Vec2,
		p4: Vec2,
		col: u32,
		thickness: f32,
		num_segments: i32 = 0) ---
	// Quadratic Bezier (3 control points)
	@(link_name = "ImDrawList_AddBezierQuadratic")
	DrawList_AddBezierQuadratic :: proc(
		self: ^DrawList,
		p1: Vec2,
		p2: Vec2,
		p3: Vec2,
		col: u32,
		thickness: f32,
		num_segments: i32 = 0) ---
	// General polygon
	// - Only simple polygons are supported by filling functions (no self-intersections, no holes).
	// - Concave polygon fill is more expensive than convex one: it has O(N^2) complexity. Provided as a convenience for the user but not used by the main library.
	@(link_name = "ImDrawList_AddPolyline")
	DrawList_AddPolyline :: proc(
		self: ^DrawList,
		points: ^Vec2,
		num_points: i32,
		col: u32,
		thickness: f32,
		flags: DrawFlags = {}) ---
	@(link_name = "ImDrawList_AddConvexPolyFilled")
	DrawList_AddConvexPolyFilled :: proc(
		self: ^DrawList,
		points: ^Vec2,
		num_points: i32,
		col: u32) ---
	@(link_name = "ImDrawList_AddConcavePolyFilled")
	DrawList_AddConcavePolyFilled :: proc(
		self: ^DrawList,
		points: ^Vec2,
		num_points: i32,
		col: u32) ---
	// Image primitives
	// - Read FAQ to understand what ImTextureID/ImTextureRef are.
	// - "p_min" and "p_max" represent the upper-left and lower-right corners of the rectangle.
	// - "uv_min" and "uv_max" represent the normalized texture coordinates to use for those corners. Using (0,0)->(1,1) texture coordinates will generally display the entire texture.
	@(link_name = "ImDrawList_AddImage")
	ImDrawList_AddImage :: proc(
		self: ^DrawList,
		tex_ref: TextureRef,
		p_min: Vec2,
		p_max: Vec2,
		uv_min: Vec2 = Vec2{0, 0},
		uv_max: Vec2 = Vec2{1, 1},
		col: u32 = 0xff_ff_ff_ff) ---
	@(link_name = "ImDrawList_AddImageQuad")
	ImDrawList_AddImageQuad :: proc(
		self: ^DrawList,
		tex_ref: TextureRef,
		p1: Vec2,
		p2: Vec2,
		p3: Vec2,
		p4: Vec2,
		uv1: Vec2 = Vec2{0, 0},
		uv2: Vec2 = Vec2{1, 0},
		uv3: Vec2 = Vec2{1, 1},
		uv4: Vec2 = Vec2{0, 1},
		col: u32 = 0xff_ff_ff_ff) ---
	@(link_name = "ImDrawList_AddImageRounded")
	ImDrawList_AddImageRounded :: proc(
		self: ^DrawList,
		tex_ref: TextureRef,
		p_min: Vec2,
		p_max: Vec2,
		uv_min: Vec2,
		uv_max: Vec2,
		col: u32,
		rounding: f32,
		flags: DrawFlags = {}) ---
	// Stateful path API, add points then finish with PathFillConvex() or PathStroke()
	// - Important: filled shapes must always use clockwise winding order! The anti-aliasing fringe depends on it. Counter-clockwise shapes will have "inward" anti-aliasing.
	//   so e.g. 'PathArcTo(center, radius, PI * -0.5f, PI)' is ok, whereas 'PathArcTo(center, radius, PI, PI * -0.5f)' won't have correct anti-aliasing when followed by PathFillConvex().
	@(link_name = "ImDrawList_PathClear")
	DrawList_PathClear :: proc(
		self: ^DrawList) ---
	@(link_name = "ImDrawList_PathLineTo")
	DrawList_PathLineTo :: proc(
		self: ^DrawList,
		pos: Vec2) ---
	@(link_name = "ImDrawList_PathLineToMergeDuplicate")
	DrawList_PathLineToMergeDuplicate :: proc(
		self: ^DrawList,
		pos: Vec2) ---
	@(link_name = "ImDrawList_PathFillConvex")
	DrawList_PathFillConvex :: proc(
		self: ^DrawList,
		col: u32) ---
	@(link_name = "ImDrawList_PathFillConcave")
	DrawList_PathFillConcave :: proc(
		self: ^DrawList,
		col: u32) ---
	@(link_name = "ImDrawList_PathStroke")
	DrawList_PathStroke :: proc(
		self: ^DrawList,
		col: u32,
		thickness: f32 = 1.0,
		flags: DrawFlags = {}) ---
	@(link_name = "ImDrawList_PathArcTo")
	DrawList_PathArcTo :: proc(
		self: ^DrawList,
		center: Vec2,
		radius: f32,
		a_min: f32,
		a_max: f32,
		num_segments: i32 = 0) ---
	// Use precomputed angles for a 12 steps circle
	@(link_name = "ImDrawList_PathArcToFast")
	DrawList_PathArcToFast :: proc(
		self: ^DrawList,
		center: Vec2,
		radius: f32,
		a_min_of_12: i32,
		a_max_of_12: i32) ---
	// Ellipse
	@(link_name = "ImDrawList_PathEllipticalArcTo")
	DrawList_PathEllipticalArcTo :: proc(
		self: ^DrawList,
		center: Vec2,
		radius: Vec2,
		rot: f32,
		a_min: f32,
		a_max: f32,
		num_segments: i32 = 0) ---
	// Cubic Bezier (4 control points)
	@(link_name = "ImDrawList_PathBezierCubicCurveTo")
	DrawList_PathBezierCubicCurveTo :: proc(
		self: ^DrawList,
		p2: Vec2,
		p3: Vec2,
		p4: Vec2,
		num_segments: i32 = 0) ---
	// Quadratic Bezier (3 control points)
	@(link_name = "ImDrawList_PathBezierQuadraticCurveTo")
	DrawList_PathBezierQuadraticCurveTo :: proc(
		self: ^DrawList,
		p2: Vec2,
		p3: Vec2,
		num_segments: i32 = 0) ---
	@(link_name = "ImDrawList_PathRect")
	DrawList_PathRect :: proc(
		self: ^DrawList,
		rect_min: Vec2,
		rect_max: Vec2,
		rounding: f32 = 0.0,
		flags: DrawFlags = {}) ---
	// Advanced: Draw Callbacks
	// - May be used to alter render state (change sampler, blending, current shader). May be used to emit custom rendering commands (difficult to do correctly, but possible).
	// - Use special GetPlatformIO().DrawCallback_ResetRenderState callback to instruct backend to reset its render state to the default.
	// - See other standard callbacks in GetPlatformIO(), which may or not be supported by your backend.
	// - Your rendering loop must check for 'UserCallback' in ImDrawCmd and call the function instead of rendering triangles. All standard backends are honoring this.
	// - For some backends, the callback may access selected render-states exposed by the backend in a ImGui_ImplXXXX_RenderState structure pointed to by platform_io.Renderer_RenderState.
	// - IMPORTANT: please be mindful of the different level of indirection between using size==0 (copying argument) and using size>0 (copying pointed data into a buffer).
	//   - If userdata_size == 0: we copy/store the 'userdata' argument as-is. It will be available unmodified in ImDrawCmd::UserCallbackData during render.
	//   - If userdata_size > 0,  we copy/store 'userdata_size' bytes pointed to by 'userdata'. We store them in a buffer stored inside the drawlist. ImDrawCmd::UserCallbackData will point inside that buffer so you have to retrieve data from there. Your callback may need to use ImDrawCmd::UserCallbackDataSize if you expect dynamically-sized data.
	//   - Support for userdata_size > 0 was added in v1.91.4, October 2024. So earlier code always only allowed to copy/store a simple void*.
	@(link_name = "ImDrawList_AddCallback")
	DrawList_AddCallback :: proc(
		self: ^DrawList,
		callback: DrawCallback,
		userdata: rawptr = nil,
		userdata_size: uint = {}) ---
	// Advanced: Miscellaneous
	// This is useful if you need to forcefully create a new draw call (to allow for dependent rendering / blending). Otherwise primitives are merged into the same draw-call as much as possible
	@(link_name = "ImDrawList_AddDrawCmd")
	DrawList_AddDrawCmd :: proc(
		self: ^DrawList) ---
	// Create a clone of the CmdBuffer/IdxBuffer/VtxBuffer. For multi-threaded rendering, consider using `imgui_threaded_rendering` from https://github.com/ocornut/imgui_club instead.
	@(link_name = "ImDrawList_CloneOutput")
	DrawList_CloneOutput :: proc(
		self: ^DrawList) -> ^DrawList ---
	// Advanced: Channels
	// - Use to split render into layers. By switching channels to can render out-of-order (e.g. submit FG primitives before BG primitives)
	// - Use to minimize draw calls (e.g. if going back-and-forth between multiple clipping rectangles, prefer to append into separate channels then merge at the end)
	// - This API shouldn't have been in ImDrawList in the first place!
	//   Prefer using your own persistent instance of ImDrawListSplitter as you can stack them.
	//   Using the ImDrawList::ChannelsXXXX you cannot stack a split over another.
	@(link_name = "ImDrawList_ChannelsSplit")
	DrawList_ChannelsSplit :: proc(
		self: ^DrawList,
		count: i32) ---
	@(link_name = "ImDrawList_ChannelsMerge")
	DrawList_ChannelsMerge :: proc(
		self: ^DrawList) ---
	@(link_name = "ImDrawList_ChannelsSetCurrent")
	DrawList_ChannelsSetCurrent :: proc(
		self: ^DrawList,
		n: i32) ---
	// Advanced: Primitives allocations
	// - We render triangles (three vertices)
	// - All primitives needs to be reserved via PrimReserve() beforehand.
	@(link_name = "ImDrawList_PrimReserve")
	DrawList_PrimReserve :: proc(
		self: ^DrawList,
		idx_count: i32,
		vtx_count: i32) ---
	@(link_name = "ImDrawList_PrimUnreserve")
	DrawList_PrimUnreserve :: proc(
		self: ^DrawList,
		idx_count: i32,
		vtx_count: i32) ---
	// Axis aligned rectangle (composed of two triangles)
	@(link_name = "ImDrawList_PrimRect")
	DrawList_PrimRect :: proc(
		self: ^DrawList,
		a: Vec2,
		b: Vec2,
		col: u32) ---
	@(link_name = "ImDrawList_PrimRectUV")
	DrawList_PrimRectUV :: proc(
		self: ^DrawList,
		a: Vec2,
		b: Vec2,
		uv_a: Vec2,
		uv_b: Vec2,
		col: u32) ---
	@(link_name = "ImDrawList_PrimQuadUV")
	DrawList_PrimQuadUV :: proc(
		self: ^DrawList,
		a: Vec2,
		b: Vec2,
		c: Vec2,
		d: Vec2,
		uv_a: Vec2,
		uv_b: Vec2,
		uv_c: Vec2,
		uv_d: Vec2,
		col: u32) ---
	@(link_name = "ImDrawList_PrimWriteVtx")
	DrawList_PrimWriteVtx :: proc(
		self: ^DrawList,
		pos: Vec2,
		uv: Vec2,
		col: u32) ---
	@(link_name = "ImDrawList_PrimWriteIdx")
	DrawList_PrimWriteIdx :: proc(
		self: ^DrawList,
		idx: DrawIdx) ---
	// Write vertex with unique index
	@(link_name = "ImDrawList_PrimVtx")
	DrawList_PrimVtx :: proc(
		self: ^DrawList,
		pos: Vec2,
		uv: Vec2,
		col: u32) ---
	// [Internal helpers]
	@(link_name = "ImDrawList__SetDrawListSharedData")
	DrawList__SetDrawListSharedData :: proc(
		self: ^DrawList,
		data: ^DrawListSharedData) ---
	@(link_name = "ImDrawList__ResetForNewFrame")
	DrawList__ResetForNewFrame :: proc(
		self: ^DrawList) ---
	@(link_name = "ImDrawList__ClearFreeMemory")
	DrawList__ClearFreeMemory :: proc(
		self: ^DrawList) ---
	@(link_name = "ImDrawList__PopUnusedDrawCmd")
	DrawList__PopUnusedDrawCmd :: proc(
		self: ^DrawList) ---
	@(link_name = "ImDrawList__TryMergeDrawCmds")
	DrawList__TryMergeDrawCmds :: proc(
		self: ^DrawList) ---
	@(link_name = "ImDrawList__OnChangedClipRect")
	DrawList__OnChangedClipRect :: proc(
		self: ^DrawList) ---
	@(link_name = "ImDrawList__OnChangedTexture")
	DrawList__OnChangedTexture :: proc(
		self: ^DrawList) ---
	@(link_name = "ImDrawList__OnChangedVtxOffset")
	DrawList__OnChangedVtxOffset :: proc(
		self: ^DrawList) ---
	@(link_name = "ImDrawList__SetTexture")
	DrawList__SetTexture :: proc(
		self: ^DrawList,
		tex_ref: TextureRef) ---
	@(link_name = "ImDrawList__CalcCircleAutoSegmentCount")
	DrawList__CalcCircleAutoSegmentCount :: proc(
		self: ^DrawList,
		radius: f32) -> i32 ---
	@(link_name = "ImDrawList__PathArcToFastEx")
	DrawList__PathArcToFastEx :: proc(
		self: ^DrawList,
		center: Vec2,
		radius: f32,
		a_min_sample: i32,
		a_max_sample: i32,
		a_step: i32) ---
	@(link_name = "ImDrawList__PathArcToN")
	DrawList__PathArcToN :: proc(
		self: ^DrawList,
		center: Vec2,
		radius: f32,
		a_min: f32,
		a_max: f32,
		num_segments: i32) ---
	@(link_name = "ImDrawData_Clear")
	DrawData_Clear :: proc(
		self: ^DrawData) ---
	// Helper to add an external draw list into an existing ImDrawData.
	@(link_name = "ImDrawData_AddDrawList")
	DrawData_AddDrawList :: proc(
		self: ^DrawData,
		draw_list: ^DrawList) ---
	// Helper to convert all buffers from indexed to non-indexed, in case you cannot render indexed. Note: this is slow and most likely a waste of resources. Always prefer indexed rendering!
	@(link_name = "ImDrawData_DeIndexAllBuffers")
	DrawData_DeIndexAllBuffers :: proc(
		self: ^DrawData) ---
	// Helper to scale the ClipRect field of each ImDrawCmd. Use if your final output buffer is at a different scale than Dear ImGui expects, or if there is a difference between your window resolution and framebuffer resolution.
	@(link_name = "ImDrawData_ScaleClipRects")
	DrawData_ScaleClipRects :: proc(
		self: ^DrawData,
		fb_scale: Vec2) ---
	@(link_name = "ImTextureData_Create")
	TextureData_Create :: proc(
		self: ^TextureData,
		format: TextureFormat,
		w: i32,
		h: i32) ---
	@(link_name = "ImTextureData_DestroyPixels")
	TextureData_DestroyPixels :: proc(
		self: ^TextureData) ---
	@(link_name = "ImTextureData_GetPixels")
	TextureData_GetPixels :: proc(
		self: ^TextureData) -> rawptr ---
	@(link_name = "ImTextureData_GetPixelsAt")
	TextureData_GetPixelsAt :: proc(
		self: ^TextureData,
		x: i32,
		y: i32) -> rawptr ---
	@(link_name = "ImTextureData_GetSizeInBytes")
	TextureData_GetSizeInBytes :: proc(
		self: ^TextureData) -> i32 ---
	@(link_name = "ImTextureData_GetPitch")
	TextureData_GetPitch :: proc(
		self: ^TextureData) -> i32 ---
	@(link_name = "ImTextureData_GetTexRef")
	TextureData_GetTexRef :: proc(
		self: ^TextureData) -> TextureRef ---
	@(link_name = "ImTextureData_GetTexID")
	TextureData_GetTexID :: proc(
		self: ^TextureData) -> TextureID ---
	// Called by Renderer backend
	// - Call SetTexID() and SetStatus() after honoring texture requests. Never modify TexID and Status directly!
	// - A backend may decide to destroy a texture that we did not request to destroy, which is fine (e.g. freeing resources), but we immediately set the texture back in _WantCreate mode.
	@(link_name = "ImTextureData_SetTexID")
	TextureData_SetTexID :: proc(
		self: ^TextureData,
		tex_id: TextureID) ---
	@(link_name = "ImTextureData_SetStatus")
	TextureData_SetStatus :: proc(
		self: ^TextureData,
		status: TextureStatus) ---
	@(link_name = "ImFontGlyphRangesBuilder_Clear")
	FontGlyphRangesBuilder_Clear :: proc(
		self: ^FontGlyphRangesBuilder) ---
	// Get bit n in the array
	@(link_name = "ImFontGlyphRangesBuilder_GetBit")
	FontGlyphRangesBuilder_GetBit :: proc(
		self: ^FontGlyphRangesBuilder,
		n: uint) -> bool ---
	// Set bit n in the array
	@(link_name = "ImFontGlyphRangesBuilder_SetBit")
	FontGlyphRangesBuilder_SetBit :: proc(
		self: ^FontGlyphRangesBuilder,
		n: uint) ---
	// Add character
	@(link_name = "ImFontGlyphRangesBuilder_AddChar")
	FontGlyphRangesBuilder_AddChar :: proc(
		self: ^FontGlyphRangesBuilder,
		c: Wchar) ---
	// Add string (each character of the UTF-8 string are added)
	@(link_name = "ImFontGlyphRangesBuilder_AddText")
	FontGlyphRangesBuilder_AddText :: proc(
		self: ^FontGlyphRangesBuilder,
		text: cstring,
		text_end: cstring = nil) ---
	// Add ranges, e.g. builder.AddRanges(ImFontAtlas::GetGlyphRangesDefault()) to force add all of ASCII/Latin+Ext
	@(link_name = "ImFontGlyphRangesBuilder_AddRanges")
	FontGlyphRangesBuilder_AddRanges :: proc(
		self: ^FontGlyphRangesBuilder,
		ranges: ^Wchar) ---
	// Output new ranges (ImVector_Construct()/ImVector_Destruct() can be used to safely construct out_ranges)
	@(link_name = "ImFontGlyphRangesBuilder_BuildRanges")
	FontGlyphRangesBuilder_BuildRanges :: proc(
		self: ^FontGlyphRangesBuilder,
		out_ranges: ^Vector_Wchar) ---
	@(link_name = "ImFontAtlas_AddFont")
	FontAtlas_AddFont :: proc(
		self: ^FontAtlas,
		font_cfg: ^FontConfig) -> ^Font ---
	// Selects between AddFontDefaultVector() and AddFontDefaultBitmap().
	@(link_name = "ImFontAtlas_AddFontDefault")
	FontAtlas_AddFontDefault :: proc(
		self: ^FontAtlas,
		font_cfg: ^FontConfig = nil) -> ^Font ---
	// Embedded scalable font. Recommended at any higher size.
	@(link_name = "ImFontAtlas_AddFontDefaultVector")
	FontAtlas_AddFontDefaultVector :: proc(
		self: ^FontAtlas,
		font_cfg: ^FontConfig = nil) -> ^Font ---
	// Embedded classic pixel-clean font. Recommended at Size 13px with no scaling.
	@(link_name = "ImFontAtlas_AddFontDefaultBitmap")
	FontAtlas_AddFontDefaultBitmap :: proc(
		self: ^FontAtlas,
		font_cfg: ^FontConfig = nil) -> ^Font ---
	@(link_name = "ImFontAtlas_AddFontFromFileTTF")
	FontAtlas_AddFontFromFileTTF :: proc(
		self: ^FontAtlas,
		filename: cstring,
		size_pixels: f32 = 0.0,
		font_cfg: ^FontConfig = nil,
		glyph_ranges: ^Wchar = nil) -> ^Font ---
	// Note: Transfer ownership of 'ttf_data' to ImFontAtlas! Will be deleted after destruction of the atlas. Set font_cfg->FontDataOwnedByAtlas=false to keep ownership of your data and it won't be freed.
	@(link_name = "ImFontAtlas_AddFontFromMemoryTTF")
	FontAtlas_AddFontFromMemoryTTF :: proc(
		self: ^FontAtlas,
		font_data: rawptr,
		font_data_size: i32,
		size_pixels: f32 = 0.0,
		font_cfg: ^FontConfig = nil,
		glyph_ranges: ^Wchar = nil) -> ^Font ---
	// 'compressed_font_data' still owned by caller. Compress with binary_to_compressed_c.cpp.
	@(link_name = "ImFontAtlas_AddFontFromMemoryCompressedTTF")
	FontAtlas_AddFontFromMemoryCompressedTTF :: proc(
		self: ^FontAtlas,
		compressed_font_data: rawptr,
		compressed_font_data_size: i32,
		size_pixels: f32 = 0.0,
		font_cfg: ^FontConfig = nil,
		glyph_ranges: ^Wchar = nil) -> ^Font ---
	// 'compressed_font_data_base85' still owned by caller. Compress with binary_to_compressed_c.cpp with -base85 parameter.
	@(link_name = "ImFontAtlas_AddFontFromMemoryCompressedBase85TTF")
	FontAtlas_AddFontFromMemoryCompressedBase85TTF :: proc(
		self: ^FontAtlas,
		compressed_font_data_base85: cstring,
		size_pixels: f32 = 0.0,
		font_cfg: ^FontConfig = nil,
		glyph_ranges: ^Wchar = nil) -> ^Font ---
	// Remove a font
	@(link_name = "ImFontAtlas_RemoveFont")
	FontAtlas_RemoveFont :: proc(
		self: ^FontAtlas,
		font: ^Font) ---
	// Compact cached glyphs and texture.
	@(link_name = "ImFontAtlas_CompactCache")
	FontAtlas_CompactCache :: proc(
		self: ^FontAtlas) ---
	// Change font loader at runtime.
	@(link_name = "ImFontAtlas_SetFontLoader")
	FontAtlas_SetFontLoader :: proc(
		self: ^FontAtlas,
		font_loader: ^FontLoader) ---
	// Clearing the atlas/fonts has little use nowadays, unless you want to batch remove all fonts.
	// - Since 1.92, you can call ClearFonts() mid-frame, if you load new fonts afterwards.
	// - As we are transitioning toward our new font system the semantic for those functions gets increasingly misleading and are often a source of issues.
	//   TL;DR; most likely, don't use any of those functions. We expect to obsolete/rework them.
	// Clear everything (fonts + textures). Don't call mid-frame!
	@(link_name = "ImFontAtlas_Clear")
	FontAtlas_Clear :: proc(
		self: ^FontAtlas) ---
	// Clear input+output font data/glyphs. New fonts and textures will be recreated afterwards.
	@(link_name = "ImFontAtlas_ClearFonts")
	FontAtlas_ClearFonts :: proc(
		self: ^FontAtlas) ---
	// [OBSOLETE] Clear input data (all ImFontConfig structures including sizes, TTF data, glyph ranges, etc.) = all the data used to build the texture and fonts.
	@(link_name = "ImFontAtlas_ClearInputData")
	FontAtlas_ClearInputData :: proc(
		self: ^FontAtlas) ---
	// [OBSOLETE] Clear CPU-side copy of the texture data. Saves RAM once the texture has been copied to graphics memory.
	@(link_name = "ImFontAtlas_ClearTexData")
	FontAtlas_ClearTexData :: proc(
		self: ^FontAtlas) ---
	// Since 1.92: specifying glyph ranges is only useful/necessary if your backend doesn't support ImGuiBackendFlags_RendererHasTextures!
	// Basic Latin, Extended Latin
	@(link_name = "ImFontAtlas_GetGlyphRangesDefault")
	FontAtlas_GetGlyphRangesDefault :: proc(
		self: ^FontAtlas) -> ^Wchar ---
	// Register and retrieve custom rectangles
	// - You can request arbitrary rectangles to be packed into the atlas, for your own purpose.
	// - Since 1.92.0, packing is done immediately in the function call (previously packing was done during the Build call)
	// - You can render your pixels into the texture right after calling the AddCustomRect() functions.
	// - VERY IMPORTANT:
	//   - Texture may be created/resized at any time when calling ImGui or ImFontAtlas functions.
	//   - IT WILL INVALIDATE RECTANGLE DATA SUCH AS UV COORDINATES. Always use latest values from GetCustomRect().
	//   - UV coordinates are associated to the current texture identifier aka 'atlas->TexRef'. Both TexRef and UV coordinates are typically changed at the same time.
	// - If you render colored output into your custom rectangles: set 'atlas->TexPixelsUseColors = true' as this may help some backends decide of preferred texture format.
	// - Read docs/FONTS.md for more details about using colorful icons.
	// - Note: this API may be reworked further in order to facilitate supporting e.g. multi-monitor, varying DPI settings.
	// - (Pre-1.92 names) ------------> (1.92 names)
	//   - GetCustomRectByIndex()   --> Use GetCustomRect()
	//   - CalcCustomRectUV()       --> Use GetCustomRect() and read uv0, uv1 fields.
	//   - AddCustomRectRegular()   --> Renamed to AddCustomRect()
	//   - AddCustomRectFontGlyph() --> Prefer using custom ImFontLoader inside ImFontConfig
	//   - ImFontAtlasCustomRect    --> Renamed to ImFontAtlasRect
	// Register a rectangle. Return -1 (ImFontAtlasRectId_Invalid) on error.
	@(link_name = "ImFontAtlas_AddCustomRect")
	FontAtlas_AddCustomRect :: proc(
		self: ^FontAtlas,
		width: i32,
		height: i32,
		out_r: ^FontAtlasRect = nil) -> FontAtlasRectId ---
	// Unregister a rectangle. Existing pixels will stay in texture until resized / garbage collected.
	@(link_name = "ImFontAtlas_RemoveCustomRect")
	FontAtlas_RemoveCustomRect :: proc(
		self: ^FontAtlas,
		id: FontAtlasRectId) ---
	// Get rectangle coordinates for current texture. Valid immediately, never store this (read above)!
	@(link_name = "ImFontAtlas_GetCustomRect")
	FontAtlas_GetCustomRect :: proc(
		self: ^FontAtlas,
		id: FontAtlasRectId,
		out_r: ^FontAtlasRect) -> bool ---
	@(link_name = "ImFontBaked_ClearOutputData")
	FontBaked_ClearOutputData :: proc(
		self: ^FontBaked) ---
	// Return U+FFFD glyph if requested glyph doesn't exists.
	@(link_name = "ImFontBaked_FindGlyph")
	FontBaked_FindGlyph :: proc(
		self: ^FontBaked,
		c: Wchar) -> ^FontGlyph ---
	// Return NULL if glyph doesn't exist
	@(link_name = "ImFontBaked_FindGlyphNoFallback")
	FontBaked_FindGlyphNoFallback :: proc(
		self: ^FontBaked,
		c: Wchar) -> ^FontGlyph ---
	@(link_name = "ImFontBaked_GetCharAdvance")
	FontBaked_GetCharAdvance :: proc(
		self: ^FontBaked,
		c: Wchar) -> f32 ---
	@(link_name = "ImFontBaked_IsGlyphLoaded")
	FontBaked_IsGlyphLoaded :: proc(
		self: ^FontBaked,
		c: Wchar) -> bool ---
	@(link_name = "ImFont_IsGlyphInFont")
	Font_IsGlyphInFont :: proc(
		self: ^Font,
		c: Wchar) -> bool ---
	@(link_name = "ImFont_IsLoaded")
	Font_IsLoaded :: proc(
		self: ^Font) -> bool ---
	// Fill ImFontConfig::Name.
	@(link_name = "ImFont_GetDebugName")
	Font_GetDebugName :: proc(
		self: ^Font) -> cstring ---
	// [Internal] Don't use!
	// 'max_width' stops rendering after a certain width (could be turned into a 2d size). FLT_MAX to disable.
	// 'wrap_width' enable automatic word-wrapping across multiple lines to fit into given width. 0.0f to disable.
	// Get or create baked data for given size
	@(link_name = "ImFont_GetFontBaked")
	Font_GetFontBaked :: proc(
		self: ^Font,
		font_size: f32,
		density: f32 = -1.0) -> ^FontBaked ---
	@(link_name = "ImFont_CalcTextSizeA")
	Font_CalcTextSizeA :: proc(
		self: ^Font,
		size: f32,
		max_width: f32,
		wrap_width: f32,
		text_begin: cstring,
		text_end: cstring = nil,
		out_remaining: ^cstring = nil) -> Vec2 ---
	@(link_name = "ImFont_CalcWordWrapPosition")
	Font_CalcWordWrapPosition :: proc(
		self: ^Font,
		size: f32,
		text: cstring,
		text_end: cstring,
		wrap_width: f32) -> cstring ---
	@(link_name = "ImFont_RenderChar")
	Font_RenderChar :: proc(
		self: ^Font,
		draw_list: ^DrawList,
		size: f32,
		pos: Vec2,
		col: u32,
		c: Wchar,
		cpu_fine_clip: ^Vec4 = nil) ---
	@(link_name = "ImFont_RenderText")
	Font_RenderText :: proc(
		self: ^Font,
		draw_list: ^DrawList,
		size: f32,
		pos: Vec2,
		col: u32,
		clip_rect: Vec4,
		text_begin: cstring,
		text_end: cstring,
		wrap_width: f32 = 0.0,
		flags: DrawTextFlags = {}) ---
	// [Internal] Don't use!
	@(link_name = "ImFont_ClearOutputData")
	Font_ClearOutputData :: proc(
		self: ^Font) ---
	// Makes 'from_codepoint' character points to 'to_codepoint' glyph.
	@(link_name = "ImFont_AddRemapChar")
	Font_AddRemapChar :: proc(
		self: ^Font,
		from_codepoint: Wchar,
		to_codepoint: Wchar) ---
	@(link_name = "ImFont_IsGlyphRangeUnused")
	Font_IsGlyphRangeUnused :: proc(
		self: ^Font,
		c_begin: u32,
		c_last: u32) -> bool ---
	// Helpers
	@(link_name = "ImGuiViewport_GetCenter")
	Viewport_GetCenter :: proc(
		self: ^Viewport) -> Vec2 ---
	@(link_name = "ImGuiViewport_GetWorkCenter")
	Viewport_GetWorkCenter :: proc(
		self: ^Viewport) -> Vec2 ---
	@(link_name = "ImGuiViewport_GetDebugName")
	Viewport_GetDebugName :: proc(
		self: ^Viewport) -> cstring ---
	// Clear all Platform_XXX fields. Typically called on Platform Backend shutdown.
	@(link_name = "ImGuiPlatformIO_ClearPlatformHandlers")
	PlatformIO_ClearPlatformHandlers :: proc(
		self: ^PlatformIO) ---
	// Clear all Renderer_XXX fields. Typically called on Renderer Backend shutdown.
	@(link_name = "ImGuiPlatformIO_ClearRendererHandlers")
	PlatformIO_ClearRendererHandlers :: proc(
		self: ^PlatformIO) ---
}