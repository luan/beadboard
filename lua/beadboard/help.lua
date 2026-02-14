local M = {}

local ns = vim.api.nvim_create_namespace('beadboard_help')
local filetype = 'beadboard_help'

local function _has_snacks_win()
  local ok, snacks = pcall(require, 'snacks')
  return ok and snacks.win and type(snacks.win) == 'table'
end

-- Curated keymap sections. Each section: { title, { {lhs, desc}, ... } }
-- Kept static because beadboard keymaps lack desc fields.
local sections = {
  {
    'List',
    {
      { '<CR>', 'Open bead detail' },
      { 'R', 'Refresh' },
      { 'q', 'Close buffer' },
      { 's', 'Cycle status forward' },
      { 'S', 'Pick status' },
      { 'p', 'Priority up' },
      { 'P', 'Priority down' },
      { 'c', 'Close bead' },
      { 'o', 'Reopen bead' },
      { 'gK', 'Claim bead' },
      { 'C', 'Create bead' },
      { 'dd', 'Delete bead' },
      { 'gD', 'Defer bead' },
      { 'gU', 'Undefer bead' },
      { 'f', 'Filter' },
      { 'F', 'Clear filters' },
      { 'gs', 'Sort by field' },
      { 'gS', 'Reverse sort' },
      { '/', 'Text search' },
      { 'gq', 'Query expression' },
      { 'gC', 'Claude skills' },
    },
  },
  {
    'List (visual)',
    {
      { 'V+c', 'Bulk close' },
      { 'V+dd', 'Bulk delete' },
      { 'V+gD', 'Bulk defer' },
      { 'V+s', 'Bulk status' },
      { 'V+gC', 'Claude skills (multi)' },
    },
  },
  {
    'Detail',
    {
      { 'q / <BS>', 'Back to list' },
      { 'R', 'Refresh' },
      { 's / S', 'Status cycle/pick' },
      { 'p / P', 'Priority up/down' },
      { 'c', 'Close bead' },
      { 'o', 'Reopen bead' },
      { 'gK', 'Claim bead' },
      { 'a', 'Set assignee' },
      { 'gl', 'Add label' },
      { 'gL', 'Remove label' },
      { '<C-c>', 'Add comment' },
      { 'gD', 'Defer bead' },
      { 'gU', 'Undefer bead' },
      { 'ed', 'Edit description' },
      { 'eD', 'Edit design' },
      { 'en', 'Edit notes' },
      { 'ea', 'Edit acceptance' },
      { 'et', 'Edit title' },
      { 'eU', 'Edit due date' },
      { 'eE', 'Edit estimate' },
      { 'eI', 'Rename issue ID' },
      { 'gP', 'Set parent' },
      { 'gd', 'Show deps' },
      { 'gp', 'Go to parent' },
      { 'gc', 'Show children' },
      { 'gG', 'Dep graph' },
      { 'gx', 'Mark duplicate' },
      { 'gX', 'Supersede' },
      { 'gW', 'Promote wisp' },
      { 'da', 'Add depends-on' },
      { 'db', 'Add blocks' },
      { 'dr', 'Remove dep' },
      { 'dR', 'Relate issue' },
      { 'dU', 'Unrelate issue' },
      { 'gC', 'Claude skills' },
      { 'gT', 'Jump to Claude' },
    },
  },
  {
    'Activity',
    {
      { '<CR>', 'Open issue' },
      { 'R', 'Refresh' },
      { 'a', 'Toggle auto-refresh' },
      { 'q', 'Close buffer' },
      { '?', 'Show help' },
    },
  },
  {
    'Graph',
    {
      { '<CR>', 'Open issue' },
      { 'R', 'Refresh' },
      { 'q', 'Close buffer' },
      { '?', 'Show help' },
    },
  },
  {
    'Edit',
    {
      { ':w', 'Save changes' },
      { 'q', 'Close (no save)' },
    },
  },
  {
    'Commands',
    {
      { ':Beadboard', 'Open list' },
      { ':BdSearch <t>', 'Search beads' },
      { ':BdQuery <e>', 'Query beads' },
      { ':BdReady', 'Ready beads' },
      { ':BdBlocked', 'Blocked beads' },
      { ':BdStale [d]', 'Stale beads' },
      { ':BdCreate', 'Create bead' },
      { ':BdStatus', 'Dashboard' },
      { ':BdEpicStatus', 'Epic progress' },
      { ':BdGraph [id]', 'Dep graph' },
      { ':BdActivity', 'Activity feed' },
    },
  },
}

--- Pad or truncate string to exact display width.
---@param str string
---@param len number
---@param align? "left"|"right"
---@return string
local function pad(str, len, align)
  local w = vim.api.nvim_strwidth(str)
  if w > len then
    return vim.fn.strcharpart(str, 0, len - 1) .. '\u{2026}'
  end
  local space = string.rep(' ', len - w)
  return align == 'right' and (space .. str) or (str .. space)
end

