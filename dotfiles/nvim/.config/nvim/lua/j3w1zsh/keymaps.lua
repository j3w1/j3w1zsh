local map = vim.keymap.set

local cheatsheet_path = vim.fn.stdpath("config") .. "/CHEATSHEET.md"

local function find_cheatsheet_window()
  local absolute_path = vim.fn.fnamemodify(cheatsheet_path, ":p")
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p")
    if name == absolute_path then
      return win
    end
  end
end

local function open_cheatsheet(cursor_line)
  if vim.fn.filereadable(cheatsheet_path) == 0 then
    vim.notify(
      "Cheat sheet not found at " .. cheatsheet_path,
      vim.log.levels.ERROR,
      { title = "j3w1zsh Neovim" }
    )
    return
  end

  local narrow = vim.o.columns < 140
  local buf = vim.fn.bufadd(cheatsheet_path)
  vim.fn.bufload(buf)
  vim.bo[buf].filetype = "markdown"

  local win
  if narrow then
    local width = math.max(1, math.min(vim.o.columns - 4, math.floor(vim.o.columns * 0.94)))
    local height = math.max(1, math.min(vim.o.lines - 4, math.floor(vim.o.lines * 0.90)))
    win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2) - 1,
      col = math.floor((vim.o.columns - width) / 2),
      style = "minimal",
      border = "rounded",
      title = " j3w1zsh Neovim Cheat Sheet ",
      title_pos = "center",
      zindex = 60,
    })
  else
    local width = math.min(68, math.max(56, math.floor(vim.o.columns * 0.36)))
    vim.cmd("topleft " .. width .. "vsplit")
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    vim.wo[win].winfixwidth = true
  end

  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].bufhidden = "wipe"
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.wo[win].linebreak = false
  vim.wo[win].winhighlight = "Normal:NormalFloat,CursorLine:NvimTreeCursorLine"

  if cursor_line then
    local last_line = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_win_set_cursor(win, { math.min(cursor_line, last_line), 0 })
  end

  map("n", "q", "<cmd>close<CR>", {
    buffer = buf,
    silent = true,
    desc = "Close cheat sheet",
  })
end

local function toggle_cheatsheet()
  local win = find_cheatsheet_window()
  if win then
    vim.api.nvim_win_close(win, false)
    return
  end
  open_cheatsheet()
end

local cheatsheet_group = vim.api.nvim_create_augroup("J3W1ZSHCheatsheet", { clear = true })
vim.api.nvim_create_autocmd("VimResized", {
  group = cheatsheet_group,
  callback = function()
    local win = find_cheatsheet_window()
    if not win then
      return
    end

    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    vim.api.nvim_win_close(win, false)
    vim.schedule(function()
      open_cheatsheet(cursor_line)
    end)
  end,
})

map({ "n", "x" }, "j", function()
  return vim.v.count == 0 and "gj" or "j"
end, { expr = true, silent = true, desc = "Down by visual line" })
map({ "n", "x" }, "k", function()
  return vim.v.count == 0 and "gk" or "k"
end, { expr = true, silent = true, desc = "Up by visual line" })

map("i", "jk", "<Esc>", { desc = "Leave insert mode" })
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

map("n", "<leader>w", "<cmd>write<CR>", { desc = "Save" })
map("n", "<leader>q", "<cmd>quit<CR>", { desc = "Quit window" })
map("n", "<leader>Q", "<cmd>quit!<CR>", { desc = "Quit without saving" })
map("n", "<leader>?", toggle_cheatsheet, { desc = "Toggle workstation cheat sheet" })

map("n", "<C-h>", "<C-w>h", { desc = "Focus left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Focus lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Focus upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Focus right window" })

map("n", "<leader>e", "<cmd>NvimTreeToggle<CR>", { desc = "Toggle file tree" })
map("n", "<leader>ef", "<cmd>NvimTreeFindFile<CR>", { desc = "Reveal current file" })

map("n", "<leader>ff", "<cmd>Telescope find_files hidden=true<CR>", { desc = "Find files" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", { desc = "Search text" })
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { desc = "Open buffers" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", { desc = "Search help" })
map("n", "<leader>fr", "<cmd>Telescope oldfiles<CR>", { desc = "Recent files" })

map("n", "<leader>z", "<cmd>ZenMode<CR>", { desc = "Focus writing mode" })
map("n", "<leader>mr", "<cmd>RenderMarkdown toggle<CR>", { desc = "Toggle rendered Markdown" })
map({ "n", "x" }, "<leader>mf", function()
  require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "Format document/code" })

map("n", "<leader>ss", "z=", { desc = "Spelling suggestions" })
map("n", "<leader>sa", "zg", { desc = "Add word to dictionary" })
map("n", "<leader>su", "zug", { desc = "Undo dictionary addition" })

map("n", "]b", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "[b", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Close buffer" })

map("n", "<leader>nh", "<cmd>checkhealth<CR>", { desc = "Open health report" })
map("n", "<leader>nl", "<cmd>Lazy<CR>", { desc = "Manage plugins" })
