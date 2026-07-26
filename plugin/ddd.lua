if vim.g.loaded_ddd_nvim == 1 then
  return
end
vim.g.loaded_ddd_nvim = 1

---@param opts vim.api.keyset.create_user_command.command_args
local function command(opts)
  require("ddd").execute(opts.bang, opts.args)
end

vim.api.nvim_create_user_command("DDD", command, {
  nargs = "?",
  bang = true,
  bar = true,
  desc = "Toggle ddd.nvim focus mode",
})
