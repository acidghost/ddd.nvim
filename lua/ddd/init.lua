---@alias ddd.Size integer|string
---@alias ddd.HookName "enter"|"leave"
---@alias ddd.Cursor [integer, integer]

---@class ddd.Decoration
---@field elements string[]
---@field density number

---@class ddd.DecorationOptions
---@field elements? string[]
---@field density? number

---@class ddd.Hooks
---@field enter? fun()
---@field leave? fun()

---@class ddd.Config
---@field width ddd.Size
---@field height ddd.Size
---@field margin_top? ddd.Size
---@field margin_bottom? ddd.Size
---@field line_numbers boolean
---@field background string
---@field decoration ddd.Decoration
---@field hooks ddd.Hooks
---@field _height_explicit? boolean

---@class ddd.ConfigOptions
---@field width? ddd.Size
---@field height? ddd.Size
---@field margin_top? ddd.Size
---@field margin_bottom? ddd.Size
---@field line_numbers? boolean
---@field background? string
---@field decoration? ddd.DecorationOptions
---@field hooks? ddd.Hooks

---@class ddd.Dimensions
---@field width integer
---@field height integer
---@field xoff integer
---@field yoff integer

---@class ddd.State
---@field original_tab integer
---@field original_win integer
---@field buffer integer
---@field cursor ddd.Cursor
---@field options table<string, any>
---@field dim ddd.Dimensions
---@field expression string
---@field show_number boolean
---@field show_relativenumber boolean
---@field closing boolean
---@field tab? integer
---@field backdrop_win? integer
---@field backdrop_buf? integer
---@field focus_win? integer

---@class ddd.Current
---@field tab integer
---@field window integer
---@field backdrop integer
---@field dimensions ddd.Dimensions

---@class ddd
local M = {}

---@type ddd.Config
local defaults = {
  width = 80,
  height = "85%",
  line_numbers = false,
  background = "black",
  decoration = {
    elements = { "~" },
    density = 0,
  },
  hooks = {},
}

---@type ddd.Config
local config = vim.deepcopy(defaults)
---@type ddd.State?
local state
---@type string
local group_name = "ddd.nvim"
---@type string[]
local mapped_keys = {}

---@param message string
---@param level? integer
local function notify(message, level)
  vim.notify("ddd.nvim: " .. message, level or vim.log.levels.WARN)
end

---@param win? integer
---@return boolean?
local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

---@param buf? integer
---@return boolean?
local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

---@param tab? integer
---@return boolean?
local function valid_tab(tab)
  return tab and vim.api.nvim_tabpage_is_valid(tab)
end

---@param win? integer
---@param name string
---@param value any
local function set_win_option(win, name, value)
  if valid_win(win) then
    pcall(vim.api.nvim_set_option_value, name, value, { win = win })
  end
end

---@generic T
---@param name string
---@param fallback T
---@return T
local function global(name, fallback)
  local value = vim.g["ddd_" .. name]
  if value == nil then
    return fallback
  end
  return value
end

---@param value ddd.Size
---@param limit integer
---@return integer
local function relative_size(value, limit)
  if type(value) == "number" then
    return math.floor(value)
  end
  value = tostring(value)
  local percent = value:match("^([+-]?%d+)%%$")
  if percent then
    return math.floor(limit * assert(tonumber(percent), "invalid percentage") / 100)
  end
  return math.floor(assert(tonumber(value), "invalid size: " .. value))
end

---@return ddd.Dimensions
local function dimensions_default()
  local columns = vim.o.columns
  local lines = vim.o.lines
  local layout_lines = math.max(1, lines - math.max(1, vim.o.cmdheight))
  local margin_top = global("margin_top", config.margin_top)
  local margin_bottom = global("margin_bottom", config.margin_bottom)
  local configured_height = global("height", config.height)
  local use_margins = (margin_top ~= nil or margin_bottom ~= nil) and not config._height_explicit

  local height, yoff
  if use_margins and vim.g.ddd_height == nil then
    local top = math.max(0, relative_size(margin_top or 4, layout_lines) or 0)
    local bottom = math.max(0, relative_size(margin_bottom or 4, layout_lines) or 0)
    height = layout_lines - top - bottom
    yoff = math.floor((top - bottom) / 2)
  else
    height = relative_size(configured_height or "85%", lines)
    yoff = 0
  end

  return {
    width = relative_size(global("width", config.width), columns),
    height = height,
    xoff = 0,
    yoff = yoff,
  }
end

