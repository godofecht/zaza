#include "imgui.h"
#include <cstdio>
#include <cstdint>
int main() {
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(1280, 720);
    io.DeltaTime = 1.0f / 60.0f;
    unsigned char* pixels; int w, h;
    io.Fonts->GetTexDataAsRGBA32(&pixels, &w, &h);
    io.Fonts->TexID = (ImTextureID)(intptr_t)1;

    ImDrawData* dd = nullptr;
    // A few frames: the first lays windows out, later frames emit geometry.
    for (int frame = 0; frame < 3; ++frame) {
        ImGui::NewFrame();
        ImGui::Begin("zaza+imgui slice");
        ImGui::Text("Dear ImGui %s built via Zaza", IMGUI_VERSION);
        ImGui::Button("ok");
        ImGui::Separator();
        ImGui::Text("headless render, no GPU backend");
        ImGui::End();
        ImGui::Render();
        dd = ImGui::GetDrawData();
    }
    printf("zaza+imgui slice: valid=%d cmd_lists=%d vtx=%d idx=%d (font atlas %dx%d)\n",
           dd->Valid, dd->CmdListsCount, dd->TotalVtxCount, dd->TotalIdxCount, w, h);
    ImGui::DestroyContext();
    return (dd->Valid && dd->TotalVtxCount > 0) ? 0 : 1;
}
