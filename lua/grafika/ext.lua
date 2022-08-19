-- ext.lua is a set of miscellaneous utility functions that do
-- not use grafika features, but are still useful when dealing with UIs

local M = {}

---@class Prompt
---@field win integer Window handle
---@field buf integer Buffer ID
---@field get_input fun(self: Prompt):string Returns the current input
---@field close fun(self: Prompt) Closes the prompt window and delete the buffer

---@class OpenPromptOptions
---@field ft? string Buffer filetype. Defaults to grafika-prompt
---@field prefix? string Prompt prefix
---@field must_focus? boolean Whether to close the prompt when it gets unfocused. Defaults to true
---@field start_insert? boolean Whether to start in insert mode. Defaults to true
---@field prepare_buf? fun(buf: integer) Callback to do stuff with the buffer before opening it in a window
---@field always_confirm? boolean Whether to always call on_confirm when the prompt closes. Otherwise, on_confirm will only be called when prompt:confirm() is called. Defaults to false
---@field on_confirm? fun(input: string) Callback to handle prompt confirmation
---@field on_close? fun() Callback to handle prompt close event
---@field on_update? fun(input: string) Callback to handle user input event. The call will be deferred with vim.schedule

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

    local should_confirm = opts.always_confirm ~= nil and opts.always_confirm
    local closing = false
    local input = ""

    function prompt:get_input()
        return input
    end

    function prompt:confirm()
        should_confirm = true
        self:close()
    end

    function prompt:close()
        if closing then
            return
        end
        closing = true
        if should_confirm and type(opts.on_confirm) == "function" then
            pcall(opts.on_confirm, input)
        end
        if type(opts.on_close) == "function" then
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

    local on_update = type(opts.on_update) == "function" and opts.on_update or nil

    vim.api.nvim_buf_attach(buf, false, {
        -- "lines", buf, changedtick, first_line, last_line, last_line_bis
        on_lines = function(_, _, _, _, last_line, _)
            -- we only care about the last line, since this is a prompt-buffer
            local lines = vim.api.nvim_buf_get_lines(buf, last_line - 1, last_line, false)
            input = lines[1] or ""
            if last_line == 1 then
                local prompt_prefix = vim.fn.prompt_getprompt(buf)
                input = string.sub(input, #prompt_prefix + 1, -1)
            end
            if on_update ~= nil then
                -- schedule here so the callback doesn't have to do it
                vim.schedule(function()
                    on_update(input)
                end)
            end
        end,
        on_detach = function()
            prompt:close()
        end,
    })

    if opts.start_insert == nil or opts.start_insert then
        vim.api.nvim_command("startinsert!")
    end

    return prompt
end

return M
