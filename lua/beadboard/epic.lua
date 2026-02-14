local cli = require('beadboard.cli')

local M = {}

local ns = vim.api.nvim_create_namespace('beadboard_epic')

local separator = string.rep('\u{2500}', 52)

local function pad_right(s, width)
  s = tostring(s or '')
  if #s >= width then return s end
  return s .. string.rep(' ', width - #s)
end

local function pad_left(s, width)
  s = tostring(s or '')
  if #s >= width then return s end
  return string.rep(' ', width - #s) .. s
end

local function bar(done, total, max_width)
  if total == 0 then return '' end
  local width = math.floor((done / total) * max_width + 0.5)
  if done > 0 and width == 0 then width = 1 end
  return string.rep('\u{2588}', width)
    .. string.rep('\u{2591}', max_width - width)
end

local function render(buf, epics)
  local lines = {}
  local highlights = {}

  lines[#lines + 1] = 'beadboard \u{2014} Epic Status'
  highlights[#highlights + 1] = { #lines - 1, 'BeadboardHeader', 0, -1 }
  lines[#lines + 1] = separator
  highlights[#highlights + 1] = { #lines - 1, 'Comment', 0, -1 }

  if not epics or #epics == 0 then
    lines[#lines + 1] = ''
    lines[#lines + 1] = '(no epics found)'
  else
    for _, epic in ipairs(epics) do
      lines[#lines + 1] = ''
      local id_str = epic.id or '?'
      local title = epic.title or ''
      local header = id_str .. ' \u{2014} ' .. title
      lines[#lines + 1] = header
      highlights[#highlights + 1] = { #lines - 1, 'BeadboardId', 0, #id_str }

      local total = epic.total_children or epic.total or 0
      local closed = epic.closed_children or epic.closed or 0
      local pct = total > 0 and math.floor((closed / total) * 100 + 0.5) or 0
      local progress = '  '
        .. bar(closed, total, 20)
        .. '  ' .. pad_left(tostring(closed), 3)
        .. '/' .. pad_left(tostring(total), 3)
        .. '  (' .. pct .. '%)'
      lines[#lines + 1] = progress

      if epic.status then
        lines[#lines + 1] = '  Status: ' .. epic.status
      end
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, ns, h[2], h[1], h[3], h[4])
  end
end

local function refresh(buf)
  cli.run({ 'epic', 'status' }, function(err, data)
    if err then
      vim.notify('beadboard: ' .. err, vim.log.levels.ERROR)
      return
    end
    if not vim.api.nvim_buf_is_valid(buf) then return end
    render(buf, data)
  end)
end

function M.open()
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'beadboard-epic'

  vim.api.nvim_set_current_buf(buf)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '[beadboard] Loading epic status...' })
  vim.bo[buf].modifiable = false

  vim.keymap.set('n', 'q', function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, { buffer = buf, nowait = true, silent = true, desc = 'Close buffer' })

  vim.keymap.set('n', 'R', function()
    refresh(buf)
  end, { buffer = buf, nowait = true, silent = true, desc = 'Refresh' })

  refresh(buf)
end

return M
