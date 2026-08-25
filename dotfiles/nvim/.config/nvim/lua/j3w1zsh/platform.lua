-- Clipboard integration shared by Windows WSL and the Termux app on Android.
local is_wsl = vim.fn.has("wsl") == 1
local is_termux = vim.env.PREFIX ~= nil
  and vim.env.PREFIX:match("/com%.termux/files/usr$") ~= nil

local copy_command
local paste_command
local clipboard_name
local platform_name

if is_wsl and vim.fn.executable("clip.exe") == 1 then
  copy_command = { "clip.exe" }
  paste_command = {
    "powershell.exe",
    "-NoLogo",
    "-NoProfile",
    "-Command",
    "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-Clipboard -Raw",
  }
  clipboard_name = "Windows clipboard through WSL"
  platform_name = "Windows"
elseif is_termux and vim.fn.executable("termux-clipboard-set") == 1 then
  copy_command = { "termux-clipboard-set" }
  paste_command = { "termux-clipboard-get" }
  clipboard_name = "Android clipboard through Termux:API"
  platform_name = "Android"
else
  return
end

vim.g.clipboard = {
  name = clipboard_name,
  copy = {
    ["+"] = copy_command,
    ["*"] = copy_command,
  },
  paste = {
    ["+"] = paste_command,
    ["*"] = paste_command,
  },
  cache_enabled = 0,
}

vim.opt.clipboard = "unnamedplus"

vim.keymap.set("n", "<C-c>", '"+yy', {
  silent = true,
  desc = "Copy current line to " .. platform_name,
})

vim.keymap.set("x", "<C-c>", '"+y', {
  silent = true,
  desc = "Copy selection to " .. platform_name,
})

vim.keymap.set("n", "<C-v>", '"+p', {
  silent = true,
  desc = "Paste from " .. platform_name,
})

vim.keymap.set("x", "<C-v>", '"+P', {
  silent = true,
  desc = "Replace selection from " .. platform_name,
})

vim.keymap.set("i", "<C-v>", "<C-r>+", {
  silent = true,
  desc = "Paste from " .. platform_name,
})

vim.keymap.set("c", "<C-v>", "<C-r>+", {
  silent = true,
  desc = "Paste from " .. platform_name,
})

-- Preserve Visual Block mode after assigning Ctrl-V to system paste.
vim.keymap.set({ "n", "x" }, "<C-q>", "<C-v>", {
  silent = true,
  desc = "Visual Block mode",
})
