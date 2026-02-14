local cli = require('beadboard.cli')

local M = {}

local default_types = { 'task', 'bug', 'feature', 'chore', 'epic' }
local priority_choices = { '0', '1', '2', '3', '4' }

local function fetch_types(callback)
  cli.run({ 'types' }, function(err, data)
    if err or not data then
      callback(default_types)
      return
    end
    local types = {}
    for _, list in ipairs({ data.core_types or {}, data.custom_types or {} }) do
      for _, t in ipairs(list) do
        types[#types + 1] = t.name
      end
    end
    if #types == 0 then
      types = default_types
    end
    callback(types)
  end)
end

local function fetch_labels(callback)
  cli.run({ 'label', 'list-all' }, function(err, data)
    if err or not data or type(data) ~= 'table' then
      callback({})
      return
    end
    callback(data)
  end)
end

-- Open a scratch buffer for multiline description input.
-- Calls callback(text) on save, callback(nil) on quit without saving.
local function open_description_buf(callback)
  local buf = vim.api.nvim_create_buf(false, true)
  local called = false

  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'markdown'

  vim.api.nvim_buf_set_name(buf, 'beadboard://new/description')

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '' })
  vim.bo[buf].modified = false

  vim.api.nvim_set_current_buf(buf)

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local content = table.concat(
        vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'
      )
      content = content:gsub('\n+$', '')
      vim.bo[buf].modified = false
      called = true
      vim.api.nvim_buf_delete(buf, { force = true })
      callback(content)
    end,
  })

  vim.keymap.set('n', 'q', function()
    if not called then
      called = true
      vim.api.nvim_buf_delete(buf, { force = true })
      callback(nil)
    end
  end, { buffer = buf, nowait = true, silent = true, desc = 'Close without saving' })
end

-- Run the sequential create wizard, then call on_done() on success.
function M.open(on_done)
  vim.notify('beadboard: loading types and labels...', vim.log.levels.INFO)

  local types, labels
  local ready = 0

  local function check_ready()
    ready = ready + 1
    if ready < 2 then return end
    M._wizard(types, labels, on_done)
  end

  fetch_types(function(t)
    types = t
    check_ready()
  end)

  fetch_labels(function(l)
    labels = l
    check_ready()
  end)
end

function M._wizard(types, labels, on_done)
  -- Step 1: Title (required)
  vim.ui.input({ prompt = 'Title: ' }, function(title)
    if not title or title == '' then return end

    -- Step 2: Type
    vim.ui.select(types, {
      prompt = 'Type:',
      format_item = function(t) return t end,
    }, function(chosen_type)
      chosen_type = chosen_type or 'task'

      -- Step 3: Priority
      vim.ui.select(priority_choices, {
        prompt = 'Priority:',
        format_item = function(p) return 'P' .. p end,
      }, function(chosen_priority)
        chosen_priority = chosen_priority or '2'

        -- Step 4: Description (scratch buffer)
        open_description_buf(function(description)

          -- Step 5: Assignee
          vim.ui.input({ prompt = 'Assignee (empty to skip): ' }, function(assignee)
            assignee = (assignee and assignee ~= '') and assignee or nil

            -- Step 6: Labels
            M._pick_labels(labels, {}, function(chosen_labels)

              -- Step 7: Parent
              vim.ui.input({ prompt = 'Parent ID (empty to skip): ' }, function(parent)
                parent = (parent and parent ~= '') and parent or nil

                M._submit(title, chosen_type, chosen_priority,
                  description, assignee, chosen_labels, parent, on_done)
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end

-- Allow picking multiple labels via repeated vim.ui.select.
function M._pick_labels(available, chosen, callback)
  if #available == 0 then
    callback(chosen)
    return
  end

  local items = { '(done)' }
  for _, l in ipairs(available) do
    items[#items + 1] = l
  end

  vim.ui.select(items, {
    prompt = 'Add label:',
    format_item = function(item)
      if item == '(done)' then return '(done selecting labels)' end
      return item
    end,
  }, function(choice)
    if not choice or choice == '(done)' then
      callback(chosen)
      return
    end
    chosen[#chosen + 1] = choice
    -- Remove selected label from available to avoid duplicates
    local remaining = {}
    for _, l in ipairs(available) do
      if l ~= choice then
        remaining[#remaining + 1] = l
      end
    end
    M._pick_labels(remaining, chosen, callback)
  end)
end

function M._submit(title, type_name, priority, description, assignee,
                    labels, parent, on_done)
  local args = { 'create', title, '--type', type_name, '--priority', priority }

  if description and description ~= '' then
    args[#args + 1] = '--description'
    args[#args + 1] = description
  end

  if assignee then
    args[#args + 1] = '--assignee'
    args[#args + 1] = assignee
  end

  for _, l in ipairs(labels) do
    args[#args + 1] = '--add-label'
    args[#args + 1] = l
  end

  if parent then
    args[#args + 1] = '--parent'
    args[#args + 1] = parent
  end

  cli.run(args, function(err, data)
    if err then
      vim.notify('beadboard: ' .. err, vim.log.levels.ERROR)
      return
    end
    local id = data and data.id or '?'
    vim.notify('beadboard: created ' .. id)
    if on_done then on_done() end
  end)
end

return M
