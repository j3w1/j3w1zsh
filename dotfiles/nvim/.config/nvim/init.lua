require("j3w1zsh.platform")
vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

require("j3w1zsh.options")

local tracked_lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
local runtime_lock_dir = vim.fn.stdpath("state") .. "/j3w1zsh"
local runtime_lockfile = runtime_lock_dir .. "/lazy-lock.json"
local lockfile = runtime_lockfile
local reconciliation = vim.env.J3W1ZSH_NEOVIM_RECONCILE == "1"
local missing_install = vim.env.J3W1ZSH_NEOVIM_INSTALL_MISSING == "1"
local verification = vim.env.J3W1ZSH_NEOVIM_VERIFY == "1"
local managed_reconciliation = reconciliation or missing_install

local function tracked_lazy_state()
  local handle = assert(io.open(tracked_lockfile, "rb"), "Could not read the reviewed Neovim lock")
  local contents = handle:read("*a")
  handle:close()
  local ok, decoded = pcall(vim.json.decode, contents)
  assert(ok and type(decoded) == "table", "The reviewed Neovim lock is malformed")
  local entry = decoded["lazy.nvim"]
  assert(
    type(entry) == "table"
      and type(entry.branch) == "string"
      and entry.branch:match("^[A-Za-z0-9][A-Za-z0-9._/-]*$")
      and type(entry.commit) == "string"
      and entry.commit:match("^[0-9a-f]+$")
      and #entry.commit == 40,
    "The reviewed Neovim lock does not contain a valid lazy.nvim branch and commit"
  )
  return entry.branch, entry.commit
end

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local branch, commit = tracked_lazy_state()
  vim.fn.mkdir(lazypath, "p")
  local result = vim.fn.system({ "git", "-C", lazypath, "init" })
  if vim.v.shell_error == 0 then
    result = vim.fn.system({
      "git",
      "-C",
      lazypath,
      "remote",
      "add",
      "origin",
      "https://github.com/folke/lazy.nvim.git",
    })
  end
  if vim.v.shell_error == 0 then
    result = vim.fn.system({
      "git",
      "-C",
      lazypath,
      "fetch",
      "--filter=blob:none",
      "--no-tags",
      "origin",
      "refs/heads/" .. branch .. ":refs/remotes/origin/" .. branch,
    })
  end
  if vim.v.shell_error == 0 then
    result = vim.fn.system({ "git", "-C", lazypath, "remote", "set-head", "origin", branch })
  end
  if vim.v.shell_error == 0 then
    result = vim.fn.system({ "git", "-C", lazypath, "checkout", "--detach", commit })
  end
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Could not install the reviewed lazy.nvim commit:\n", "ErrorMsg" },
      { result, "WarningMsg" },
    }, true, {})
    return
  end
end
vim.opt.rtp:prepend(lazypath)

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

local plugins = require("j3w1zsh.plugins")
if managed_reconciliation then
  for _, plugin in ipairs(plugins) do
    if type(plugin) == "table" then
      plugin.lazy = true
    end
  end
end

require("lazy").setup(plugins, {
  lockfile = lockfile,
  local_spec = false,
  checker = { enabled = not managed_reconciliation and not verification, notify = false },
  change_detection = { notify = false },
  install = { missing = missing_install or (not reconciliation and not verification) },
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
