# dmgbuild settings for the release DMG; make-dmg.sh passes the app path with -D.
app = defines["app"]

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = ["Toolbelt.app"]
icon = app + "/Contents/Resources/AppIcon.icns"
background = "builtin-arrow"

window_rect = ((100, 100), (640, 280))
icon_size = 128
icon_locations = {"Toolbelt.app": (140, 120), "Applications": (500, 120)}
