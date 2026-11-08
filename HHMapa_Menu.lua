-- ============================================================
--  HH Mapa - Menú del clic derecho
--  Enviar mensaje privado / Invitar al grupo / Invitar a la banda
-- ============================================================
local ADDON, ns = ...

local menu, target
local pendingRaid = 0   -- GetTime() hasta el que esperamos para convertir a banda

-- ------------------------------------------------------------
-- Acciones
-- ------------------------------------------------------------
local function WhoName(m)
    return m.sender or m.name
end

function ns.Tell(m)
    local tell = ChatFrame_SendTell or (ChatFrameUtil and ChatFrameUtil.SendTell)
    if tell then tell(WhoName(m)) end
end

local function Invite(m)
    local name = WhoName(m)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    else
        InviteUnit(name)
    end
end

local function ConvertRaid()
    if C_PartyInfo and C_PartyInfo.ConvertToRaid then
        C_PartyInfo.ConvertToRaid()
    else
        ConvertToRaid()
    end
end

local function InviteRaid(m)
    if IsInRaid() then
        Invite(m)
    elseif IsInGroup() then
        if UnitIsGroupLeader("player") then
            ConvertRaid()
            Invite(m)
        else
            ns.Print("Debes ser el líder del grupo para crear la banda.")
        end
    else
        -- Aún no hay grupo: invitamos y convertimos cuando acepte
        pendingRaid = GetTime() + 60
        Invite(m)
        ns.Print("Invitación enviada. El grupo pasará a banda cuando " .. m.name .. " acepte.")
    end
end

-- Al formarse el grupo, lo convertimos en banda si quedó pendiente
local ev = CreateFrame("Frame")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function()
    if pendingRaid > GetTime() and IsInGroup() and not IsInRaid() and UnitIsGroupLeader("player") then
        pendingRaid = 0
        ConvertRaid()
    end
end)

-- Clic izquierdo "atraviesa" el ícono (para arrastrar el mapa o pinchar el minimapa).
-- Es una función protegida en combate: devuelve false si no se pudo aplicar.
function ns.PassLeftClick(frame)
    if not frame.SetPassThroughButtons then return true end
    if InCombatLockdown() then return false end
    return (pcall(frame.SetPassThroughButtons, frame, "LeftButton"))
end

-- ------------------------------------------------------------
-- Ventana del menú
-- ------------------------------------------------------------
local ITEMS = {
    { text = "Enviar mensaje privado", func = ns.Tell },
    { text = "Invitar al grupo",       func = Invite },
    { text = "Invitar a la banda",     func = InviteRaid },
    { text = "Cancelar",               cancel = true },
}

local function CreateMenu()
    menu = CreateFrame("Frame", "HHMapaMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(200)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetSize(180, 34 + #ITEMS * 18)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    menu:SetBackdropColor(0, 0, 0, 0.92)
    menu:SetBackdropBorderColor(0.83, 0.69, 0.22)

    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    menu.title:SetPoint("TOPLEFT", 10, -8)
    menu.title:SetPoint("TOPRIGHT", -10, -8)
    menu.title:SetJustifyH("LEFT")

    for i, item in ipairs(ITEMS) do
        local b = CreateFrame("Button", nil, menu)
        b:SetHeight(18)
        b:SetPoint("TOPLEFT", 6, -26 - (i - 1) * 18)
        b:SetPoint("TOPRIGHT", -6, -26 - (i - 1) * 18)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        local fs = b:CreateFontString(nil, "OVERLAY", item.cancel and "GameFontDisableSmall" or "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 6, 0)
        fs:SetText(item.text)

        b:SetScript("OnClick", function()
            menu:Hide()
            if item.func and target then item.func(target) end
        end)
    end

    -- Se cierra solo si el mouse se aleja más de un segundo
    menu:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver() then
            self.away = 0
        else
            self.away = (self.away or 0) + elapsed
            if self.away > 1 then self:Hide() end
        end
    end)

    tinsert(UISpecialFrames, "HHMapaMenu") -- se cierra con Escape
    menu:Hide()
end

function ns.ShowMenu(m)
    if not m then return end
    if not menu then CreateMenu() end
    target = m

    menu.title:SetText((m.leader and "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:14:14|t " or "")
        .. "|c" .. ns.ClassHex(m.class) .. m.name .. "|r")

    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 10, y / scale + 10)
    menu.away = 0
    GameTooltip:Hide()
    menu:Show()
end

function ns.HideMenu()
    if menu then menu:Hide() end
end
