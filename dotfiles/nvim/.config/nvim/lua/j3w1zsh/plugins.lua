local p = require("j3w1zsh.theme").palette

return {
  {
    "nvim-tree/nvim-web-devicons",
    lazy = true,
    opts = { color_icons = true },
  },

  {
    "nvim-tree/nvim-tree.lua",
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      sort = { sorter = "case_sensitive" },
      sync_root_with_cwd = true,
      respect_buf_cwd = true,
      update_focused_file = { enable = true, update_root = false },
      view = {
        side = "right",
        width = 32,
        preserve_window_proportions = true,
        signcolumn = "no",
      },
      renderer = {
        group_empty = true,
        highlight_git = true,
        indent_markers = { enable = true },
        icons = {
          git_placement = "after",
          show = { file = true, folder = true, folder_arrow = true, git = true },
        },
      },
      filters = { dotfiles = false },
      diagnostics = { enable = true, show_on_dirs = true },
      git = { enable = true, ignore = false },
      actions = { open_file = { resize_window = false } },
    },
  },

  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = function()
      local theme = {
        normal = {
          a = { fg = p.bg, bg = p.bright, gui = "bold" },
          b = { fg = p.pale, bg = p.blood },
          c = { fg = p.fg, bg = p.bg_soft },
        },
        insert = { a = { fg = p.bg, bg = p.pale, gui = "bold" } },
        visual = { a = { fg = p.bg, bg = p.yellow, gui = "bold" } },
        replace = { a = { fg = p.pale, bg = p.accent, gui = "bold" } },
        command = { a = { fg = p.bg, bg = p.blue, gui = "bold" } },
        inactive = {
          a = { fg = p.fg_dim, bg = p.bg_soft },
          b = { fg = p.fg_dim, bg = p.bg_soft },
          c = { fg = p.fg_dim, bg = p.bg },
        },
      }

      local function word_count()
        if not vim.tbl_contains({ "markdown", "text", "asciidoc" }, vim.bo.filetype) then
          return ""
        end
        return tostring(vim.fn.wordcount().words) .. " words"
      end

      return {
        options = {
          theme = theme,
          globalstatus = true,
          component_separators = { left = "│", right = "│" },
          section_separators = { left = "", right = "" },
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch" },
          lualine_c = { { "filename", path = 1 } },
          lualine_x = { word_count, "diagnostics", "filetype" },
          lualine_y = { "progress" },
          lualine_z = { "location" },
        },
      }
    end,
  },

  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      delay = 350,
      spec = {
        { "<leader>b", group = "buffers" },
        { "<leader>c", group = "code" },
        { "<leader>e", group = "explorer" },
        { "<leader>f", group = "find" },
        { "<leader>m", group = "markdown" },
        { "<leader>n", group = "neovim" },
        { "<leader>s", group = "spelling" },
      },
    },
  },

  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons" },
    opts = {
      defaults = {
        border = true,
        color_devicons = true,
        path_display = { "smart" },
        layout_strategy = "vertical",
        layout_config = {
          vertical = { width = 0.92, height = 0.90, preview_cutoff = 32 },
        },
        mappings = {
          i = {
            ["<C-j>"] = "move_selection_next",
            ["<C-k>"] = "move_selection_previous",
          },
        },
      },
    },
  },

  {
    "saghen/blink.cmp",
    version = "1.*",
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = { "ribru17/blink-cmp-spell" },
    opts = {
      keymap = {
        preset = "enter",
        ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
        ["<C-n>"] = { "select_next", "fallback" },
        ["<C-p>"] = { "select_prev", "fallback" },
        ["<C-e>"] = { "hide", "fallback" },
      },
      appearance = { nerd_font_variant = "mono" },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 350 },
        menu = { border = "rounded", draw = { treesitter = { "lsp" } } },
      },
      fuzzy = { implementation = "lua" },
      sources = {
        default = { "lsp", "path", "snippets", "buffer", "spell" },
        providers = {
          spell = {
            name = "Spell",
            module = "blink-cmp-spell",
            opts = {
              use_cmp_spell_sorting = true,
              enable_in_context = function()
                return vim.tbl_contains(
                  { "markdown", "text", "asciidoc", "gitcommit" },
                  vim.bo.filetype
                )
              end,
            },
          },
        },
      },
      cmdline = { enabled = true },
    },
  },

  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "saghen/blink.cmp" },
    config = function()
      local capabilities = require("blink.cmp").get_lsp_capabilities()
      vim.lsp.config("*", { capabilities = capabilities })

      local servers = {
        marksman = {},
        lua_ls = {
          settings = {
            Lua = {
              runtime = { version = "LuaJIT" },
              diagnostics = { globals = { "vim" } },
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
            },
          },
        },
        pyright = {},
        ts_ls = {},
      }

      local executables = {
        marksman = "marksman",
        lua_ls = "lua-language-server",
        pyright = "pyright-langserver",
        ts_ls = "typescript-language-server",
      }

      for server, config in pairs(servers) do
        vim.lsp.config(server, config)
        if vim.fn.executable(executables[server]) == 1 then
          vim.lsp.enable(server)
        end
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local opts = { buffer = args.buf, silent = true }
          local function diagnostic_jump(count)
            vim.diagnostic.jump({ count = count, float = true })
          end
          vim.keymap.set("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Definition" }))
          vim.keymap.set("n", "gr", vim.lsp.buf.references, vim.tbl_extend("force", opts, { desc = "References" }))
          vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Documentation" }))
          vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "Rename" }))
          vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "Code action" }))
          vim.keymap.set("n", "[d", function()
            diagnostic_jump(-1)
          end, vim.tbl_extend("force", opts, { desc = "Previous diagnostic" }))
          vim.keymap.set("n", "]d", function()
            diagnostic_jump(1)
          end, vim.tbl_extend("force", opts, { desc = "Next diagnostic" }))
        end,
      })
    end,
  },

  {
    "echasnovski/mini.icons",
    version = false,
    lazy = true,
    opts = {},
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = { "echasnovski/mini.icons" },
    opts = {
      render_modes = { "n", "c", "t", "i" },
      sign = { enabled = false },
      heading = {
        enabled = true,
        position = "inline",
        icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
        width = "block",
        left_pad = 1,
        right_pad = 1,
      },
      bullet = {
        enabled = true,
        icons = { "●", "○", "◆", "◇" },
      },
      checkbox = { enabled = true },
      code = {
        enabled = true,
        sign = false,
        width = "block",
        left_pad = 1,
        right_pad = 1,
        border = "thin",
      },
      pipe_table = { enabled = true, preset = "round" },
      link = { enabled = true },
      latex = { enabled = false },
    },
  },

  {
    "jakewvincent/mkdnflow.nvim",
    ft = "markdown",
    opts = {
      modules = { maps = false },
      perspective = { priority = "current", fallback = "first" },
      links = { conceal = true, transform_explicit = false },
      new_file_template = {
        enabled = false,
        placeholders = { title = "link_title" },
        template = "# {{ title }}",
      },
      to_do = {
        statuses = {
          not_started = { marker = " " },
          in_progress = { marker = "-" },
          complete = { marker = { "X", "x" } },
        },
        status_order = { "not_started", "in_progress", "complete" },
        status_propagation = { up = true, down = false },
      },
      on_attach = function(bufnr)
        local function bmap(mode, lhs, rhs, desc)
          vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
        end
        bmap("n", "<CR>", "<cmd>MkdnEnter<CR>", "Open link or fold heading")
        bmap("n", "<BS>", "<cmd>MkdnGoBack<CR>", "Go back")
        bmap("n", "<Tab>", "<cmd>MkdnNextLink<CR>", "Next Markdown link")
        bmap("n", "<S-Tab>", "<cmd>MkdnPrevLink<CR>", "Previous Markdown link")
        bmap("n", "]]", "<cmd>MkdnNextHeading<CR>", "Next heading")
        bmap("n", "[[", "<cmd>MkdnPrevHeading<CR>", "Previous heading")
        bmap("n", "<leader>mt", "<cmd>MkdnToggleToDo<CR>", "Toggle task")
        bmap("x", "<leader>ml", ":MkdnCreateLink<CR>", "Create link")
        bmap("n", "<leader>mT", "<cmd>MkdnTableFormat<CR>", "Format table")
        bmap("n", "<leader>mb", "<cmd>MkdnGoBack<CR>", "Go back")
        bmap("n", "<leader>mn", "<cmd>enew<CR><cmd>setfiletype markdown<CR>", "New note")
      end,
    },
  },

  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    opts = {
      formatters_by_ft = {
        markdown = { "prettier" },
        json = { "prettier" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        css = { "prettier" },
        html = { "prettier" },
        lua = { "stylua", stop_after_first = true },
        python = { "black", stop_after_first = true },
      },
      default_format_opts = { lsp_format = "fallback" },
      formatters = {
        prettier = { prepend_args = { "--prose-wrap", "preserve", "--print-width", "100" } },
      },
    },
  },

  {
    "folke/zen-mode.nvim",
    cmd = "ZenMode",
    opts = {
      window = {
        backdrop = 1,
        width = 0.86,
        height = 1,
        options = {
          number = false,
          relativenumber = false,
          signcolumn = "no",
          cursorline = true,
        },
      },
      plugins = {
        options = { enabled = true, laststatus = 0 },
        twilight = { enabled = false },
        gitsigns = { enabled = false },
        tmux = { enabled = false },
      },
    },
  },

  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {
      check_ts = false,
      disable_filetype = { "TelescopePrompt" },
    },
  },

  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "│" },
        change = { text = "│" },
        delete = { text = "▁" },
        topdelete = { text = "▔" },
        changedelete = { text = "~" },
        untracked = { text = "┆" },
      },
    },
  },
}
