local err = require("grafika/error")
local types = require("grafika/types")

local M = {}

---Creates a new empty buffer
---@param ft? string Filetype to use. Defaults to 'grafika'
---@return integer Buffer ID
function M.create_buf(ft)
    ft = ft or "grafika"

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, "filetype", ft)
    vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(buf, "swapfile", false)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)

    return buf
end

---Creates a an empty buffer and a canvas.
---If you want to use an already existing buffer, just use the Canvas constructor
---@param ft? string Filetype to use. Defaults to 'grafika'
---@return Canvas Empty canvas
function M.create_canvas(ft)
    local buf = M.new_buf(ft)
    return types.Canvas(buf)
end

---@class WindowObserver
---@field restore fun(WindowObserver) Restore options

---Utility to keep track of option changes in a window and apply them back once we're done
---@param win integer Window handle
---@return table
local function WindowObserver(win)
    local o, opts = {}, {}

    function o:restore()
        for key, val in pairs(opts) do
            vim.api.nvim_win_set_option(win, key, val)
        end
        opts = {}
    end

    setmetatable(o, {
        __newindex = function(_, key, val)
            local current = vim.api.nvim_win_get_option(win, key)
            opts[key] = current
            vim.api.nvim_win_set_option(win, key, val)
        end,
    })

    return o
end

---@class OpenCanvasOptions
---@field win_opts? table Custom window options. Defaults to grafika.default_win_opts
---@field on_exit? fun() Callback called when the canvas is unloaded

---Binds (aka. open) a canvas to a window
---@param canvas Canvas - to open
---@param win? integer Window handle. Defaults to current window
---@param opts? OpenCanvasOptions Extra options
function M.bind_canvas(canvas, win, opts)
    err.expect_param("bind_canvas", "canvas", canvas)

    if canvas.win ~= nil then
        vim.api.nvim_err_writeln("grafika.nvim: Trying to open a canvas in a second window")
        return
    end

    win = win or vim.api.nvim_get_current_win()
    opts = opts or {}

    vim.api.nvim_win_set_buf(win, canvas.buf)
    canvas.win = win

    local observer = WindowObserver(win)
    for key, val in pairs(opts.win_opts or require("grafika").default_win_opts) do
        observer[key] = val
    end

    vim.api.nvim_create_autocmd({ "BufUnload" }, {
        buffer = canvas.buf,
        once = true,
        callback = function()
            observer:restore()
            if opts.on_exit ~= nil then
                opts.on_exit()
            end
        end,
    })
end

---@class FloatPosition
---@field relative "editor"|"win"|"cursor" Window relative setting
---@field anchor? "NW"|"NE"|"SW"|"SE" Window anchor setting
---@field win? integer Window handle for relative="win"
---@field row integer Window row setting
---@field col integer Window row setting

---@class Popup
---@field buf integer Buffer ID
---@field win integer Window handle
---@field opts OpenPopupOptions Options used to open the popup
---@field close fun(self: Popup) Closes the popup
---@field update fun(self: Popup) Re-draw the popup
---@field win_width fun(self: Popup):integer Returns the current width of the floating window
---@field win_height fun(self: Popup):integer Returns the current height of the floating window
---@field find_hl_groups fun(self: Popup, hl_group: string) Finds regions matching a target highlight group within the popup
---@field auto_child fun(self: Popup, hl_group: string):FloatPosition,Rect Automatically gets float options for a child window based on a highlight group

---@class OpenPopupOptions
---@field ft? string Filetype to use for the buffer. Defaults to 'grafika'
---@field padding? integer Inner window padding
---@field must_focus? boolean Enter the window after creation and close it when out of focus
---@field focusable? boolean Focusable window setting
---@field border? string|string[] Window border setting
---@field zindex? integer Window zindex setting
---@field position? "center-win"|"center-editor"|"last_cursor"|FloatPosition Where to position the popup. Defaults to center
---@field on_exit? fun() Callback called when the popup is closed

