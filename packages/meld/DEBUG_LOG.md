# Meld AppImage for RHEL9 — Debug Log

## Goal
Package Meld 3.22.3 as an AppImage (wrapped in a tarball) that passes `meld --version` in a bare AlmaLinux 9 container.

---

## Issues found and fixed

**1. `appimagetool` missing `file` command**
Added `file` to dnf install list.

**2. `appimagetool` missing `appstreamcli`**
Added `appstream` to dnf install list.

**3. Desktop file not found by appimagetool**
`find -name "*meld*"` was case-sensitive; meld 3.22.3 installs `org.gnome.Meld.desktop` (capital M). Fixed with `-iname`.

**4. `gi.repository` not importable**
The `gi` Python package is split across two directories on AlmaLinux 9:
- `/usr/lib64/python3.9/site-packages/gi/` — `__init__.py`, compiled `.so` extensions
- `/usr/lib/python3.9/site-packages/gi/` — `gi/repository/` (the actual import hook) and `gi/overrides/`

We were only copying the lib64 half. Fixed by merging both into the bundle.

**5. GI typelibs missing (`xlib-2.0.typelib` etc.)**
Rather than enumerate them individually, switched to copying all `*.typelib` files from the system.

**6. Transitive shared library deps missing (`libfribidi`, etc.)**
`libpango` needs `libfribidi`, which wasn't bundled. Added an iterative `ldd`-based dep resolver loop. Also added `libfribidi`, `libharfbuzz`, `libfontconfig`, and X11 libs to the explicit copy list.

**7. `grep "=> /"` returning exit code 1 killing the build**
With `set -euo pipefail`, when `grep` finds no `=> /` lines in `ldd` output (e.g. for a statically-linked `.so`), it returns exit code 1. This propagated through the pipeline and silently killed the build, leaving the old tarball in place. Fixed with `|| true` after the inner `grep` pipeline.

**8. `python3: not found` in test container**
The AppImage called `python3` from PATH, but the bare test container has no Python installed. Fixed by bundling the Python 3.6 interpreter and its stdlib from the build container, and using the bundled interpreter in AppRun.

**9. `No module named 'encodings'` — PYTHONHOME in wrong path**
On AlmaLinux 8, Python's stdlib lives in `/usr/lib64/python3.6/`, not `/usr/lib/python3.6/`. PYTHONHOME substitution maps the prefix (`/usr`) to `${HERE}/usr`, so the bundled stdlib must mirror the same `lib64` layout. Fixed by copying the stdlib to `${APPDIR}/usr/lib64/python3.6/` instead of `lib/`.

**10. `GDK_BACKEND=offscreen` is not a valid GTK3 display backend**
`Gtk.init_check()` returns False with this backend — it's only available in GTK4. The test was using it to avoid a display. Fixed by installing `xorg-x11-server-Xvfb` in `test.sh` and starting `Xvfb :99`.

**11. `libgtksourceview-3.0.so.1: cannot open shared object file`**
Meld 3.20.4 uses `gi.require_version('GtkSource', '3.0')` — version 3, not 4. The build was installing `gtksourceview4` and bundling `libgtksourceview-4.so.0`. Switched to `gtksourceview3` / `libgtksourceview-3.0`.

**12. `DATADIR = "/usr/share/meld"` hardcoded in `meld/conf.py`**
The RPM-installed `meld/conf.py` has the data dir baked in as an absolute path. The bundled copy would always look at the system path. Fixed by sed-patching the DATADIR line after copying the package into the AppDir, and deleting all `__pycache__` dirs so Python recompiles from the patched source.

**13. `No GSettings schemas are installed on the system`**
GSettings aborts (SIGTRAP) if no compiled schema database is found anywhere on the system. Fixed by:
- Installing `gsettings-desktop-schemas` in the build container
- Copying all `/usr/share/glib-2.0/schemas/*.xml` files into the AppDir
- Running `glib-compile-schemas` on that dir at build time
- AppRun already sets `XDG_DATA_DIRS` to include `${HERE}/usr/share`, which is where GSettings finds the compiled schemas

