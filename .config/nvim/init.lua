vim.opt.cursorline = true
vim.opt.expandtab = true
vim.opt.list = true
vim.opt.number = true
vim.opt.scrolloff = 5
vim.opt.shiftwidth = 4
vim.opt.signcolumn = 'yes'
vim.opt.tabstop = 4
vim.opt.relativenumber = true

vim.pack.add({
    {
        src = 'https://github.com/nvim-neo-tree/neo-tree.nvim',
        version = vim.version.range('3')
    },
    -- dependencies
    "https://github.com/nvim-lua/plenary.nvim",
    "https://github.com/MunifTanjim/nui.nvim",
    -- optional, but recommended
    "https://github.com/nvim-tree/nvim-web-devicons",
})
require('neo-tree').setup({
    filesystem = {
        filtered_items = { visible = true }
    }
})

vim.pack.add({
    'https://github.com/nvim-tree/nvim-web-devicons',
    'https://github.com/nvim-lualine/lualine.nvim'
})
require('lualine').setup()

vim.pack.add({
    'https://github.com/akinsho/bufferline.nvim'
})
require("bufferline").setup{}
