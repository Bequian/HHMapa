-- ============================================================
--  HH Mapa - Mapa del mundo
--  Pines (data provider nativo de Blizzard), tooltip, botón y lista.
-- ============================================================
local ADDON, ns = ...

local PIN_TEMPLATE = "HHMapaPinTemplate"
local TEX   = "Interface\\AddOns\\HHMapa\\Textures\\"
local DOT   = TEX .. "dot"
local CROWN = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local CROWN_TEXT = "|T" .. CROWN .. ":14:14|t"
local MAX_ROWS = 25

ns.zoneList = {}

-- ------------------------------------------------------------
-- Helpers compartidos (también los usa el minimapa)
-- ------------------------------------------------------------
function ns.ClassColor(class)
    local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class or ""]
    if c then return c.r, c.g, c.b end
    return 0.7, 0.7, 0.7
end

function ns.ClassHex(class)
    local r, g, b = ns.ClassColor(class)
    return string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- 1 = mismo layer que yo, -1 = otro layer, 0 = no se sabe
function ns.LayerState(m)
    if ns.layer == 0 or m.layer == 0 then return 0 end
    return (m.layer == ns.layer) and 1 or -1
end

function ns.LayerText(m, short)
    local st = ns.LayerState(m)
    if m.layer == 0 then
        return short and "|cff888888L?|r" or "|cff888888Layer desconocido|r"
    elseif st == 1 then
        return short and ("|cff20ff20L" .. m.layer .. "|r") or ("|cff20ff20Layer " .. m.layer .. " (tu layer)|r")
    elseif st == -1 then
        return short and ("|cffff5050L" .. m.layer .. "|r") or ("|cffff5050Layer " .. m.layer .. " (otro layer)|r")
    end
    return short and ("L" .. m.layer) or ("Layer " .. m.layer)
end

-- Miembros de mi grupo: Blizzard ya los dibuja
function ns.IsHidden(m)
    return HHMapaDB.hideGroup and (UnitInParty(m.name) or UnitInRaid(m.name))
end

-- ¿El mapa childID está dentro de mapID? (sube por los mapas padre)
local parentCache = {}
function ns.IsOnMap(childID, mapID)
    local id = childID
    for _ = 1, 6 do
        if id == mapID then return true end
        local p = parentCache[id]
        if p == nil then
            local info = C_Map.GetMapInfo(id)
            p = info and info.parentMapID or 0
            parentCache[id] = p
        end
        if p == 0 then return false end
        id = p
    end
    return false
end

-- Convierte la posición del miembro a coordenadas del mapa mapID
function ns.ProjectToMap(m, mapID)
    if m.mapID == mapID then return m.x, m.y end
    if not m.cont or not m.wpos then return end
    local _, pos = C_Map.GetMapPosFromWorldPos(m.cont, m.wpos, mapID)
    if not pos then return end
    local x, y = pos:GetXY()
    if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

-- Clases que tienen ícono propio en Textures\ (Evoker usa un punto de color)
local CLASS_ICON = {
    WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true,
    PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true,
    DRUID = true, DEATHKNIGHT = true, MONK = true, DEMONHUNTER = true,
}

-- Crea las texturas de un icono (anillo del líder + ícono de clase + corona)
function ns.BuildDot(f)
    f.ring = f:CreateTexture(nil, "BORDER")
    f.ring:SetTexture(DOT)
    f.ring:SetVertexColor(1, 0.82, 0)               -- anillo dorado
    f.ring:SetPoint("CENTER")
    f.ring:Hide()

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()

    f.crown = f:CreateTexture(nil, "OVERLAY")
    f.crown:SetTexture(CROWN)
    f.crown:SetPoint("BOTTOM", f, "TOP", 0, -6)
    f.crown:Hide()
end

-- Aplica ícono de clase, corona del líder y transparencia por layer
function ns.StyleDot(f, m, size)
    if m.leader then size = size + 2 end
    f:SetSize(size, size)

    if CLASS_ICON[m.class] then
        f.icon:SetTexture(TEX .. m.class)
        f.icon:SetVertexColor(1, 1, 1)
    else
        f.icon:SetTexture(DOT)
        f.icon:SetVertexColor(ns.ClassColor(m.class))
    end

    if m.leader then
        f.ring:SetSize(size + 6, size + 6)
        f.ring:Show()
        f.crown:SetSize(size * 0.9, size * 0.9)
        f.crown:Show()
    else
        f.ring:Hide()
        f.crown:Hide()
    end

    -- Otro layer: ícono en gris y transparente
    local other = ns.LayerState(m) == -1
    f.icon:SetDesaturated(other)
    f:SetAlpha(other and 0.4 or 1)
