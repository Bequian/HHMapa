-- ============================================================
--  HH Mapa - Miembros de HustlinHitmans en el mapa y minimapa
--  Núcleo: comunicación, datos de miembros, layer, opciones.
--  Sin librerías externas.
-- ============================================================
local ADDON, ns = ...

local PREFIX    = "HHMapa"   -- prefijo de mensajes de addon (máx. 16 caracteres)
local PROTO     = "1"        -- versión del protocolo
local SEND_TICK = 2.5        -- cada cuánto revisamos si hay que enviar (seg)
local HEARTBEAT = 10         -- enviamos al menos cada X seg aunque no nos movamos
local TIMEOUT   = 30         -- si no sabemos de alguien en X seg, lo quitamos
local MOVE_MIN  = 0.002      -- movimiento mínimo (coords de mapa) para reenviar

ns.members = {}   -- [nombre] = { name, sender, mapID, x, y, level, class, layer, leader, seen, cont, wpos }
ns.layer   = 0    -- nuestro layer (0 = desconocido)
ns.dirty   = false
ns.mmDirty = true

local members = ns.members
local defaults = { map = true, minimap = true, hideGroup = true, share = true, panel = false }

-- ------------------------------------------------------------
-- Utilidades
-- ------------------------------------------------------------
function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd4af37HH Mapa|r: " .. msg)
end

-- "Nombre-Reino" -> "Nombre"
function ns.ShortName(name)
    return name and (name:match("^([^%-]+)") or name)
end

-- Valores "secretos" (APIs restringidas en clientes modernos)
function ns.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

function ns.Changed()
    ns.dirty = true
    ns.mmDirty = true
end

-- Posición del jugador: mapID, x, y (nil si no hay posición, p. ej. en mazmorras)
function ns.GetPlayerPos()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    if not x or ns.IsSecret(x) or (x == 0 and y == 0) then return end
    return mapID, x, y
end

-- Layer actual: lo entrega NovaWorldBuffs si está instalado
local function ReadLayer()
    return tonumber(NWB_CurrentLayer) or 0
end

-- ------------------------------------------------------------
-- Envío de nuestra posición
-- ------------------------------------------------------------
local myGUID
local last = { mapID = -1, x = 0, y = 0, layer = -1, t = 0 }

local function Send(force)
    if not IsInGuild() or not myGUID then return end

    local mapID, x, y = 0, 0, 0
    if HHMapaDB.share then
        local m, px, py = ns.GetPlayerPos()
        if m then mapID, x, y = m, px, py end
    end

    -- mapID 0 = "ocúltame": basta con avisarlo una vez
    if mapID == 0 and last.mapID == 0 and not force then return end

    local now = GetTime()
    local changed = mapID ~= last.mapID
        or math.abs(x - last.x) > MOVE_MIN
        or math.abs(y - last.y) > MOVE_MIN
        or ns.layer ~= last.layer
    if not force and not changed and (now - last.t) < HEARTBEAT then return end

    local _, class = UnitClass("player")
    local leader = (IsGuildLeader and IsGuildLeader()) and 1 or 0
    local msg = string.format("%s,%d,%.4f,%.4f,%d,%s,%d,%d,%s",
        PROTO, mapID, x, y, UnitLevel("player"), class, ns.layer, leader, myGUID)

    C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")
    last.mapID, last.x, last.y, last.layer, last.t = mapID, x, y, ns.layer, now
end
ns.Send = Send

-- ------------------------------------------------------------
-- Recepción de posiciones
-- ------------------------------------------------------------
local vec -- vector reutilizable

local function OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= PREFIX or channel ~= "GUILD" then return end

    local proto, mapID, x, y, level, class, layer, leader, guid = strsplit(",", text)
    if proto ~= PROTO or not guid or guid == myGUID then return end

    local name = ns.ShortName(sender)
    mapID, x, y = tonumber(mapID) or 0, tonumber(x), tonumber(y)

    -- Sin posición (mazmorra, posición oculta, etc.): lo quitamos
    if mapID == 0 or not x or not y then
        if members[name] then
            members[name] = nil
            ns.Changed()
        end
        return
    end

    local m = members[name]
    if not m then
        m = {}
        members[name] = m
    end
    m.name, m.sender = name, sender
    m.mapID, m.x, m.y = mapID, x, y
    m.level  = tonumber(level) or 0
    m.class  = class
    m.layer  = tonumber(layer) or 0
    m.leader = (leader == "1")
    m.seen   = GetTime()

    -- Posición "mundial": sirve para proyectar en otros mapas y en el minimapa
    vec = vec or CreateVector2D(0, 0)
    vec:SetXY(x, y)
    m.cont, m.wpos = C_Map.GetWorldPosFromMapPos(mapID, vec)

    ns.Changed()
end

