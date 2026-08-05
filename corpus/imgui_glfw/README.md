# imgui + GLFW/OpenGL3 corpus slice

The heavier end of the `zig-gamedev` candidate: [Dear ImGui](https://github.com/ocornut/imgui)
`1.87` core plus its `imgui_impl_glfw` and `imgui_impl_opengl3` backends, built as
a Zaza static-library target and linked against system **GLFW** and **OpenGL**.
The consumer opens a GLFW window, creates a GL context, and renders a real ImGui
frame — run headless under a virtual framebuffer.

```sh
# system prerequisites (Debian/Ubuntu):
apt-get install libglfw3-dev libgl1-mesa-dev libgl1-mesa-dri xvfb

./fetch.sh
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a zig build run
# -> zaza+imgui+glfw slice: GL=4.5 (Core Profile) Mesa ... | valid=1 vtx=242 idx=411
```

The full recorded comparison — pinned commit, upstream and Zaza commands,
artifacts, and known gaps — is in [`PROOF.md`](PROOF.md).
