-- Enable syntax highlighting
vim.cmd('syntax on')

-- Enable file type detection, plugins, and indentation
vim.cmd('filetype plugin indent on')

vim.o.number = true
vim.o.relativenumber = true
vim.o.signcolumn = 'yes'

vim.o.expandtab = true
vim.o.shiftwidth = 4
vim.o.showcmd = true
vim.o.softtabstop = 4
vim.o.tabstop = 4

vim.o.laststatus = 2


-- We define a global function so it can be called from the statusline option string
function _G.MyStatusLine()
    -- Get variable values for dynamic width calculations
    local columns = vim.o.columns
    local total_lines = vim.fn.line("$")

    -- Calculate widths exactly like the vimrc logic (strlen of value)
    local width_cols = #tostring(columns)
    local width_lines = #tostring(total_lines)

    -- Build the statusline string
    local parts = {
        '[%t]',                                     -- tail of the file name
        '[fenc=%{&fileencoding}, ff=%{&fileformat}, ft=%{&filetype}]',
        '%m',                                       -- modified flag
        '%r',                                       -- read only flag
        '%=',                                       -- right align following items
        '[ts=%{&ts}, sts=%{&sts}, sw=%{&sw}, et=%{&et}]',

        -- Column info: [c= padded_col / padded_line_len / columns]
        string.format(
            "[c=%%%dc/%%%d{strlen(getline('.'))}/%%{&columns}]",
            width_cols,
            width_cols
        ),

        -- Line info: [l= padded_cur_line / total_lines  percent]
        string.format(
            "[l=%%%dl/%%L %%3p%%%%]",
            width_lines
        ),

        string.format('[%d.%d.%d]', vim.version().major, vim.version().minor, vim.version().patch)
    }

    return table.concat(parts, "")
end

-- Set the statusline to call the global Lua function
vim.o.statusline = "%!v:lua.MyStatusLine()"

-- Helper function to preserve view state while running commands
local function preserve_view(callback)
    local save = vim.fn.winsaveview()
    callback()
    vim.fn.winrestview(save)
end

-- Trim Trailing Whitespace
local function trim_trailing_whitespace()
    preserve_view(function()
        -- 'keeppatterns' ensures the search history isn't modified
        -- The 'e' flag suppresses errors if no match is found
        vim.cmd([[keeppatterns %s/\s\+$//e]])
    end)
end

-- Trim Final Newlines
local function trim_final_newlines()
    preserve_view(function()
        vim.cmd([[keeppatterns %s/\n\+\%$//e]])
    end)
end

-- Create User Commands
vim.api.nvim_create_user_command('TrimTrailingWhitespace', trim_trailing_whitespace, {})
vim.api.nvim_create_user_command('TrimFinalNewlines', trim_final_newlines, {})

-- Use pcall (protected call) to prevent errors if the theme isn't installed
local status_ok, _ = pcall(vim.cmd.colorscheme, "mycolorscheme")
if not status_ok then
    print("Colorscheme 'mycolorscheme' not found!")
end
