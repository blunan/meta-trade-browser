#!/usr/bin/python3 -I
# notice.py: the window on the desktop while MetaTrader can't start yet, or
# when Python couldn't be installed or updated. run-terminal.sh opens it, and
# sends it one line per update, its fields separated by tabs:
#   install <step>             MetaTrader is installing, and is at this step
#   retry <seconds> <reason>   this attempt failed; the next starts in <seconds>
#   start                      MetaTrader is starting
#   warning <reason>           Python couldn't be installed or updated, but
#                              MetaTrader starts: this one stays above
#                              MetaTrader's window until it's closed
#
# Openbox manages it, so it has the same title bar as MetaTrader's windows, and
# it's styled like MetaTrader's dialogs under Wine: the colours are theirs.
# Openbox maximizes every window, but a fixed size keeps this one small, as it
# does those dialogs. It stays centred when the screen changes size, as it does
# when a browser connects. Closing it hides it until the next update. It exits
# once its parent has gone, so it never outlives run-terminal.sh, or MetaTrader
# after the hand-off.
import math
import os

# The desktop has no accessibility bus, and GTK would warn that it's missing.
os.environ["NO_AT_BRIDGE"] = "1"

import gi  # noqa: E402

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
from gi.repository import GLib  # noqa: E402

# Before GTK starts: its window class, which tests look for, comes from this.
GLib.set_prgname("mt-notice")

from gi.repository import Gdk, GdkPixbuf, Gtk  # noqa: E402

CSS = b"""
window {
  background-color: #f5f5f5;
}
label {
  color: #000000;
  font-family: "Noto Sans", sans-serif;
  font-size: 9pt;
}
label.mt-heading {
  color: #003399;
  font-size: 12pt;
  font-weight: normal;
}
progressbar trough {
  min-height: 8px;
  border: 1px solid #aeaeae;
  border-radius: 0;
  background-color: #ffffff;
  background-image: none;
  box-shadow: none;
}
progressbar progress {
  min-height: 8px;
  margin: 0;
  border: none;
  border-radius: 0;
  background-color: #3096fa;
  background-image: none;
  box-shadow: none;
}
"""

# Wide enough for each step, and most reasons, on one line.
TEXT_WIDTH = 420


def error_icon(size=32):
    """Wine's error icon, drawn here: the base has no SVG loader for the theme's
    icons, and no cairo for Python. A red circle, darker below and at its rim,
    with a white cross, each pixel sampled 4 x 4 times for smooth edges."""
    top, bottom, rim = (0xF6, 0x47, 0x47), (0xD0, 0x0B, 0x0B), (0xA8, 0x08, 0x08)
    radius = size / 2 - 1.5
    reach, stroke = size * 0.23, size * 0.13
    samples = 4
    pixels = bytearray()
    for py in range(size):
        for px in range(size):
            colours = []
            for sy in range(samples):
                for sx in range(samples):
                    x = px + (sx + 0.5) / samples - size / 2
                    y = py + (sy + 0.5) / samples - size / 2
                    distance = math.hypot(x, y)
                    if distance > radius:
                        continue
                    if max(abs(x), abs(y)) <= reach and abs(abs(x) - abs(y)) <= stroke / math.sqrt(2):
                        colours.append((0xFF, 0xFF, 0xFF))
                    elif distance > radius - 1:
                        colours.append(rim)
                    else:
                        shade = (y + radius) / (2 * radius)
                        colours.append(tuple(a + (b - a) * shade for a, b in zip(top, bottom)))
            if colours:
                pixels += bytes(round(sum(c[i] for c in colours) / len(colours)) for i in range(3))
            else:
                pixels += b"\0\0\0"
            pixels.append(round(255 * len(colours) / samples**2))
    return GdkPixbuf.Pixbuf.new_from_bytes(
        GLib.Bytes.new(bytes(pixels)), GdkPixbuf.Colorspace.RGB, True, 8, size, size, size * 4
    )


