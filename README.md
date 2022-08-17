# 🪶 grafika.nvim - Simplified interface drawing

This is a library to draw user interfaces in neovim.

## Get Started

### Basic

Grafika can replace most of your window/buffer creation logic.

```lua
local gk = require("grafika")

-- this will create a buffer with the filetype 'myfiletype' and return a canvas
local canvas = gk.create_canvas("myfiletype")

-- Note: this is optional. Grafika can draw on your buffer, you can take `canvas.buf` and show it in whatever window you want
gk.bind_canvas(canvas, 0, {}) -- 0 means current window

-- you can now draw on the canvas!
canvas:draw_component(gk.Component({"This is a test!"}))
```

### Using an existing buffer

If you want to take care of creating your own buffer, you can too!

```lua
local gk = require("grafika")

local buf = 123 -- your buffer
local canvas = gk.Canvas(buf)

-- that's it! You can do whatever you want, it's a fully functional canvas
```

### Component Builder

As you just saw, grafika works by drawing components. The component builder is a powerful and covenient way easily create complex UIs with highlight groups, etc.

```lua
local gk = require("grafika")

local builder = gk.ComponentBuilder()
builder:line("Oops, something went wrong!") -- add a new line with the given text
builder:line("Error: ", "Error") -- highlight the text with the "Error" group
builder:append("Something bad happened", "ErrorDescription") -- append some text with another highlight group on the current line
builder:line("Questions?")
builder:append_right("Call us!") -- append text at the right of the component

-- Note: text appended at the right will be calculated when you build the component.
-- It will try to fit within the current width of your component (i.e. width of the line with max length), but will grow it if some space is needed to fit everything

local component = builder:build()
-- do whatever you want with the component
```

### Using boundaries

Grafika can draw on a limited part of a buffer, it will prevent drawing outside of these boundaries, and will offset the components for you.

```lua
local gk = require("grafika")

local canvas = ... -- your canvas

local header_bounds = gk.Bounds(0, 0, -1, 2) -- height of 2!
local content_bounds = gk.Bounds(1, 5)

local header_comp = gk.Component({"Title!", "Subtitle", "This line won't display"})
local content_comp = gk.Component({"Some content"})

-- header_comp will be drawn in the first 2 lines of the buffer, the 3rd line will be discarded
canvas:draw_component(header_comp, header_bounds)
-- content_comp will be drawn starting at the 5th line and 2nd column. This creates some padding
canvas:draw_component(content_comp, content_bounds)
```
