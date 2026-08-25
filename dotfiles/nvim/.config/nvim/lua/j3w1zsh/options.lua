local opt = vim.opt

opt.termguicolors = true
opt.background = "dark"
opt.mouse = "a"
opt.number = true
opt.relativenumber = false
opt.cursorline = true
opt.signcolumn = "yes"
opt.scrolloff = 5
opt.sidescrolloff = 4

opt.wrap = true
opt.linebreak = true
opt.breakindent = true
opt.showbreak = "↳ "
opt.textwidth = 0
opt.colorcolumn = ""
opt.conceallevel = 2
opt.concealcursor = "nc"

opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = 2
opt.smartindent = true

opt.ignorecase = true
opt.smartcase = true
opt.inccommand = "split"
opt.splitright = true
opt.splitbelow = true
opt.completeopt = { "menu", "menuone", "noselect" }
opt.pumheight = 10

opt.undofile = true
opt.swapfile = false
opt.backup = false
opt.writebackup = false
opt.autoread = true
opt.updatetime = 250
opt.timeoutlen = 400

opt.spell = false
opt.spelllang = { "en_us", "es" }
opt.spelloptions = "camel"

opt.laststatus = 3
opt.showmode = false
opt.cmdheight = 1
opt.fillchars = {
  eob = " ",
  fold = " ",
  foldopen = "",
  foldclose = "",
  foldsep = " ",
  diff = "╱",
}

opt.sessionoptions = {
  "buffers",
  "curdir",
  "folds",
  "help",
  "tabpages",
  "winsize",
}
vim.api.nvim_create_autocmd("FileType", {
  pattern = {
    "markdown",
    "text",
    "gitcommit",
  },
  callback = function()
    vim.opt_local.spell = true
    vim.opt_local.spelllang = { "en_us", "es" }
  end,
  desc = "Enable English and Spanish spelling for prose",
})
