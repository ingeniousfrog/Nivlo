on run argv
  set volumeName to item 1 of argv
  set appName to item 2 of argv

  tell application "Finder"
    tell disk volumeName
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {200, 120, 860, 520}
      set viewOptions to the icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 128
      set background picture of viewOptions to file ".background:background.png"
      set position of item (appName & ".app") of container window to {180, 170}
      set position of item "Applications" of container window to {480, 170}
      close
      open
      update without registering applications
      delay 2
    end tell
  end tell
end run