--- Build extmark virt_text rows from sections data.
--- Returns list of rows, each row is a list of {text, hl_group} chunks.
---@param width number available width
---@return table[] rows
local function build_rows(width)
  local col_width = 32
  local key_width = 14
  local cols = math.max(1, math.floor(width / col_width))

  -- Flatten all entries with section headers interleaved.
  -- Each entry: { key, desc, is_header }
  local flat = {}
  for _, section in ipairs(sections) do
    table.insert(flat, { section[1], '', true })
    for _, binding in ipairs(section[2]) do
      table.insert(flat, { binding[1], binding[2], false })
    end
  end

  -- Lay out into columns, filling column-first.
  local total = #flat
  local rows_needed = math.ceil(total / cols)
  local grid = {} ---@type table[][]
  for r = 1, rows_needed do
    grid[r] = {}
  end

  local idx = 1
  for col = 1, cols do
    for row = 1, rows_needed do
      if idx <= total then
        grid[row][col] = flat[idx]
        idx = idx + 1
      end
    end
  end

  -- Convert grid to virt_text rows.
  local result = {}
  for _, row_data in ipairs(grid) do
    local chunks = {}
    for c, entry in ipairs(row_data) do
      if c > 1 then
        table.insert(chunks, { '  ', '' })
      end
      if entry[3] then
        -- Section header
        table.insert(chunks, { pad(entry[1], col_width), 'BeadboardHeader' })
      else
        table.insert(chunks, { pad(entry[1], key_width, 'right'), 'SnacksWinKey' })
        table.insert(chunks, { ' ', '' })
        table.insert(chunks, { '\u{27a4}', 'SnacksWinKeySep' })
        table.insert(chunks, { ' ', '' })
        table.insert(chunks, {
          pad(entry[2], col_width - key_width - 3),
          'SnacksWinKeyDesc',
        })
      end
    end
    table.insert(result, chunks)
  end
  return result
end

--- Close any existing beadboard help float on the current tab.
---@return boolean true if a help window was found and closed
local function close_existing()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == filetype then
        vim.api.nvim_win_close(win, true)
        return true
      end
    end
  end
  return false
end

--- Open help as Snacks.win float anchored to bottom.
---@param source_buf number the buffer that triggered help
local function open_snacks(source_buf)
  local Snacks = require('snacks')
  local win = Snacks.win({
    show = false,
    focusable = false,
    position = 'float',
    backdrop = false,
    border = 'top',
    row = -1,
    width = 0,
    height = 0.4,
    zindex = 51,
    bo = { filetype = filetype },
  })

  local dim = win:dim()
  local rows = build_rows(dim.width)
  win.opts.height = #rows
  win:show()

  for i, chunks in ipairs(rows) do
    vim.api.nvim_buf_set_lines(win.buf, i - 1, i, false, { '' })
    vim.api.nvim_buf_set_extmark(win.buf, ns, i - 1, 0, {
      virt_text = chunks,
      virt_text_pos = 'overlay',
    })
  end

  -- Auto-close when source buffer is wiped or its window closes.
  local augroup = vim.api.nvim_create_augroup(
    'beadboard_help_' .. source_buf,
    { clear = true }
  )
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = augroup,
    buffer = source_buf,
    once = true,
    callback = function()
      if win:valid() then win:close() end
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = augroup,
    callback = function(ev)
      local closed_win = tonumber(ev.match)
      if closed_win and vim.fn.winbufnr(closed_win) == source_buf then
        if win:valid() then win:close() end
        pcall(vim.api.nvim_del_augroup_by_id, augroup)
      end
    end,
  })
end

--- Fallback: open help in a plain nvim_open_win float.
---@param source_buf number the buffer that triggered help
local function open_fallback(source_buf)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = filetype

  local rows = build_rows(vim.o.columns)
  local lines = {}
  for _ = 1, #rows do
    table.insert(lines, '')
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  for i, chunks in ipairs(rows) do
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
      virt_text = chunks,
      virt_text_pos = 'overlay',
    })
  end

  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = vim.o.lines - #rows - 2,
    col = 0,
    width = vim.o.columns,
    height = #rows,
    style = 'minimal',
    border = { '\u{2500}', '\u{2500}', '\u{2500}', '', '', '', '', '' },
    focusable = false,
    zindex = 51,
  })
  vim.wo[win].winhighlight = 'Normal:NormalFloat'

  local augroup = vim.api.nvim_create_augroup(
    'beadboard_help_' .. source_buf,
    { clear = true }
  )
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = augroup,
    buffer = source_buf,
    once = true,
    callback = function()
      pcall(vim.api.nvim_win_close, win, true)
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = augroup,
    callback = function(ev)
      local closed_win = tonumber(ev.match)
      if closed_win and vim.fn.winbufnr(closed_win) == source_buf then
        pcall(vim.api.nvim_win_close, win, true)
        pcall(vim.api.nvim_del_augroup_by_id, augroup)
      end
    end,
  })
end

--- Toggle help overlay. Press ? to open, press again to close.
function M.toggle()
  if close_existing() then
    return
  end
  local source_buf = vim.api.nvim_get_current_buf()
  if _has_snacks_win() then
    open_snacks(source_buf)
  else
    open_fallback(source_buf)
  end
end

-- Backward compat: old callers use M.open()
M.open = M.toggle

return M
