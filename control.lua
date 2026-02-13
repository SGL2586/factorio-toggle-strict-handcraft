local function parse_blocked_items(player)
  local setting = settings.get_player_settings(player)["strict-handcraft-items"].value
  local blocked = {}

  for item in string.gmatch(setting, "([^,]+)") do
    local trimmed = string.gsub(item, "^%s*(.-)%s*$", "%1")
    blocked[trimmed] = true
  end

  return blocked
end

local function is_strict_enabled(player)
  global.strict_enabled = global.strict_enabled or {}
  return global.strict_enabled[player.index] == true
end

local function set_strict_enabled(player, state)
  global.strict_enabled = global.strict_enabled or {}
  global.strict_enabled[player.index] = state
end

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= "strict-handcraft-toggle" then return end

  local player = game.get_player(event.player_index)
  if not player then return end

  local current = is_strict_enabled(player)
  local new_state = not current

  set_strict_enabled(player, new_state)
  player.set_shortcut_toggled("strict-handcraft-toggle", new_state)

  if new_state then
    player.print("Strict Handcraft Mode ENABLED")
  else
    player.print("Strict Handcraft Mode DISABLED")
  end
end)

script.on_event(defines.events.on_pre_player_crafted_item, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  if not is_strict_enabled(player) then return end

  local recipe = event.recipe
  if not recipe then return end

  local blocked = parse_blocked_items(player)

  -- Check recipe results
  for _, product in pairs(recipe.products) do
    if blocked[product.name] then
      -- Cancel crafting
      player.cancel_crafting({ index = event.queue_index, count = event.queued_count })

      player.print("Handcrafting of '" .. product.name .. "' is disabled in Strict Mode.")
      return
    end
  end
end)
