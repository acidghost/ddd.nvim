# ddd.nvim

Distraction-free writing for Neovim, inspired by
[goyo.vim](https://github.com/junegunn/goyo.vim).

This is a Lua implementation designed around Neovim rather than a line-for-line
Vimscript port. It opens the current buffer in a centered floating window on a
temporary backdrop tab, leaving the original tab and split layout untouched.
Highlights are scoped to its windows, so entering and leaving focus mode does
not reload or modify your colorscheme.

## Requirements

- Neovim 0.9 or newer

## Installation

### lazy.nvim

```lua
{
  "your-name/ddd.nvim",
  opts = {},
  keys = {
    { "<leader>z", "<cmd>DDD<cr>", desc = "Focus mode" },
  },
}
```

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({ "https://github.com/your-name/ddd.nvim" })
require("ddd").setup()
```

## Usage

```vim
:DDD                 " Toggle focus mode
:DDD 100             " Set text width
:DDD 100x30          " Set width and height
:DDD 60%+10%x80%     " Percentages and offsets
:DDD!                " Leave focus mode
```

Dimension expressions use this syntax:

```text
[WIDTH][XOFFSET][x[HEIGHT][YOFFSET]]
```

Each value may be absolute or a percentage. Offsets require `+` or `-`.

While active, the usual `[count]<C-w>>`, `<C-w><`, `<C-w>+`, and `<C-w>-`
mappings resize the writing area. `<C-w>=` restores the requested dimensions.
Closing the floating window with `:q`, closing its tab, or changing tabs exits
focus mode cleanly.

## Configuration

```lua
require("ddd").setup({
  width = 80,
  height = "85%",

  -- Preserve the current window's number/relativenumber settings.
  line_numbers = false,

  -- Used when Normal has a transparent background.
  background = "black",

  decoration = {
    elements = { "~" },
    density = 0, -- 0..1
  },

  hooks = {
    enter = function()
      -- vim.cmd("Limelight")
    end,
    leave = function()
      -- vim.cmd("Limelight!")
    end,
  },
})
```

Instead of `height`, asymmetric margins can be configured:

```lua
require("ddd").setup({
  margin_top = 4,
  margin_bottom = 4,
})
```

The corresponding `g:ddd_*` variables can also be used from Vimscript:

- `g:ddd_width`, `g:ddd_height`
- `g:ddd_margin_top`, `g:ddd_margin_bottom`
- `g:ddd_linenr`, `g:ddd_bg`
- `g:ddd_decoration_elements`, `g:ddd_decoration_density`

## Lua API

```lua
local focus = require("ddd")

focus.open("100x80%")
focus.resize("120")
focus.close()
focus.toggle()
focus.is_active()
focus.current() -- tab, window, backdrop, and current dimensions
```

## Events

These `User` events are emitted after hooks:

```vim
autocmd User DDDEnter lua vim.opt_local.spell = true
autocmd User DDDLeave echo "Back to work"
```

Statusline and sign plugins are not detected by name or mutated globally; use
hooks/events if an integration needs explicit control.

## Why this differs from goyo.vim

- Uses Neovim windows and buffers through the Lua API.
- Uses one centered float instead of four spacer splits.
- Uses per-window `winhighlight` groups instead of changing global highlights
  and reloading the colorscheme on exit.
- Keeps the original tab, splits, local options, and cursor location intact.
- Provides Lua setup, hooks, and a small programmatic API.

## License

MIT. The original design and behavior are derived from goyo.vim by Junegunn
Choi; see [LICENSE](LICENSE).
