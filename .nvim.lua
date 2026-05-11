vim.lsp.config("sourcekit", {
  cmd = { "xcrun", "sourcekit-lsp" },
  filetypes = { "swift" },
  root_markers = { "Package.swift", ".git" },
})
vim.lsp.enable("sourcekit")
