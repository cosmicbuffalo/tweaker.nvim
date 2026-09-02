# tweaker.nvim feature-tour demo tape (https://github.com/charmbracelet/vhs)
#
# Render with:  demo/record.sh   (isolates config/data; never touches yours).
# Outputs GIF + MP4 into demo/.
#
# The tour opens the tweaker.nvim source in the inkline "original" colorscheme,
# then live-edits highlight groups under the cursor and bakes the result into a
# standalone colorscheme (whose file renders as a live legend).

Output demo/tweaker-demo.gif
Output demo/tweaker-demo.mp4

Require nvim

Set Shell "bash"
Set FontSize 18
Set Width 1400
Set Height 800
Set Padding 14
Set Theme "Dracula"
Set TypingSpeed 90ms

# --- Isolated env; open the tweaker repo in inkline-original ----------------
Hide
Type "export XDG_DATA_HOME=/tmp/twd/data XDG_STATE_HOME=/tmp/twd/state XDG_CONFIG_HOME=/tmp/twd/config" Enter
Type "export TWEAKER_DIR=$PWD INKLINE_DIR=$PWD/demo/.deps/inkline.nvim" Enter
Type "clear" Enter
Type "nvim -u demo/init.lua -i NONE lua/tweaker/init.lua" Enter
Sleep 2.5s
Show

# Admire the starting colorscheme (inkline "original") for a beat.
Sleep 1.8s

# --- Inspect what's under the cursor ----------------------------------------
# Land on an identifier and open Tweaker on the groups painting it.
Type "/defaults" Enter
Sleep 900ms
Type ":Tweaker" Enter
Sleep 2.5s

# --- Live-edit the foreground: the code recolors as you type ----------------
Type "R#ff5faf"
Sleep 900ms
Escape
Sleep 1.6s

# --- Give it a background too ------------------------------------------------
Tab
Sleep 600ms
Type "R#243b4d"
Sleep 800ms
Escape
Sleep 1.8s
Type "q"
Sleep 1.2s

# --- Name a group directly: recolor every comment at once ------------------
Type ":Tweaker Comment" Enter
Sleep 2.5s
Type "R#7fd88f"
Sleep 1s
Escape
Sleep 2s
Type "q"
Sleep 1.2s

# --- Bake the tweaks into a standalone colorscheme --------------------------
Type ":TweakerBake sunset" Enter
Sleep 4s

# --- Open the baked file: it renders as a live legend -----------------------
Type ":e /tmp/twd/config/nvim/colors/sunset.lua" Enter
Sleep 3s
Ctrl+D
Sleep 3s