---@param value string
---@return string? size
---@return string? offset
local function parse_axis(value)
  local size = value:match("^%d+%%?")
  local rest = size and value:sub(#size + 1) or value
  local offset
  if rest ~= "" then
    offset = rest:match("^[+-]%d+%%?$")
    if not offset then
      return nil
    end
  end
  return size, offset
end

---@param expression? string
---@return ddd.Dimensions?
local function parse_dimensions(expression)
  local dim = dimensions_default()
  expression = vim.trim(expression or "")
  if expression == "" then
    return dim
  end

  local first_x = expression:find("x", 1, true)
  local left, right
  if first_x then
    if expression:find("x", first_x + 1, true) then
      return nil
    end
    left = expression:sub(1, first_x - 1)
    right = expression:sub(first_x + 1)
  else
    left = expression
  end

  local width, xoff = parse_axis(left)
  if width == nil and xoff == nil and left ~= "" then
    return nil
  end
  if not first_x and width == nil and xoff == nil then
    return nil
  end

  local height, yoff
  if first_x then
    height, yoff = parse_axis(right)
    if height == nil and yoff == nil and right ~= "" then
      return nil
    end
  end

  if width then
    dim.width = relative_size(width, vim.o.columns)
  end
  if xoff then
    dim.xoff = relative_size(xoff, vim.o.columns)
  end
  if height then
    dim.height = relative_size(height, vim.o.lines)
  end
  if yoff then
    dim.yoff = relative_size(yoff, vim.o.lines)
  end
  return dim
end

---@return string? foreground
---@return string background
local function normal_colors()
  local ok, normal = pcall(vim.api.nvim_get_hl, 0, { name = "Normal", link = false })
  if not ok then
    normal = {}
  end
  local background = global("bg", config.background)
  local bg = normal.bg and string.format("#%06x", normal.bg) or background
  local fg = normal.fg and string.format("#%06x", normal.fg) or nil
  return fg, bg
end

---@return nil
local function update_highlights()
  local fg, bg = normal_colors()
  vim.api.nvim_set_hl(0, "DDDBackdrop", { fg = fg, bg = bg, default = false })
  vim.api.nvim_set_hl(0, "DDDBackdropFill", { fg = bg, bg = bg, default = false })
  vim.api.nvim_set_hl(0, "DDDHidden", { fg = bg, default = false })
end

---@return string[] elements
---@return number density
local function decoration_options()
  local decoration = config.decoration or {}
  local elements = global("decoration_elements", decoration.elements or { "~" })
  local density = tonumber(global("decoration_density", decoration.density or 0)) or 0
  density = math.max(0, math.min(1, density))
  if type(elements) ~= "table" or #elements == 0 then
    elements = { "~" }
  end
  return elements, density
end

---@return nil
local function decorate_backdrop()
  if not state or not valid_buf(state.backdrop_buf) then
    return
  end

  local elements, density = decoration_options()
  local width = math.max(vim.o.columns, 1)
  local height = math.max(vim.o.lines, 1)
  local lines = {}

  if density > 0 then
    local cell_width = 1
    for _, element in ipairs(elements) do
      cell_width = math.max(cell_width, vim.fn.strdisplaywidth(tostring(element)))
    end

    for _ = 1, height do
      local cells = {}
      for _ = 1, math.ceil(width / cell_width) do
        if math.random() < density then
          local element = tostring(elements[math.random(#elements)])
          local element_width = vim.fn.strdisplaywidth(element)
          local room = math.max(0, cell_width - element_width)
          local left = room > 0 and math.random(0, room) or 0
          cells[#cells + 1] = string.rep(" ", left) .. element .. string.rep(" ", room - left)
        else
          cells[#cells + 1] = string.rep(" ", cell_width)
        end
      end
      lines[#lines + 1] = table.concat(cells)
    end
  else
    lines = { "" }
  end

  vim.bo[state.backdrop_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.backdrop_buf, 0, -1, false, lines)
  vim.bo[state.backdrop_buf].modifiable = false
end

---@return integer width
---@return integer height
local function usable_size()
  -- With the tabline and statusline hidden, only the command line is outside
  -- the editor grid available to a relative='editor' floating window.
  local width = math.max(1, vim.o.columns)
  local height = math.max(1, vim.o.lines - math.max(1, vim.o.cmdheight))
  return width, height
end

---@return integer
local function number_column_width()
  if not state or not state.show_number then
    return 0
  end
  local line_count = valid_buf(state.buffer) and vim.api.nvim_buf_line_count(state.buffer) or 1
  return math.max(#tostring(line_count) + 1, vim.o.numberwidth)
end

---@return nil
local function resize()
  if not state or not valid_win(state.focus_win) then
    return
  end

  local available_width, available_height = usable_size()
  state.dim.width = math.max(2, math.min(math.floor(state.dim.width), available_width))
  state.dim.height = math.max(2, math.min(math.floor(state.dim.height), available_height))

  local total_width = math.min(available_width, state.dim.width + number_column_width())
  local max_xoff = math.max(0, math.floor((available_width - total_width) / 2))
  local max_yoff = math.max(0, math.floor((available_height - state.dim.height) / 2))
  local xoff = math.max(-max_xoff, math.min(max_xoff, math.floor(state.dim.xoff or 0)))
  local yoff = math.max(-max_yoff, math.min(max_yoff, math.floor(state.dim.yoff or 0)))

  vim.api.nvim_win_set_config(state.focus_win, {
    relative = "editor",
    width = total_width,
    height = state.dim.height,
    col = math.floor((available_width - total_width) / 2) + xoff,
    row = math.floor((available_height - state.dim.height) / 2) + yoff,
  })
  decorate_backdrop()
end

---@return nil
local function apply_focus_options()
  if not state or not valid_win(state.focus_win) then
    return
  end
  local win = state.focus_win
  set_win_option(win, "number", state.show_number)
  set_win_option(win, "relativenumber", state.show_relativenumber)
  set_win_option(win, "colorcolumn", "")
  set_win_option(win, "cursorline", false)
  set_win_option(win, "cursorcolumn", false)
  set_win_option(win, "foldcolumn", "0")
  set_win_option(win, "signcolumn", "no")
  set_win_option(win, "statusline", " ")
  set_win_option(win, "winbar", "")
  set_win_option(
    win,
    "winhighlight",
    table.concat({
      "NonText:DDDHidden",
      "EndOfBuffer:DDDHidden",
      "FoldColumn:DDDHidden",
      "SignColumn:DDDHidden",
      "StatusLine:DDDHidden",
      "StatusLineNC:DDDHidden",
    }, ",")
  )
end

---@param name ddd.HookName
---@return nil
local function run_hook(name)
  local hook = config.hooks and config.hooks[name]
  if type(hook) == "function" then
    local ok, err = pcall(hook)
    if not ok then
      notify(name .. " hook failed: " .. tostring(err), vim.log.levels.ERROR)
    end
  end
end

---@param name "Enter"|"Leave"
---@return nil
local function emit(name)
  pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "DDD" .. name, modeline = false })
end

---@return nil
local function restore_mappings()
  for _, lhs in ipairs(mapped_keys) do
    pcall(vim.keymap.del, "n", lhs)
  end
  mapped_keys = {}
end

---@param lhs string
---@param callback fun()
---@return nil
local function map_if_free(lhs, callback)
  if vim.fn.maparg(lhs, "n") == "" then
    vim.keymap.set("n", lhs, callback, { silent = true, desc = "ddd.nvim" })
    mapped_keys[#mapped_keys + 1] = lhs
  end
end

---@return nil
local function install_mappings()
  for _, key in ipairs({ "R", "H", "J", "K", "L", "|", "_" }) do
    map_if_free("<C-w>" .. key, function() end)
  end
  map_if_free("<C-w>=", function()
    if state then
      local dim = parse_dimensions(state.expression)
      if dim then
        state.dim = dim
        resize()
      end
    end
  end)
  map_if_free("<C-w>>", function()
    if state then
      state.dim.width = state.dim.width + 2 * vim.v.count1
      resize()
    end
  end)
  map_if_free("<C-w><", function()
    if state then
      state.dim.width = state.dim.width - 2 * vim.v.count1
      resize()
    end
  end)
  map_if_free("<C-w>+", function()
    if state then
      state.dim.height = state.dim.height + 2 * vim.v.count1
      resize()
    end
  end)
  map_if_free("<C-w>-", function()
    if state then
      state.dim.height = state.dim.height - 2 * vim.v.count1
      resize()
    end
  end)
end

---@param saved table<string, any>
---@return nil
local function restore_options(saved)
  -- Set minima first so restoring preferred dimensions cannot violate them.
  for _, name in ipairs({ "winminwidth", "winminheight", "winwidth", "winheight" }) do
    if saved[name] ~= nil then
      pcall(function()
        vim.o[name] = saved[name]
      end)
    end
  end
  for name, value in pairs(saved) do
    if
      name ~= "winminwidth"
      and name ~= "winminheight"
      and name ~= "winwidth"
      and name ~= "winheight"
    then
      pcall(function()
        vim.o[name] = value
      end)
    end
  end
end

---@return nil
local function close_internal()
  if not state or state.closing then
    return
  end
  state.closing = true
  local closing = state
  local target_tab = vim.api.nvim_get_current_tabpage()
  local cursor = valid_win(closing.focus_win) and vim.api.nvim_win_get_cursor(closing.focus_win)
    or closing.cursor

  pcall(vim.api.nvim_del_augroup_by_name, group_name)
  restore_mappings()

  if valid_tab(closing.tab) then
    if #vim.api.nvim_list_tabpages() == 1 then
      vim.cmd("tabnew")
      target_tab = vim.api.nvim_get_current_tabpage()
    end
    if valid_tab(closing.tab) then
      pcall(vim.api.nvim_set_current_tabpage, closing.tab)
      pcall(function()
        vim.cmd("tabclose")
      end)
    end
  end

  if valid_tab(target_tab) and target_tab ~= closing.tab then
    pcall(vim.api.nvim_set_current_tabpage, target_tab)
  elseif valid_tab(closing.original_tab) then
    pcall(vim.api.nvim_set_current_tabpage, closing.original_tab)
  end

  if
    cursor
    and valid_win(closing.original_win)
    and vim.api.nvim_win_get_buf(closing.original_win) == closing.buffer
  then
    pcall(vim.api.nvim_win_set_cursor, closing.original_win, cursor)
  end

  restore_options(closing.options)
  state = nil
  run_hook("leave")
  emit("Leave")
  vim.cmd("redraw")
end

---@return nil
local function create_autocmds()
  local focus_win = assert(state and state.focus_win, "focus window is not initialized")
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      vim.schedule(resize)
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      update_highlights()
      vim.schedule(decorate_backdrop)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = group,
    callback = function(args)
      if not state or state.closing then
        return
      end
      if valid_win(state.focus_win) and vim.api.nvim_get_current_win() == state.focus_win then
        apply_focus_options()
      elseif
        args.event == "WinEnter"
        and valid_tab(state.tab)
        and vim.api.nvim_get_current_tabpage() == state.tab
        and valid_win(state.focus_win)
      then
        vim.schedule(function()
          if state and not state.closing and valid_win(state.focus_win) then
            pcall(vim.api.nvim_set_current_win, state.focus_win)
          end
        end)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "WinLeave" }, {
    group = group,
    callback = function()
      if
        state
        and valid_win(state.focus_win)
        and vim.api.nvim_get_current_win() == state.focus_win
      then
        state.cursor = vim.api.nvim_win_get_cursor(state.focus_win)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(focus_win),
    callback = function()
      vim.schedule(close_internal)
    end,
  })
  vim.api.nvim_create_autocmd("TabLeave", {
    group = group,
    callback = function()
      if state and not state.closing and vim.api.nvim_get_current_tabpage() == state.tab then
        vim.schedule(close_internal)
      end
    end,
  })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      if state and not state.closing and not valid_tab(state.tab) then
        vim.schedule(close_internal)
      end
    end,
  })
  vim.api.nvim_create_autocmd("TermClose", {
    group = group,
    callback = function()
      vim.schedule(resize)
    end,
  })
end

---Opens focus mode or resizes the active focus window.
---@param expression? string Dimension expression.
---@return boolean? success
function M.open(expression)
  if state then
    if expression and vim.trim(expression) ~= "" then
      return M.resize(expression)
    end
    return
  end

  expression = expression or ""
  local dim = parse_dimensions(expression)
  if not dim then
    notify("invalid dimension expression: " .. expression)
    return false
  end

  local original_win = vim.api.nvim_get_current_win()
  local original_number = vim.wo[original_win].number
  local original_relativenumber = vim.wo[original_win].relativenumber
  local keep_numbers = global("linenr", config.line_numbers) == true
    or global("linenr", config.line_numbers) == 1
  ---@type table<string, any>
  local saved_options = {}
  for _, name in ipairs({
    "laststatus",
    "showtabline",
    "ruler",
    "winminwidth",
    "winwidth",
    "winminheight",
    "winheight",
    "sidescroll",
    "sidescrolloff",
  }) do
    saved_options[name] = vim.o[name]
  end

  ---@type ddd.State
  local pending = {
    original_tab = vim.api.nvim_get_current_tabpage(),
    original_win = original_win,
    buffer = vim.api.nvim_get_current_buf(),
    cursor = vim.api.nvim_win_get_cursor(original_win),
    options = saved_options,
    dim = dim,
    expression = expression,
    show_number = keep_numbers and original_number,
    show_relativenumber = keep_numbers and original_relativenumber,
    closing = false,
  }

  vim.o.laststatus = 0
  vim.o.showtabline = 0
  vim.o.ruler = false
  vim.o.winminwidth = 1
  vim.o.winwidth = 1
  vim.o.winminheight = 1
  vim.o.winheight = 1
  vim.o.sidescroll = 1
  vim.o.sidescrolloff = 0

  local ok, err = pcall(function()
    vim.cmd("tabnew")
    pending.tab = vim.api.nvim_get_current_tabpage()
    pending.backdrop_win = vim.api.nvim_get_current_win()
    pending.backdrop_buf = vim.api.nvim_get_current_buf()

    vim.bo[pending.backdrop_buf].buftype = "nofile"
    vim.bo[pending.backdrop_buf].bufhidden = "wipe"
    vim.bo[pending.backdrop_buf].swapfile = false
    vim.bo[pending.backdrop_buf].buflisted = false
    vim.bo[pending.backdrop_buf].modifiable = false
    set_win_option(pending.backdrop_win, "number", false)
    set_win_option(pending.backdrop_win, "relativenumber", false)
    set_win_option(pending.backdrop_win, "cursorline", false)
    set_win_option(pending.backdrop_win, "cursorcolumn", false)
    set_win_option(pending.backdrop_win, "foldcolumn", "0")
    set_win_option(pending.backdrop_win, "signcolumn", "no")
    set_win_option(pending.backdrop_win, "wrap", false)
    set_win_option(pending.backdrop_win, "winbar", "")
    set_win_option(pending.backdrop_win, "statusline", " ")
    set_win_option(
      pending.backdrop_win,
      "winhighlight",
      table.concat({
        "Normal:DDDBackdrop",
        "NormalNC:DDDBackdrop",
        "EndOfBuffer:DDDBackdropFill",
        "NonText:DDDBackdropFill",
        "StatusLine:DDDBackdropFill",
        "StatusLineNC:DDDBackdropFill",
      }, ",")
    )

    local available_width, available_height = usable_size()
    pending.focus_win = vim.api.nvim_open_win(pending.buffer, true, {
      relative = "editor",
      width = math.max(1, math.min(dim.width, available_width)),
      height = math.max(1, math.min(dim.height, available_height)),
      row = 0,
      col = 0,
      style = "minimal",
      border = "none",
      zindex = 50,
    })
  end)

  if not ok then
    restore_options(saved_options)
    if valid_tab(pending.tab) then
      pcall(function()
        vim.cmd("tabclose")
      end)
    end
    notify("could not open focus mode: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  state = pending
  update_highlights()
  apply_focus_options()
  install_mappings()
  create_autocmds()
  resize()
  run_hook("enter")
  emit("Enter")
  return true
end

---Closes focus mode and restores the original editor state.
---@return nil
function M.close()
  close_internal()
end

---Resizes focus mode, opening it when inactive.
---@param expression? string Dimension expression.
---@return boolean? success
function M.resize(expression)
  if not state then
    return M.open(expression)
  end
  local dim = parse_dimensions(expression or state.expression)
  if not dim then
    notify("invalid dimension expression: " .. tostring(expression))
    return false
  end
  state.dim = dim
  state.expression = expression or state.expression
  resize()
  return true
end

---Toggles focus mode, or resizes it when an expression is provided.
---@param expression? string Dimension expression.
---@return boolean? success
function M.toggle(expression)
  if state then
    if expression and vim.trim(expression) ~= "" then
      return M.resize(expression)
    end
    return M.close()
  end
  return M.open(expression)
end

---Handles the `:DDD` command.
---@param bang boolean Whether the command was invoked with `!`.
---@param expression? string Dimension expression.
---@return boolean? success
function M.execute(bang, expression)
  if bang then
    return M.close()
  end
  return M.toggle(expression)
end

---Returns whether focus mode is active.
---@return boolean
function M.is_active()
  return state ~= nil and not state.closing
end

---Configures ddd.nvim.
---@param opts? ddd.ConfigOptions
---@return ddd
function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  config._height_explicit = opts.height ~= nil
  return M
end

---Returns handles and dimensions for the active focus window.
---Useful for health checks and tests without exposing mutable state.
---@return ddd.Current?
function M.current()
  if not state then
    return nil
  end
  return {
    tab = state.tab,
    window = state.focus_win,
    backdrop = state.backdrop_win,
    dimensions = vim.deepcopy(state.dim),
  }
end

return M
