local M = {}

function M.expect_param(fn, param, val)
    if val == nil then
        vim.api.nvim_err_writeln("grafika.nvim: function `" .. fn .. "` expects a non-nil `" .. param .. "` parameter")
    end
end

function M.log(message)
    vim.api.nvim_err_writeln("grafika.nvim: " .. message)
end

return M
