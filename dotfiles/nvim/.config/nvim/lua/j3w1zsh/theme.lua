local M = {}

local roles = {
  background = "#000000",
  foreground = "#FFF1F1",
  blood = "#B00020",
  bright_red = "#FF334D",
  selection = "#3A0010",
  muted = "#DFA0A0",
  orange = "#FF8C42",
  blue = "#5FAFFF",
  semantic_green = "#50FA7B",
}

local generated = vim.fn.expand("~/.config/j3w1zsh/generated/theme/theme.lua")
local loader = loadfile(generated)
if loader then
  local ok, candidate = pcall(loader)
  if ok and type(candidate) == "table" then
    local valid = true
    for name in pairs(roles) do
      if type(candidate[name]) ~= "string" or not candidate[name]:match("^#%x%x%x%x%x%x$") then
        valid = false
        break
      end
    end
    if valid then
      roles = candidate
    end
  end
end

M.palette = {
  bg = roles.background,
  bg_alt = roles.background,
  bg_soft = roles.selection,
  fg = roles.foreground,
  fg_dim = roles.muted,
  accent = roles.blood,
  blood = roles.blood,
  selection = roles.selection,
  bright = roles.bright_red,
  pale = roles.foreground,
  muted = roles.muted,
  yellow = roles.orange,
  green = roles.semantic_green,
  blue = roles.blue,
}

