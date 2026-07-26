local focus = require("ddd")

assert(vim.fn.exists(":DDD") == 2)
assert(vim.fn.exists(":DotDotDot") == 0)
assert(not focus.is_active())

local options = { vim.o.laststatus, vim.o.showtabline, vim.o.ruler }
assert(focus.open("60%+10%x50%-10%"))
assert(focus.is_active())

local current = assert(focus.current())
assert(vim.api.nvim_win_is_valid(current.window))
assert(vim.api.nvim_tabpage_is_valid(current.tab))
assert(vim.wo[current.window].colorcolumn == "")
assert(not vim.wo[current.window].winhighlight:find("ColorColumn:", 1, true))
assert(current.dimensions.width == math.floor(vim.o.columns * 0.6))
assert(current.dimensions.xoff == math.floor(vim.o.columns * 0.1))
assert(current.dimensions.yoff == math.floor(vim.o.lines * -0.1))

focus.close()
assert(not focus.is_active())
assert(#vim.api.nvim_list_tabpages() == 1)
assert(vim.o.laststatus == options[1])
assert(vim.o.showtabline == options[2])
assert(vim.o.ruler == options[3])

print("ddd.nvim smoke test: ok")
vim.cmd("qa!")
