--- STEAMODDED HEADER
--- MOD_NAME: Alphabetical Mods Menu
--- MOD_ID: AlphaModsMenuSort
--- MOD_AUTHOR: [ChatGPT]
--- MOD_DESCRIPTION: Sorts the Mods menu alphabetically for display only (does not change load order).
--- PRIORITY: 1000000000
--- BADGE_COLOUR: 5A2D82
--- BADGE_TEXT_COLOUR: FFFFFF
--- DISPLAY_NAME: A→Z
--- VERSION: 1.0.0
--- PREFIX: amz

-- Alphabetical Mods Menu Sort (display-only)
-- This mod patches Steamodded's Mods menu builder so the list is sorted alphabetically
-- without changing the underlying load order (priority-based).

local function _safe_lower(s)
  s = tostring(s or "")
  return string.lower(s)
end

local function _display_name(mod)
  -- Prefer localized name if available, else mod.name, else mod.id
  local name = mod and (mod.name or mod.id) or ""
  if type(localize) == "function" and mod and mod.id and G and G.localization and G.localization.descriptions
     and (G.localization.descriptions.Mod or {})[mod.id] then
    local ok, loc = pcall(function()
      return localize({ type = "name_text", set = "Mod", key = mod.id })
    end)
    if ok and type(loc) == "string" and loc ~= "ERROR" and loc ~= "" then
      name = loc
    end
  end
  return name
end

-- Retrieve a named upvalue from a Lua function, returns nil on any failure.
local function _try_get_upvalue(func, name)
  if not debug or type(debug.getupvalue) ~= "function" then return nil end
  local i = 1
  while true do
    local n, v = debug.getupvalue(func, i)
    if n == nil then break end
    if n == name then return v end
    i = i + 1
  end
  return nil
end

local function _sorted_copy(mod_list)
  local t = {}
  for i, v in ipairs(mod_list or {}) do t[i] = v end
  table.sort(t, function(a, b)
    -- Pure alphabetical, no group separation
    local na, nb = _safe_lower(_display_name(a)), _safe_lower(_display_name(b))
    if na ~= nb then return na < nb end
    return tostring(a.id or "") < tostring(b.id or "")
  end)
  return t
end

local function _patch_dynamic()
  if not SMODS or not SMODS.GUI then return false end
  if SMODS.GUI.__amz_patched then return true end
  if type(SMODS.GUI.dynamicModListContent) ~= "function" then return false end

  local old = SMODS.GUI.dynamicModListContent

  -- Extract Steamodded-internal local functions via upvalues so we can build
  -- a full replacement that merges the config/no-config sections into one pass.
  local create_box  = _try_get_upvalue(old, "createClickableModBox")
  local recalc_list = _try_get_upvalue(old, "recalculateModsList")

  if create_box and recalc_list then
    -- Full replacement: combines the two can_load passes (with/without config_tab)
    -- into a single alphabetical section.
    SMODS.GUI.dynamicModListContent = function(page)
      local scale   = 0.75
      local sorted  = _sorted_copy(SMODS.mod_list)
      local _, _, showingList, startIndex, endIndex, modsRowPerPage, modsColPerRow =
        recalc_list(page)
      local modNodes = {}

      if not showingList then
        table.insert(modNodes, {
          n = G.UIT.R,
          config = { padding = 0, align = "cm" },
          nodes = {{ n = G.UIT.T, config = {
            text = localize('b_no_mods'), shadow = true,
            scale = scale * 0.5, colour = G.C.UI.TEXT_DARK
          }}}
        })
      else
        local modCount    = 0
        local id          = 0
        local current_row = {}

        -- Single pass: pure alphabetical, no grouping
        for _, modInfo in ipairs(sorted) do
          if modCount >= modsRowPerPage * modsColPerRow then break end
          id = id + 1
          if id >= startIndex and id <= endIndex then
            table.insert(current_row, create_box(modInfo, scale * 0.5))
            modCount = modCount + 1
            if modCount % modsColPerRow == 0 then
              table.insert(modNodes, {
                n = G.UIT.R,
                config = { padding = 0, align = "lc" },
                nodes = current_row
              })
              current_row = {}
            end
          end
        end

        if #current_row > 0 then
          table.insert(modNodes, {
            n = G.UIT.R,
            config = { padding = 0, align = "lc" },
            nodes = current_row
          })
        end
      end

      return { n = G.UIT.C, config = { r = 0.1, align = "cm", padding = 0 }, nodes = modNodes }
    end
  else
    -- Fallback when the debug library or upvalue names are unavailable:
    -- sort mod_list so each section is alphabetical even if they remain separate.
    SMODS.GUI.dynamicModListContent = function(page, ...)
      local orig    = SMODS.mod_list
      local swapped = false
      if type(orig) == "table" then
        SMODS.mod_list = _sorted_copy(orig)
        swapped = true
      end
      local ok, res = pcall(old, page, ...)
      if swapped then SMODS.mod_list = orig end
      if not ok then error(res) end
      return res
    end
  end

  SMODS.GUI.__amz_patched = true
  return true
end

-- Try immediately (many setups already have SMODS.GUI by the time mods load)
if not _patch_dynamic() then
  -- Fallback: patch as soon as the Mods menu is opened.
  -- This ensures we don't depend on load ordering across Steamodded versions.
  if G and G.FUNCS and type(G.FUNCS.mods_button) == "function" and not G.FUNCS.__amz_wrapped then
    local old_btn = G.FUNCS.mods_button
    G.FUNCS.mods_button = function(e)
      _patch_dynamic()
      return old_btn(e)
    end
    G.FUNCS.__amz_wrapped = true
  end
end
