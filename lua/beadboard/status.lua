local cli = require('beadboard.cli')

local M = {}

local ns = vim.api.nvim_create_namespace('beadboard_status')

local separator = string.rep('\u{2500}', 40)

local function bar(count, max_count, max_width)
  if max_count == 0 then
    return ''
  end
  local width = math.floor((count / max_count) * max_width + 0.5)
  if count > 0 and width == 0 then
    width = 1
  end
  return string.rep('\u{2588}', width)
end

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

local priority_names = {
  [0] = 'P0 (critical)',
  [1] = 'P1 (high)',
  [2] = 'P2 (medium)',
  [3] = 'P3 (low)',
  [4] = 'P4 (backlog)',
}

local function render(buf, status_data, by_status, by_priority, by_type, by_assignee, by_label)
  local lines = {}
  local highlights = {}

  lines[#lines + 1] = 'beadboard \u{2014} Project Dashboard'
  highlights[#highlights + 1] = { #lines - 1, 'BeadboardHeader', 0, -1 }
  lines[#lines + 1] = separator
  highlights[#highlights + 1] = { #lines - 1, 'Comment', 0, -1 }

  -- Summary from status_data
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'Summary'
  highlights[#highlights + 1] = { #lines - 1, 'BeadboardHeader', 0, -1 }

  local summary = status_data and status_data.summary or {}
  local total = summary.total_issues or 0
  local open = summary.open_issues or 0
  local wip = summary.in_progress_issues or 0
  local closed = summary.closed_issues or 0
  lines[#lines + 1] = '  Total: ' .. total
    .. ' | Open: ' .. open
    .. ' | In Progress: ' .. wip
    .. ' | Closed: ' .. closed

  -- By Status
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'By Status'
  highlights[#highlights + 1] = { #lines - 1, 'BeadboardHeader', 0, -1 }

  local max_bar = 20
  if by_status and type(by_status) == 'table' then
    local max_count = 0
    for _, entry in ipairs(by_status) do
      local c = entry.count or 0
      if c > max_count then max_count = c end
    end
    for _, entry in ipairs(by_status) do
      local name = entry.status or entry.name or '?'
      local count = entry.count or 0
      local b = bar(count, max_count, max_bar)
      lines[#lines + 1] = '  ' .. pad_right(name, 14) .. b .. '  ' .. count
    end
  end

  -- By Priority
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'By Priority'
  highlights[#highlights + 1] = { #lines - 1, 'BeadboardHeader', 0, -1 }

  if by_priority and type(by_priority) == 'table' then
    -- Build lookup by priority value
    local prio_counts = {}
    for _, entry in ipairs(by_priority) do
      local p = entry.priority or entry.name
      prio_counts[tostring(p)] = entry.count or 0
    end
    for i = 0, 4 do
      local label = priority_names[i]
      local count = prio_counts[tostring(i)] or 0
      lines[#lines + 1] = '  ' .. pad_right(label, 16) .. pad_left(tostring(count), 3)
    end
  end

  -- By Type
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'By Type'
  highlights[#highlights + 1] = { #lines - 1, 'BeadboardHeader', 0, -1 }

  if by_type and type(by_type) == 'table' then
    for _, entry in ipairs(by_type) do
      local name = entry.issue_type or entry.type or entry.name or '?'
      local count = entry.count or 0
      lines[#lines + 1] = '  ' .. pad_right(name, 12) .. pad_left(tostring(count), 3)
    end
  end

  -- By Assignee
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'By Assignee'
  highlights[#highlights + 1] = { #lines - 1, 'BeadboardHeader', 0, -1 }

  if by_assignee and type(by_assignee) == 'table' then
    for _, entry in ipairs(by_assignee) do
      local name = entry.assignee or entry.name or '(unassigned)'
      local count = entry.count or 0
      lines[#lines + 1] = '  ' .. pad_right(name, 20) .. pad_left(tostring(count), 3)
    end
  end

  -- By Label
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'By Label'
  highlights[#highlights + 1] = { #lines - 1, 'BeadboardHeader', 0, -1 }

  if by_label and type(by_label) == 'table' then
    for _, entry in ipairs(by_label) do
      local name = entry.label or entry.name or '(none)'
      local count = entry.count or 0
      lines[#lines + 1] = '  ' .. pad_right(name, 20) .. pad_left(tostring(count), 3)
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
  local status_data, by_status, by_priority, by_type, by_assignee, by_label
  local pending = 6

  local function try_render()
    pending = pending - 1
    if pending > 0 then return end
    if not vim.api.nvim_buf_is_valid(buf) then return end
    render(buf, status_data, by_status, by_priority, by_type, by_assignee, by_label)
  end

  cli.run({ 'status' }, function(err, data)
    if not err and data then status_data = data end
    try_render()
  end)

  cli.run({ 'count', '--by-status' }, function(err, data)
    if not err and data then by_status = data end
    try_render()
  end)

  cli.run({ 'count', '--by-priority' }, function(err, data)
    if not err and data then by_priority = data end
    try_render()
  end)

  cli.run({ 'count', '--by-type' }, function(err, data)
    if not err and data then by_type = data end
    try_render()
  end)

  cli.run({ 'count', '--by-assignee' }, function(err, data)
    if not err and data then by_assignee = data end
    try_render()
  end)

  cli.run({ 'count', '--by-label' }, function(err, data)
    if not err and data then by_label = data end
    try_render()
  end)
end

function M.open()
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'beadboard-status'

  vim.api.nvim_set_current_buf(buf)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '[beadboard] Loading dashboard...' })
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
