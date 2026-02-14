local cli = require('beadboard.cli')
local util = require('beadboard.util')
local hl = require('beadboard.highlight')

local M = {}

local ns = vim.api.nvim_create_namespace('beadboard_detail')

-- Per-buffer state: buf -> { bead_id, bead, comments, deps }
local buf_state = {}

local status_cycle = { 'open', 'in_progress', 'blocked', 'deferred', 'closed' }
local status_index = {}
for i, s in ipairs(status_cycle) do
  status_index[s] = i
end

local separator = string.rep('\u{2500}', 52)

local function fmt_date(ts)
  if not ts or ts == '' then
    return '?'
  end
  return string.match(ts, '^(%d%d%d%d%-%d%d%-%d%d)') or ts
end

local function fmt_or_none(val)
  if not val or val == '' then
    return '(none)'
  end
  return val
end

local function fmt_labels(labels)
  if not labels or #labels == 0 then
    return '(none)'
  end
  return table.concat(labels, ', ')
end

local function split_lines(text)
  if not text or text == '' then
    return { '(empty)' }
  end
  local lines = {}
  for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    lines[#lines + 1] = line
  end
  return lines
end

local function count_deps(deps)
  local blocking, blocked_by = 0, 0
  if not deps then
    return blocking, blocked_by
  end
  for _, dep in ipairs(deps) do
    if dep.blocks then
      blocking = blocking + 1
    end
    if dep.blocked_by then
      blocked_by = blocked_by + 1
    end
  end
  return blocking, blocked_by
end

local function build_lines(bead, comments, deps)
  local lines = {}
  local highlights = {} -- { {row, group, col_start, col_end}, ... }

  -- Line 1: <id> — <title>
  local id_str = bead.id or '?'
  local title_line = id_str .. ' \u{2014} ' .. (bead.title or '')
  lines[#lines + 1] = title_line
  highlights[#highlights + 1] = {
    #lines - 1, 'BeadboardId', 0, #id_str,
  }

  -- Line 2: Status | Priority | Type
  local status_str = bead.status or '?'
  local priority_str = util.priority_label(bead.priority)
  local type_str = bead.issue_type or '?'
  local meta_line = 'Status: ' .. status_str
    .. ' | Priority: ' .. priority_str
    .. ' | Type: ' .. type_str
  lines[#lines + 1] = meta_line
  local row = #lines - 1
  local s_start = #'Status: '
  local s_end = s_start + #status_str
  highlights[#highlights + 1] = { row, hl.status_group(bead.status), s_start, s_end }
  local p_start = s_end + #' | Priority: '
  local p_end = p_start + #priority_str
  highlights[#highlights + 1] = { row, hl.priority_group(bead.priority), p_start, p_end }
  local t_start = p_end + #' | Type: '
  local t_end = t_start + #type_str
  highlights[#highlights + 1] = { row, 'BeadboardType', t_start, t_end }

  -- Line 3: Owner | Assignee
  lines[#lines + 1] = 'Owner: ' .. fmt_or_none(bead.owner)
    .. ' | Assignee: ' .. fmt_or_none(bead.assignee)

  -- Line 4: Labels
  lines[#lines + 1] = 'Labels: ' .. fmt_labels(bead.labels)

  -- Line 5: Created | Updated
  lines[#lines + 1] = 'Created: ' .. fmt_date(bead.created_at)
    .. ' | Updated: ' .. fmt_date(bead.updated_at)

  -- Line 6: Dependencies
  local blocking, blocked_by = count_deps(deps)
  lines[#lines + 1] = 'Dependencies: '
    .. blocking .. ' blocking, '
    .. blocked_by .. ' blocked by'

  -- Separator
  lines[#lines + 1] = separator
  highlights[#highlights + 1] = { #lines - 1, 'Comment', 0, -1 }

  -- Sections
  local sections = {
    { '## Description', bead.description },
    { '## Design', bead.design },
    { '## Notes', bead.notes },
    { '## Acceptance Criteria', bead.acceptance },
  }
  for _, sec in ipairs(sections) do
    lines[#lines + 1] = ''
    lines[#lines + 1] = sec[1]
    highlights[#highlights + 1] = { #lines - 1, 'BeadboardHeader', 0, -1 }
    for _, l in ipairs(split_lines(sec[2])) do
      lines[#lines + 1] = l
    end
  end

  -- Comments
  comments = comments or {}
  lines[#lines + 1] = ''
  local comments_header = '## Comments (' .. #comments .. ')'
  lines[#lines + 1] = comments_header
  highlights[#highlights + 1] = { #lines - 1, 'BeadboardHeader', 0, -1 }

  if #comments == 0 then
    lines[#lines + 1] = '(none)'
  else
    for _, c in ipairs(comments) do
      lines[#lines + 1] = (c.author or '?') .. ' (' .. fmt_date(c.created_at) .. '):'
      for _, l in ipairs(split_lines(c.body)) do
        lines[#lines + 1] = l
      end
      lines[#lines + 1] = ''
    end
  end

  return lines, highlights
end

local function render(buf, bead, comments, deps)
  local lines, highlights = build_lines(bead, comments, deps)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, ns, h[2], h[1], h[3], h[4])
  end
end

local function refresh_detail(buf, bead_id)
  local bead, comments, deps
  local pending = 3

  local function try_render()
    pending = pending - 1
    if pending > 0 then
      return
    end
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    if not bead then
      vim.notify('beadboard: failed to load bead ' .. bead_id, vim.log.levels.ERROR)
      return
    end
    local state = buf_state[buf]
    if state then
      state.bead = bead
      state.comments = comments
      state.deps = deps
    end
    render(buf, bead, comments, deps)
  end

  cli.run({ 'show', bead_id }, function(err, data)
    if not err and data and #data > 0 then
      bead = data[1]
    elseif err then
      vim.notify('beadboard: ' .. err, vim.log.levels.ERROR)
    end
    try_render()
  end)

  cli.run({ 'comments', bead_id }, function(err, data)
    if not err and data then
      comments = data
    end
    try_render()
  end)

  cli.run({ 'dep', 'list', bead_id }, function(err, data)
    if not err and data then
      deps = data
    end
    try_render()
  end)
end

local function mutate_and_refresh(buf, bead_id, args)
  cli.run(args, function(err)
    if err then
      vim.notify('beadboard: ' .. err, vim.log.levels.ERROR)
      return
    end
    refresh_detail(buf, bead_id)
  end)
end

local function setup_keymaps(buf)
  local opts = { buffer = buf, nowait = true, silent = true }

  local function state()
    return buf_state[buf]
  end

  vim.keymap.set('n', 'q', function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, opts)

  vim.keymap.set('n', '<BS>', function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, opts)

  vim.keymap.set('n', 'R', function()
    local s = state()
    if s then refresh_detail(buf, s.bead_id) end
  end, opts)

  -- Status cycle forward
  vim.keymap.set('n', 's', function()
    local s = state()
    if not s or not s.bead then return end
    local idx = status_index[s.bead.status] or 1
    local next = status_cycle[(idx % #status_cycle) + 1]
    mutate_and_refresh(buf, s.bead_id, { 'update', s.bead_id, '--status', next })
  end, vim.tbl_extend('force', opts, { desc = 'Cycle status forward' }))

  -- Status pick
  vim.keymap.set('n', 'S', function()
    local s = state()
    if not s or not s.bead then return end
    vim.ui.select(status_cycle, { prompt = 'Status:' }, function(choice)
      if not choice then return end
      mutate_and_refresh(buf, s.bead_id, { 'update', s.bead_id, '--status', choice })
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Pick status' }))

  -- Priority cycle up
  vim.keymap.set('n', 'p', function()
    local s = state()
    if not s or not s.bead then return end
    local cur = s.bead.priority or 4
    local next = (cur - 1) % 5
    mutate_and_refresh(buf, s.bead_id, { 'update', s.bead_id, '--priority', tostring(next) })
  end, vim.tbl_extend('force', opts, { desc = 'Priority up' }))

  -- Priority cycle down
  vim.keymap.set('n', 'P', function()
    local s = state()
    if not s or not s.bead then return end
    local cur = s.bead.priority or 0
    local next = (cur + 1) % 5
    mutate_and_refresh(buf, s.bead_id, { 'update', s.bead_id, '--priority', tostring(next) })
  end, vim.tbl_extend('force', opts, { desc = 'Priority down' }))

  -- Close
  vim.keymap.set('n', 'c', function()
    local s = state()
    if not s then return end
    mutate_and_refresh(buf, s.bead_id, { 'close', s.bead_id })
  end, vim.tbl_extend('force', opts, { desc = 'Close bead' }))

  -- Reopen
  vim.keymap.set('n', 'o', function()
    local s = state()
    if not s then return end
    mutate_and_refresh(buf, s.bead_id, { 'reopen', s.bead_id })
  end, vim.tbl_extend('force', opts, { desc = 'Reopen bead' }))

  -- Claim
  vim.keymap.set('n', 'gK', function()
    local s = state()
    if not s then return end
    mutate_and_refresh(buf, s.bead_id, { 'update', s.bead_id, '--claim' })
  end, vim.tbl_extend('force', opts, { desc = 'Claim bead' }))

  -- Assignee
  vim.keymap.set('n', 'a', function()
    local s = state()
    if not s then return end
    vim.ui.input({ prompt = 'Assignee: ' }, function(val)
      if not val or val == '' then return end
      mutate_and_refresh(buf, s.bead_id, { 'update', s.bead_id, '--assignee', val })
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Set assignee' }))

  -- Add label
  vim.keymap.set('n', 'gl', function()
    local s = state()
    if not s then return end
    cli.run({ 'label', 'list-all' }, function(err, data)
      local labels = {}
      if not err and data and type(data) == 'table' then
        labels = data
      end
      labels[#labels + 1] = '(custom...)'
      vim.ui.select(labels, { prompt = 'Add label:' }, function(choice)
        if not choice then return end
        if choice == '(custom...)' then
          vim.ui.input({ prompt = 'Add label: ' }, function(val)
            if not val or val == '' then return end
            mutate_and_refresh(buf, s.bead_id, { 'update', s.bead_id, '--add-label', val })
          end)
        else
          mutate_and_refresh(buf, s.bead_id, { 'update', s.bead_id, '--add-label', choice })
        end
      end)
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Add label' }))

  -- Remove label
  vim.keymap.set('n', 'gL', function()
    local s = state()
    if not s then return end
    vim.ui.input({ prompt = 'Remove label: ' }, function(val)
      if not val or val == '' then return end
      mutate_and_refresh(buf, s.bead_id, { 'update', s.bead_id, '--remove-label', val })
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Remove label' }))

  -- Add comment
  vim.keymap.set('n', '<C-c>', function()
    local s = state()
    if not s then return end
    vim.ui.input({ prompt = 'Comment: ' }, function(text)
      if not text or text == '' then return end
      mutate_and_refresh(buf, s.bead_id, { 'comments', 'add', s.bead_id, text })
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Add comment' }))

  -- Field editing via scratch buffer
  local edit_fields = {
    { key = 'ed', field = 'description', desc = 'Edit description' },
    { key = 'eD', field = 'design', desc = 'Edit design' },
    { key = 'en', field = 'notes', desc = 'Edit notes' },
    { key = 'ea', field = 'acceptance', desc = 'Edit acceptance' },
    { key = 'et', field = 'title', desc = 'Edit title' },
  }
  for _, f in ipairs(edit_fields) do
    vim.keymap.set('n', f.key, function()
      local s = state()
      if not s or not s.bead then return end
      local current = s.bead[f.field] or ''
      require('beadboard.edit').open(s.bead_id, f.field, current, function()
        refresh_detail(buf, s.bead_id)
      end)
    end, vim.tbl_extend('force', opts, { desc = f.desc }))
  end

  -- Show dependencies picker
  vim.keymap.set('n', 'gd', function()
    local s = state()
    if not s or not s.deps or #s.deps == 0 then
      vim.notify('beadboard: no dependencies')
      return
    end
    local items = {}
    for _, d in ipairs(s.deps) do
      local label = d.id or d.blocks or d.blocked_by or tostring(d)
      table.insert(items, label)
    end
    vim.ui.select(items, { prompt = 'Dependency:' }, function(choice)
      if choice then
        require('beadboard.detail').open(choice)
      end
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Show dependencies' }))

  -- Dep add: current issue depends on target
  vim.keymap.set('n', 'da', function()
    local s = state()
    if not s then return end
    local picker = require('beadboard.picker')
    picker.pick_issue('Depends on', function(target)
      if not target then return end
      mutate_and_refresh(buf, s.bead_id, { 'dep', 'add', s.bead_id, target })
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Add dependency' }))

  -- Dep blocks: current issue blocks target
  vim.keymap.set('n', 'db', function()
    local s = state()
    if not s then return end
    local picker = require('beadboard.picker')
    picker.pick_issue('Blocks', function(target)
      if not target then return end
      mutate_and_refresh(buf, s.bead_id, { 'dep', s.bead_id, '--blocks', target })
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Add blocker' }))

  -- Dep remove: select from existing deps
  vim.keymap.set('n', 'dr', function()
    local s = state()
    if not s or not s.deps or #s.deps == 0 then
      vim.notify('beadboard: no dependencies to remove')
      return
    end
    local items = {}
    local id_map = {}
    for _, d in ipairs(s.deps) do
      if d.dependency_type ~= 'relates-to' then
        local dep_id = d.id or ''
        local label = dep_id .. ' [' .. (d.dependency_type or '?') .. '] ' .. (d.title or '')
        items[#items + 1] = label
        id_map[label] = dep_id
      end
    end
    if #items == 0 then
      vim.notify('beadboard: no dependencies to remove')
      return
    end
    vim.ui.select(items, { prompt = 'Remove dependency:' }, function(choice)
      if not choice then return end
      local target = id_map[choice]
      mutate_and_refresh(buf, s.bead_id, { 'dep', 'remove', s.bead_id, target })
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Remove dependency' }))

  -- Dep relate: bidirectional relates_to link
  vim.keymap.set('n', 'dR', function()
    local s = state()
    if not s then return end
    local picker = require('beadboard.picker')
    picker.pick_issue('Relate to', function(target)
      if not target then return end
      mutate_and_refresh(buf, s.bead_id, { 'dep', 'relate', s.bead_id, target })
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Relate to issue' }))

  -- Dep unrelate: remove relates_to link from existing deps
  vim.keymap.set('n', 'dU', function()
    local s = state()
    if not s or not s.deps or #s.deps == 0 then
      vim.notify('beadboard: no relations to remove')
      return
    end
    local items = {}
    local id_map = {}
    for _, d in ipairs(s.deps) do
      if d.dependency_type == 'relates-to' then
        local dep_id = d.id or ''
        local label = dep_id .. ' [relates-to] ' .. (d.title or '')
        items[#items + 1] = label
        id_map[label] = dep_id
      end
    end
    if #items == 0 then
      vim.notify('beadboard: no relates-to links to remove')
      return
    end
    vim.ui.select(items, { prompt = 'Unrelate:' }, function(choice)
      if not choice then return end
      local target = id_map[choice]
      mutate_and_refresh(buf, s.bead_id, { 'dep', 'unrelate', s.bead_id, target })
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Unrelate issue' }))

  -- Go to parent
  vim.keymap.set('n', 'gp', function()
    local s = state()
    if not s or not s.bead or not s.bead.parent or s.bead.parent == '' then
      vim.notify('beadboard: no parent')
      return
    end
    require('beadboard.detail').open(s.bead.parent)
  end, vim.tbl_extend('force', opts, { desc = 'Go to parent' }))

  -- Show children
  vim.keymap.set('n', 'gc', function()
    local s = state()
    if not s or not s.bead then return end
    require('beadboard.list').open_with_mode('children', s.bead_id)
  end, vim.tbl_extend('force', opts, { desc = 'Show children' }))

  -- Defer
  vim.keymap.set('n', 'gD', function()
    local s = state()
    if not s then return end
    vim.ui.input({ prompt = 'Defer until (optional, empty to defer now): ' }, function(val)
      local args = { 'defer', s.bead_id }
      if val and val ~= '' then
        table.insert(args, '--until')
        table.insert(args, val)
      end
      cli.run(args, function(err)
        if err then
          vim.notify('beadboard: ' .. err, vim.log.levels.ERROR)
          return
        end
        refresh_detail(buf, s.bead_id)
      end)
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Defer bead' }))

  -- Undefer
  vim.keymap.set('n', 'gU', function()
    local s = state()
    if not s then return end
    mutate_and_refresh(buf, s.bead_id, { 'update', s.bead_id, '--status', 'open' })
  end, vim.tbl_extend('force', opts, { desc = 'Undefer bead' }))

  -- Edit due date
  vim.keymap.set('n', 'eU', function()
    local s = state()
    if not s then return end
    vim.ui.input({ prompt = 'Due date (+6h, +1d, +2w, tomorrow, YYYY-MM-DD, empty to clear): ' }, function(val)
      if val == nil then return end
      mutate_and_refresh(buf, s.bead_id, { 'update', s.bead_id, '--due', val })
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Edit due date' }))

  -- Edit estimate
  vim.keymap.set('n', 'eE', function()
    local s = state()
    if not s then return end
    vim.ui.input({ prompt = 'Estimate (minutes): ' }, function(val)
      if not val or val == '' then return end
      mutate_and_refresh(buf, s.bead_id, { 'update', s.bead_id, '--estimate', val })
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Edit estimate' }))

  -- Set parent
  vim.keymap.set('n', 'gP', function()
    local s = state()
    if not s then return end
    local picker = require('beadboard.picker')
    picker.pick_issue('Parent', function(target)
      if not target then return end
      mutate_and_refresh(buf, s.bead_id, { 'update', s.bead_id, '--parent', target })
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Set parent' }))

  -- Dependency graph
  vim.keymap.set('n', 'gG', function()
    local s = state()
    if not s then return end
    require('beadboard.graph').open(s.bead_id)
  end, vim.tbl_extend('force', opts, { desc = 'Dependency graph' }))

  -- Mark as duplicate of another issue
  vim.keymap.set('n', 'gx', function()
    local s = state()
    if not s then return end
    local picker = require('beadboard.picker')
    picker.pick_issue('Duplicate of', function(target)
      if not target then return end
      mutate_and_refresh(buf, s.bead_id, { 'duplicate', s.bead_id, '--of', target })
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Mark as duplicate' }))

  -- Supersede with another issue
  vim.keymap.set('n', 'gX', function()
    local s = state()
    if not s then return end
    local picker = require('beadboard.picker')
    picker.pick_issue('Supersede with', function(target)
      if not target then return end
      mutate_and_refresh(buf, s.bead_id, { 'supersede', s.bead_id, '--with', target })
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Supersede with issue' }))

  -- Rename issue ID
  vim.keymap.set('n', 'eI', function()
    local s = state()
    if not s then return end
    vim.ui.input({ prompt = 'New ID: ' }, function(new_id)
      if not new_id or new_id == '' then return end
      cli.run({ 'rename', s.bead_id, new_id }, function(err)
        if err then
          vim.notify('beadboard: ' .. err, vim.log.levels.ERROR)
          return
        end
        vim.notify('beadboard: renamed to ' .. new_id)
        s.bead_id = new_id
        refresh_detail(buf, new_id)
      end)
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Rename issue ID' }))

  -- Promote wisp to permanent bead
  vim.keymap.set('n', 'gW', function()
    local s = state()
    if not s then return end
    vim.ui.input({ prompt = 'Promote reason (optional): ' }, function(reason)
      local args = { 'promote', s.bead_id }
      if reason and reason ~= '' then
        args[#args + 1] = '--reason'
        args[#args + 1] = reason
      end
      mutate_and_refresh(buf, s.bead_id, args)
    end)
  end, vim.tbl_extend('force', opts, { desc = 'Promote wisp' }))

  -- Claude skill picker
  vim.keymap.set('n', 'gC', function()
    local s = state()
    if not s then return end
    require('beadboard.claude').pick_and_run(s.bead or s.bead_id)
  end, vim.tbl_extend('force', opts, { desc = 'Claude skill picker' }))

  -- Jump to active Claude session
  vim.keymap.set('n', 'gT', function()
    local s = state()
    if not s then return end
    require('beadboard.claude').focus(s.bead_id)
  end, vim.tbl_extend('force', opts, { desc = 'Jump to Claude' }))

  -- Help
  vim.keymap.set('n', '?', function()
    require('beadboard.help').open()
  end, opts)
end

function M.refresh(buf, bead_id)
  local s = buf_state[buf]
  if s then
    refresh_detail(buf, s.bead_id)
  elseif bead_id then
    refresh_detail(buf, bead_id)
  end
end

function M.get_state(buf)
  return buf_state[buf]
end

function M.should_refresh(buf)
  local state = buf_state[buf]
  if not state or not state.bead or not state.bead_id then return false end
  local data, err = cli.run_sync({ 'show', state.bead_id })
  if err or not data or #data == 0 then return false end
  return data[1].updated_at ~= state.bead.updated_at
end

function M.open(bead_id)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'beadboard-detail'

  buf_state[buf] = { bead_id = bead_id }

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function()
      buf_state[buf] = nil
    end,
  })

  vim.api.nvim_set_current_buf(buf)
  setup_keymaps(buf)

  -- Loading message
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '[beadboard] Loading ' .. bead_id .. '...' })
  vim.bo[buf].modifiable = false

  refresh_detail(buf, bead_id)
end

return M
