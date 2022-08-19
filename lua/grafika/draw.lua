local api = vim.api

local err = require("grafika/error")

local ns_id

local M = {}

---Returns the namespace ID used to add highlight groups
---@return integer
function M.get_ns()
    if ns_id ~= nil then
        return ns_id
    end
    ns_id = api.nvim_create_namespace("grafika")
    return ns_id
end

---Draws a compoment on a canvas
---@param canvas Canvas - to draw on
---@param comp Component - to draw
---@param bounds Rect Boundaries, the component will be trimmed to fit inside and hightlight will be cleared
function M.draw_component(canvas, comp, bounds)
    err.expect_param("draw_component", "canvas", canvas)
    err.expect_param("draw_component", "comp", comp)
    err.expect_param("draw_component", "bounds", bounds)

    if bounds.width == 0 or bounds.height == 0 then
        return
    end

    if canvas.force_win_focus then
        local cur_win = api.nvim_get_current_win()
        if api.nvim_win_get_buf(cur_win) ~= canvas.buf then
            if canvas.win == nil then
                return
            end
            if cur_win ~= canvas.win then
                api.nvim_win_call(canvas.win, function()
                    M.draw_component(canvas, comp, bounds)
                end)
            end
            return
        end
    end

    local buf, ns = canvas.buf, M.get_ns()
    local base_x, base_y = canvas.bounds.x + bounds.x, canvas.bounds.y + bounds.y
    local height = comp:height()

    local end_line, end_col
    if bounds.height == -1 then
        end_line = base_y + height
    else
        end_line = base_y + math.min(bounds.height, height)
    end
    if bounds.width == -1 then
        end_col = base_x + comp:display_width()
    else
        end_col = base_x + bounds.width
    end

    canvas:start_draw()

    -- add missing lines before component y pos
    local line_count = api.nvim_buf_line_count(buf)
    if line_count < base_y then
        local fill_from = math.max(line_count, 0)
        local fill = {}
        for _ = fill_from, base_y - 1 do
            table.insert(fill, "")
        end
        api.nvim_buf_set_lines(buf, fill_from, base_y, false, fill)
    end

    local projected_end, lines
    if bounds.height > -1 then
        projected_end = end_line
        lines = comp.lines
    else
        projected_end = -1
        lines = {}
        for i = 1, end_line - base_y + 1 do
            lines[i] = comp.lines[i]
        end
        -- leftover lines will be removed by `set_lines` call
    end

    -- save byte positions for highlight groups
    local hl_pos = {}
    -- merge with other content on lines if it must draw within a subset of the full buf width
    if base_x > 0 or bounds.width > 0 then
        local width = end_col - base_x
        local prev_lines = api.nvim_buf_get_lines(buf, base_y, projected_end, false)
        for i = 1, #lines do
            local prev_line = prev_lines[i] or ""
            local insert = string.sub(lines[i] or "", 0, width)
            local insert_width = api.nvim_strwidth(insert)
            if insert_width < width then
                insert = insert .. string.rep(" ", width - insert_width)
            end
            -- note : string.sub is 1-based inclusive and our bounds are 0-based
            local prepend = string.sub(prev_line, 0, base_x)
            local prepend_width = api.nvim_strwidth(prepend)
            if prepend_width < base_x then
                prepend = prepend .. string.rep(" ", base_x - prepend_width)
            end
            lines[i] = prepend .. insert .. string.sub(prev_line, end_col + 1, -1)
            hl_pos[i] = { #prepend, #insert }
        end
    else
        for i = 1, #lines do
            hl_pos[i] = { 0, #lines[i] }
        end
    end

    api.nvim_buf_set_lines(buf, base_y, projected_end, false, lines)

    -- add highlight groups
    api.nvim_buf_clear_namespace(buf, ns, base_y, projected_end)
    for _, hl in ipairs(comp.hl_info) do
        local hl_line, hl_end_line = base_y + hl.rect.y, nil
        if hl.rect.height > -1 then
            hl_end_line = hl_line + hl.rect.height
        else
            hl_end_line = hl_line + height
        end

        if hl_pos[hl.rect.y + 1] ~= nil then
            local pos = hl_pos[hl.rect.y + 1]
            local hl_col, hl_end_col = pos[1] + hl.rect.x, nil
            if hl.rect.width > -1 then
                hl_end_col = hl_col + hl.rect.width
            else
                hl_end_col = hl_col + pos[2]
            end

            if hl.hl_group ~= nil then
                while hl_line < hl_end_line do
                    api.nvim_buf_add_highlight(buf, ns, hl.hl_group, hl_line, hl_col, hl_end_col)
                    hl_line = hl_line + 1
                end
            end
        end
    end
    canvas:stop_draw()
end

---Toggles the drawable state of a canvas
---@param canvas Canvas Target canvas
---@param state boolean New state
function M.toggle_drawable(canvas, state)
    api.nvim_buf_set_option(canvas.buf, "modifiable", state)
end

return M