-- ------------------------------------------------------------
-- Bucle único (un solo OnUpdate para todo el addon)
-- ------------------------------------------------------------
local tSend, tPurge, tMap, tMini = 0, 0, 0, 0
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, elapsed)
    tSend, tPurge = tSend + elapsed, tPurge + elapsed
    tMap, tMini   = tMap + elapsed, tMini + elapsed

    if tSend >= SEND_TICK then
        tSend = 0
        local l = ReadLayer()
        if l ~= ns.layer then
            ns.layer = l
            ns.Changed()
        end
        Send()
    end

    if tPurge >= 5 then
        tPurge = 0
        local now = GetTime()
        for name, m in pairs(members) do
            if now - m.seen > TIMEOUT then
                members[name] = nil
                ns.Changed()
            end
        end
    end

    -- Mapa del mundo: como máximo 2 refrescos por segundo y solo si algo cambió
    if tMap >= 0.5 then
        tMap = 0
        if ns.dirty then
            ns.dirty = false
            if ns.RefreshMap then ns.RefreshMap() end
        end
    end

    -- Minimapa: 10 veces por segundo (es barato y se ve fluido)
    if tMini >= 0.1 then
        tMini = 0
        if ns.UpdateMinimap then ns.UpdateMinimap() end
    end
end)

-- ------------------------------------------------------------
-- Panel de opciones (muy básico)
-- ------------------------------------------------------------
function ns.OnOptionChanged(key)
    if key == "share" then
        Send(true)
    end
    ns.Changed()
end

local function CreateOptions()
    local p = CreateFrame("Frame")
    p.name = "HH Mapa"

    local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("HH Mapa |cff888888- HustlinHitmans|r")

    local sub = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Comandos: /hhm mapa | mini | lista | compartir | layer | quien")

    local y = -64
    local function Check(key, label)
        local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 16, y)
        y = y - 32
        local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        fs:SetText(label)
        cb:SetScript("OnShow", function(self) self:SetChecked(HHMapaDB[key]) end)
        cb:SetScript("OnClick", function(self)
            HHMapaDB[key] = self:GetChecked() and true or false
            ns.OnOptionChanged(key)
        end)
    end

    Check("map",       "Mostrar miembros en el mapa del mundo")
    Check("minimap",   "Mostrar miembros en el minimapa")
    Check("hideGroup", "Ocultar a los miembros de mi grupo (Blizzard ya los muestra)")
    Check("share",     "Compartir mi posición con la hermandad")

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(p, p.name)
        Settings.RegisterAddOnCategory(cat)
        ns.settingsCategory = cat
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(p)
    end
    ns.optionsPanel = p
end

local function OpenOptions()
    if ns.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel) -- 2 veces: bug clásico de Blizzard
    end
end

-- ------------------------------------------------------------
-- Comandos
-- ------------------------------------------------------------
local function Toggle(key, label)
    HHMapaDB[key] = not HHMapaDB[key]
    ns.OnOptionChanged(key)
    ns.Print(label .. ": " .. (HHMapaDB[key] and "|cff20ff20activado|r" or "|cffff5050desactivado|r"))
end

SLASH_HHMAPA1 = "/hhm"
SLASH_HHMAPA2 = "/hhmapa"
SlashCmdList.HHMAPA = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "mapa" then
        Toggle("map", "Iconos en el mapa")
    elseif msg == "mini" then
        Toggle("minimap", "Iconos en el minimapa")
    elseif msg == "compartir" then
        Toggle("share", "Compartir mi posición")
    elseif msg == "lista" then
        if ns.TogglePanel then ns.TogglePanel() end
    elseif msg == "layer" then
        if ns.layer == 0 then
            ns.Print("Layer desconocido. Instala NovaWorldBuffs para detectar el layer.")
        else
            ns.Print("Estás en el layer " .. ns.layer .. ".")
        end
    elseif msg == "quien" then
        local list = {}
        for name, m in pairs(members) do
            local c = (RAID_CLASS_COLORS[m.class] or { colorStr = "ffffffff" }).colorStr
            list[#list + 1] = "|c" .. c .. name .. "|r"
        end
        table.sort(list)
        ns.Print(#list .. " miembro(s) con HH Mapa visibles: " .. table.concat(list, ", "))
    else
        OpenOptions()
    end
end

-- ------------------------------------------------------------
-- Eventos
-- ------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("PLAYER_GUILD_UPDATE")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        OnAddonMessage(...)

    elseif event == "ADDON_LOADED" then
        if ... == ADDON then
            HHMapaDB = HHMapaDB or {}
            for k, v in pairs(defaults) do
                if HHMapaDB[k] == nil then HHMapaDB[k] = v end
            end
        end

    elseif event == "PLAYER_LOGIN" then
        myGUID = UnitGUID("player")
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        ns.layer = ReadLayer()
        CreateOptions()

        -- El mapa del mundo puede cargarse bajo demanda
        if not WorldMapFrame then
            local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
            load("Blizzard_WorldMap")
        end
        if WorldMapFrame and ns.InitMap then ns.InitMap() end
        if ns.InitMinimap then ns.InitMinimap() end

        driver:Show()

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(2, function() Send(true) end)

    elseif event == "PLAYER_GUILD_UPDATE" then
        if not IsInGuild() then
            wipe(members)
            ns.Changed()
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        ns.Changed()
    end
end)
