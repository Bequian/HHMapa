-- ============================================================
--  HH Mapa - Minimapa
--  Calcula la distancia en yardas desde el jugador a cada miembro
--  y coloca el punto sobre el minimapa (con soporte de rotación).
-- ============================================================
local ADDON, ns = ...

local PIN_SIZE = 16
local pins = {}       -- [nombre] = frame
local active = {}     -- pines visibles (para el tooltip de superpuestos)

-- Diámetro visible del minimapa en yardas por nivel de zoom (clientes sin C_Minimap)
local DIAMETER = {
    indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
}
local indoors = "outdoor"
local checking = false

local function CheckIndoors()
    if checking or (C_Minimap and C_Minimap.GetViewRadius) then return end
    checking = true
    local zoom = Minimap:GetZoom()
    if GetCVar("minimapZoom") == GetCVar("minimapInsideZoom") then
        Minimap:SetZoom(zoom < 2 and zoom + 1 or zoom - 1)
    end
    indoors = (tonumber(GetCVar("minimapZoom")) == Minimap:GetZoom()) and "outdoor" or "indoor"
    Minimap:SetZoom(zoom)
    checking = false
end

local function ViewRadius()
    if C_Minimap and C_Minimap.GetViewRadius then
        return C_Minimap.GetViewRadius()
    end
    return (DIAMETER[indoors][Minimap:GetZoom()] or 466) / 2
end

-- ------------------------------------------------------------
-- Ejes del mapa actual en coordenadas de mundo.
-- Así sabemos hacia dónde es "este" y "sur" sin suponer nada
-- sobre cómo Blizzard orienta el sistema de coordenadas.
-- ------------------------------------------------------------
local vec = CreateVector2D(0, 0)
local axisMap, ex, ey, sx, sy, axesOK

local function WorldPos(mapID, x, y)
    vec:SetXY(x, y)
    return C_Map.GetWorldPosFromMapPos(mapID, vec)
end

local function SetupAxes(mapID)
    axisMap, axesOK = mapID, false
    local _, p00 = WorldPos(mapID, 0, 0)
    local _, p10 = WorldPos(mapID, 1, 0)
    local _, p01 = WorldPos(mapID, 0, 1)
    if not (p00 and p10 and p01) then return end

    local ax, ay = p00:GetXY()
    local bx, by = p10:GetXY()
    local cx, cy = p01:GetXY()
    ex, ey = bx - ax, by - ay   -- vector "este"
    sx, sy = cx - ax, cy - ay   -- vector "sur"
    local eLen = math.sqrt(ex * ex + ey * ey)
    local sLen = math.sqrt(sx * sx + sy * sy)
    if eLen == 0 or sLen == 0 then return end
    ex, ey, sx, sy = ex / eLen, ey / eLen, sx / sLen, sy / sLen
    axesOK = true
end

-- ------------------------------------------------------------
-- Pines
-- ------------------------------------------------------------
local function OnEnter(self)
    ns.ShowTooltip(self, self.member, active)
end

local function OnLeave()
    GameTooltip:Hide()
end

local function OnMouseUp(self, button)
    if button == "RightButton" then ns.ShowMenu(self.member) end
end

local function CreatePin(name)
    local pin = CreateFrame("Frame", nil, Minimap)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    ns.BuildDot(pin)
    pin:SetMouseMotionEnabled(true)  -- tooltip
    pin:SetMouseClickEnabled(true)   -- clic derecho = menú
    pin.passOK = ns.PassLeftClick(pin) -- clic izquierdo sigue llegando al minimapa
    pin:SetScript("OnMouseUp", OnMouseUp)
    pin:SetScript("OnEnter", OnEnter)
    pin:SetScript("OnLeave", OnLeave)
    pins[name] = pin
    return pin
end

local function HideAll()
    for _, pin in pairs(pins) do pin:Hide() end
    wipe(active)
end

function ns.UpdateMinimap()
    if not HHMapaDB.minimap or not next(ns.members) then
        if #active > 0 then HideAll() end
        return
    end

    local mapID, px, py = ns.GetPlayerPos()
    if not mapID then HideAll() return end
    if mapID ~= axisMap then SetupAxes(mapID) end
    if not axesOK then HideAll() return end

    local cont, ppos = WorldPos(mapID, px, py)
    if not ppos then HideAll() return end
    local pwx, pwy = ppos:GetXY()

    local radius = ViewRadius()
    local half = Minimap:GetWidth() / 2

    -- Rotación del minimapa
    local rotate = GetCVar("rotateMinimap") == "1"
    local sinF, cosF = 0, 1
    if rotate then
        local f = GetPlayerFacing()
        if f and not ns.IsSecret(f) then
            sinF, cosF = math.sin(f), math.cos(f)
        end
    end

    local restyle = ns.mmDirty
    ns.mmDirty = false
    wipe(active)

    for name, m in pairs(ns.members) do
        local shown = false
        if m.cont == cont and m.wpos and not ns.IsHidden(m) then
            local wx, wy = m.wpos:GetXY()
            local dx, dy = wx - pwx, wy - pwy
            local east  = dx * ex + dy * ey
            local north = -(dx * sx + dy * sy)
            if rotate then
                east, north = east * cosF + north * sinF, -east * sinF + north * cosF
            end

            if east * east + north * north < radius * radius then
                local pin = pins[name]
                local isNew = not pin
                if isNew then pin = CreatePin(name) end
                if isNew or restyle or pin.member ~= m then
                    pin.member = m
                    ns.StyleDot(pin, m, PIN_SIZE)
                end
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", Minimap, "CENTER", east / radius * half, north / radius * half)
                if not pin.passOK then pin.passOK = ns.PassLeftClick(pin) end
                pin:Show()
                active[#active + 1] = pin
                shown = true
            end
        end
        if not shown and pins[name] then pins[name]:Hide() end
    end

    -- Pines de miembros que ya no están
    for name, pin in pairs(pins) do
        if not ns.members[name] then pin:Hide() end
    end
end

function ns.InitMinimap()
    local f = CreateFrame("Frame")
    f:RegisterEvent("MINIMAP_UPDATE_ZOOM")
    f:RegisterEvent("ZONE_CHANGED")
    f:RegisterEvent("ZONE_CHANGED_INDOORS")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:SetScript("OnEvent", CheckIndoors)
    CheckIndoors()
end
