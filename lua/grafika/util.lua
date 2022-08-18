local err = require("grafika/error")
local types = require("grafika/types")

local M = {}

---@class MergeOptions
---@field sep? string

---Merges two or more components into one by putting them side by side (horizontal merge)
---@param components Component?[] Components to merge. Nil elemenst will be ignored
---@param opts? MergeOptions Merge options
---@return Component?,Rect? New component and offset boundaries of right-most input component
function M.merge_h(components, opts)
    if components == nil or #components == 0 then
        return nil
    end

    local height = 0
    local nonnil = {}
    for i = 1, #components do
        local comp = components[i]
        if comp ~= nil then
            if comp:height() > height then
                height = comp:height()
            end
            table.insert(nonnil, comp)
        end
    end
    if height == 0 then
        return nil
    end

    -- no need to merge if there is only one applicable component
    local comps_count = #nonnil
    if comps_count == 1 then
        local comp = nonnil[1]
        return comp, types.Rect(0, 0, comp:display_width(), comp:height())
    end

    opts = opts or {}
    local sep = opts.sep

    local stroffset = 0
    local lines, hl_info = {}, {}
    for i = 1, comps_count do
        local comp = nonnil[i]
        local width = comp:display_width()
        stroffset = stroffset + width

        for _, hl in ipairs(comp.hl_info) do
            local rect = hl.rect
            local offset = #(lines[rect.y + 1] or "")
            rect.x = offset + rect.x
            if rect.width < 0 then
                rect.width = #(comp.lines[rect.y + 1] or "")
            end
            table.insert(hl_info, hl)
        end
        for y = 1, height do
            local line = comp.lines[y]
            if line == nil then
                line = string.rep(" ", width)
            else
                line = line .. string.rep(" ", width - vim.api.nvim_strwidth(line))
            end
            lines[y] = (lines[y] or "") .. line
        end

        if i < comps_count and sep ~= nil then
            stroffset = stroffset + vim.api.nvim_strwidth(sep)
            for y = 1, height do
                lines[y] = lines[y] .. sep
            end
        end
    end

    local last = nonnil[comps_count]
    local last_rect = types.Rect(stroffset - last:display_width(), 0, last:display_width(), last:height())
    return types.Component(lines, hl_info, nil, height), last_rect
end

---Merges two components by overlapping one on top of another
---@param lhs Component Base component
---@param rhs Component Overlapping component (will be on top of lhs)
---@param bounds? Rect Where can rhs overlap on lhs. This will do offsetting too
---@return Component Merged component
function M.merge_overlap(lhs, rhs, bounds)
    err.expect_param("merge_overlap", "lhs", lhs)
    err.expect_param("merge_overlap", "rhs", rhs)

    bounds = bounds or types.Bounds()

    local lines = vim.deepcopy(lhs.lines)
    local hl_info = vim.deepcopy(lhs.hl_info)

    -- data to move highlight groups
    local hl_move = {}

    local line_count = math.max(lhs:height(), rhs:height())
    if bounds.height > -1 then
        line_count = math.min(bounds.height, line_count)
    end
    local last_line = 0
    for i = 1, line_count do
        local to_merge = rhs.lines[i]
        if to_merge ~= nil then
            last_line = bounds.y + i
            local line = lines[last_line] or ""

            local offset = bounds.x
            local line_width = vim.api.nvim_strwidth(line)
            local width = vim.api.nvim_strwidth(to_merge)
            if bounds.width > -1 and width > bounds.width then
                width = bounds.width
                to_merge = string.sub(to_merge, 0, vim.fn.byteidx(to_merge, width))
            end

            local hl_offset
            if line_width <= offset then
                hl_offset = #line
                line = line .. string.rep(" ", offset - line_width) .. to_merge
            else
                local pre = string.sub(line, 0, vim.fn.byteidx(line, offset))
                hl_offset = #pre
                local post = string.sub(line, vim.fn.byteidx(line, offset + width) + 1, -1)
                line = pre .. to_merge .. post
            end

            lines[last_line] = line
            hl_move[i] = {
                new_line = last_line,
                offset = hl_offset,
            }
        end
    end

    for _, hl in ipairs(rhs.hl_info) do
        local rect = hl.rect
        local move_data = hl_move[rect.y]
        if move_data ~= nil then
            rect.x = rect.x + move_data.offset
            if rect.width < 0 then
                rect.width = #(rhs.lines[rect.y + 1] or "")
            end
            rect.y = move_data.new_line
            table.insert(hl_info, hl)
        end
    end

    -- make sure lines is a valid list
    for i = 1, last_line do
        if lines[i] == nil then
            lines[i] = ""
        end
    end

    return types.Component(lines, hl_info)
