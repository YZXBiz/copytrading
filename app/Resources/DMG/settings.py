# dmgbuild settings for the CopyTrading disk image; `app/scripts/build_dmg.py` supplies `app`
# and `background` (dmgbuild runs this file without `__file__`).
import os

application = defines["app"]  # noqa: F821 - dmgbuild injects `defines`
format = "UDZO"
compression_level = 9
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(application, "Contents/Resources/AppIcon.icns")
background = defines["background"]  # noqa: F821
# 420 points of content under a 32-point title bar.
window_rect = ((200, 160), (660, 452))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {"CopyTrading.app": (165, 196), "Applications": (495, 196)}
hide_extension = ["CopyTrading.app"]
