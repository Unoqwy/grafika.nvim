local err = require("grafika/error")
local draw = require("grafika/draw")

local M = {}

---@class Canvas
---@field buf integer
---@field win? integer Window the canvas is currently opened in
---@field bounds Rect
---@field draw_component fun(self: Canvas, comp: Component, bounds?: Rect)
---@field start_draw fun(self: Canvas) Start drawing on the canvas, unlock it
---@field stop_draw fun(self: Canvas) Stop drawing on the canvas, lock it back
---@field find_hl_groups fun(self: Canvas, hl_group: string) Finds regions matching a target highlight group within bounds
---
---@param buf integer Buffer handle to draw on
---@param bounds? Rect
---@return Canvas
function M.Canvas(buf, bounds)
    err.expect_param("Canvas", "buf", buf)

    local o = {
        buf = buf,
        bounds = bounds or M.Bounds(),
    }

    function o:draw_component(comp, _bounds)
        return draw.draw_component(self, comp, _bounds or M.Bounds())
    end

    -- store count of current draw stack so that if they
    -- ever end up being nested, stop_drow won't prevent
    -- a upper block from finishing its draw
    local draw_rc = 0

    function o:start_draw()
        draw_rc = draw_rc + 1
        if draw_rc == 1 then
            draw.toggle_drawable(self, true)
        end
    end

    function o:stop_draw()
        draw_rc = draw_rc - 1
        if draw_rc == 0 then
            draw.toggle_drawable(self, false)
        end
    end

    function o:find_hl_groups(hl_group)
        local ret = {}
        local matches = require("grafika/util").find_hl_groups(o.buf, draw.get_ns(), hl_group)
        for _, rect in ipairs(matches) do
            if rect.x < o.bounds.x then
                if rect.x + rect.width >= o.bounds.x then
                    local offset = o.bounds.x - rect.x
                    rect.x = o.bounds.x
                    if o.bounds.width > -1 then
                        rect.width = rect.width - offset
                    end
                else
                    rect.width = 0
                end
            end
            if o.bounds.width > -1 and rect.x + rect.width > o.bounds.x + o.bounds.width then
                rect.width = o.bounds.x + o.bounds.width - rect.x
            end

            if rect.y < o.bounds.y then
                if rect.y + rect.height >= o.bounds.y then
                    local offset = o.bounds.y - rect.y
                    rect.y = o.bounds.y
                    if o.bounds.height > -1 then
                        rect.height = rect.height - offset
                    end
                else
                    rect.height = 0
                end
            end
            if o.bounds.height > -1 and rect.y + rect.height > o.bounds.y + o.bounds.height then
                rect.height = o.bounds.y + o.bounds.height - rect.y
            end

            if rect.width > 0 and rect.height > 0 then
                table.insert(ret, rect)
            end
        end
        return ret
    end

    return o
end

---@class Rect
---@field x integer Zero-based column in line
---@field y integer Zero-based line in buffer
---@field width integer Number of columns (width)
---@field height integer Number of lines (height)
---
---@param x integer?
---@param y integer?
---@param width integer?
---@param height integer?
---@return Rect
function M.Rect(x, y, width, height)
    return {
        x = x or 0,
        y = y or 0,
        width = width or 0,
        height = height or 0,
    }
end

---Similar to `Rect` but width and height default to -1 when unset
---@param x integer?
---@param y integer?
---@param width integer?
---@param height integer?
---@return Rect
function M.Bounds(x, y, width, height)
    return {
        x = x or 0,
        y = y or 0,
        width = width or -1,
        height = height or -1,
    }
end

---@class Component
---@field lines string[] Content to draw
---@field hl_info HighlightInfo[]
---@field height fun(self: Component):integer Get or calc height
---@field display_width fun(self: Component):integer Get or calc display width
---
---@param lines string[]
---@param hl_info HighlightInfo[]?
---@param display_width integer? Positive display width or nil to infer
---@param height integer? Positive height or nil to infer
---@return Component
function M.Component(lines, hl_info, display_width, height)
    err.expect_param("Component", "lines", lines)

    if hl_info ~= nil and type(hl_info) == "table" and hl_info.rect ~= nil then
        hl_info = { hl_info }
    end

    local o = {
        lines = lines,
        hl_info = hl_info or {},
    }

    function o:height()
        return height or #self.lines
    end

    function o:display_width()
        if display_width ~= nil then
            return display_width
        end

        local max_w = 0
        for _, line in ipairs(self.lines) do
            local w = vim.fn.strdisplaywidth(line)
            if w > max_w then
                max_w = w
            end
        end
        display_width = max_w
        return max_w
    end

    return o
