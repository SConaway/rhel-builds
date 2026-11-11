#!/usr/bin/env bash
# Smoke test for the libnotify package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

dnf install -y -q glib2 gdk-pixbuf2 dbus-daemon

ROOT="${1}"
export PATH="${ROOT}/bin:${PATH}"

echo "--- notify-send --version ---"
notify-send --version

echo "--- ldd (must have no missing libs) ---"
for b in "${ROOT}"/bin/* "${ROOT}"/lib/*.so*; do
    [[ -f "${b}" ]] || continue
    head -c4 "${b}" | grep -q ELF || continue
    if ldd "${b}" | grep "not found"; then
        echo "ERROR: unresolved libraries in ${b}" >&2
        exit 1
    fi
done

echo "--- notify-send against a fake notification server ---"
dnf install -y -q python3-gobject-base platform-python
cat > /tmp/server.py <<'PY'
import sys
from gi.repository import Gio, GLib

XML = """<node><interface name="org.freedesktop.Notifications">
<method name="Notify">
 <arg type="s" direction="in"/><arg type="u" direction="in"/><arg type="s" direction="in"/>
 <arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/>
 <arg type="a{sv}" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="out"/>
</method>
<method name="GetServerInformation">
 <arg type="s" direction="out"/><arg type="s" direction="out"/><arg type="s" direction="out"/><arg type="s" direction="out"/>
</method>
<method name="GetCapabilities"><arg type="as" direction="out"/></method>
<method name="CloseNotification"><arg type="u" direction="in"/></method>
</interface></node>"""
loop = GLib.MainLoop()

def handle(conn, sender, path, iface, method, params, inv):
    if method == "Notify":
        a = params.unpack()
        open("/tmp/received", "w").write("%s|%s" % (a[3], a[4]))
        inv.return_value(GLib.Variant("(u)", (1,)))
        GLib.timeout_add(200, loop.quit)
    elif method == "GetServerInformation":
        inv.return_value(GLib.Variant("(ssss)", ("fake", "test", "1", "1.2")))
    elif method == "GetCapabilities":
        inv.return_value(GLib.Variant("(as)", ([],)))
    else:
        inv.return_value(None)

def acquired(conn, name):
    conn.register_object("/org/freedesktop/Notifications",
        Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], handle, None, None)
    print("fake server ready", flush=True)

Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.Notifications",
                 Gio.BusNameOwnerFlags.NONE, acquired, None, None)
GLib.timeout_add_seconds(15, loop.quit)
loop.run()
PY
cat > /tmp/inner.sh <<'INNER'
set -eu
/usr/libexec/platform-python /tmp/server.py &
SRV=$!
sleep 2
notify-send "hello" "from libnotify"
wait "${SRV}" || true
cat /tmp/received; echo
grep -q '^hello|from libnotify$' /tmp/received
INNER
dbus-run-session -- bash /tmp/inner.sh
echo "libnotify OK"
