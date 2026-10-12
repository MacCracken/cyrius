-- Cyrius LSP configuration for Neovim
-- Add to your init.lua or lazy.nvim config

-- File type detection
vim.filetype.add({
  extension = {
    cyr = "cyrius",
  },
})

-- LSP setup
vim.api.nvim_create_autocmd("FileType", {
  pattern = "cyrius",
  callback = function()
    vim.lsp.start({
      name = "cyrius-lsp",
      cmd = { "cyrius-lsp" }, -- must be in PATH or use absolute path
      root_dir = vim.fs.dirname(
        vim.fs.find({ "cyrius.cyml", ".git" }, { upward = true })[1]
      ),
    })
  end,
})

-- Comment string
vim.api.nvim_create_autocmd("FileType", {
  pattern = "cyrius",
  callback = function()
    vim.bo.commentstring = "# %s"
  end,
})
