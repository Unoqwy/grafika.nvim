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
            local min_col, max_col = math.min(start_col, opts.end_col), math.max(start_col, opts.end_col)
            table.insert(matches, types.Rect(min_col, start_row, max_col - min_col, opts.end_row - start_row + 1))
        end
    end

    return matches
end

return M
