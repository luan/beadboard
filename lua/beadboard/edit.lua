local cli = require('beadboard.cli')

local M = {}

function M.open(bead_id, field, current_value, on_save)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = (field == 'title') and 'text' or 'markdown'

  vim.api.nvim_buf_set_name(buf, 'beadboard://' .. bead_id .. '/' .. field)

  local lines = vim.split(current_value or '', '\n', { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false

  vim.api.nvim_set_current_buf(buf)

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local content = table.concat(
        vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'
      )
      content = content:gsub('\n+$', '')

      cli.run({ 'update', bead_id, '--' .. field, content }, function(err)
        if err then
          vim.notify('beadboard: ' .. err, vim.log.levels.ERROR)
          return
        end
        vim.bo[buf].modified = false
        vim.notify('beadboard: saved ' .. field)
        if on_save then on_save() end
      end)
    end,
  })

  vim.keymap.set('n', 'q', function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, { buffer = buf, nowait = true, silent = true, desc = 'Close without saving' })
end

return M