end

---Checks if a position (x,y) is contained within a rect
---@param rect Rect
---@param x integer
---@param y integer
function M.rect_contains(rect, x, y)
    err.expect_param("rect_contains", "rect", rect)
    err.expect_param("rect_contains", "x", x)
    err.expect_param("rect_contains", "y", y)

    return x >= rect.x and x <= rect.x + rect.width and y >= rect.y and y <= rect.y + rect.height
end

---Searches for highlight groups in a buffer and returns found regions
---It will return approximate rectangles when a highlight starts and finishes on different rows
---This returns positions in virtual chars, not bytes
---@param buf integer Buffer to search in
---@param ns_id integer Namespace ID
---@param hl_group string Highlight group to search for
---@return Rect[] Found regions
function M.find_hl_groups(buf, ns_id, hl_group)
    err.expect_param("find_hl_groups", "buf", buf)
    err.expect_param("find_hl_groups", "ns_id", ns_id)
    err.expect_param("find_hl_groups", "hl_group", hl_group)

    local matches = {}
    local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {
        details = true,
    })
    for _, extmark in ipairs(extmarks) do
        local opts = extmark[4]
        if opts.hl_group == hl_group then
            local start_row = extmark[2]
            local start_col = extmark[3]
            local height = opts.end_row - start_row + 1

            -- convert byte positions into virtual positions
            local lines = vim.api.nvim_buf_get_lines(buf, start_row, start_row + height, false)
            local min_col, max_col = nil, 0
            for idx, line in ipairs(lines) do
                local start_at, end_at = 0, nil
                if idx == 1 then
                    start_at = start_col > 0 and vim.api.nvim_strwidth(string.sub(line, 0, start_col)) or 0
                end
                if idx == #lines then
                    end_at = vim.api.nvim_strwidth(string.sub(line, 0, opts.end_col))
                end
                if end_at == nil then
                    end_at = vim.api.nvim_strwidth(line)
                end

                if min_col == nil or start_at < min_col then
                    min_col = start_at
                end
                if end_at > max_col then
                    max_col = end_at
                end
            end

            -- create a rect from virtual positions
            local rect = types.Rect(min_col, start_row, max_col - min_col, opts.end_row - start_row + 1)
            table.insert(matches, rect)
        end
    end

    return matches
end

---@alias BorderPosition "top-left"|"top-center"|"top-right"|"bottom-left"|"bottom-center"|"bottom-right"

---@class BorderDecoration
---@field str string Text to display
---@field position? BorderPosition Position. Defaults to "top-center"
---@field hl_group? string Highlight group

---@class CreateBorderOptions
---@field hl_border? string Highlight group for border chars
---@field hl_fill? string Highlight group for filler chars
---@field fill? string Filler char. Defaults to space
---@field decoration? BorderDecoration|BorderDecoration[] A border decoration or several

