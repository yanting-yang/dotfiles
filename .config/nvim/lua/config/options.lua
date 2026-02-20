vim.opt.cursorline = true
vim.opt.expandtab = true
vim.opt.list = true
vim.opt.number = true
vim.opt.scrolloff = 5
vim.opt.shiftwidth = 4
vim.opt.showtabline = 2
vim.opt.signcolumn = 'yes'
vim.opt.statusline = '%{&fenc}|%{&ff}|%{&ft}%=%-14.(%l,%c%V%) %P'
vim.opt.tabstop = 4
vim.opt.winbar = '%f %m%r'
vim.opt.relativenumber = true

-- Custom function to display buffers in the tabline, emulating bufferline.nvim
function _G.show_buffers_tabline()
    local line = ""
    -- Iterate over all buffers
    for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
        -- Only show listed buffers
        if vim.bo[buf_id].buflisted then
            -- Check if this is the current buffer
            local is_current = buf_id == vim.api.nvim_get_current_buf()

            -- Set highlight group based on whether it's the current buffer
            if is_current then
                line = line .. "%#TabLineSel#"
            else
                line = line .. "%#TabLine#"
            end

            -- Get buffer name or use "[No Name]"
            local name = vim.api.nvim_buf_get_name(buf_id)
            if name == "" then
                name = "[No Name]"
            else
                name = vim.fn.fnamemodify(name, ":t")
            end

            -- Append buffer number and name
            line = line .. " " .. buf_id .. " " .. name

            -- Add spacing
            line = line .. " "
        end
    end
    -- Fill the rest of the tabline
    line = line .. "%#TabLineFill#"

    -- Tabpage integration
    local tab_count = vim.fn.tabpagenr('$')
    line = line .. "%=" -- Right align
    for i = 1, tab_count do
        local is_current = i == vim.fn.tabpagenr()
        local tab_hl = is_current and "%#TabLineSel#" or "%#TabLine#"
        line = line .. tab_hl .. " " .. i .. " "
    end
    -- Reset highlight after tabs
    line = line .. "%#TabLineFill#"

    return line
end

-- Set the tabline option to use the custom function
vim.opt.tabline = "%!v:lua.show_buffers_tabline()"
