-- ext.lua is a set of miscellaneous utility functions that do
-- not use grafika features, but are still useful when dealing with UIs

local M = {}

---@class Prompt
---@field win integer Window handle
---@field buf integer Buffer ID
---@field close fun(self: Prompt) Closes the prompt window and delete the buffer

---@class OpenPromptOptions
---@field ft? string Buffer filetype. Defaults to grafika-prompt
---@field prefix? string Prompt prefix
---@field must_focus? boolean Whether to close the prompt when it gets unfocused. Defaults to true
---@field start_insert? boolean Whether to start in insert mode. Defaults to true
---@field prepare_buf? fun(buf: integer) Callback to do stuff with the buffer before opening it in a window
---@field on_close? fun() Callback to handle prompt close event

---Creates a prompt buffer/floating window and enter it
---@param winopts table Window options
---@param opts? OpenPromptOptions Extra options
---@return Prompt Opened prompt
function M.create_prompt(winopts, opts)
    opts = opts or {}

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, "buftype", "prompt")
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(buf, "swapfile", false)
    vim.api.nvim_buf_set_option(buf, "filetype", opts.ft or "grafika-prompt")

    if opts.prefix ~= nil then
        vim.fn.prompt_setprompt(buf, opts.prefix)
    end

    if opts.prepare_buf ~= nil and type(opts.prepare_buf) == "function" then
        opts.prepare_buf(buf)
    end

    local default_winopts = {
        style = "minimal",
        border = "none",
        noautocmd = true,
    }
    local win = vim.api.nvim_open_win(buf, true, vim.tbl_extend("keep", winopts, default_winopts))

    local prompt = {
        win = win,
        buf = buf,
    }

    local closing = false

    function prompt:close()
        if closing then
            return
        end
        closing = true
        if opts.on_close ~= nil and type(opts.on_close) == "function" then
            pcall(opts.on_close)
        end
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, {
                force = true,
            })
        end
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end

    vim.api.nvim_create_autocmd({ "BufUnload" }, {
        buffer = buf,
        once = true,
        callback = function()
            prompt:close()
        end,
    })

    if opts.must_focus == nil or opts.must_focus then
        vim.api.nvim_create_autocmd({ "BufLeave" }, {
            buffer = buf,
            once = true,
            callback = function()
                prompt:close()
            end,
        })
    end

    if opts.start_insert == nil or opts.start_insert then
        vim.api.nvim_command("startinsert!")
    end

    return prompt
end

return M