end

---@class ComponentBuilder
---@field lines string[] Lines
---@field hl_info HighlightInfo[] Highlight info
---
---@field line fun(self: ComponentBuilder, str: string, hl_group?: string) Add a line
---@field append fun(self: ComponentBuilder, str: string, hl_group?: string) Append a string to previous line
---@field append_comp fun(self: ComponentBuilder, comp: Component) Append a component to previous line
---@field append_right fun(self: ComponentBuilder, str: string, hl_group?: string) Append to right of previous line
---@field build fun(self: ComponentBuilder):Component Build the component

---Utility to create components
---@return ComponentBuilder
function M.ComponentBuilder()
    local o = {
        lines = {},
        hl_info = {},
    }

    local append_right = {}

    function o:line(str, hl_group)
        if type(str) ~= "string" then
            str = tostring(str)
        end
        table.insert(o.lines, str)
        if hl_group ~= nil then
            table.insert(o.hl_info, M.HighlightInfo(M.Rect(0, #o.lines - 1, #str, 1), hl_group))
        end
    end

    function o:append(str, hl_group)
        if type(str) ~= "string" then
            str = tostring(str)
        end
        local idx = math.max(#o.lines, 1)
        local line = o.lines[idx] or ""
        if hl_group ~= nil then
            table.insert(o.hl_info, M.HighlightInfo(M.Rect(#line, idx - 1, #str, 1), hl_group))
        end
        o.lines[idx] = line .. str
    end

    function o:append_comp(comp)
        if #comp.lines ~= 1 then
            vim.api.nvim_err_writeln("grafika.nvim: ComponentBuilder:append_comp takes a component with only one line")
            return
        end

        comp = vim.deepcopy(comp)
        local idx = math.max(#o.lines, 1)
        local line = o.lines[idx] or ""
        o.lines[idx] = line .. comp.lines[1]
        for _, hl in ipairs(comp.hl_info) do
            hl.rect.x = hl.rect.x + #line
            hl.rect.y = hl.rect.y + (#o.lines - 1)
            table.insert(o.hl_info, hl)
        end
    end

    function o:append_right(str, hl_group)
        if str == nil then
            return
        end
        table.insert(append_right, { #o.lines, str, hl_group })
    end

    function o:build()
        local display_width = nil
        if #append_right > 0 then
            display_width = 0
            for _, line in ipairs(o.lines) do
                local w = vim.fn.strdisplaywidth(line)
                if w > display_width then
                    display_width = w
                end
            end

            for _, append in ipairs(append_right) do
                local idx = math.max(append[1], 1)
                local line = o.lines[idx] or ""
                local fill = display_width - vim.api.nvim_strwidth(line) - vim.api.nvim_strwidth(append[2])
                if fill > 0 then
                    line = line .. string.rep(" ", fill)
                elseif fill < 0 then
                    -- component width is currently too short to display the right element, expand it
                    display_width = display_width + math.abs(fill)
                end
                if append[3] ~= nil then
                    table.insert(o.hl_info, M.HighlightInfo(M.Rect(#line, idx - 1, #append[2], 2), append[3]))
                end
                o.lines[idx] = line .. append[2]
            end
        end

        return M.Component(o.lines, o.hl_info, display_width)
    end

    return o
end

---@class HighlightInfo
---@field rect Rect
---@field hl_group string?
---
---@param rect Rect
---@param hl_group string?
---@return HighlightInfo
function M.HighlightInfo(rect, hl_group)
    err.expect_param("HighlightInfo", "rect", rect)

    return {
        rect = rect,
        hl_group = hl_group,
    }
end

return M
