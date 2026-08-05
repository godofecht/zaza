#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_opengl3.h"
#include <GLFW/glfw3.h>
#include <cstdio>

int main() {
    if (!glfwInit()) { printf("glfwInit failed\n"); return 1; }
    glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    GLFWwindow* win = glfwCreateWindow(1280, 720, "zaza+imgui+glfw", NULL, NULL);
    if (!win) { printf("glfwCreateWindow failed\n"); glfwTerminate(); return 1; }
    glfwMakeContextCurrent(win);
    glfwSwapInterval(0);

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGui::StyleColorsDark();
    ImGui_ImplGlfw_InitForOpenGL(win, true);
    ImGui_ImplOpenGL3_Init("#version 130");

    ImDrawData* dd = nullptr;
    for (int frame = 0; frame < 3; ++frame) {
        glfwPollEvents();
        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();
        ImGui::Begin("zaza+imgui+glfw slice");
        ImGui::Text("Dear ImGui %s over GLFW + OpenGL3", IMGUI_VERSION);
        ImGui::Button("ok");
        ImGui::End();
        ImGui::Render();
        int w, h; glfwGetFramebufferSize(win, &w, &h);
        glViewport(0, 0, w, h);
        glClearColor(0.1f, 0.1f, 0.1f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        dd = ImGui::GetDrawData();
        ImGui_ImplOpenGL3_RenderDrawData(dd);
        glfwSwapBuffers(win);
    }
    printf("zaza+imgui+glfw slice: GL=%s | valid=%d vtx=%d idx=%d\n",
           glGetString(GL_VERSION), dd->Valid, dd->TotalVtxCount, dd->TotalIdxCount);

    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    glfwDestroyWindow(win);
    glfwTerminate();
    return (dd->Valid && dd->TotalVtxCount > 0) ? 0 : 1;
}
