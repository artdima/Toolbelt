# dmgbuild settings for the release DMG; make-dmg.sh passes the paths with -D.
app = defines["app"]

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = ["Toolbelt.app"]
icon = app + "/Contents/Resources/AppIcon.icns"
background = defines["background"]

# The bounds take in the 32 pt title bar, leaving 640 x 366 for the background.
window_rect = ((200, 160), (640, 398))
icon_size = 128
# The arrow in the background points from the first slot to the second.
icon_locations = {"Toolbelt.app": (180, 216), "Applications": (466, 216)}
