mkdir dear_bindings
cd dear_bindings
curl -L -O https://github.com/dearimgui/dear_bindings/releases/download/DearBindings_v0.24_ImGui_v1.92.9b-docking/dcimgui.cpp
curl -L -O https://github.com/dearimgui/dear_bindings/releases/download/DearBindings_v0.24_ImGui_v1.92.9b-docking/dcimgui.h
curl -L -O https://github.com/dearimgui/dear_bindings/releases/download/DearBindings_v0.24_ImGui_v1.92.9b-docking/dcimgui_internal.cpp
curl -L -O https://github.com/dearimgui/dear_bindings/releases/download/DearBindings_v0.24_ImGui_v1.92.9b-docking/dcimgui_internal.h
cd ..
git clone --branch v1.92.9b-docking --depth 1 git@github.com:ocornut/imgui.git