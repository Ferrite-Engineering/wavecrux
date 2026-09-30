#include "my_application.h"

#include <glib.h>
#include <string.h>

// Under WSLg the default GPU stack (Mesa's Zink GL-on-Vulkan over the Dozen /
// D3D12 Vulkan layer) is frequently non-conformant and presents a *black*
// window — the app appears not to open (only a taskbar entry, with a
// "[WARN:COPY MODE]" title). Fall back to Mesa's software rasterizer
// (llvmpipe) when running under WSL, unless the user has already chosen a GL
// mode via the environment. Native Linux installs are untouched. This must run
// before any GL/EGL context is created (before the GTK app starts).
static void wcx_force_software_gl_on_wsl() {
  if (g_getenv("LIBGL_ALWAYS_SOFTWARE") != nullptr) {
    return;  // respect an explicit user choice
  }
  g_autofree gchar* osrelease = nullptr;
  if (!g_file_get_contents("/proc/sys/kernel/osrelease", &osrelease, nullptr,
                           nullptr)) {
    return;
  }
  g_autofree gchar* lower = g_ascii_strdown(osrelease, -1);
  if (strstr(lower, "microsoft") != nullptr || strstr(lower, "wsl") != nullptr) {
    g_setenv("LIBGL_ALWAYS_SOFTWARE", "1", TRUE);
    if (g_getenv("GALLIUM_DRIVER") == nullptr) {
      g_setenv("GALLIUM_DRIVER", "llvmpipe", TRUE);
    }
  }
}

int main(int argc, char** argv) {
  wcx_force_software_gl_on_wsl();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
