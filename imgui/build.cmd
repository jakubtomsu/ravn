cl /c /Od /Zi /MTd /Iimgui /DIMGUI_DISABLE_OBSOLETE_FUNCTIONS ^
    imgui_unity_build.cpp dear_bindings/dcimgui.cpp dear_bindings/dcimgui_internal.cpp
lib /OUT:imgui_windows_x86_64.lib imgui_unity_build.obj dcimgui.obj dcimgui_internal.obj
del imgui_unity_build.obj
del dcimgui.obj
del dcimgui_internal.obj
