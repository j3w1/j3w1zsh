local group = vim.api.nvim_create_augroup("WriterNvim", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = { "markdown", "text", "asciidoc", "gitcommit" },
  callback = function()
    vim.opt_local.spell = true
    vim.opt_local.spelllang = { "en_us", "es" }
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
    vim.opt_local.conceallevel = 2
    if vim.bo.filetype == "markdown" then
      pcall(vim.treesitter.start, 0, "markdown")
    end
  end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
  group = group,
  callback = function(args)
    local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
    local lines = vim.api.nvim_buf_line_count(args.buf)
    if mark[1] > 0 and mark[1] <= lines then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function()
    vim.highlight.on_yank({ higroup = "Visual", timeout = 180 })
  end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
  group = group,
  callback = function(args)
    local file = vim.api.nvim_buf_get_name(args.buf)
    if file ~= "" and not file:match("^%a+://") then
      vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
    end
  end,
})

vim.api.nvim_create_autocmd("VimEnter", {
  group = group,
  callback = function()
    vim.schedule(function()
      if vim.bo.filetype ~= "lazy" and vim.bo.filetype ~= "help" then
        pcall(vim.cmd, "NvimTreeOpen")
        pcall(vim.cmd, "wincmd p")
      end
    end)
  end,
})