---Creates and opens a popup from a component
---@param comp fun():Component|Component Callback to get the component to draw, or static component
---@param opts? OpenPopupOptions
function M.open_popup(comp, opts)
    err.expect_param("open_popup", "comp", comp)

    opts = opts or {}

    local padding = opts.padding or 0
    local must_focus = opts.must_focus ~= nil and opts.must_focus or false

    local winopts = {
        style = "minimal",
        border = opts.border or "none",
        focusable = opts.focusable,
        noautocmd = true,
    }

    local cur_win = vim.api.nvim_get_current_win() or 0
    opts.position = opts.position or "center-editor"
    if type(opts.position) == "table" then
        winopts.relative = opts.position.relative
        winopts.anchor = opts.position.anchor
        winopts.win = opts.position.win
        winopts.row = opts.position.row
        winopts.col = opts.position.col
    elseif opts.position == "center-win" or opts.position == "center-editor" then
        local global = opts.position == "center-editor"
        winopts.relative = global and "editor" or "win"
        if not global then
            winopts.win = cur_win
        end
    else -- "last_cursor" or anything else
        winopts.relative = "win"
        winopts.win = cur_win
        local cursor = vim.api.nvim_win_get_cursor(cur_win)
        winopts.row = cursor[1]
        winopts.col = cursor[2]
    end

    ---Last component returned by the draw function
    ---@type Component
    local last_comp
    if type(comp) == "function" then
        last_comp = comp()
    else
        last_comp = comp
    end
    if last_comp == nil then
        vim.api.nvim_err_writeln("grafika.nvim: Cannot create a popup with a nil component!")
        return
    end

    ---Calculates window settings that might change after a component change
    local function calc_winopts()
        local width = last_comp:display_width()
        local height = last_comp:height()
        local newopts = {
            width = width + padding * 2,
            height = height + padding * 2,
        }
        if opts.position == "center-win" or opts.position == "center-editor" then
            local global = opts.position == "center-editor"
            newopts.row, newopts.col = M._calc_center(global, cur_win, height, width)
        end
        return newopts
    end

    -- create the buffer
    local buf = M.create_buf(opts.ft)
    -- set the default width, height, and maybe positioning
    winopts = vim.tbl_extend("error", winopts, calc_winopts())
    -- create the floating window
    local win = vim.api.nvim_open_win(buf, must_focus, winopts)

    local canvas = types.Canvas(buf)
    local popup = {
        buf = buf,
        win = win,
        opts = opts,
    }

    -- don't expose the canvas itself, draws need to be done by calling 'popup:update()'
    function popup:find_hl_groups(hl_group)
        return canvas:find_hl_groups(hl_group)
    end

    function popup:auto_child(hl_group)
        if not vim.api.nvim_win_is_valid(win) then
            return
        end

        local matches = canvas:find_hl_groups(hl_group)
        local rect = matches[1]
        if rect == nil then
            return nil, nil
        end

        local cur_winopts = vim.api.nvim_win_get_config(win)
        local attach_to, row, col
        if cur_winopts.win ~= nil and cur_winopts.win > 0 and cur_winopts.row ~= nil and cur_winopts.col ~= nil then
            attach_to = winopts.win
            local cur_row = type(cur_winopts.row) == "table" and cur_winopts.row[false] or cur_winopts.row
            local cur_col = type(cur_winopts.col) == "table" and cur_winopts.col[false] or cur_winopts.col
            row = cur_row + rect.y
            col = cur_col + rect.x
        else
            -- This should be preferable all the time, however it has a glitch which is quite annoying
            attach_to = canvas.win
            row = rect.y
            col = rect.x
        end

        ---@type FloatPosition
        local floatopts = {
            relative = "win",
            win = attach_to,
            row = row,
            col = col,
            width = rect.width,
            height = rect.height,
        }
        return floatopts, rect
    end

    -- the draw area in within the padding
    local bounds = types.Bounds(padding, padding)

    function popup:close()
        vim.api.nvim_win_close(win, false)
    end

    function popup:update()
        if not vim.api.nvim_win_is_valid(win) then
            return
        end

        if type(comp) == "function" then
            last_comp = comp()
        else
            last_comp = comp
        end
        if last_comp == nil then
            popup:close()
            return
        end

        vim.api.nvim_win_set_config(win, calc_winopts())
        canvas:draw_component(last_comp, bounds)
    end

    function popup:win_width()
        if not vim.api.nvim_win_is_valid(win) then
            return 0
        end
        return vim.api.nvim_win_get_config(win).width
    end

    function popup:win_height()
        if not vim.api.nvim_win_is_valid(win) then
            return 0
        end
        return vim.api.nvim_win_get_config(win).height
    end

    -- bind the canvas and draw the initial component on it
    M.bind_canvas(canvas, win, {
        on_exit = opts.on_exit,
    })
    canvas:draw_component(last_comp, bounds)

    -- setup autocommands
    if must_focus then
        vim.api.nvim_create_autocmd({ "BufLeave" }, {
            buffer = canvas.buf,
            once = true,
            callback = function()
                popup:close()
            end,
        })
    end

    return popup
end

function M._calc_center(global, win, height, width)
    local max_width = global and vim.o.columns or vim.api.nvim_win_get_width(win)
    local max_height = global and vim.o.lines - vim.o.cmdheight - 2 or vim.api.nvim_win_get_height(win)
    return math.floor((max_height - height) / 2), math.floor((max_width - width) / 2)
end

return M