---Creates a border as a component
---@param borderchars string|string[] Border chars
---@param width integer Width of the border
---@param height integer Height of the border
---@param opts? CreateBorderOptions Extra options
---@return Component
function M.create_comp_border(borderchars, width, height, opts)
    err.expect_param("create_comp_border", "borderchars", borderchars)
    err.expect_param("create_comp_border", "width", width)
    err.expect_param("create_comp_border", "height", height)

    if width <= 0 or height <= 0 then
        err.log("Width and height must be greater than 0 while creating a border component")
        return
    end

    opts = opts or {}
    local border = M._read_borderchars(borderchars)
    if border == nil then
        return
    end

    local hl_border = opts.hl_border
    local hl_fill = opts.hl_fill

    local fill = opts.fill or " "
    local builder = types.ComponentBuilder()
    for y = 1, height do
        local fill_width = math.max(width - 2, 0)
        if y == 1 then
            builder:line(border.topleft .. string.rep(border.top, fill_width) .. border.topright, hl_border)
        elseif y == height then
            builder:line(border.bottomleft .. string.rep(border.bottom, fill_width) .. border.bottomright, hl_border)
        else
            builder:line(border.left, hl_border)
            builder:append(string.rep(fill, fill_width), hl_fill)
            builder:append(border.right, hl_border)
        end
    end
    local comp = builder:build()

    local decoration = opts.decoration or {}
    if type(decoration) == "table" and decoration.str ~= nil then
        decoration = { decoration } -- single decoration passed
    end

    for _, elt in ipairs(decoration) do
        local str = elt.str or ""
        local pos = elt.position or "top-center"

        local x_pos, y_pos
        if pos == "top-left" then
            x_pos = "left"
            y_pos = "top"
        elseif pos == "top-center" then
            x_pos = "center"
            y_pos = "top"
        elseif pos == "top-right" then
            x_pos = "right"
            y_pos = "top"
        elseif pos == "bottom-left" then
            x_pos = "left"
            y_pos = "bottom"
        elseif pos == "bottom-center" then
            x_pos = "center"
            y_pos = "bottom"
        elseif pos == "bottom-right" then
            x_pos = "right"
            y_pos = "bottom"
        else
            err.log(string.format("Unknown border decoration position '%s'", pos))
        end

        local x, y
        if x_pos == "left" then
            x = 2
        elseif x_pos == "center" then
            x = math.floor((width - vim.api.nvim_strwidth(str)) / 2)
        elseif x_pos == "right" then
            x = math.max(width - vim.api.nvim_strwidth(str) - 2, 0)
        end
        if y_pos == "top" then
            y = 0
        elseif y_pos == "bottom" then
            y = height - 1
        end

        local merge_bounds = types.Bounds(x, y, width - x, 1)
        comp = M.merge_overlap(comp, types.SimpleComponent(str, elt.hl_group), merge_bounds)
    end

    return comp
end

---Reads border chars into a usable table
---@param borderchars string|string[] Border chars
---@return table Named border chars
function M._read_borderchars(borderchars)
    local istable = type(borderchars) == "table"
    local isstr = type(borderchars) == "string"
    if not istable and not isstr then
        err.log("Border chars may only be parsed from a string or a list of string")
        return
    end

    if istable and #borderchars == 8 then
        return {
            top = borderchars[1],
            right = borderchars[2],
            bottom = borderchars[3],
            left = borderchars[4],
            topleft = borderchars[5],
            topright = borderchars[6],
            bottomright = borderchars[7],
            bottomleft = borderchars[8],
        }
    end

    local char_a, char_b
    if isstr then
        char_a = borderchars
    elseif istable and #borderchars == 1 then
        char_a = borderchars[1]
    elseif istable and #borderchars == 2 then
        char_a = borderchars[1]
        char_b = borderchars[2]
    else
        err.log("Unexpected list length for border chars")
        return
    end

    if char_b == nil then
        char_b = char_a
    end

    return {
        top = char_a,
        right = char_a,
        bottom = char_a,
        left = char_a,
        topleft = char_b,
        topright = char_b,
        bottomright = char_b,
        bottomleft = char_b,
    }
end

return M
