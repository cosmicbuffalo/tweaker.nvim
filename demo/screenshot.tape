# Capture a still of the baked-file live legend for the README.
#
# Replays the demo's edits (pink accent + green comments), bakes `sunset`, opens
# the baked file (which renders as a live legend), and screenshots it. Run via
# demo/record.sh (which isolates config/data and provides inkline in .deps/).

Output demo/.deps/_screenshot-throwaway.gif

Require nvim

Set Shell "bash"
Set FontSize 18
Set Width 1400
Set Height 800
Set Padding 14
Set Theme "Dracula"
Set TypingSpeed 40ms

# --- Isolated env; open the tweaker repo in inkline-original ----------------
Type "export XDG_DATA_HOME=/tmp/twd/data XDG_STATE_HOME=/tmp/twd/state XDG_CONFIG_HOME=/tmp/twd/config" Enter
Type "export TWEAKER_DIR=$PWD INKLINE_DIR=$PWD/demo/.deps/inkline.nvim" Enter
Type "clear" Enter
Type "nvim -u demo/init.lua -i NONE lua/tweaker/init.lua" Enter
Sleep 2s

# Recolor a name (fg + bg) and every comment, exactly like the demo.
Type "/defaults" Enter
Type ":Tweaker" Enter
Sleep 800ms
Type "R#ff5faf"
Escape
Tab
Type "R#243b4d"
Escape
Sleep 400ms
Type "q"
Type ":Tweaker Comment" Enter
Sleep 800ms
Type "R#7fd88f"
Escape
Sleep 400ms
Type "q"

# Bake and open the baked file: it renders as a live legend.
Type ":TweakerBake sunset" Enter
Sleep 1s
Type ":e /tmp/twd/config/nvim/colors/sunset.lua" Enter
Sleep 1.5s
# Scroll to the palette block (swatches + group names in their own colors) and
# clear the message line before the shot.
Ctrl+D
Type ":echo ''" Enter
Sleep 800ms

Screenshot demo/baked-preview.png