end

-- Tooltip: nombre, nivel, clase, layer, zona y otros miembros encima
function ns.ShowTooltip(owner, m, others)
    if not m then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")

    local r, g, b = ns.ClassColor(m.class)
    GameTooltip:AddLine((m.leader and (CROWN_TEXT .. " ") or "") .. m.name, r, g, b)
    if m.leader then
        GameTooltip:AddLine("Líder de la hermandad", 1, 0.82, 0)
    end
    local className = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[m.class]) or m.class or "?"
    GameTooltip:AddLine("Nivel " .. m.level .. " " .. className, 1, 1, 1)
    GameTooltip:AddLine(ns.LayerText(m))
    local info = C_Map.GetMapInfo(m.mapID)
    if info then GameTooltip:AddLine(info.name, 0.7, 0.7, 0.7) end

    -- Otros puntos que se superponen con este
    if others then
        local ox, oy = owner:GetCenter()
        local w, h = owner:GetWidth(), owner:GetHeight()
        local first = true
        for _, f in ipairs(others) do
            if f ~= owner and f.member and f:IsShown() then
                local fx, fy = f:GetCenter()
                if ox and fx and math.abs(fx - ox) < w and math.abs(fy - oy) < h then
                    if first then
                        GameTooltip:AddLine(" ")
                        first = false
                    end
                    local o = f.member
                    GameTooltip:AddLine((o.leader and (CROWN_TEXT .. " ") or "") .. "|c" .. ns.ClassHex(o.class) .. o.name
                        .. "|r |cffffffff" .. o.level .. "|r " .. ns.LayerText(o, true))
                end
            end
        end
    end
    GameTooltip:AddLine("Clic derecho: más opciones", 0.5, 0.8, 1)
    GameTooltip:Show()
end

-- ------------------------------------------------------------
-- Pines del mapa y data provider
-- (se crean al iniciar porque Blizzard_MapCanvas puede cargar tarde)
-- ------------------------------------------------------------
local provider
local pinList = {}

-- Global desde la carga para que la plantilla XML lo encuentre;
-- los métodos base de Blizzard se le agregan en ns.InitMap().
HHMapaPinMixin = {}
local PinMethods = HHMapaPinMixin

function PinMethods:OnLoad()
    local mgr = self:GetMap():GetPinFrameLevelsManager()
    if mgr and mgr.definitions and mgr.definitions.PIN_FRAME_LEVEL_GROUP_MEMBER then
        self:UseFrameLevelType("PIN_FRAME_LEVEL_GROUP_MEMBER")
    end
    self:SetScalingLimits(1, 1.0, 1.2)
    ns.BuildDot(self)
end

local function PinMouseUp(self, button)
    if button == "RightButton" then ns.ShowMenu(self.member) end
end

function PinMethods:OnAcquired(m, x, y)
    -- Clic derecho abre el menú; el izquierdo pasa al mapa (para arrastrarlo)
    if not self.hhClicks then
        self:SetMouseClickEnabled(true)
        self:SetScript("OnMouseUp", PinMouseUp)
        self.hhClicks = ns.PassLeftClick(self)
    end
    self.member = m
    self:SetPosition(x, y)
    ns.StyleDot(self, m, 20)
end

function PinMethods:OnReleased()
    self.member = nil
end

