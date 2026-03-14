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

local function _group(mod)
  -- Keep Steamodded's current grouping idea:
  -- 1) enabled mods with config
  -- 2) enabled mods
  -- 3) disabled mods
  if mod and mod.disabled then return 3 end
  if mod and mod.config_tab then return 1 end
  return 2
end

local function _sorted_copy(mod_list)
  local t = {}
  for i, v in ipairs(mod_list or {}) do t[i] = v end
  table.sort(t, function(a, b)
    local ga, gb = _group(a), _group(b)
    if ga ~= gb then return ga < gb end
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
  SMODS.GUI.dynamicModListContent = function(page, ...)
    local orig = SMODS.mod_list
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
