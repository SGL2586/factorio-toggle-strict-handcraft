----------------------------------------------------------------
-- STORAGE INIT
----------------------------------------------------------------
script.on_init(function()
  storage.strict_enabled = {}
  storage.blocked_recipes = {}
  storage.consumed_items = {}
  storage.blocked_counts = {}
end)
script.on_configuration_changed(function()
  storage.strict_enabled = storage.strict_enabled or {}
  storage.blocked_recipes = storage.blocked_recipes or {}
  storage.consumed_items = storage.consumed_items or {}
  storage.blocked_counts = storage.blocked_counts or {}
end)

local function is_strict_enabled(player)
  return storage.strict_enabled[player.index] == true
end
local function set_strict_enabled(player, state)
  storage.strict_enabled[player.index] = state
end
local function get_blocked(player)
  storage.blocked_recipes = storage.blocked_recipes or {}
  return storage.blocked_recipes[player.index]
end
local function set_blocked(player, value)
  storage.blocked_recipes = storage.blocked_recipes or {}
  storage.blocked_recipes[player.index] = value
end

----------------------------------------------------------------
-- BLACKLIST HELPERS
----------------------------------------------------------------
local function get_blacklist(player)
  local raw = settings.get_player_settings(player)["strict-handcraft-items"].value
  local blacklist = {}
  for item in raw:gmatch("[^,]+") do
    local trimmed = item:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      blacklist[trimmed] = true
    end
  end
  return blacklist
end

----------------------------------------------------------------
-- TOGGLE SHORTCUT HANDLER
----------------------------------------------------------------
script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= "strict-handcraft-toggle" then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local new_state = not is_strict_enabled(player)
  set_strict_enabled(player, new_state)
  set_blocked(player, nil)
  player.print(new_state
    and "[Strict Handcraft] Enabled"
    or  "[Strict Handcraft] Disabled"
  )
end)

----------------------------------------------------------------
-- PRE-CRAFT — identify blocked crafts and snapshot consumed items
----------------------------------------------------------------
script.on_event(defines.events.on_pre_player_crafted_item, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  if not is_strict_enabled(player) then return end

  local recipe = event.recipe
  if not recipe or not recipe.enabled then return end

  local blacklist = get_blacklist(player)

  local blocked_item = nil
  if blacklist[recipe.name] then
    blocked_item = recipe.name
  else
    for _, item in pairs(event.items.get_contents()) do
      if blacklist[item.name] then
        blocked_item = item.name
        break
      end
    end
  end

  if not blocked_item then return end

  storage.consumed_items = storage.consumed_items or {}
  storage.blocked_counts = storage.blocked_counts or {}

  -- Store total ingredients consumed for the whole batch
  -- We'll divide at refund time to avoid floor-to-zero on large batches
  local snapshot = {}
  for _, item in pairs(event.items.get_contents()) do
    table.insert(snapshot, {
      name = item.name,
      count = item.count,  -- total for whole batch
      quality = item.quality
    })
  end
  storage.consumed_items[player.index] = snapshot
  storage.blocked_counts[player.index] = event.queued_count

  set_blocked(player, blocked_item)

  player.print(
    "[Strict Handcraft] Blocked! '"
    .. recipe.name
    .. "' uses blacklisted item '"
    .. blocked_item
    .. "'. Items refunded."
  )
end)

----------------------------------------------------------------
-- POST-CRAFT — undo any blocked craft using the snapshot
----------------------------------------------------------------
script.on_event(defines.events.on_player_crafted_item, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  if not is_strict_enabled(player) then return end

  local blocked_item = get_blocked(player)
  if not blocked_item then return end

  local recipe = event.recipe
  if not recipe then return end

  local inventory = player.get_main_inventory()
  if not inventory then return end

  -- Always remove whatever was just crafted
  inventory.remove({ name = event.item_stack.name, count = event.item_stack.count })

  if recipe.name == blocked_item or event.item_stack.name == blocked_item then
    storage.blocked_counts = storage.blocked_counts or {}
    local total_crafts = storage.blocked_counts[player.index] or 1
    local remaining = total_crafts - 1
    storage.blocked_counts[player.index] = remaining

    local snapshot = storage.consumed_items and storage.consumed_items[player.index]
    if snapshot then
      for _, item in pairs(snapshot) do
        -- Use ceil(remaining_total / remaining_crafts) so rounding
        -- errors accumulate forward rather than leaving items unrefunded
        local refund = math.ceil(item.count / total_crafts)
        item.count = item.count - refund
        if refund > 0 then
          inventory.insert({ name = item.name, count = refund, quality = item.quality })
        end
      end
    end

    if remaining <= 0 then
      storage.consumed_items[player.index] = nil
      storage.blocked_counts[player.index] = nil
      set_blocked(player, nil)
    end
  end
end)
