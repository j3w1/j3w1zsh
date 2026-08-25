require("j3w1zsh.platform")
vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

require("j3w1zsh.options")

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local result = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Could not install lazy.nvim:\n", "ErrorMsg" },
      { result, "WarningMsg" },
    }, true, {})
    return
  end
end
vim.opt.rtp:prepend(lazypath)

local tracked_lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
local runtime_lock_dir = vim.fn.stdpath("state") .. "/j3w1zsh"
local runtime_lockfile = runtime_lock_dir .. "/lazy-lock.json"
local lockfile = runtime_lockfile

-- Normal Neovim sessions use device-local runtime state. This keeps plugin maintenance from
-- dirtying the Git checkout through the managed ~/.config/nvim symlink. Repository maintainers
-- opt into the tracked lockfile through scripts/update-neovim-lock.sh.
if vim.env.J3W1ZSH_MAINTAINER == "1" then
  lockfile = tracked_lockfile
else
  vim.fn.mkdir(runtime_lock_dir, "p")
  if not vim.uv.fs_stat(runtime_lockfile) and vim.uv.fs_stat(tracked_lockfile) then
    local copied, copy_error = vim.uv.fs_copyfile(tracked_lockfile, runtime_lockfile)
    if not copied then
      vim.notify("Could not seed j3w1zsh's runtime plugin lock: " .. copy_error, vim.log.levels.WARN)
    end
  end
end

require("lazy").setup(require("j3w1zsh.plugins"), {
  lockfile = lockfile,
  checker = { enabled = true, notify = false },
  change_detection = { notify = false },
  install = { missing = true },
  ui = { border = "rounded" },
  rocks = { enabled = false },
})

require("j3w1zsh.keymaps")
require("j3w1zsh.autocmds")
require("j3w1zsh.theme").setup()

vim.api.nvim_create_autocmd("User", {
  pattern = "LazyDone",
  callback = function()
    require("j3w1zsh.theme").setup()
  end,
})
