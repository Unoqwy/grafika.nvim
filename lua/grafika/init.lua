local types = require("grafika/types")
local util = require("grafika/util")
local window = require("grafika/window")

local M = {}

M.default_win_opts = {
    listchars = "trail: ",
    colorcolumn = "",
    cursorcolumn = false,
    cursorline = false,
}

-- re-export everything so it's more convenient to use
-- Note: We cannot use vim.tbl_extend here because it sadly doesn't retain documentation for methods

M.Canvas = types.Canvas
M.Rect = types.Rect
M.Bounds = types.Bounds
M.Component = types.Component
M.ComponentBuilder = types.ComponentBuilder
M.HighlightInfo = types.HighlightInfo

M.merge_h = util.merge_h
M.rect_contains = util.rect_contains

M.create_buf = window.create_buf
M.create_canvas = window.create_canvas
M.bind_canvas = window.bind_canvas
M.open_popup = window.open_popup

return M
