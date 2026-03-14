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

-- Pagination constants matching Steamodded's defaults (src/ui.lua ~line 1959).
local MODS_ROWS_PER_PAGE = 4
local MODS_COLS_PER_ROW  = 3
-- Scale at which each mod box is rendered (Steamodded passes 0.75 * 0.5).
local MOD_BOX_SCALE      = 0.375

-- Inlined pagination logic from Steamodded's recalculateModsList (src/ui.lua ~line 1959).
-- Returns: nil, nil, showingList, startIndex, endIndex, modsRowPerPage, modsColPerRow
local function _inline_recalc(page, total)
  page = page or 1
  local startIndex = (page - 1) * MODS_ROWS_PER_PAGE * MODS_COLS_PER_ROW + 1
  local endIndex   = startIndex + MODS_ROWS_PER_PAGE * MODS_COLS_PER_ROW - 1
  local showingList = total > 0
  return nil, nil, showingList, startIndex, endIndex, MODS_ROWS_PER_PAGE, MODS_COLS_PER_ROW
end

-- Try to locate createClickableModBox: first by upvalue name, then by probing all
-- function-type upvalues of old_fn.  Returns nil when the debug library is absent
-- or no matching candidate is found.
local function _find_create_box(old_fn)
  if not debug or type(debug.getupvalue) ~= "function" then return nil end

  -- Try the known upvalue name first.
  local cb = _try_get_upvalue(old_fn, "createClickableModBox")
  if cb then return cb end

  -- Iterate every upvalue and test function-type candidates.
  -- createClickableModBox(modInfo, scale) returns a {n = G.UIT.C, ...} table.
  if not (G and G.UIT and SMODS and SMODS.mod_list and SMODS.mod_list[1]) then
    return nil
  end
  local i = 1
  while true do
    local n, v = debug.getupvalue(old_fn, i)
    if n == nil then break end
    if type(v) == "function" then
      -- Save and restore SMODS.LAST_VIEWED_MODS_PAGE around the probe call,
      -- because calling recalculateModsList (another upvalue) with a non-number
      -- argument would corrupt this global and cause a crash later.
      local saved_page = SMODS.LAST_VIEWED_MODS_PAGE
      local ok, result = pcall(v, SMODS.mod_list[1], MOD_BOX_SCALE)
      SMODS.LAST_VIEWED_MODS_PAGE = saved_page
      if ok and type(result) == "table" and result.n == G.UIT.C then
        return v
      end
    end
    i = i + 1
  end
  return nil
end

-- Build the shared single-pass mod-grid body used when create_box is available.
local function _build_grid(sorted, startIndex, endIndex, modsRowPerPage, modsColPerRow, create_box)
  local modNodes    = {}
  local modCount    = 0
  local id          = 0
  local current_row = {}

  for _, modInfo in ipairs(sorted) do
    if modCount >= modsRowPerPage * modsColPerRow then break end
    id = id + 1
    if id >= startIndex and id <= endIndex then
      table.insert(current_row, create_box(modInfo, MOD_BOX_SCALE))
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
  return modNodes
end

local function _patch_dynamic()
  if not SMODS or not SMODS.GUI then return false end
  if SMODS.GUI.__amz_patched then return true end
  if type(SMODS.GUI.dynamicModListContent) ~= "function" then return false end

  local old = SMODS.GUI.dynamicModListContent

  local create_box = _find_create_box(old)

  if create_box then
    -- Full replacement: single alphabetical pass, no grouping by can_load / config_tab.
    SMODS.GUI.dynamicModListContent = function(page)
      local sorted  = _sorted_copy(SMODS.mod_list)
      local _, _, showingList, startIndex, endIndex, modsRowPerPage, modsColPerRow =
        _inline_recalc(page, #sorted)
      local modNodes = {}

      if not showingList then
        table.insert(modNodes, {
          n = G.UIT.R,
          config = { padding = 0, align = "cm" },
          nodes = {{ n = G.UIT.T, config = {
            text = localize('b_no_mods'), shadow = true,
            scale = MOD_BOX_SCALE, colour = G.C.UI.TEXT_DARK
          }}}
        })
      else
        modNodes = _build_grid(sorted, startIndex, endIndex, modsRowPerPage, modsColPerRow, create_box)
      end

      return { n = G.UIT.C, config = { r = 0.1, align = "cm", padding = 0 }, nodes = modNodes }
    end
  else
    -- Robust fallback: call the original function once per mod (with a temporary
    -- single-element mod list) to extract each mod's pre-rendered UI box, then
    -- assemble them in alphabetical order with our own pagination.  This avoids
    -- any dependence on debug.getupvalue and still produces a single A→Z list.
    SMODS.GUI.dynamicModListContent = function(page)
      local sorted  = _sorted_copy(SMODS.mod_list)
      local total   = #sorted
      local _, _, showingList, startIndex, endIndex, modsRowPerPage, modsColPerRow =
        _inline_recalc(page, total)
      local modNodes = {}

      if not showingList then
        local ok, res = pcall(old, page)
        if ok and res then return res end
        table.insert(modNodes, {
          n = G.UIT.R,
          config = { padding = 0, align = "cm" },
          nodes = {{ n = G.UIT.T, config = {
            text = localize('b_no_mods'), shadow = true,
            scale = MOD_BOX_SCALE, colour = G.C.UI.TEXT_DARK
          }}}
        })
      else
        local orig_list   = SMODS.mod_list
        local id          = 0
        local modCount    = 0
        local current_row = {}

        for _, modInfo in ipairs(sorted) do
          if modCount >= modsRowPerPage * modsColPerRow then break end
          id = id + 1
          if id >= startIndex and id <= endIndex then
            -- Temporarily replace mod_list so the original function renders only
            -- this one mod, letting createClickableModBox run naturally.
            SMODS.mod_list = { modInfo }
            local ok, res = pcall(old, 1)
            SMODS.mod_list = orig_list  -- always restore immediately

            -- Extract the first G.UIT.C node from the returned tree.
            local box = nil
            if ok and type(res) == "table" and res.nodes then
              for _, row in ipairs(res.nodes) do
                if type(row) == "table" and row.nodes then
                  for _, b in ipairs(row.nodes) do
                    if type(b) == "table" and b.n == G.UIT.C then
                      box = b
                      break
                    end
                  end
                end
                if box then break end
              end
            end

            if box then
              table.insert(current_row, box)
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
