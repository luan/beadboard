local cli = require('beadboard.cli')

local M = {}

local ns = vim.api.nvim_create_namespace('beadboard_activity')

local separator = string.rep('\u{2500}', 52)

-- Per-buffer state for auto-refresh timer
local buf_timers = {}

local event_symbols = {
  created = '+',
  in_progress = '\u{2192}',
  completed = '\u{2713}',
  failed = '\u{2717}',
  deleted = '\u{2298}',
}

local function fmt_timestamp(ts)
  if not ts or ts == '' then return '?' end
  -- Show date + time (HH:MM)
  local date = string.match(ts, '^(%d%d%d%d%-%d%d%-%d%d)') or ''
  local time = string.match(ts, 'T(%d%d:%d%d)') or ''
  if date ~= '' and time ~= '' then
    return date .. ' ' .. time
  end
  return date ~= '' and date or ts
end

local function build_lines(events)
  local lines = {}
  local highlights = {}

  lines[#lines + 1] = 'beadboard \u{2014} Activity Feed'
  highlights[#highlights + 1] = { #lines - 1, 'BeadboardHeader', 0, -1 }
  lines[#lines + 1] = separator
  highlights[#highlights + 1] = { #lines - 1, 'Comment', 0, -1 }

  if not events or #events == 0 then
    lines[#lines + 1] = '(no activity)'
    return lines, highlights
  end

  for _, ev in ipairs(events) do
    local sym = event_symbols[ev.type] or '\u{00b7}'
    local id = ev.issue_id or ev.id or '?'
    local title = ev.title or ''
    local ts = fmt_timestamp(ev.timestamp or ev.created_at)
    local line = '[' .. ts .. '] ' .. sym .. ' ' .. id .. ' \u{2014} ' .. title
    lines[#lines + 1] = line

    local row = #lines - 1
    -- Highlight the ID portion
    local id_start = #('[' .. ts .. '] ' .. sym .. ' ')
    local id_end = id_start + #id
    highlights[#highlights + 1] = { row, 'BeadboardId', id_start, id_end }
  end

  return lines, highlights
end

local function render(buf, events)
  local lines, highlights = build_lines(events)

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
  cli.run({ 'activity' }, function(err, data)
    if err then
      vim.notify('beadboard: ' .. err, vim.log.levels.ERROR)
      return
    end
    if not vim.api.nvim_buf_is_valid(buf) then return end
    render(buf, data)
  end)
end

local function stop_timer(buf)
  local timer = buf_timers[buf]
  if timer then
    timer:stop()
    timer:close()
    buf_timers[buf] = nil
  end
end

local function start_timer(buf)
  stop_timer(buf)
  local timer = vim.loop.new_timer()
  buf_timers[buf] = timer
  timer:start(10000, 10000, vim.schedule_wrap(function()
    if vim.api.nvim_buf_is_valid(buf) then
      refresh(buf)
    else
      stop_timer(buf)
    end
  end))
end

local function extract_id_from_line(line)
  -- Format: [timestamp] symbol id -- title
  -- Match the ID after the symbol
  local id = line:match('%] . (%S+) \u{2014}')
  if id then return id end
  -- Fallback: match any word-dash-word pattern
  return line:match('(%S+%-%S+)')
end

function M.open()
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'beadboard-activity'

  vim.api.nvim_set_current_buf(buf)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '[beadboard] Loading activity...' })
  vim.bo[buf].modifiable = false

  local auto_refresh = false
  local opts = { buffer = buf, nowait = true, silent = true }

  vim.keymap.set('n', 'q', function()
    stop_timer(buf)
    vim.api.nvim_buf_delete(buf, { force = true })
  end, vim.tbl_extend('force', opts, { desc = 'Close buffer' }))

  vim.keymap.set('n', 'R', function()
    refresh(buf)
  end, vim.tbl_extend('force', opts, { desc = 'Refresh' }))

  vim.keymap.set('n', '<CR>', function()
    local line = vim.api.nvim_get_current_line()
    local id = extract_id_from_line(line)
    if id then
      require('beadboard.detail').open(id)
    end
  end, vim.tbl_extend('force', opts, { desc = 'Open issue' }))

  vim.keymap.set('n', 'a', function()
    auto_refresh = not auto_refresh
    if auto_refresh then
      start_timer(buf)
      vim.notify('beadboard: auto-refresh ON (10s)')
    else
      stop_timer(buf)
      vim.notify('beadboard: auto-refresh OFF')
    end
  end, vim.tbl_extend('force', opts, { desc = 'Toggle auto-refresh' }))

  vim.keymap.set('n', '?', function()
    require('beadboard.help').open()
  end, opts)

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function()
      stop_timer(buf)
    end,
  })

  refresh(buf)
end

return M