function M.setup()
  local p = M.palette
  vim.cmd("highlight clear")
  if vim.fn.exists("syntax_on") == 1 then
    vim.cmd("syntax reset")
  end
  vim.g.colors_name = "j3w1zsh"

  local groups = {
    Normal = { fg = p.fg, bg = p.bg },
    NormalNC = { fg = p.fg_dim, bg = p.bg },
    NormalFloat = { fg = p.fg, bg = p.bg_alt },
    FloatBorder = { fg = p.accent, bg = p.bg_alt },
    FloatTitle = { fg = p.pale, bg = p.bg_alt, bold = true },
    CursorLine = { bg = p.bg_soft },
    CursorColumn = { bg = p.bg_soft },
    ColorColumn = { bg = p.bg_soft },
    LineNr = { fg = p.muted, bg = p.bg },
    CursorLineNr = { fg = p.bright, bg = p.bg, bold = true },
    SignColumn = { fg = p.accent, bg = p.bg },
    Visual = { fg = p.pale, bg = p.blood },
    Search = { fg = p.bg, bg = p.bright, bold = true },
    IncSearch = { fg = p.bg, bg = p.yellow, bold = true },
    CurSearch = { fg = p.bg, bg = p.yellow, bold = true },
    MatchParen = { fg = p.pale, bg = p.accent, bold = true },
    WinSeparator = { fg = p.blood, bg = p.bg },
    StatusLine = { fg = p.pale, bg = p.blood, bold = true },
    StatusLineNC = { fg = p.fg_dim, bg = p.bg_soft },
    Pmenu = { fg = p.fg, bg = p.bg_alt },
    PmenuSel = { fg = p.pale, bg = p.accent, bold = true },
    PmenuSbar = { bg = p.bg_soft },
    PmenuThumb = { bg = p.accent },
    Folded = { fg = p.fg_dim, bg = p.bg_soft, italic = true },
    NonText = { fg = p.muted },
    SpecialKey = { fg = p.muted },
    Directory = { fg = p.bright, bold = true },
    Title = { fg = p.bright, bold = true },
    Comment = { fg = p.fg_dim, italic = true },
    Constant = { fg = p.yellow },
    String = { fg = p.green },
    Identifier = { fg = p.pale },
    Function = { fg = p.bright },
    Statement = { fg = p.bright, bold = true },
    PreProc = { fg = p.yellow },
    Type = { fg = p.blue },
    Special = { fg = p.yellow },
    Underlined = { fg = p.blue, underline = true },
    Error = { fg = p.pale, bg = p.accent, bold = true },
    Todo = { fg = p.bg, bg = p.yellow, bold = true },

    SpellBad = { undercurl = true, sp = p.bright },
    SpellCap = { undercurl = true, sp = p.yellow },
    SpellRare = { undercurl = true, sp = p.blue },
    SpellLocal = { undercurl = true, sp = p.green },
    DiagnosticError = { fg = p.bright },
    DiagnosticWarn = { fg = p.yellow },
    DiagnosticInfo = { fg = p.blue },
    DiagnosticHint = { fg = p.green },
    DiagnosticUnderlineError = { undercurl = true, sp = p.bright },
    DiagnosticUnderlineWarn = { undercurl = true, sp = p.yellow },

    ["@markup.heading.1.markdown"] = { fg = p.bright, bold = true },
    ["@markup.heading.2.markdown"] = { fg = p.pale, bold = true },
    ["@markup.heading.3.markdown"] = { fg = p.yellow, bold = true },
    ["@markup.heading.4.markdown"] = { fg = p.blue, bold = true },
    ["@markup.heading.5.markdown"] = { fg = p.green, bold = true },
    ["@markup.heading.6.markdown"] = { fg = p.fg_dim, bold = true },
    ["@markup.strong"] = { fg = p.pale, bold = true },
    ["@markup.italic"] = { fg = p.fg_dim, italic = true },
    ["@markup.link"] = { fg = p.blue, underline = true },
    ["@markup.raw"] = { fg = p.green },
    ["@markup.list"] = { fg = p.bright },

    RenderMarkdownH1Bg = { fg = p.pale, bg = p.blood, bold = true },
    RenderMarkdownH2Bg = { fg = p.pale, bg = p.bg_soft, bold = true },
    RenderMarkdownH3Bg = { fg = p.yellow, bg = p.bg_alt, bold = true },
    RenderMarkdownCode = { bg = p.bg_alt },
    RenderMarkdownCodeInline = { fg = p.green, bg = p.bg_alt },
    RenderMarkdownBullet = { fg = p.bright },
    RenderMarkdownChecked = { fg = p.green },
    RenderMarkdownUnchecked = { fg = p.fg_dim },
    RenderMarkdownTableHead = { fg = p.pale, bold = true },
    RenderMarkdownTableRow = { fg = p.fg_dim },

    NvimTreeNormal = { fg = p.fg_dim, bg = p.bg_alt },
    NvimTreeNormalNC = { fg = p.fg_dim, bg = p.bg_alt },
    NvimTreeRootFolder = { fg = p.bright, bold = true },
    NvimTreeFolderName = { fg = p.pale },
    NvimTreeOpenedFolderName = { fg = p.bright, bold = true },
    NvimTreeIndentMarker = { fg = p.muted },
    NvimTreeCursorLine = { fg = p.pale, bg = p.selection, bold = true },
    NvimTreeWinSeparator = { fg = p.blood, bg = p.bg_alt },

    BlinkCmpMenu = { fg = p.fg, bg = p.bg_alt },
    BlinkCmpMenuBorder = { fg = p.accent, bg = p.bg_alt },
    BlinkCmpMenuSelection = { fg = p.pale, bg = p.accent, bold = true },
    BlinkCmpLabelMatch = { fg = p.bright, bold = true },
    BlinkCmpKind = { fg = p.yellow },
    BlinkCmpDoc = { fg = p.fg, bg = p.bg_alt },
    BlinkCmpDocBorder = { fg = p.accent, bg = p.bg_alt },

    WhichKey = { fg = p.bright },
    WhichKeyGroup = { fg = p.yellow },
    WhichKeyDesc = { fg = p.fg },
    WhichKeyBorder = { fg = p.accent },
    TelescopeNormal = { fg = p.fg, bg = p.bg_alt },
    TelescopeBorder = { fg = p.accent, bg = p.bg_alt },
    TelescopeSelection = { fg = p.pale, bg = p.blood, bold = true },
    TelescopeMatching = { fg = p.bright, bold = true },
    TelescopePromptPrefix = { fg = p.bright },
    GitSignsAdd = { fg = p.green },
    GitSignsChange = { fg = p.yellow },
    GitSignsDelete = { fg = p.bright },
  }

  for group, spec in pairs(groups) do
    vim.api.nvim_set_hl(0, group, spec)
  end
end

return M