class Notice(Gtk.Window):
    def __init__(self):
        super().__init__(title="MetaTrader")
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        self.set_resizable(False)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.connect("delete-event", lambda *_: self.hide() or True)
        # GTK centres the window without its title bar, and a new size keeps
        # its top-left corner, so it's centred again whenever its frame or the
        # screen changes size.
        self.centred = None
        self.connect("configure-event", self.on_configure)
        Gdk.Screen.get_default().connect("size-changed", lambda *_: self.centre())

        self.icon = Gtk.Image.new_from_pixbuf(error_icon())
        self.icon.set_valign(Gtk.Align.START)
        self.heading = self.text("mt-heading")
        self.detail = self.text()
        self.bar = Gtk.ProgressBar()
        self.bar.set_pulse_step(0.04)
        self.note = self.text()
        self.note.set_margin_top(4)

        column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        column.set_size_request(TEXT_WIDTH, -1)
        for widget in (self.heading, self.detail, self.bar, self.note):
            column.pack_start(widget, False, False, 0)
        row = Gtk.Box(spacing=12)
        row.set_border_width(18)
        row.pack_start(self.icon, False, False, 0)
        row.pack_start(column, True, True, 0)
        self.add(row)
        for widget in (row, column, self.heading):
            widget.show()

        self.deadline = None
        self.parent = os.getppid()
        self.input = b""
        GLib.io_add_watch(0, GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN | GLib.IOCondition.HUP, self.read)
        GLib.timeout_add(100, self.pulse)
        GLib.timeout_add_seconds(1, self.tick)

    @staticmethod
    def text(style=None):
        label = Gtk.Label()
        label.set_xalign(0)
        label.set_line_wrap(True)
        # Never wider than the column, which then decides where lines break.
        label.set_max_width_chars(1)
        if style:
            label.get_style_context().add_class(style)
        return label

    def read(self, fd, _condition):
        data = os.read(fd, 4096)
        if not data:
            # run-terminal.sh closed its end: the last update stays.
            return False
        self.input += data
        while b"\n" in self.input:
            line, self.input = self.input.split(b"\n", 1)
            self.update(line.decode("utf-8", "replace").split("\t"))
        return True

    def update(self, fields):
        kind, args = fields[0], fields[1:]
        if kind == "install" and len(args) == 1:
            self.deadline = None
            self.show_state(
                "Installing MetaTrader",
                detail=args[0],
                bar=True,
                note="This takes a couple of minutes. MetaTrader opens here when it's done.",
            )
        elif kind == "retry" and len(args) == 2 and args[0].isdigit():
            self.deadline = GLib.get_monotonic_time() + int(args[0]) * 1_000_000
            self.show_state("MetaTrader can't start yet", icon=True, detail=args[1], note=self.countdown())
        elif kind == "start" and not args:
            self.deadline = None
            self.show_state("Starting MetaTrader", bar=True)
        elif kind == "warning" and len(args) == 1:
            self.deadline = None
            self.show_state(
                "Python couldn't be installed or updated",
                icon=True,
                detail=args[0],
                note="MetaTrader runs all the same, and the next start tries again. "
                "The container's log (docker logs) has the details.",
                above=True,
            )

    def show_state(self, heading, icon=False, detail=None, bar=False, note=None, above=False):
        # Above MetaTrader's maximized window, or it would hide this one.
        self.set_keep_above(above)
        self.heading.set_text(heading)
        self.icon.set_visible(icon)
        self.bar.set_visible(bar)
        for label, text in ((self.detail, detail), (self.note, note)):
            label.set_text(text or "")
            label.set_visible(bool(text))
        if not self.get_visible():
            self.show()
            self.centre()

    def countdown(self):
        left = math.ceil((self.deadline - GLib.get_monotonic_time()) / 1_000_000)
        if left <= 0:
            when = "Retrying now."
        elif left == 1:
            when = "Retrying in 1 second."
        else:
            when = f"Retrying in {left} seconds."
        return f"{when} The container's log (docker logs) has the details."

    def on_configure(self, *_):
        frame = self.get_window().get_frame_extents()
        if (frame.width, frame.height) != self.centred:
            self.centre()
        return False

    def centre(self):
        if not self.get_visible():
            return
        frame = self.get_window().get_frame_extents()
        self.centred = (frame.width, frame.height)
        display = Gdk.Display.get_default()
        area = (display.get_primary_monitor() or display.get_monitor(0)).get_geometry()
        # Where the frame's top-left corner goes, title bar included.
        self.move(area.x + (area.width - frame.width) // 2, area.y + (area.height - frame.height) // 2)

    def pulse(self):
        if self.bar.get_visible():
            self.bar.pulse()
        return True

    def tick(self):
        if os.getppid() != self.parent:
            Gtk.main_quit()
            return False
        if self.deadline is not None:
            self.note.set_text(self.countdown())
        return True


def main():
    css = Gtk.CssProvider()
    css.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )
    Notice()
    Gtk.main()


main()
