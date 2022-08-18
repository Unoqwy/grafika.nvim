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

As you just saw, grafika works by drawing components. The component builder is a powerful and convenient way easily create complex UIs with highlight groups, etc.

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

### Popups

Grafika can ease your life if you ever need to make popups.

```lua
local gk = require("grafika")

local account = {
    locked = false,
    online_viewers = 1,
    balance = 1381205.820,
}

local function draw_callback()
    local builder = gk.ComponentBuilder()
    builder:line("Account Information", "Header")
    if not locked then
        builder:line("Online Viewers", "InfoLabel")
        builder:append(online_viewers, "InfoValue") -- number will be converted using tostring() automatically
        builder:line("Balance", "InfoLabel")
        builder:append(vim.fn.printf("%'.2f", account.balance), "InfoValue")
    else
        builder:line("This account was locked by the owner!", "AcountLocked")
    end
    return builder:build()
end

local popup = gk.open_popup(draw_callback, {
    ft = "myfiletype",
    position = "center-editor", -- center in the middle of the editor. Available: center-win, last-cursor
    focusable = false,
    -- more options are available, check 'lua/grafika/window.lua'
})
-- the popup is now displayed in the center of the editor, its size fitting the content

-- for the following example, we assume `events.on()` allows you to subscribe to external changes
events.on("account_lock_update", function(new_status)
    account.locked = new_status
    popup:update() -- this re-renders the popup
    -- a line of the popup has been removed because the component is no longer the same size
end)
```

## Extra Utils

grafika.nvim contains some utilities that can prove to be useful.

### Component from border chars

Using the same `borderchars` format as many other plugins, you can create a component.

```lua
local borderchars = { "─", "│", "─", "│", "┌", "┐", "┘", "└" } -- this could be a simple string, or have only two elements
local width = 20
local height = 5

-- create the component
local border = require("grafika/util").create_comp_border(borderchars, width, height, {
    -- these options are optional, you can just give borderchars, width, height if you don't need highlight
    hl_border = "BorderHighlight",
    hl_fill = "FillHighlight",
    fill = " ", -- character to fill the "middle" of the box being created from border chars
})
```

### Search for highlight regions

You can search a buffer for highlight regions with a group name.

```lua
-- you can check out the following method, in-code docs are enough to cover it
require("grafika/util").find_hl_groups(buf, ns_id, hl_group)

-- it's also available from a canvas, you don't need to pass a buf nor ns_id for it
canvas:find_hl_groups(hl_group)

-- it's available from a popup as well
popup:find_hl_groups(hl_group)
```

### Popup Auto Child

Using the above util (search for highlight regions), you can create a child popup from an existing one by searching for a region via highlight group.

```lua
local gk = require("grafika")

local function draw_callback()
    local builder = gk.ComponentBuilder()
    builder:line("Write your name below:", "NameInputHeader")
    builder:line(">> ", "NameInputPrefix")
    builder:append(string.rep(" ", 10), "NameInputPrompt")
    return builder:build()
end

local popup = gk.open_popup(draw_callback, {})

local auto_child, rect = popup:auto_child("NameInputPrompt")
-- 'auto_child' is a window options table containing all the required positionning settings

local winopts = {
    style = "minimal",
}
winopts = vim.tbl_extend("error", winopts, auto_child)
local win = vim.api.nvim_open_win(buf, true, winopts)

-- 'win' is a window of 10x1 (10 width, 1 height) exactly where the input was wanted
-- you can think of "NameInputPrompt" as a layout marker telling the popup where to fork
```

### Creating a prompt

Creating prompt is a utility that does not use grafika features but can be quite convenient when paired with `auto_child`.

```lua
local winopts = ... -- your window options, this could be 'auto_child'

-- this will create a floating window with a prompt buffer (':h prompt-buffer')
local prompt = require("grafika/ext").create_prompt(winopts, {
    ft = "myfiletype",
    prefix = "> ",
    on_close = function()
        -- do something when prompt is closed
    end,
})

-- later..
prompt:close() -- deletes the buffer and close the window
```