**14. `No module named 'cairo'`**
meld imports the `cairo` Python module (pycairo) directly. It's not in the stdlib and was removed from site-packages when we stripped them from the stdlib copy. Fixed by explicitly bundling the `cairo` package alongside `gi` and `meld` in `${APPDIR}/usr/lib/cairo/`.

**15. `undefined symbol: _dl_make_stack_executable, version GLIBC_PRIVATE` on rhel9**
The ldd transitive dep resolver copied `libpthread.so.0`, `libc.so.6`, `libm.so.6`, `libdl.so.2`, `libresolv.so.2`, and `librt.so.1` from the AlmaLinux 8 build container into the bundle. These are glibc internals that make cross-version private symbol calls (`GLIBC_PRIVATE`), which broke on AlmaLinux 9 (glibc 2.34). Fixed by adding an exclusion list in the ldd loop: any library matching `libc`, `libpthread`, `libdl`, `libm`, `libresolv`, `librt`, or `ld-linux` is skipped — these must always come from the host system.

**16. `undefined symbol: g_task_set_name` in system gvfs modules**
On RHEL9/Rocky 9, GIO loads gio modules from `/usr/lib64/gio/modules/`. The system's gvfs modules (libgvfsdbus.so etc.) were compiled against RHEL9's newer GLib and reference `g_task_set_name`, which doesn't exist in our bundled AlmaLinux 8 GLib. Fixed by:
1. Copying the AlmaLinux 8 build container's own gio modules into `${APPDIR}/usr/lib64/gio/modules/`
2. Setting `GIO_MODULE_DIR="${HERE}/usr/lib64/gio/modules"` in AppRun so GIO uses only the bundled (ABI-compatible) modules

**18. `Icon 'meld-change-apply-right' not present in theme Adwaita` when opening a diff**
meld installs its action icons (`meld-change-apply-right`, `meld-change-delete`, etc.) into the hicolor icon theme at `/usr/share/icons/hicolor/`. The build was not bundling that tree, so at runtime GTK searched `$XDG_DATA_DIRS/icons/` (which points into the AppDir) and found nothing. Fixed by copying `/usr/share/icons/hicolor` into `${APPDIR}/usr/share/icons/` and running `gtk-update-icon-cache` on it at build time.

**17. `Couldn't find colour scheme details for meld:insert-background; this is a bad install`**
meld's custom GtkSourceView colour scheme (`meld.xml`) inherits from the `classic` base scheme. The base schemes ship with GtkSourceView 3 in `/usr/share/gtksourceview-3.0/styles/`. We bundled `/usr/share/meld/` but not `/usr/share/gtksourceview-3.0/`. On RHEL9, there is no GtkSourceView 3 system installation (it uses v4), so the base schemes were missing. Fixed by adding `cp -r /usr/share/gtksourceview-3.0 "${APPDIR}/usr/share/"` to the build. `XDG_DATA_DIRS` already includes `${HERE}/usr/share`, so GtkSourceView finds them automatically.


---

## Current state

**PASSING on both rhel8 and rhel9, and verified functional on a real Rocky 9 system.** `./test.sh meld rhel8` and `./test.sh meld rhel9` both exit 0 and print `meld 3.20.4`. The rhel8 artifact runs unchanged on AlmaLinux 9 via glibc forwards-compatibility.

Fix #18 (icon theme) was applied 2026-06-23 — rebuild and retest needed.

### Remaining known noise (not failures)
- `GLib-GIO-CRITICAL: g_dbus_proxy_new_sync` — no D-Bus session bus in bare container; harmless for `--version`
- `Fontconfig error: Cannot load default config file` — no fontconfig cache in bare container; harmless for `--version`
- `Fontconfig warning: … unknown element "reset-dirs"` — bundled AlmaLinux 8 libfontconfig doesn't understand a newer conf.avail element on the host; harmless, meld renders fonts fine
- `Xlib is not thread-safe` (rhel9 only) — Xvfb warning; harmless

### Next step
Wire up the GitHub Actions workflow (copy an existing workflow, substitute `meld` and version tag prefix).