function PinMethods:OnMouseEnter()
    wipe(pinList)
    for pin in self:GetMap():EnumeratePinsByTemplate(PIN_TEMPLATE) do
        pinList[#pinList + 1] = pin
    end
    ns.ShowTooltip(self, self.member, pinList)
end

function PinMethods:OnMouseLeave()
    GameTooltip:Hide()
end

local ProviderMethods = {}

function ProviderMethods:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

function ProviderMethods:RefreshAllData()
    self:RemoveAllData()
    local map = self:GetMap()
    local mapID = map:GetMapID()
    local list = ns.zoneList
    wipe(list)

    if mapID then
        for _, m in pairs(ns.members) do
            if ns.IsOnMap(m.mapID, mapID) then
                list[#list + 1] = m
                if HHMapaDB.map and not ns.IsHidden(m) then
                    local x, y = ns.ProjectToMap(m, mapID)
                    if x then map:AcquirePin(PIN_TEMPLATE, m, x, y) end
                end
            end
        end
    end
    if ns.UpdatePanel then ns.UpdatePanel(mapID) end
end

function ns.RefreshMap()
    if provider and WorldMapFrame:IsShown() then
        provider:RefreshAllData()
    end
end

-- ------------------------------------------------------------
-- Botón en el mapa + lista de miembros en la zona
-- ------------------------------------------------------------
local button, panel
local rows = {}

local function SortMembers(a, b)
    if a.leader ~= b.leader then return a.leader end
    return a.name < b.name
end

local function CreateRow(i)
    local row = CreateFrame("Button", nil, panel)
    row:SetHeight(16)
    row:SetPoint("TOPLEFT", 8, -26 - (i - 1) * 16)
    row:SetPoint("TOPRIGHT", -8, -26 - (i - 1) * 16)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 2, 0)
    row.name:SetJustifyH("LEFT")

    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.info:SetPoint("RIGHT", -2, 0)
    row.info:SetJustifyH("RIGHT")

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouse)
        if not self.member then return end
        if mouse == "RightButton" then
            ns.ShowMenu(self.member)
        else
            ns.Tell(self.member)
        end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.member then return end
        ns.ShowTooltip(self, self.member)
        GameTooltip:AddLine("Clic izquierdo: susurrar", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    rows[i] = row
    return row
end

function ns.UpdatePanel(mapID)
    local list = ns.zoneList
    local n = #list
    if button then button.count:SetText(n > 0 and n or "") end
    if not panel or not panel:IsShown() then return end

    table.sort(list, SortMembers)
    local info = mapID and C_Map.GetMapInfo(mapID)
    panel.title:SetText("HustlinHitmans en " .. (info and info.name or "?") .. " |cffffffff(" .. n .. ")|r")

    local shown = math.min(n, MAX_ROWS)
    for i = 1, shown do
        local m = list[i]
        local row = rows[i] or CreateRow(i)
        row.member = m
        row.name:SetText((m.leader and (CROWN_TEXT .. " ") or "") .. "|c" .. ns.ClassHex(m.class) .. m.name .. "|r")
        row.info:SetText("Nv " .. m.level .. "  " .. ns.LayerText(m, true))
        row:SetAlpha(ns.LayerState(m) == -1 and 0.6 or 1)
        row:Show()
    end
    for i = shown + 1, #rows do
        rows[i]:Hide()
        rows[i].member = nil
    end

    local extra = ""
    if n == 0 then
        extra = "Nadie de la hermandad en esta zona."
    elseif n > MAX_ROWS then
        extra = "... y " .. (n - MAX_ROWS) .. " más"
    end
    panel.footer:SetText(extra)
    local lines = shown + (extra ~= "" and 1 or 0)
    panel.footer:SetPoint("TOPLEFT", 10, -28 - shown * 16)
    panel:SetHeight(34 + lines * 16)
end

function ns.TogglePanel()
    if not panel then return end
    HHMapaDB.panel = not panel:IsShown()
    panel:SetShown(HHMapaDB.panel)
    ns.RefreshMap()
end

local function CreateButton()
    local container = WorldMapFrame:GetCanvasContainer()

    button = CreateFrame("Button", "HHMapaMapButton", WorldMapFrame)
    button:SetSize(31, 31)
    button:SetFrameStrata("FULLSCREEN_DIALOG")
    button:SetPoint("TOPRIGHT", container, "TOPRIGHT", -6, -6)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", 2, -2)

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            HHMapaDB.map = not HHMapaDB.map
            ns.Changed()
            ns.RefreshMap()
        else
            ns.TogglePanel()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("HH Mapa", 0.83, 0.69, 0.22)
        GameTooltip:AddLine("Clic izquierdo: miembros en esta zona", 1, 1, 1)
        GameTooltip:AddLine("Clic derecho: " .. (HHMapaDB.map and "ocultar" or "mostrar") .. " iconos", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Lista
    panel = CreateFrame("Frame", "HHMapaPanel", WorldMapFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetSize(240, 60)
    panel:SetPoint("TOPRIGHT", button, "TOPLEFT", -2, 0)
    panel:EnableMouse(true)
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    panel:SetBackdropBorderColor(0.83, 0.69, 0.22)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 10, -8)
    panel.title:SetPoint("TOPRIGHT", -10, -8)
    panel.title:SetJustifyH("LEFT")

    panel.footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.footer:SetJustifyH("LEFT")

    panel:SetShown(HHMapaDB.panel)
end

-- ------------------------------------------------------------
-- Inicio
-- ------------------------------------------------------------
function ns.InitMap()
    if provider or not MapCanvasPinMixin then return end

    for k, v in pairs(MapCanvasPinMixin) do
        if PinMethods[k] == nil then PinMethods[k] = v end
    end
    provider = CreateFromMixins(MapCanvasDataProviderMixin, ProviderMethods)

    CreateButton()
    WorldMapFrame:AddDataProvider(provider)
    WorldMapFrame:HookScript("OnHide", function() ns.HideMenu() end)
end
