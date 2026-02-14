local cli = require('beadboard.cli')

local M = {}

function M.open(issue_id)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'beadboard-graph'

  vim.api.nvim_set_current_buf(buf)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '[beadboard] Loading graph...' })
  vim.bo[buf].modifiable = false

  local args = { 'graph' }
  if issue_id then
    args[#args + 1] = issue_id
  else
    args[#args + 1] = '--all'
  end

  local function refresh()
    cli.run_raw(args, function(err, text)
      if err then
        vim.notify('beadboard: ' .. err, vim.log.levels.ERROR)
        return
      end
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local lines = vim.split(text or '', '\n', { plain = true })
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
      vim.bo[buf].modified = false
    end)
  end

  local opts = { buffer = buf, nowait = true, silent = true }

  vim.keymap.set('n', 'q', function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, vim.tbl_extend('force', opts, { desc = 'Close buffer' }))

  vim.keymap.set('n', 'R', function()
    refresh()
  end, vim.tbl_extend('force', opts, { desc = 'Refresh' }))

  vim.keymap.set('n', '<CR>', function()
    local line = vim.api.nvim_get_current_line()
    -- Strip box-drawing borders and whitespace
    local trimmed = line:match('^%s*\u{2502}?%s*(.-)%s*\u{2502}?%s*$') or line
    -- Extract issue ID (word-dash-word pattern)
    local id = trimmed:match('(%S+%-%S+)')
    if id then
      -- Strip leading status icons
      id = id:gsub('^[\u{25CB}\u{25D0}\u{25CF}\u{2713}\u{2744}]%s*', '')
      -- Strip trailing punctuation
      id = id:gsub('[,%.;:\u{2026}]+$', '')
      if id ~= '' then
        require('beadboard.detail').open(id)
      end
    end
  end, vim.tbl_extend('force', opts, { desc = 'Open issue' }))

  vim.keymap.set('n', '?', function()
    require('beadboard.help').open()
  end, opts)

  refresh()
end

return M
