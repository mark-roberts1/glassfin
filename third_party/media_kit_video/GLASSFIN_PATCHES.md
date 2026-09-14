# Glassfin's changes to media_kit_video 2.0.1

The package is otherwise byte-for-byte the pub.dev release; `git log -- third_party/media_kit_video`
shows the unmodified import as its own commit, so `git diff <that commit> -- third_party/` is the
whole patch. Every changed line is marked `Glassfin patch` in the source.

Only the Linux plugin is touched.

## GPU rendering without a current EGL context — `linux/video_output.cc`, `linux/texture_gl.cc`

Upstream finds Flutter's EGL display by asking what is current on the GTK main thread. Under
Wayland that is usually GTK's own EGL context, by coincidence; under X11 GTK's contexts are GLX,
nothing EGL is ever current, and the plugin logs `EGL display or context is invalid.` followed by
`S/W rendering.` Every frame is then converted to RGB on the CPU and uploaded again.

X11 is not an edge case for Glassfin: Steam's Game Mode (gamescope) sets no `WAYLAND_DISPLAY`, so
a Flatpak launched from it gets X11. On the BC-250 this was the whole of the stutter.

Flutter's engine builds its display from GDK's native display on both backends
(`fl_opengl_manager.cc`), and `eglGetPlatformDisplayEXT` with the same arguments returns the same
`EGLDisplay`. So when nothing is current, the plugin now gets the display that way and picks a
config with the engine's own attributes. The existing isolated-context and EGLImage path is
unchanged from there. The context save/restore in both files releases mpv's context instead of
"restoring" a context that was never there.

`texture_gl_dispose` no longer deletes Flutter's texture name when no EGL context is current: under
X11 that call would reach GTK's GLX context. Glassfin keeps one `Player` for the session, so this
only runs at exit.

## Don't block Flutter's raster thread — `linux/texture_gl.cc`

`MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME = 0`, taken verbatim from upstream `main`, where it is the
only difference from 2.0.1 in the Linux sources. Without it `mpv_render_context_render` waits until
the frame is due, inside Flutter's texture callback.

## Updating

Replace the directory with the new release in one commit, then re-apply these changes in the next.
If upstream has fixed the display lookup, drop that patch rather than merging it.
