"""Finder layout for the Dakt installer; no Finder automation is required."""
import os

app = os.path.abspath(defines["app"])
root = os.path.abspath(defines["root"])
format = "UDZO"
filesystem = "HFS+"
files = [
    app,
    (os.path.join(root, "ПРОЧИТАЙ МЕНЯ.txt"), "Начало работы.txt"),
    (os.path.join(root, "LICENSE"), "Лицензия.txt"),
]
symlinks = {"Applications": "/Applications"}
background = os.path.abspath(defines["background"])
badge_icon = os.path.join(root, "Resources", "AppIcon.png")
window_rect = ((180, 120), (720, 540))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
icon_size = 96
text_size = 13
icon_locations = {
    "Dakt.app": (190, 220),
    "Applications": (530, 220),
    "Начало работы.txt": (245, 425),
    "Лицензия.txt": (475, 425),
}
