# lite-xl-easingpreview
Easing previewer for Lite XL. Currently only works with Lua.

## How to use

Run `easing-preview:show` (this one mapped to `ctrl+shift+e` by default) over the signature of a Penner easing function:
```lua
function linear(t, b, c, d) -- execute here
  return c * t / d + b
end
```
Click anywhere else (or run `easing-preview:hide` (mapped to `ctrl+alt+e`)) to hide the prompt.

## Config

```lua
local easing_previewer = config.plugins.easing_previewer
easing_previewer.displayWidth = 150
easing_previewer.displayHeight = 100

easing_previewer.arrowWidth = 0.2 -- normalized
easing_previewer.arrowHeight = 0.2 -- normalized (based on height of the display (should probably change that))

easing_previewer.pointSize = 5
easing_previewer.steps = 100 -- resolution of the graph
easing_previewer.padding = 10
```

There's also a config spec, in case you use [settings](https://github.com/lite-xl/lite-xl-plugins/blob/master/plugins/settings.lua?raw=1).
