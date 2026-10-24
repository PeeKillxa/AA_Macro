-- ============================================================
--  AA Macro Studio v2.0  |  Cyberpunk Dashboard Edition
--  Created by cook45 & clack
--  File: AA_Macro/main_v2.lua
-- ============================================================

-- ── Location Check (Lobby vs Combat) ────────────────────────
local LOBBY_PLACE_ID = 8304191830
local isLobby = (game.PlaceId == LOBBY_PLACE_ID)
if isLobby then
    print("[AA Macro] 🏠 สถานะ: อยู่ใน Lobby (PlaceId: 8304191830) — เปิดโหมด Event & Matchmaking")
else
    print("[AA Macro] ⚔️ สถานะ: อยู่ในแมพต่อสู้ (PlaceId: " .. tostring(game.PlaceId) .. ") — เปิดโหมด Macro & Battlefield")
end

-- ── 0. Cleanup Previous Window & Overlays ───────────────────
local gethui = gethui or function() return game:GetService("CoreGui") end

if _G.AAMacroUI and typeof(_G.AAMacroUI.Destroy) == "function" then
    pcall(function() _G.AAMacroUI:Destroy() end)
    _G.AAMacroUI = nil
end

pcall(function()
    for _, ch in ipairs(gethui():GetChildren()) do
        if ch:IsA("ScreenGui") and (ch.Name == "AAMacro_HUD_v2" or ch.Name == "ScreenGui") then
            pcall(function() ch:Destroy() end)
        end
    end
end)

-- ── 1. Load Fluent UI ───────────────────────────────────────
local Fluent = loadstring(game:HttpGet(
    "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- ── 2. Services & References ────────────────────────────────
local RS          = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UIS         = game:GetService("UserInputService")
local plr         = game:GetService("Players").LocalPlayer

local endpoints     = RS:FindFirstChild("endpoints") and RS.endpoints:FindFirstChild("client_to_server")
local spawnRemote   = endpoints and endpoints:FindFirstChild("spawn_unit")
local upgradeRemote = endpoints and endpoints:FindFirstChild("upgrade_unit_ingame")
local sellRemote        = endpoints and endpoints:FindFirstChild("sell_unit_ingame")
local useSpellRemote        = endpoints and endpoints:FindFirstChild("use_ingame_spell")
local deleteSpellRemote     = endpoints and endpoints:FindFirstChild("delete_ingame_spell")
local deleteTempUnitRemote  = endpoints and endpoints:FindFirstChild("delete_ingame_temporary_unit")
local moneyLabel    = plr.PlayerGui:FindFirstChild("spawn_units") and plr.PlayerGui.spawn_units:FindFirstChild("Lives") and plr.PlayerGui.spawn_units.Lives:FindFirstChild("Frame") and plr.PlayerGui.spawn_units.Lives.Frame:FindFirstChild("Resource") and plr.PlayerGui.spawn_units.Lives.Frame.Resource:FindFirstChild("Money") and plr.PlayerGui.spawn_units.Lives.Frame.Resource.Money:FindFirstChild("text")
local unitsFrame    = plr.PlayerGui:FindFirstChild("spawn_units") and plr.PlayerGui.spawn_units:FindFirstChild("Lives") and plr.PlayerGui.spawn_units.Lives:FindFirstChild("Frame") and plr.PlayerGui.spawn_units.Lives.Frame:FindFirstChild("Units")

-- โหลดฐานข้อมูล Units ผ่าน Loader ของเกม เพื่อดึงราคา Upgrade และ Spawn จริงทุกยูนิต
local UnitsData = nil
local function getUnitsData()
    if UnitsData then return UnitsData end
    pcall(function()
        local src = RS:FindFirstChild("src")
        local loaderModule = src and (src:FindFirstChild("Loader") or src:FindFirstChild("loader"))
        if loaderModule then
            local loader = require(loaderModule)
            if loader and loader.load_data then
                UnitsData = loader:load_data("Units")
            end
        end
    end)
    if not UnitsData and RS:FindFirstChild("src") and RS.src:FindFirstChild("Data") and RS.src.Data:FindFirstChild("Units") then
        pcall(function()
            UnitsData = require(RS.src.Data.Units)
        end)
    end
    return UnitsData
end

local function getUnitUpgradeCostFromData(unitId, targetLevel)
    local data = getUnitsData()
    if data and unitId then
        local cleanId = tostring(unitId):gsub("_unit$", "")
        local u = data[unitId] or data[cleanId]
        if u and u.upgrade and targetLevel and tonumber(targetLevel) then
            local info = u.upgrade[tonumber(targetLevel)]
            if info and info.cost then
                return tonumber(info.cost)
            end
        end
    end
    return nil
end

local function getUnitSpawnCostFromData(unitId)
    local data = getUnitsData()
    if data and unitId then
        local cleanId = tostring(unitId):gsub("_unit$", "")
        local u = data[unitId] or data[cleanId]
        if u and u.cost then
            return tonumber(u.cost)
        end
    end
    return nil
end

-- ดึงฐานข้อมูล Units ทันทีเมื่อเริ่มต้น
getUnitsData()

-- โฟลเดอร์จัดเก็บข้อมูล
if not isfolder("AA_Macro") then makefolder("AA_Macro") end
if not isfolder("AA_Macro/profiles") then makefolder("AA_Macro/profiles") end
if not isfolder("AA_Macro/configs") then makefolder("AA_Macro/configs") end

-- ── 3. Helper Functions ─────────────────────────────────────
local function getGold()
    local ok, val = pcall(function()
        return tonumber((moneyLabel.Text:gsub("[^%d]", ""))) or 0
    end)
    return ok and val or 0
end

local function getWave()
    local ok, val = pcall(function()
        return workspace._wave_num.Value
    end)
    return ok and val or 0
end

local function getSlotSpawnCost(slotIndex)
    local ok, val = pcall(function()
        local slot = unitsFrame:FindFirstChild(tostring(slotIndex))
        if not slot then return 0 end
        if slot:FindFirstChild("Cost") and slot.Cost:FindFirstChild("text") then
            return tonumber((slot.Cost.text.Text:gsub("[^%d]", ""))) or 0
        end
        if slot:FindFirstChild("cost") then
            return tonumber((slot.cost.Text:gsub("[^%d]", ""))) or 0
        end
        return 0
    end)
    return ok and val or 0
end

local function getSlotUnitName(slotIndex)
    local ok, name = pcall(function()
        local slot = unitsFrame:FindFirstChild(tostring(slotIndex))
        local wm = slot.Main.View.WorldModel
        local ch = wm:GetChildren()[1]
        return ch and ch.Name or "Unit"
    end)
    return ok and name or "Unit"
end

local function findSlotByUnitId(unitId)
    for i = 1, 6 do
        local slot = unitsFrame:FindFirstChild(tostring(i))
        if slot then
            local attrUuid = slot:GetAttribute("_equipped_frame_unit_uuid")
            if attrUuid == unitId then return i end
            local uid = slot:FindFirstChild("unit_id") or slot:FindFirstChild("unitId")
            if uid and uid.Value == unitId then return i end
        end
    end
    return nil
end

local function findCurrentUuidForSpawn(entry)
    if not entry then return nil end

    if entry.unitId then
        for si = 1, 6 do
            local slot = unitsFrame:FindFirstChild(tostring(si))
            if slot then
                local attrUuid = slot:GetAttribute("_equipped_frame_unit_uuid")
                if attrUuid and attrUuid == entry.unitId then
                    return attrUuid
                end
            end
        end
    end

    if entry.unitName and entry.unitName ~= "" and entry.unitName ~= "Unit" then
        local target = entry.unitName:lower()
        for si = 1, 6 do
            local name = getSlotUnitName(si)
            if name and (name:lower() == target or name:lower():find(target, 1, true) or target:find(name:lower(), 1, true)) then
                local slot = unitsFrame:FindFirstChild(tostring(si))
                local attrUuid = slot and slot:GetAttribute("_equipped_frame_unit_uuid")
                if attrUuid then
                    return attrUuid
                end
            end
        end
    end

    if entry.slotIndex then
        local slot = unitsFrame:FindFirstChild(tostring(entry.slotIndex))
        local attrUuid = slot and slot:GetAttribute("_equipped_frame_unit_uuid")
        if attrUuid then
            return attrUuid
        end
    end

    return entry.unitId
end

local function getActiveUnitsCount()
    local count = 0
    local folder = workspace:FindFirstChild("_UNITS")
    if folder then
        for _, u in ipairs(folder:GetChildren()) do
            local stats = u:FindFirstChild("_stats")
            if stats and stats:FindFirstChild("player") and stats.player.Value == plr then
                count = count + 1
            end
        end
    end
    return count
end

-- ค้นหา unit ของผู้เล่นใน workspace._UNITS ตามตำแหน่งและชื่อตัวละคร (สำหรับ Upgrade & ทั่วไป)
local function findLiveUnitForUpgrade(targetPos, unitName, maxDist)
    if not targetPos then return nil end
    maxDist = maxDist or 8
    local unitsFolder = workspace:FindFirstChild("_UNITS")
    if not unitsFolder then return nil end

    local bestMatchUnit = nil
    local bestMatchDist = maxDist
    local fallbackUnit  = nil
    local fallbackDist  = maxDist

    for _, u in ipairs(unitsFolder:GetChildren()) do
        local stats = u:FindFirstChild("_stats")
        if stats and stats:FindFirstChild("player") and stats.player.Value == plr then
            local pos = nil
            pcall(function()
                local pPart = u.PrimaryPart or u:FindFirstChild("HumanoidRootPart")
                if pPart then
                    pos = pPart.Position
                elseif u:IsA("Model") then
                    pos = u:GetPivot().Position
                end
            end)
            if pos then
                local d = (pos - targetPos).Magnitude
                if d < maxDist then
                    local uId = stats:FindFirstChild("id") and stats.id.Value
                    local isNameMatch = (unitName and unitName ~= "Unit") and (
                        u.Name:lower() == unitName:lower() or
                        (uId and tostring(uId):lower() == unitName:lower()) or
                        u.Name:lower():find(unitName:lower(), 1, true)
                    )
                    if isNameMatch and d < bestMatchDist then
                        bestMatchDist = d
                        bestMatchUnit = u
                    end
                    if d < fallbackDist then
                        fallbackDist = d
                        fallbackUnit = u
                    end
                end
            end
        end
    end
    return bestMatchUnit or fallbackUnit
end

local function getLiveUnitByPosition(targetPos, maxDist, unitName)
    return findLiveUnitForUpgrade(targetPos, unitName, maxDist or 6)
end

-- ตรวจสอบและค้นหายูนิตของผู้เล่นใน _UNITS (ไม่รวม mob ศัตรู)
local findLivePlayerUnit = findLiveUnitForUpgrade

local function getUpgradeCostFromOverview(targetUnit)
    if not targetUnit then return nil end
    local ok, cost = pcall(function()
        local uo = plr.PlayerGui:FindFirstChild("UnitOverview")
        if not uo then return nil end
        local scroll = uo:FindFirstChild("OuterOuter")
            and uo.OuterOuter:FindFirstChild("Outer")
            and uo.OuterOuter.Outer:FindFirstChild("ScrollingFrame")
        if not scroll then return nil end
        for _, ch in ipairs(scroll:GetChildren()) do
            if ch:IsA("GuiObject") and ch:FindFirstChild("_unit_char_ref") and ch._unit_char_ref.Value == targetUnit then
                local txt = ch.Outer.buttons.Upgrade.Main.Text.Text
                return tonumber((txt:gsub("[^%d]", "")))
            end
        end
        return nil
    end)
    return ok and cost or nil
end

local function getUpgradeCost(entry)
    local liveUnit = entry and entry.position and getLiveUnitByPosition(entry.position, 8, entry.unitName)
    local stats = liveUnit and liveUnit:FindFirstChild("_stats")
    local uId = stats and stats:FindFirstChild("id") and stats.id.Value or (entry and (entry.unitId or entry.unitName))
    local curUpg = stats and stats:FindFirstChild("upgrade") and stats.upgrade.Value or (entry and entry.currentUpgrade or 0)
    local targetUpg = entry and entry.targetUpgrade or (curUpg + 1)

    -- 1. จาก Units Database ของเกม (Realtime Loader Data แม่นยำ 100%)
    local dataCost = getUnitUpgradeCostFromData(uId, targetUpg) or (curUpg and getUnitUpgradeCostFromData(uId, curUpg + 1))
    if dataCost and dataCost > 0 then
        return dataCost
    end

    -- 2. จาก entry.cost ที่บันทึกไว้ตอน record
    if entry and entry.cost and entry.cost > 0 then
        return entry.cost
    end

    -- 3. จาก UnitOverview GUI (ถ้าเปิดอยู่)
    if liveUnit then
        local ovCost = getUpgradeCostFromOverview(liveUnit)
        if ovCost and ovCost > 0 then
            return ovCost
        end
    end

    -- 4. จาก UnitUpgrade GUI (ถ้าเปิดอยู่)
    local ok, val = pcall(function()
        local txt = plr.PlayerGui.UnitUpgrade.Primary.Container.Main.Main.Buttons.Upgrade.Main.Text.Text
        return tonumber((txt:gsub("[^%d]", ""))) or 0
    end)
    if ok and val and val > 0 then return val end

    -- สำคัญ: ห้าม fallback เป็น entry.gold (เพราะคือยอดเงินในกระเป๋า ไม่ใช่ราคาอัปเกรด)
    return 0
end

local function canAfford(entry)
    local gold = getGold()
    if entry.type == "spawn" then
        local slot = findSlotByUnitId(entry.unitId)
        local cost = slot and getSlotSpawnCost(slot) or 0
        if cost == 0 then
            cost = getUnitSpawnCostFromData(entry.unitId) or (entry.cost or 0)
        end
        return gold >= cost
    elseif entry.type == "upgrade" then
        local cost = getUpgradeCost(entry)
        return gold >= cost
    elseif entry.type == "sell" then
        return true  -- sell ไม่ต้องใช้เงิน ทำได้เสมอ
    end
    return true
end

-- ค้นหา unit ที่ active อยู่ใน workspace._UNITS ตาม position และ unitName (สำหรับ sell replay)
local function findLiveUnitForSell(targetPos, unitName, maxDist)
    maxDist = maxDist or 8
    local unitsFolder = workspace:FindFirstChild("_UNITS")
    if unitsFolder then
        local bestMatchUnit = nil
        local bestMatchDist = maxDist
        local fallbackUnit  = nil
        local fallbackDist  = maxDist

        for _, u in ipairs(unitsFolder:GetChildren()) do
            local stats = u:FindFirstChild("_stats")
            if stats and stats:FindFirstChild("player") and stats.player.Value == plr then
                local pos = nil
                pcall(function()
                    local pPart = u.PrimaryPart or u:FindFirstChild("HumanoidRootPart")
                    if pPart then
                        pos = pPart.Position
                    elseif u:IsA("Model") then
                        pos = u:GetPivot().Position
                    end
                end)
                local uId = stats:FindFirstChild("id") and stats.id.Value
                local isNameMatch = (unitName and unitName ~= "Unit") and (
                    u.Name:lower() == unitName:lower() or
                    (uId and tostring(uId):lower() == unitName:lower()) or
                    u.Name:lower():find(unitName:lower(), 1, true)
                )

                if pos and targetPos then
                    local d = (pos - targetPos).Magnitude
                    if d < maxDist then
                        if isNameMatch and d < bestMatchDist then
                            bestMatchDist = d
                            bestMatchUnit = u
                        end
                        if d < fallbackDist then
                            fallbackDist = d
                            fallbackUnit = u
                        end
                    end
                elseif not targetPos then
                    if isNameMatch then
                        return u
                    end
                    fallbackUnit = fallbackUnit or u
                end
            end
        end
        if bestMatchUnit then return bestMatchUnit end
        if fallbackUnit then return fallbackUnit end
    end
    return nil
end

-- สร้าง Unicode Block Progress Bar แบบคมชัดสไตล์ Cyberpunk
local function generateProgressBar(current, total, barLength)
    barLength = barLength or 14
    if total == 0 then
        return "░░░░░░░░░░░░░░  0%"
    end
    local pct = math.clamp(current / total, 0, 1)
    local filled = math.floor(pct * barLength)
    local empty = barLength - filled
    return string.format("%s%s  %3.0f%%", string.rep("█", filled), string.rep("░", empty), pct * 100)
end

-- ── 4. Macro Core State ─────────────────────────────────────
if _G.AAMacro and _G.AAMacro._orig then
    local mtOld = getrawmetatable(game)
    setreadonly(mtOld, false)
    mtOld.__namecall = _G.AAMacro._orig
    setreadonly(mtOld, true)
end

local savedMacro   = _G.AAMacro and _G.AAMacro.macro or {}
local savedProfile = _G.AAMacro and _G.AAMacro.currentProfileName or "Default_Macro"
_G.AAMacro = nil
task.wait(0.05)

_G.AAMacro = {
    recording          = false,
    playing            = false,
    currentStep        = 0,
    macro              = savedMacro,
    startTime          = nil,
    _orig              = nil,
    playMode           = "Wave+Delay",
    actionDelay        = 0.15,
    autoReplay         = true,
    replayDelay        = 2.0,
    autoStartOnMatch       = false,
    autoVoteStart          = true,
    autoPlayMacroOnMatch   = false,
    _replaying             = false,
    _hasAutoStarted        = false,
    _hasVotedStart         = false,
    showHUD                = true,
    currentProfileName     = savedProfile,
    -- ── Webhook Configuration ───────────────────
    webhookUrl             = "",
    webhookEnabled         = false,
    webhookNotifyOnFinish  = true,
    webhookCensorUser      = false,
    _matchStartTime        = nil,
    _hasSentMatchWebhook   = false,
    _lastWebhookStatus     = "ยังไม่มีการส่ง",
    -- ── April Fool's Event & AI Autoplay ────────
    eventAutoPlay          = false,
    eventInterval          = 3.0,
    eventAttempts          = 0,
    eventLastCaptcha       = "-",
    eventStatusText        = "⏹️ STANDBY — รอคำสั่ง",
    aiAutoplay             = false,
    aiAutoUpgrade          = true,
    autoDeleteRefund       = true,
    failedUnitPlacements   = {},
    aiMaxUnits             = 20,
    aiInterval             = 1.0,
    aiStatusText           = "AI Standby",
}
local macro = _G.AAMacro

-- ติดตาม wave start time เพื่อคำนวณ waveOffset
local _waveStartTimes = {}
task.spawn(function()
    local lastWave = 0
    while true do
        local w = getWave()
        if w ~= lastWave and w > 0 then
            _waveStartTimes[w] = tick()
            lastWave = w
        end
        task.wait(0.2)
    end
end)
local function getWaveElapsed()
    local w = getWave()
    local t = _waveStartTimes[w]
    return t and (tick() - t) or 0
end

-- Dispatcher สำหรับ Namecall Hook เพื่อให้อัปเดตโค้ดบันทึกได้ทันทีโดยไม่ต้อง Hook ซ้ำ
local function handleRemoteDispatch(self, method, ...)
    local macroState = _G.AAMacro
    if not (macroState and macroState.recording and (method == "InvokeServer" or method == "FireServer")) then
        return
    end

    local name = self and self.Name or ""
    if name == "spawn_unit" then
        local args  = {...}
        local cf    = args[2]
        local pos   = typeof(cf) == "CFrame" and cf.Position
                   or typeof(cf) == "Vector3" and cf or nil
        local uUuid = args[1]
        local slot  = findSlotByUnitId(uUuid)
        local uName = slot and getSlotUnitName(slot) or "Unit"
        local cost  = slot and getSlotSpawnCost(slot) or 0
        if cost == 0 then
            cost = getUnitSpawnCostFromData(uName) or 0
        end

        local capWave = getWave()
        local capWaveOffset = math.floor(getWaveElapsed())
        local capGold = getGold()
        local capTime = macroState.startTime and math.floor(tick() - macroState.startTime) or 0

        -- ตรวจสอบว่าโมเดลยูนิตของผู้เล่นปรากฏขึ้นใน workspace._UNITS จริงก่อนบันทึก
        task.spawn(function()
            local spawnedUnit = nil
            local waitStart = tick()
            while (tick() - waitStart) < 2.0 do
                if not (macroState and macroState.recording) then return end
                spawnedUnit = findLiveUnitForUpgrade(pos, uName, 6)
                if spawnedUnit then break end
                task.wait(0.08)
            end

            if spawnedUnit then
                if not (macroState and macroState.recording) then return end
                local entryData = {
                    type        = "spawn",
                    timestamp   = capTime,
                    wave        = capWave,
                    waveOffset  = capWaveOffset,
                    gold        = capGold,
                    cost        = cost,
                    position    = pos,
                    unitId      = uUuid,
                    unitName    = uName,
                    slotIndex   = slot,
                    args        = args,
                }
                table.insert(macroState.macro, entryData)
                Fluent:Notify({
                    Title    = string.format("🔴 Recorded #%d: SPAWN", #macroState.macro),
                    Content  = string.format("%s (Slot %s)\nWave: %d | Gold: %d¥%s\nPos: %s",
                        uName, tostring(slot),
                        entryData.wave, entryData.gold,
                        cost > 0 and string.format(" | Cost: %d¥", cost) or "",
                        pos and string.format("(%.0f,%.0f,%.0f)", pos.X, pos.Y, pos.Z) or "nil"),
                    Duration = 3,
                })
            end
        end)

    elseif name == "upgrade_unit_ingame" then
        local args = {...}
        local unitModel = args[1]
        if typeof(unitModel) ~= "Instance" then return end

        local stats = unitModel:FindFirstChild("_stats")
        local upgObj = stats and stats:FindFirstChild("upgrade")
        local maxUpgObj = stats and stats:FindFirstChild("max_upgrade")
        local beforeLevel = upgObj and upgObj.Value or 0
        local maxUpg = maxUpgObj and maxUpgObj.Value or nil
        local uId = stats and stats:FindFirstChild("id") and stats.id.Value or unitModel.Name
        local uName = uId or unitModel.Name

        local pos = nil
        pcall(function()
            local pPart = unitModel.PrimaryPart or unitModel:FindFirstChild("HumanoidRootPart")
            if pPart then
                pos = pPart.Position
            elseif unitModel:IsA("Model") then
                pos = unitModel:GetPivot().Position
            elseif unitModel:IsA("BasePart") then
                pos = unitModel.Position
            end
        end)

        -- เช็คว่าถึงระดับ Max แล้วหรือไม่ ถ้าเต็มแล้วไม่บันทึก
        if maxUpg and beforeLevel >= maxUpg then
            return
        end

        local capWave = getWave()
        local capWaveOffset = math.floor(getWaveElapsed())
        local capGold = getGold()
        local capTime = macroState.startTime and math.floor(tick() - macroState.startTime) or 0

        -- ตรวจสอบว่า _stats.upgrade.Value เพิ่มขึ้นจริงจากเซิร์ฟเวอร์ก่อนบันทึก
        -- ป้องกันการบันทึกเมื่อเงินไม่พอ, กดรัว, หรือเซิร์ฟเวอร์ไม่อนุมัติ (ไม่นับมั่ว)
        task.spawn(function()
            local confirmedLevel = nil
            local waitStart = tick()
            while (tick() - waitStart) < 1.8 do
                if not (macroState and macroState.recording) then return end
                local cur = upgObj and upgObj.Value or beforeLevel
                if cur > beforeLevel then
                    confirmedLevel = cur
                    break
                end
                task.wait(0.05)
            end

            if confirmedLevel and confirmedLevel > beforeLevel then
                if not (macroState and macroState.recording) then return end

                -- ตรวจสอบกันบันทึกซ้ำซ้อนในระดับเดียวกันสำหรับตัวละครนี้
                macroState.recordedLevels = macroState.recordedLevels or {}
                local lastRecorded = macroState.recordedLevels[unitModel] or beforeLevel
                if confirmedLevel <= lastRecorded and lastRecorded > beforeLevel then
                    return
                end
                macroState.recordedLevels[unitModel] = confirmedLevel

                local cost = getUnitUpgradeCostFromData(uId, confirmedLevel) or 0
                local entryData2 = {
                    type            = "upgrade",
                    timestamp       = capTime,
                    wave            = capWave,
                    waveOffset      = capWaveOffset,
                    gold            = capGold,
                    cost            = cost,
                    position        = pos,
                    unitId          = uId,
                    unitName        = uName,
                    currentUpgrade  = beforeLevel,
                    targetUpgrade   = confirmedLevel,
                    maxUpgrade      = maxUpg,
                    args            = args,
                }
                table.insert(macroState.macro, entryData2)
                Fluent:Notify({
                    Title    = string.format("🔴 Recorded #%d: UPGRADE", #macroState.macro),
                    Content  = string.format("%s [Lvl %d → %d]%s\nWave: %d | Gold: %d¥%s",
                        uName, beforeLevel, confirmedLevel,
                        maxUpg and string.format(" (Max: %d)", maxUpg) or "",
                        entryData2.wave, entryData2.gold,
                        cost > 0 and string.format(" | Cost: %d¥", cost) or ""),
                    Duration = 3,
                })
            end
        end)

    elseif name == "sell_unit_ingame" then
        local args = {...}
        local unitModel = args[1]
        local pos   = nil
        local uId   = nil
        local uName = "Unit"
        if typeof(unitModel) == "Instance" then
            pcall(function()
                local pPart = unitModel.PrimaryPart or unitModel:FindFirstChild("HumanoidRootPart")
                if pPart then
                    pos = pPart.Position
                elseif unitModel:IsA("Model") then
                    pos = unitModel:GetPivot().Position
                elseif unitModel:IsA("BasePart") then
                    pos = unitModel.Position
                end
            end)
            local stats = unitModel:FindFirstChild("_stats")
            uId = stats and stats:FindFirstChild("id") and stats.id.Value or unitModel.Name
            uName = unitModel.Name
        end

        local capWave = getWave()
        local capWaveOffset = math.floor(getWaveElapsed())
        local capGold = getGold()
        local capTime = macroState.startTime and math.floor(tick() - macroState.startTime) or 0

        -- ตรวจสอบว่าตัวละครถูกขายและออกจาก workspace._UNITS จริงก่อนบันทึก
        -- เมื่อถูกขายใน Anime Adventures ตัวละครจะถูกย้ายไป workspace._DEAD_UNITS ชั่วคราวก่อนลบ
        task.spawn(function()
            local sold = false
            local waitStart = tick()
            while (tick() - waitStart) < 2.5 do
                if not (macroState and macroState.recording) then return end
                local unitsFolder = workspace:FindFirstChild("_UNITS")
                if not unitModel or not unitModel.Parent or (unitsFolder and unitModel.Parent ~= unitsFolder) then
                    sold = true
                    break
                end
                task.wait(0.08)
            end

            if sold then
                if not (macroState and macroState.recording) then return end
                local entryData3 = {
                    type        = "sell",
                    timestamp   = capTime,
                    wave        = capWave,
                    waveOffset  = capWaveOffset,
                    gold        = capGold,
                    position    = pos,
                    unitId      = uId,
                    unitName    = uName,
                    args        = args,
                }
                table.insert(macroState.macro, entryData3)
                Fluent:Notify({
                    Title    = string.format("🔴 Recorded #%d: SELL", #macroState.macro),
                    Content  = string.format("💰 Sell: %s\nWave: %d | Gold: %d¥\nPos: %s",
                        uName, entryData3.wave, entryData3.gold,
                        pos and string.format("(%.0f,%.0f,%.0f)", pos.X, pos.Y, pos.Z) or "nil"),
                    Duration = 3,
                })
            end
        end)
    end
end

_G.__AAMacroDispatcher = function(self, method, ...)
    task.spawn(handleRemoteDispatch, self, method, ...)
end

-- Hook __namecall ด้วย hookmetamethod เชื่อมโยงผ่าน Dispatcher
if not _G.__AAMacroHooked or not _G.__AAMacroDispatcherInstalled then
    _G.__AAMacroHooked = true
    _G.__AAMacroDispatcherInstalled = true
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if _G.__AAMacroDispatcher then
            task.spawn(_G.__AAMacroDispatcher, self, method, ...)
        end
        -- !! CRITICAL: คืนค่า namecall method กลับเป็นต้นฉบับ
        setnamecallmethod(method)
        return oldNamecall(self, ...)
    end))
end

-- ── 5. Timing & Trigger Check ───────────────────────────────
local function shouldTrigger(entry, startT)
    if not canAfford(entry) then return false end

    local mode = macro.playMode
    if mode == "Wave+Delay" then
        if getWave() < (entry.wave or 0) then return false end
        local wst = _waveStartTimes[entry.wave or 0] or _waveStartTimes[getWave()]
        if not wst then return true end
        return (tick() - wst) >= (entry.waveOffset or 0)
    elseif mode == "Strict Time" then
        return (tick() - startT) >= (entry.timestamp or 0)
    end
    return false
end

-- ── 6. Macro Control API ────────────────────────────────────
function macro.StartRecording()
    macro.macro          = {}
    macro.recording      = true
    macro.playing        = false
    macro.currentStep    = 0
    macro.startTime      = tick()
    macro.recordedLevels = {}
end

function macro.StopRecording()
    macro.recording = false
end

function macro.StopPlay()
    macro.playing     = false
    macro.currentStep = 0
end

function macro.Reset()
    macro.recording          = false
    macro.playing            = false
    macro.currentStep        = 0
    macro.macro              = {}
    macro.startTime          = nil
    macro.currentProfileName = "Unsaved"
    macro.recordedLevels     = {}
end

function macro.Play()
    if macro.playing or #macro.macro == 0 then return end
    macro.playing     = true
    macro.currentStep = 1
    macro.startTime   = tick()
    task.spawn(function()
        local startT = tick()
        for i, entry in ipairs(macro.macro) do
            if not macro.playing then break end
            macro.currentStep = i

            while macro.playing do
                if shouldTrigger(entry, startT) then break end
                task.wait(0.1)
            end
            if not macro.playing then break end

            if entry.type == "spawn" then
                local liveUuid = findCurrentUuidForSpawn(entry)
                -- รวบรวม CFrame จากทุก fallback path
                local cf = nil
                if entry.args and typeof(entry.args[2]) == "CFrame" then
                    cf = entry.args[2]
                end
                if not cf and entry.cframe then
                    local ok3, result3 = pcall(function()
                        return CFrame.new(table.unpack(entry.cframe))
                    end)
                    if ok3 then cf = result3 end
                end
                if not cf and entry.position then
                    cf = CFrame.new(entry.position)
                end
                -- sync กลับเข้า args[2] เผื่อ round ถัดไป
                if cf and entry.args then
                    entry.args[2] = cf
                end

                if not liveUuid then
                    Fluent:Notify({ Title = "❌ UUID nil", Content = "Spawn #"..i..": ไม่พบ UUID ให้ตรวจ Debug tab", Duration = 5 })
                elseif not cf then
                    -- ข้ามและเตือน แทนที่จะค้างหรือ crash ทั้งหมด
                    warn("[AA Macro] Spawn #"..i.." SKIPPED — ไม่มี CFrame/position บันทึกไว้ เนื่องจากไฟล์ profile เก่า ให้อัดใหม่อีกครั้ง")
                    Fluent:Notify({ Title = "⚠️ Skip #"..i, Content = entry.unitName.." ไม่มี CFrame → ข้ามไป (profile เก่า — บันทึกใหม่เพื่อแก้)", Duration = 6 })
                else
                    local targetPos = (typeof(cf) == "CFrame" and cf.Position) or entry.position
                    local spawnedUnit = nil
                    local maxSpawnAttempts = 6

                    for attempt = 1, maxSpawnAttempts do
                        if not macro.playing then break end

                        -- 1. ตรวจสอบว่ามียูนิตของผู้เล่นวางอยู่ที่พิกัดนี้อยู่แล้วหรือไม่ (กรองเฉพาะ _stats.player == plr ไม่นับ mob ศัตรู)
                        spawnedUnit = findLivePlayerUnit(targetPos, entry.unitName, 5)
                        if spawnedUnit then break end

                        -- 2. เช็คเงิน ถ้าเงินยังไม่พอ ให้รอจนกว่าเงินจะพอ
                        while macro.playing and not canAfford(entry) do
                            task.wait(0.2)
                        end
                        if not macro.playing then break end

                        -- 3. อัปเดต liveUuid ก่อนยิงคำสั่ง
                        liveUuid = findCurrentUuidForSpawn(entry)
                        if not liveUuid then
                            warn(string.format("[AA Macro] Spawn #%d: ไม่พบ liveUuid", i))
                            break
                        end

                        -- 4. ยิง Remote วางตัวละคร
                        local okInvoke, resInvoke = pcall(function()
                            return spawnRemote:InvokeServer(liveUuid, cf)
                        end)
                        if not okInvoke then
                            warn(string.format("[AA Macro] Spawn #%d attempt %d error: %s", i, attempt, tostring(resInvoke)))
                        end

                        -- 5. ตรวจสอบว่าโมเดลยูนิตของผู้เล่นปรากฏขึ้นใน workspace._UNITS จริงหรือไม่
                        -- (ตรวจสอบ _stats.player.Value == plr ทุก 0.1s รอสูงสุด 1.2 วินาที โดยไม่ใช้ #GetChildren)
                        local checkStart = tick()
                        while (tick() - checkStart) < 1.2 do
                            spawnedUnit = findLivePlayerUnit(targetPos, entry.unitName, 5)
                            if spawnedUnit then break end
                            task.wait(0.1)
                        end

                        if spawnedUnit then break end
                        task.wait(0.25)
                    end

                    if spawnedUnit then
                        Fluent:Notify({
                            Title    = "✅ Spawned #"..i,
                            Content  = string.format("%s (Slot %s)\nตรวจสอบพบตัวละครใน _UNITS สำเร็จ!",
                                tostring(entry.unitName), tostring(entry.slotIndex or "-")),
                            Duration = 3
                        })
                    else
                        warn(string.format("[AA Macro] Spawn #%d FAILED: %s ไม่ปรากฏใน workspace._UNITS", i, tostring(entry.unitName)))
                        Fluent:Notify({
                            Title    = "❌ Spawn Failed #"..i,
                            Content  = string.format("%s วางไม่สำเร็จ (ไม่พบใน _UNITS)", tostring(entry.unitName)),
                            Duration = 5
                        })
                    end
                end

            elseif entry.type == "upgrade" then
                local liveUnit = findLiveUnitForUpgrade(entry.position, entry.unitName, 8)
                if not liveUnit then
                    for _ = 1, 5 do
                        task.wait(0.3)
                        liveUnit = findLiveUnitForUpgrade(entry.position, entry.unitName, 8)
                        if liveUnit then break end
                    end
                end

                if liveUnit then
                    local stats = liveUnit:FindFirstChild("_stats")
                    local upgValObj = stats and stats:FindFirstChild("upgrade")
                    local maxUpgValObj = stats and stats:FindFirstChild("max_upgrade")

                    local startLvl = upgValObj and upgValObj.Value or 0
                    local maxLvl = maxUpgValObj and maxUpgValObj.Value or (entry.maxUpgrade or 999)
                    local targetLvl = entry.targetUpgrade or (startLvl + 1)

                    -- 1. เช็คว่าถึงระดับ Max Upgrade หรือยัง
                    if startLvl >= maxLvl then
                        warn(string.format("[AA Macro] Upgrade #%d: %s ถึงระดับสูงสุดแล้ว (%d/%d) — ข้ามไป", i, tostring(entry.unitName), startLvl, maxLvl))
                        Fluent:Notify({ Title = "⚡ Max Upgrade #"..i, Content = string.format("%s อัปเกรดเต็มแล้ว (%d/%d)", tostring(entry.unitName), startLvl, maxLvl), Duration = 3 })
                    -- 2. เช็คว่าระดับปัจจุบันถึงเป้าหมายแล้วหรือยัง
                    elseif startLvl >= targetLvl then
                        warn(string.format("[AA Macro] Upgrade #%d: %s เลเวลปัจจุบัน (%d) >= เป้าหมาย (%d) — ข้ามไป", i, tostring(entry.unitName), startLvl, targetLvl))
                    else
                        -- 3. ทำการอัปเกรดและตรวจสอบว่า _stats.upgrade.Value เพิ่มขึ้นจริง
                        local upgraded = false
                        local maxAttempts = 6

                        for attempt = 1, maxAttempts do
                            if not macro.playing then break end

                            -- ตรวจสอบว่าเลเวลขยับแล้วหรือยัง
                            local currentLvl = upgValObj and upgValObj.Value or startLvl
                            if currentLvl > startLvl or currentLvl >= targetLvl then
                                upgraded = true
                                break
                            end

                            -- เช็คเงิน ถ้าเงินยังไม่พอ ให้รอจนกว่าจะพอ
                            while macro.playing and not canAfford(entry) do
                                task.wait(0.2)
                            end
                            if not macro.playing then break end

                            -- ยิง Remote อัปเกรด
                            local okInvoke, resInvoke = pcall(function()
                                return upgradeRemote:InvokeServer(liveUnit)
                            end)
                            if not okInvoke then
                                warn(string.format("[AA Macro] Upgrade #%d attempt %d error: %s", i, attempt, tostring(resInvoke)))
                            end

                            -- รอผลการตอบสนองจากเซิร์ฟเวอร์ ให้ _stats.upgrade.Value อัปเดตจริง (รอสูงสุด 1.2 วินาที)
                            local checkStart = tick()
                            while (tick() - checkStart) < 1.2 do
                                local verifiedLvl = upgValObj and upgValObj.Value or startLvl
                                if verifiedLvl > startLvl or verifiedLvl >= targetLvl then
                                    upgraded = true
                                    break
                                end
                                task.wait(0.1)
                            end

                            if upgraded then break end
                            task.wait(0.25)
                        end

                        local finalLvl = upgValObj and upgValObj.Value or startLvl
                        if upgraded or finalLvl > startLvl then
                            Fluent:Notify({
                                Title    = "⬆️ Upgraded #"..i,
                                Content  = string.format("%s: Lvl %d → %d (Max: %s)",
                                    tostring(entry.unitName), startLvl, finalLvl,
                                    maxLvl < 999 and tostring(maxLvl) or "-"),
                                Duration = 2.5
                            })
                        else
                            warn(string.format("[AA Macro] Upgrade #%d FAILED: %s ไม่สามารถอัปเกรดได้ (ยังอยู่ที่ Lvl %d)", i, tostring(entry.unitName), finalLvl))
                            Fluent:Notify({
                                Title    = "❌ Upgrade Failed #"..i,
                                Content  = string.format("%s อัปเกรดไม่สำเร็จ (เลเวลยังเป็น %d)", tostring(entry.unitName), finalLvl),
                                Duration = 5
                            })
                        end
                    end
                else
                    warn("[AA Macro] upgrade #" .. i .. ": unit '" .. tostring(entry.unitName) .. "' not found near pos, skipping")
                    Fluent:Notify({ Title = "⚠️ Skip Upgrade #"..i, Content = entry.unitName.." ไม่พบตัวละครใกล้พิกัด", Duration = 4 })
                end

            elseif entry.type == "sell" then
                -- ค้นหา unit ที่ active อยู่ใกล้ตำแหน่งที่บันทึกไว้
                local liveUnit = findLiveUnitForSell(entry.position, entry.unitName, 8)
                if liveUnit then
                    local ok2, res2 = pcall(function()
                        return sellRemote:InvokeServer(liveUnit)
                    end)
                    if not ok2 then
                        warn("[AA Macro] sell #" .. i .. " error: " .. tostring(res2))
                        Fluent:Notify({ Title = "❌ Sell Error #"..i, Content = tostring(res2):sub(1,80), Duration = 5 })
                    else
                        Fluent:Notify({ Title = "💰 Sold #"..i, Content = tostring(entry.unitName), Duration = 2.5 })
                    end
                else
                    warn("[AA Macro] sell #" .. i .. ": unit '"..tostring(entry.unitName).."' not found near pos, skipping")
                    Fluent:Notify({ Title = "⚠️ Sell Skip #"..i, Content = entry.unitName.." ไม่พบใกล้ตำแหน่ง", Duration = 4 })
                end
            end
            task.wait(macro.actionDelay or 0.15)
        end
        macro.playing     = false
        macro.currentStep = 0
    end)
end

-- ── 7. Profile Persistence (JSON Config System) ─────────────
local function serializeMacro()
    local list = {}
    for _, entry in ipairs(macro.macro) do
        local item = {
            type        = entry.type,
            timestamp   = entry.timestamp,
            wave        = entry.wave,
            waveOffset  = entry.waveOffset or 0,
            gold        = entry.gold,
            unitId      = entry.unitId,
            unitName    = entry.unitName,
            slotIndex   = entry.slotIndex,
        }
        if entry.position then
            item.position = { entry.position.X, entry.position.Y, entry.position.Z }
        end
        if entry.type == "spawn" then
            item.unitUuid = entry.args and entry.args[1] or entry.unitId
            -- ลองได้ทุก source: args[2] → entry.cframe → position
            local cf = entry.args and typeof(entry.args[2]) == "CFrame" and entry.args[2] or nil
            if cf then
                item.cframe = { cf:GetComponents() }
            elseif entry.cframe then
                -- เก็บ raw cframe array ต่อไปเลย ไม่ต้อง reconstruct
                item.cframe = entry.cframe
            elseif entry.position then
                -- ใช้ position สร้าง cframe เพื่อให้ทุก profile มี cframe เสมอ
                local posCF = CFrame.new(entry.position)
                item.cframe = { posCF:GetComponents() }
            end
        end
        if entry.type == "upgrade" then
            item.targetUpgrade  = entry.targetUpgrade
            item.currentUpgrade = entry.currentUpgrade
            item.maxUpgrade     = entry.maxUpgrade
        end
        -- sell: บันทึก position เป็น cue หลัก (ไม่มี cframe/args ที่ใช้ได้ข้ามรอบ)
        if entry.type == "sell" and not item.position and entry.position then
            item.position = { entry.position.X, entry.position.Y, entry.position.Z }
        end
        table.insert(list, item)
    end
    return HttpService:JSONEncode(list)
end

local function deserializeMacro(jsonStr)
    local rawList = HttpService:JSONDecode(jsonStr)
    local list = {}
    for _, t in ipairs(rawList) do
        local entry = {
            type            = t.type,
            timestamp       = t.timestamp or 0,
            wave            = t.wave or 0,
            waveOffset      = t.waveOffset or 0,
            gold            = t.gold or 0,
            unitId          = t.unitId or t.unitUuid,
            unitName        = t.unitName or "Unit",
            slotIndex       = t.slotIndex,
            targetUpgrade   = t.targetUpgrade,
            currentUpgrade  = t.currentUpgrade,
            maxUpgrade      = t.maxUpgrade,
        }
        if t.position then
            entry.position = Vector3.new(t.position[1], t.position[2], t.position[3])
        end
        if t.type == "spawn" then
            local cf = nil
            if t.cframe then
                -- cframe array มี 12 components (x,y,z + rotation matrix)
                local ok, result = pcall(function()
                    return CFrame.new(table.unpack(t.cframe))
                end)
                if ok and result then
                    cf = result
                end
            end
            -- fallback: ถ้าไม่มี cframe ให้ใช้ position (แมพเดิมยังได้)
            if not cf and entry.position then
                cf = CFrame.new(entry.position)
            end
            -- เก็บทั้ง args[2] และ entry.cframe เผื่อ path ไหนก็ได้
            entry.cframe = t.cframe  -- keep raw array เผื่อ fallback อีกครั้ง
            entry.args = { t.unitUuid or entry.unitId, cf }
        elseif t.type == "upgrade" then
            entry.args = {}
        elseif t.type == "sell" then
            entry.args = {}
        end
        table.insert(list, entry)
    end
    return list
end

function macro.GetProfiles()
    if not isfolder("AA_Macro/profiles") then makefolder("AA_Macro/profiles") end
    local files = listfiles("AA_Macro/profiles")
    local profiles = {}
    for _, path in ipairs(files) do
        local name = path:match("([^\\/]+)%.json$")
        if name then
            table.insert(profiles, name)
        end
    end
    if #profiles == 0 then
        return { "(No saved profiles)" }
    end
    table.sort(profiles)
    return profiles
end

function macro.SaveProfile(name)
    if not name or name == "" or name == "(No saved profiles)" then
        name = "macro_" .. os.date("%Y%m%d_%H%M%S")
    end
    name = name:gsub("[^%w_%-]", "_")
    if not isfolder("AA_Macro/profiles") then makefolder("AA_Macro/profiles") end
    local path = "AA_Macro/profiles/" .. name .. ".json"
    local json = serializeMacro()
    writefile(path, json)
    macro.currentProfileName = name
    if macro.SaveSettings then macro.SaveSettings() end
    return name
end

function macro.LoadProfile(name)
    if not name or name == "" or name == "(No saved profiles)" then return false end
    local path = "AA_Macro/profiles/" .. name .. ".json"
    if not isfile(path) then return false end
    local json = readfile(path)
    local ok, res = pcall(deserializeMacro, json)
    if ok and res then
        macro.macro = res
        macro.currentProfileName = name
        if macro.SaveSettings then macro.SaveSettings() end
        return true
    end
    return false
end

function macro.DeleteProfile(name)
    if not name or name == "" or name == "(No saved profiles)" then return false end
    local path = "AA_Macro/profiles/" .. name .. ".json"
    if isfile(path) then
        delfile(path)
        if macro.currentProfileName == name then
            macro.currentProfileName = "Unsaved"
            if macro.SaveSettings then macro.SaveSettings() end
        end
        return true
    end
    return false
end

-- ── 7.3.5. Auto Save / Restore Settings Controller ───────────
local settingsPath = "AA_Macro/settings.json"

function macro.SaveSettings()
    pcall(function()
        if not isfolder("AA_Macro") then makefolder("AA_Macro") end
        local cfg = {
            autoStartOnMatch       = macro.autoStartOnMatch,
            autoVoteStart          = macro.autoVoteStart,
            autoPlayMacroOnMatch   = macro.autoPlayMacroOnMatch,
            aiAutoplay             = macro.aiAutoplay,
            aiAutoUpgrade          = macro.aiAutoUpgrade,
            autoDeleteRefund       = macro.autoDeleteRefund,
            aiMaxUnits             = macro.aiMaxUnits or 20,
            autoReplay             = macro.autoReplay,
            playMode               = macro.playMode,
            actionDelay            = macro.actionDelay,
            replayDelay            = macro.replayDelay,
            showHUD                = macro.showHUD,
            currentProfileName     = macro.currentProfileName,
            webhookUrl             = macro.webhookUrl or "",
            webhookEnabled         = macro.webhookEnabled or false,
            webhookNotifyOnFinish  = macro.webhookNotifyOnFinish ~= false,
            webhookCensorUser      = macro.webhookCensorUser or false,
        }
        writefile(settingsPath, HttpService:JSONEncode(cfg))
    end)
end

function macro.LoadSettings()
    pcall(function()
        if isfile and isfile(settingsPath) then
            local raw = readfile(settingsPath)
            local data = HttpService:JSONDecode(raw)
            if type(data) == "table" then
                if data.autoVoteStart ~= nil then macro.autoVoteStart = data.autoVoteStart end
                if data.autoPlayMacroOnMatch ~= nil then macro.autoPlayMacroOnMatch = data.autoPlayMacroOnMatch end
                if data.aiAutoplay ~= nil then macro.aiAutoplay = data.aiAutoplay end
                if data.aiAutoUpgrade ~= nil then macro.aiAutoUpgrade = data.aiAutoUpgrade end
                if data.autoDeleteRefund ~= nil then macro.autoDeleteRefund = data.autoDeleteRefund end
                if data.aiMaxUnits ~= nil then macro.aiMaxUnits = tonumber(data.aiMaxUnits) or 20 end
                if data.autoStartOnMatch ~= nil then macro.autoStartOnMatch = data.autoStartOnMatch end
                if data.autoReplay ~= nil then macro.autoReplay = data.autoReplay end
                if data.playMode ~= nil then macro.playMode = data.playMode end
                if data.actionDelay ~= nil then macro.actionDelay = tonumber(data.actionDelay) or macro.actionDelay end
                if data.replayDelay ~= nil then macro.replayDelay = tonumber(data.replayDelay) or macro.replayDelay end
                if data.showHUD ~= nil then macro.showHUD = data.showHUD end
                if data.webhookUrl ~= nil then macro.webhookUrl = data.webhookUrl end
                if data.webhookEnabled ~= nil then macro.webhookEnabled = data.webhookEnabled end
                if data.webhookNotifyOnFinish ~= nil then macro.webhookNotifyOnFinish = data.webhookNotifyOnFinish end
                if data.webhookCensorUser ~= nil then macro.webhookCensorUser = data.webhookCensorUser end
                if data.currentProfileName and data.currentProfileName ~= "" and data.currentProfileName ~= "(No saved profiles)" and data.currentProfileName ~= "Unsaved" then
                    macro.currentProfileName = data.currentProfileName
                    pcall(function()
                        macro.LoadProfile(data.currentProfileName)
                    end)
                end
            end
        end
    end)
end
macro.LoadSettings()

-- ── 7.4. Cloud Macro Share & Import Controller ──────────────
local function normalizeShareUrl(input)
    if not input then return nil end
    input = input:gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then return nil end
    
    if input:sub(1,1) == "{" or input:sub(1,1) == "[" then
        return "RAW_JSON", input
    end
    
    if input:find("pastes%.dev/([%w_%-]+)") then
        local key = input:match("pastes%.dev/([%w_%-]+)")
        return "URL", "https://api.pastes.dev/" .. key
    elseif input:find("pastebin%.com/raw/([%w_%-]+)") then
        return "URL", input
    elseif input:find("pastebin%.com/([%w_%-]+)") then
        local key = input:match("pastebin%.com/([%w_%-]+)")
        return "URL", "https://pastebin.com/raw/" .. key
    elseif input:find("bytebin%.lucko%.me/([%w_%-]+)") then
        local key = input:match("bytebin%.lucko%.me/([%w_%-]+)")
        return "URL", "https://bytebin.lucko.me/" .. key
    elseif input:find("^https?://") then
        return "URL", input
    elseif #input >= 5 and #input <= 30 and not input:find("[/%?]") then
        return "URL", "https://api.pastes.dev/" .. input
    end
    
    return "UNKNOWN", input
end

function macro.ShareProfile(name)
    local targetMacro = nil
    local targetName = name

    if name and name ~= "" and name ~= "(No saved profiles)" then
        local path = "AA_Macro/profiles/" .. name .. ".json"
        if isfile(path) then
            local raw = readfile(path)
            local ok, parsed = pcall(deserializeMacro, raw)
            if ok and parsed and #parsed > 0 then
                targetMacro = parsed
                targetName = name
            end
        end
    end

    if not targetMacro then
        if #macro.macro > 0 then
            targetMacro = macro.macro
            targetName = macro.currentProfileName or "My_Macro"
        else
            return false, "ไม่มีข้อมูลมาโครที่จะแชร์ กรุณาอัดมาโครหรือโหลดโปรไฟล์ก่อน"
        end
    end

    local package = {
        format = "AA_Macro_Share",
        version = "2.0",
        profileName = targetName,
        author = plr.DisplayName or plr.Name,
        createdAt = os.date("%Y-%m-%d %H:%M:%S"),
        stepsCount = #targetMacro,
        playMode = macro.playMode or "Wave+Delay",
        macro = targetMacro,
    }

    local jsonBody = game:GetService("HttpService"):JSONEncode(package)
    local httpRequest = request or http_request or (syn and syn.request) or (http and http.request)
    if not httpRequest then
        return false, "Executor ไม่รองรับคำสั่ง HTTP Request"
    end

    local shareKey = nil

    -- 1. Try pastes.dev
    pcall(function()
        local res = httpRequest({
            Url = "https://api.pastes.dev/post",
            Method = "POST",
            Headers = { ["Content-Type"] = "text/plain" },
            Body = jsonBody,
        })
        if res and (res.StatusCode == 201 or res.status_code == 201) then
            local data = game:GetService("HttpService"):JSONDecode(res.Body or res.body)
            shareKey = data.key
        end
    end)

    -- 2. Fallback to bytebin if pastes.dev fails
    if not shareKey then
        pcall(function()
            local bRes = httpRequest({
                Url = "https://bytebin.lucko.me/post",
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = jsonBody,
            })
            if bRes and (bRes.StatusCode == 201 or bRes.status_code == 201) then
                local bData = game:GetService("HttpService"):JSONDecode(bRes.Body or bRes.body)
                if bData and bData.key then
                    shareKey = "bytebin:" .. bData.key
                end
            end
        end)
    end

    if not shareKey then
        return false, "ไม่สามารถอัปโหลดไปยังคลาวด์ได้ ตรวจสอบอินเทอร์เน็ตหรือไฟร์วอลล์"
    end

    local shareUrl
    if shareKey:find("^bytebin:") then
        local rawKey = shareKey:gsub("^bytebin:", "")
        shareUrl = "https://bytebin.lucko.me/" .. rawKey
    else
        shareUrl = "https://pastes.dev/" .. shareKey
    end

    if typeof(setclipboard) == "function" then
        pcall(function() setclipboard(shareUrl) end)
    end

    return true, shareUrl, shareKey, #targetMacro, targetName
end

function macro.ImportFromLink(linkOrKey, saveAsName)
    local mode, resolved = normalizeShareUrl(linkOrKey)
    if not mode or mode == "UNKNOWN" then
        return false, "ลิงก์หรือรหัสแชร์ไม่ถูกต้อง กรุณาตรวจสอบใหม่อีกครั้ง"
    end

    local jsonString = nil
    if mode == "RAW_JSON" then
        jsonString = resolved
    else
        local httpRequest = request or http_request or (syn and syn.request) or (http and http.request)
        local ok, body = pcall(function()
            if httpRequest then
                local res = httpRequest({
                    Url = resolved,
                    Method = "GET",
                })
                if res and (res.StatusCode == 200 or res.status_code == 200) then
                    return res.Body or res.body
                end
            end
            return game:HttpGet(resolved)
        end)
        if ok and body and body ~= "" then
            jsonString = body
        else
            return false, "ดาวน์โหลดข้อมูลจากลิงก์ไม่สำเร็จ กรุณาเช็กลิงก์อีกครั้ง"
        end
    end

    local okParse, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(jsonString)
    end)
    if not okParse or not data then
        return false, "รูปแบบข้อมูล JSON เสียหายหรือไม่ถูกต้อง"
    end

    local macroSteps = nil
    local finalName = saveAsName and saveAsName:gsub("[^%w_%-]", "_") or ""

    if type(data) == "table" and data.format == "AA_Macro_Share" and type(data.macro) == "table" then
        macroSteps = data.macro
        if finalName == "" then
            finalName = (data.profileName or "Imported_Macro"):gsub("[^%w_%-]", "_")
        end
    elseif type(data) == "table" and #data > 0 and data[1].type then
        macroSteps = data
        if finalName == "" then
            finalName = "Imported_" .. os.date("%m%d_%H%M")
        end
    else
        return false, "ไม่พบข้อมูลรายการคำสั่งมาโครในไฟล์ที่ดาวน์โหลด"
    end

    if not isfolder("AA_Macro/profiles") then makefolder("AA_Macro/profiles") end
    local filePath = "AA_Macro/profiles/" .. finalName .. ".json"
    local serializedJson = game:GetService("HttpService"):JSONEncode(macroSteps)
    writefile(filePath, serializedJson)

    macro.macro = macroSteps
    macro.currentProfileName = finalName

    return true, finalName, #macroSteps
end

-- ── 7.5. Auto Replay Controller ─────────────────────────────
function macro.TriggerReplayVote()
    if macro._replaying then return end
    macro._replaying = true

    task.spawn(function()
        -- ส่ง Webhook แจ้งเตือนผลแมตช์ทันทีก่อน Replay
        if macro.webhookEnabled and macro.webhookNotifyOnFinish and not macro._hasSentMatchWebhook then
            macro._hasSentMatchWebhook = true
            task.spawn(function()
                macro.SendMatchWebhook()
            end)
        end

        Fluent:Notify({
            Title    = "Game Finished",
            Content  = string.format("🏆 ตรวจพบจบเกม! กำลังโหวต Replay ใน %.1fs...", macro.replayDelay or 2.0),
            Duration = 3,
        })

        task.wait(macro.replayDelay or 2.0)

        local resUI = plr.PlayerGui:FindFirstChild("ResultsUI")

        -- 1. กดผ่านหน้า XP / Rewards
        pcall(function()
            if resUI and resUI:FindFirstChild("Holder") and resUI.Holder.Visible then
                local btnNext = resUI.Holder.Buttons.Next
                if btnNext and btnNext.Visible then
                    local firesig = firesignal or function(sig)
                        for _, c in ipairs(getconnections(sig)) do
                            if c.Function then pcall(c.Function) end
                        end
                    end
                    firesig(btnNext.Activated)
                end
            end
        end)

        task.wait(0.5)

        -- 2. ตั้งคิว queue_on_teleport รันสคริปต์ต่อในห้องใหม่
        pcall(function()
            local qot = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
            if qot then
                qot([[task.wait(3); if isfile("AA_Macro/main_v2.lua") then loadstring(readfile("AA_Macro/main_v2.lua"))() elseif isfile("AA_Macro/main.lua") then loadstring(readfile("AA_Macro/main.lua"))() end]])
            end
        end)

        -- 3. ยิง Remote Vote Replay เข้า Server
        pcall(function()
            return RS.endpoints.client_to_server.set_game_finished_vote:InvokeServer("replay")
        end)

        -- 4. กดปุ่ม NextRetry บน GUI เพื่อความชัวร์
        pcall(function()
            if resUI and resUI:FindFirstChild("Finished") and resUI.Finished.Visible then
                local btnRetry = resUI.Finished.NextRetry
                if btnRetry and btnRetry.Visible then
                    local firesig = firesignal or function(sig)
                        for _, c in ipairs(getconnections(sig)) do
                            if c.Function then pcall(c.Function) end
                        end
                    end
                    firesig(btnRetry.Activated)
                end
            end
        end)

        Fluent:Notify({
            Title    = "Auto Replay",
            Content  = "โหวต Replay สำเร็จแล้ว! กำลังรอวาร์ปเข้าห้องใหม่...",
            Duration = 4,
        })

        task.wait(8)
        macro._replaying = false
    end)
end

-- ── 7.6. Auto Vote Start Controller ──────────────────────────
function macro.VoteGameStart()
    local vs = plr.PlayerGui:FindFirstChild("VoteStart")
    local holder = vs and vs:FindFirstChild("Holder")
    local btnHolder = holder and holder:FindFirstChild("ButtonHolder")
    local btnYes = btnHolder and btnHolder:FindFirstChild("Yes")

    local success = false

    -- 1. กดปุ่ม Yes บน GUI ด้วย firesignal / getconnections
    if btnYes then
        local firesig = firesignal or function(sig)
            for _, c in ipairs(getconnections(sig)) do
                if c.Function then pcall(c.Function) end
            end
        end

        pcall(function() firesig(btnYes.Activated) end)
        pcall(function() firesig(btnYes.MouseButton1Click) end)
        pcall(function() firesig(btnYes.MouseButton1Down) end)
        pcall(function() firesig(btnYes.MouseButton1Up) end)

        if getconnections then
            pcall(function()
                for _, c in ipairs(getconnections(btnYes.Activated)) do
                    if c.Function then pcall(c.Function) end
                    if c.Fire then pcall(function() c:Fire() end) end
                end
            end)
            pcall(function()
                for _, c in ipairs(getconnections(btnYes.MouseButton1Click)) do
                    if c.Function then pcall(c.Function) end
                    if c.Fire then pcall(function() c:Fire() end) end
                end
            end)
        end
        success = true
    end

    -- 2. ยิง Remote vote_start ตรงเข้า Server เป็น Failsafe 100%
    pcall(function()
        local ep = RS:FindFirstChild("endpoints") and RS.endpoints:FindFirstChild("client_to_server")
        if ep and ep:FindFirstChild("vote_start") then
            ep.vote_start:InvokeServer()
            success = true
        end
    end)

    return success
end

function macro.CheckAndVoteStart()
    local vs = plr.PlayerGui:FindFirstChild("VoteStart")
    if vs and vs.Enabled then
        local holder = vs:FindFirstChild("Holder")
        local btnHolder = holder and holder:FindFirstChild("ButtonHolder")
        local btnYes = btnHolder and btnHolder:FindFirstChild("Yes")
        if btnYes and btnYes.Visible then
            return macro.VoteGameStart()
        end
    end
    return false
end

-- ── 7.7. Discord Webhook Controller ──────────────────────────
local webhookConfigPath = "AA_Macro/webhook_config.json"

function macro.SaveWebhookConfig()
    pcall(function()
        if not isfolder("AA_Macro") then makefolder("AA_Macro") end
        local cfg = {
            url            = macro.webhookUrl or "",
            enabled        = macro.webhookEnabled or false,
            notifyOnFinish = macro.webhookNotifyOnFinish ~= false,
            censorUser     = macro.webhookCensorUser or false,
        }
        writefile(webhookConfigPath, game:GetService("HttpService"):JSONEncode(cfg))
        if macro.SaveSettings then macro.SaveSettings() end
    end)
end

function macro.LoadWebhookConfig()
    pcall(function()
        if isfile and isfile(webhookConfigPath) then
            local raw = readfile(webhookConfigPath)
            local data = game:GetService("HttpService"):JSONDecode(raw)
            if type(data) == "table" then
                if data.url then macro.webhookUrl = data.url end
                if data.enabled ~= nil then macro.webhookEnabled = data.enabled end
                if data.notifyOnFinish ~= nil then macro.webhookNotifyOnFinish = data.notifyOnFinish end
                if data.censorUser ~= nil then macro.webhookCensorUser = data.censorUser end
            end
        end
    end)
end
macro.LoadWebhookConfig()

local function formatNumber(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local k
    while true do
        s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return s
end

local function formatShort(n)
    n = tonumber(n) or 0
    if n >= 1e9 then
        return string.format("%.2fB", n / 1e9)
    elseif n >= 1e6 then
        return string.format("%.2fM", n / 1e6)
    elseif n >= 1e3 then
        return string.format("%.1fK", n / 1e3)
    else
        return tostring(math.floor(n))
    end
end

function macro.GetMatchData()
    local p = plr or game:GetService("Players").LocalPlayer
    local rs = RS or game:GetService("ReplicatedStorage")
    local d = {}

    d.name = p.Name
    d.displayName = p.DisplayName
    d.userId = p.UserId

    -- เลเวลจาก Character Overhead
    d.level = "?"
    pcall(function()
        local char = p.Character or workspace:FindFirstChild(p.Name)
        local head = char and char:FindFirstChild("Head")
        local ov = head and head:FindFirstChild("_overhead")
        local lvlObj = ov and ov.Frame.Level_Frame.Level
        if lvlObj and lvlObj.Text ~= "" then
            d.level = lvlObj.Text
        end
    end)

    -- สถิติพื้นฐานจาก p._stats (Gems, XP, Gold, Damage, Kills)
    d.gems = 0
    d.xp = 0
    d.gold = 0
    d.damage = 0
    d.kills = 0
    pcall(function()
        local s = p:FindFirstChild("_stats")
        if s then
            d.gems = s:FindFirstChild("gem_amount") and math.floor(s.gem_amount.Value) or 0
            d.xp = s:FindFirstChild("player_xp") and math.floor(s.player_xp.Value) or 0
            d.gold = s:FindFirstChild("gold_amount") and math.floor(s.gold_amount.Value) or 0
            d.damage = s:FindFirstChild("damage_dealt") and math.floor(s.damage_dealt.Value) or 0
            d.kills = s:FindFirstChild("kills") and math.floor(s.kills.Value) or 0
        end
    end)

    -- ข้อมูลแมพ & ด่านจาก _MAP_CONFIG.GetLevelData
    d.locationName = "Unknown Map"
    d.levelName = "Standard Mode"
    d.difficulty = "Normal"
    d.gamemode = "Standard"
    d.world = ""
    pcall(function()
        local mc = workspace:FindFirstChild("_MAP_CONFIG")
        if mc and mc:FindFirstChild("GetLevelData") then
            local lData = mc.GetLevelData:InvokeServer()
            if lData then
                d.locationName = lData._location_name or lData.map or "Unknown Map"
                d.levelName = lData.name or "Standard Mode"
                d.difficulty = lData._difficulty or (lData._MATCHMAKING and lData._MATCHMAKING.difficulty) or "Normal"
                d.gamemode = lData._gamemode or "Standard"
                d.world = lData.world or ""
            end
        end
    end)

    -- ค้นหาชื่อ World ภาษาที่เป็นทางการจาก Data.Worlds
    d.worldFriendly = d.locationName
    pcall(function()
        local worldsMod = rs.src.Data:FindFirstChild("Worlds")
        if worldsMod and d.world and d.world ~= "" then
            local worlds = require(worldsMod)
            if worlds[d.world] and worlds[d.world].name then
                d.worldFriendly = worlds[d.world].name
            end
        end
    end)

    -- ข้อมูลเวฟ
    d.wave = getWave()

    -- ข้อมูลจาก ResultsUI (ถ้าเปิดอยู่)
    d.result = "UNKNOWN"
    d.gemReward = nil
    d.goldReward = nil
    d.xpReward = nil
    d.trophyReward = nil
    d.timeTaken = nil

    pcall(function()
        local rui = p.PlayerGui:FindFirstChild("ResultsUI")
        if rui and rui.Enabled and rui:FindFirstChild("Holder") then
            local h = rui.Holder
            if h:FindFirstChild("Title") and h.Title.Text ~= "" then
                d.result = h.Title.Text:upper()
            end
            if h:FindFirstChild("LevelName") and h.LevelName.Text ~= "" then
                d.levelName = h.LevelName.Text
            end
            if h:FindFirstChild("Difficulty") and h.Difficulty.Text ~= "" then
                d.difficulty = h.Difficulty.Text
            end
            if h:FindFirstChild("Middle") then
                local m = h.Middle
                if m:FindFirstChild("WavesCompleted") and m.WavesCompleted.Text ~= "" then
                    local wNum = m.WavesCompleted.Text:match("%d+")
                    if wNum then d.wave = tonumber(wNum) end
                end
                if m:FindFirstChild("Timer") and m.Timer.Text ~= "" then
                    d.timeTaken = m.Timer.Text:gsub("Total Time:%s*", "")
                end
            end
            if h:FindFirstChild("LevelRewards") and h.LevelRewards:FindFirstChild("ScrollingFrame") then
                local sf = h.LevelRewards.ScrollingFrame
                if sf:FindFirstChild("GemReward") and sf.GemReward:FindFirstChild("Main") and sf.GemReward.Main:FindFirstChild("Amount") then
                    d.gemReward = sf.GemReward.Main.Amount.Text
                end
                if sf:FindFirstChild("GoldReward") and sf.GoldReward.Main:FindFirstChild("Amount") then
                    d.goldReward = sf.GoldReward.Main.Amount.Text
                end
                if sf:FindFirstChild("XPReward") and sf.XPReward:FindFirstChild("Main") and sf.XPReward.Main:FindFirstChild("Amount") then
                    d.xpReward = sf.XPReward.Main.Amount.Text
                end
                if sf:FindFirstChild("TrophyReward") and sf.TrophyReward:FindFirstChild("Main") and sf.TrophyReward.Main:FindFirstChild("Amount") then
                    d.trophyReward = sf.TrophyReward.Main.Amount.Text
                end
            end
        end
    end)

    -- คำนวณเวลาที่ใช้ (ถ้าไม่มีใน ResultsUI)
    if not d.timeTaken then
        local elapsed = macro._matchStartTime and (tick() - macro._matchStartTime) or 0
        d.timeTaken = string.format("%dm %02ds", math.floor(elapsed / 60), math.floor(elapsed % 60))
    end

    d.profileName = macro.currentProfileName or "Unsaved"
    d.playMode = macro.playMode or "Wave+Delay"

    return d
end

local function buildMatchEmbed(data, isTest)
    local titleText
    local color
    local resultTag

    if isTest then
        titleText = "📡 [TEST] Webhook Integration Active"
        color = 0x00D2FF
        resultTag = "TEST NOTIFICATION"
    elseif data.result:find("VICTORY") then
        titleText = "🏆 VICTORY — STAGE CLEARED"
        color = 0x00FF88
        resultTag = "VICTORY"
    elseif data.result:find("DEFEAT") then
        titleText = "💀 DEFEAT — GAME OVER"
        color = 0xFF3366
        resultTag = "DEFEAT"
    else
        titleText = "⚔️ ANIME ADVENTURES — MATCH REPORT"
        color = 0x5865F2
        resultTag = "MATCH COMPLETED"
    end

    local username = data.displayName or data.name or "Adventurer"
    if macro.webhookCensorUser and #username > 3 then
        username = username:sub(1, 2) .. string.rep("*", math.max(1, #username - 3)) .. username:sub(-1)
    end

    local avatarUrl = string.format("https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=150&height=150&format=png", data.userId or 1)

    local mapDisplay = data.worldFriendly or data.locationName or "Unknown Map"
    if data.world and data.world ~= "" and data.world:lower() ~= (data.worldFriendly or ""):lower() then
        mapDisplay = string.format("%s (%s)", mapDisplay, data.world:upper())
    end

    local gemsDisplay = string.format("**%s** 💎", formatNumber(data.gems or 0))
    if data.gemReward and data.gemReward ~= "" then
        gemsDisplay = string.format("%s `(%s)`", gemsDisplay, data.gemReward)
    end

    local xpDisplay = string.format("**%s** XP", formatNumber(data.xp or 0))
    if data.xpReward and data.xpReward ~= "" then
        xpDisplay = string.format("%s `(%s)`", xpDisplay, data.xpReward)
    end

    local fields = {
        {
            name = "👤 ผู้เล่น (Player)",
            value = string.format("**%s**\nLevel **%s**", username, tostring(data.level or "?")),
            inline = true,
        },
        {
            name = "🗺️ แมพ (Map / World)",
            value = string.format("**%s**", mapDisplay),
            inline = true,
        },
        {
            name = "🎯 ด่าน (Stage / Mode)",
            value = string.format("**%s**\n`%s • %s`", data.levelName or "Standard", data.difficulty or "Normal", data.gamemode or "Story"),
            inline = true,
        },
        {
            name = "🌊 จำนวนเวฟ (Wave)",
            value = string.format("`Wave %s`", tostring(data.wave or 0)),
            inline = true,
        },
        {
            name = "⏱️ เวลาที่ใช้ (Duration)",
            value = string.format("`%s`", data.timeTaken or "00:00"),
            inline = true,
        },
        {
            name = "💎 Gems ปัจจุบัน (+ที่ได้)",
            value = gemsDisplay,
            inline = true,
        },
        {
            name = "⭐ XP ปัจจุบัน (+ที่ได้)",
            value = xpDisplay,
            inline = true,
        },
        {
            name = "💰 เงินรางวัล (Gold)",
            value = data.goldReward and string.format("`%s ¥`", data.goldReward) or string.format("`%s ¥`", formatNumber(data.gold or 0)),
            inline = true,
        },
        {
            name = "💥 สถิติต่อสู้ (Combat)",
            value = string.format("DMG: `%s`\nKills: `%s`", formatShort(data.damage or 0), formatNumber(data.kills or 0)),
            inline = true,
        },
    }

    if data.profileName and data.profileName ~= "" then
        table.insert(fields, {
            name = "🤖 สถานะ Macro",
            value = string.format("Profile: `%s` • Mode: `%s`", data.profileName, data.playMode or "Wave+Delay"),
            inline = false,
        })
    end

    local embed = {
        title = titleText,
        description = string.format("> **ผลการเล่น:** `%s` │ **ด่าน:** `%s`", resultTag, data.levelName or "Match"),
        color = color,
        fields = fields,
        author = {
            name = string.format("%s • AA Macro Studio v2.0", data.displayName or data.name or "Adventurer"),
            icon_url = avatarUrl,
        },
        footer = {
            text = string.format("AA Macro Studio v2.0 • %s", os.date("%d/%m/%Y %H:%M:%S")),
        },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }

    return {
        username = "AA Macro Notifier",
        avatar_url = "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Fluent.png",
        embeds = { embed },
    }
end

function macro.SendWebhook(payload)
    if not macro.webhookUrl or macro.webhookUrl == "" or not macro.webhookUrl:find("https://") then
        return false, "Webhook URL ไม่ถูกต้องหรือยังไม่ได้ตั้งค่า"
    end

    local httpRequest = request or http_request or (syn and syn.request) or (http and http.request)
    if not httpRequest then
        return false, "Executor ไม่รองรับคำสั่ง HTTP Request"
    end

    local body = game:GetService("HttpService"):JSONEncode(payload)
    local ok, res = pcall(function()
        return httpRequest({
            Url = macro.webhookUrl,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = body,
        })
    end)

    if ok and res then
        local statusCode = res.StatusCode or res.status_code or res.Status
        if statusCode and (statusCode >= 200 and statusCode < 300) then
            return true, "Success (" .. tostring(statusCode) .. ")"
        else
            return false, "HTTP " .. tostring(statusCode) .. ": " .. tostring(res.Body or res.body or "No response")
        end
    end
    return false, tostring(res)
end

function macro.SendMatchWebhook()
    local data = macro.GetMatchData()
    local payload = buildMatchEmbed(data, false)
    local ok, msg = macro.SendWebhook(payload)
    if ok then
        macro._lastWebhookStatus = "ส่งสำเร็จ (" .. os.date("%H:%M:%S") .. ")"
    else
        macro._lastWebhookStatus = "ส่งไม่สำเร็จ: " .. tostring(msg)
    end
    return ok, msg
end

function macro.SendTestWebhook()
    local data = macro.GetMatchData()
    data.result = "TEST"
    local payload = buildMatchEmbed(data, true)
    local ok, msg = macro.SendWebhook(payload)
    if ok then
        macro._lastWebhookStatus = "ทดสอบสำเร็จ (" .. os.date("%H:%M:%S") .. ")"
        Fluent:Notify({
            Title    = "Webhook Test",
            Content  = "✅ ส่งข้อความทดสอบไปยัง Discord เรียบร้อยแล้ว!",
            Duration = 4,
        })
    else
        macro._lastWebhookStatus = "ทดสอบล้มเหลว: " .. tostring(msg)
        Fluent:Notify({
            Title    = "Webhook Test Failed",
            Content  = "❌ เกิดข้อผิดพลาด: " .. tostring(msg),
            Duration = 5,
        })
    end
    return ok, msg
end


-- ── 8. Floating Cyberpunk HUD Overlay ───────────────────────
local hudGui = Instance.new("ScreenGui")
hudGui.Name = "AAMacro_HUD_v2"
hudGui.ResetOnSpawn = false
hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudGui.Enabled = (macro.showHUD ~= false)
pcall(function() hudGui.Parent = gethui() end)

local hudFrame = Instance.new("Frame")
hudFrame.Name = "MainHUD"
hudFrame.Size = UDim2.fromOffset(270, 130)
hudFrame.Position = UDim2.new(1, -290, 0, 45)
hudFrame.BackgroundColor3 = Color3.fromRGB(13, 15, 23)
hudFrame.BackgroundTransparency = 0.15
hudFrame.BorderSizePixel = 0
hudFrame.Parent = hudGui

local hudCorner = Instance.new("UICorner")
hudCorner.CornerRadius = UDim.new(0, 10)
hudCorner.Parent = hudFrame

local hudStroke = Instance.new("UIStroke")
hudStroke.Thickness = 1.6
hudStroke.Color = Color3.fromRGB(0, 180, 255)
hudStroke.Transparency = 0.2
hudStroke.Parent = hudFrame

-- Top Bar
local hudTop = Instance.new("Frame")
hudTop.Size = UDim2.new(1, -16, 0, 24)
hudTop.Position = UDim2.new(0, 8, 0, 6)
hudTop.BackgroundTransparency = 1
hudTop.Parent = hudFrame

local hudTitle = Instance.new("TextLabel")
hudTitle.Size = UDim2.new(0, 130, 1, 0)
hudTitle.BackgroundTransparency = 1
hudTitle.Text = "⚡ AA MACRO v2"
hudTitle.Font = Enum.Font.GothamBold
hudTitle.TextSize = 13
hudTitle.TextColor3 = Color3.fromRGB(240, 245, 255)
hudTitle.TextXAlignment = Enum.TextXAlignment.Left
hudTitle.Parent = hudTop

local hudBadge = Instance.new("TextLabel")
hudBadge.Size = UDim2.new(0, 65, 0, 18)
hudBadge.Position = UDim2.new(1, -65, 0, 3)
hudBadge.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
hudBadge.Text = "STANDBY"
hudBadge.Font = Enum.Font.GothamBold
hudBadge.TextSize = 9
hudBadge.TextColor3 = Color3.fromRGB(180, 190, 210)
hudBadge.Parent = hudTop

local badgeCorner = Instance.new("UICorner")
badgeCorner.CornerRadius = UDim.new(0, 5)
badgeCorner.Parent = hudBadge

-- Stats Line
local hudStats = Instance.new("TextLabel")
hudStats.Size = UDim2.new(1, -16, 0, 18)
hudStats.Position = UDim2.new(0, 8, 0, 34)
hudStats.BackgroundTransparency = 1
hudStats.Text = "🌊 Wave 0   |   💰 0 ¥   |   🛡️ 0"
hudStats.Font = Enum.Font.GothamMedium
hudStats.TextSize = 11
hudStats.TextColor3 = Color3.fromRGB(160, 180, 215)
hudStats.TextXAlignment = Enum.TextXAlignment.Left
hudStats.Parent = hudFrame

-- Progress Bar
local hudProgBg = Instance.new("Frame")
hudProgBg.Size = UDim2.new(1, -16, 0, 14)
hudProgBg.Position = UDim2.new(0, 8, 0, 58)
hudProgBg.BackgroundColor3 = Color3.fromRGB(22, 26, 40)
hudProgBg.BorderSizePixel = 0
hudProgBg.Parent = hudFrame

local progBgCorner = Instance.new("UICorner")
progBgCorner.CornerRadius = UDim.new(0, 4)
progBgCorner.Parent = hudProgBg

local hudProgFill = Instance.new("Frame")
hudProgFill.Size = UDim2.new(0, 0, 1, 0)
hudProgFill.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
hudProgFill.BorderSizePixel = 0
hudProgFill.Parent = hudProgBg

local progFillCorner = Instance.new("UICorner")
progFillCorner.CornerRadius = UDim.new(0, 4)
progFillCorner.Parent = hudProgFill

local hudProgText = Instance.new("TextLabel")
hudProgText.Size = UDim2.new(1, 0, 1, 0)
hudProgText.BackgroundTransparency = 1
hudProgText.Text = "0% (0/0)"
hudProgText.Font = Enum.Font.GothamBold
hudProgText.TextSize = 9
hudProgText.TextColor3 = Color3.fromRGB(255, 255, 255)
hudProgText.Parent = hudProgBg

-- Next Action Text
local hudNext = Instance.new("TextLabel")
hudNext.Size = UDim2.new(1, -16, 0, 42)
hudNext.Position = UDim2.new(0, 8, 0, 78)
hudNext.BackgroundTransparency = 1
hudNext.Text = "🎯 Next: รอคำสั่ง..."
hudNext.Font = Enum.Font.Gotham
hudNext.TextSize = 10
hudNext.TextColor3 = Color3.fromRGB(150, 170, 200)
hudNext.TextXAlignment = Enum.TextXAlignment.Left
hudNext.TextYAlignment = Enum.TextYAlignment.Top
hudNext.TextWrapped = true
hudNext.Parent = hudFrame

-- Make HUD Smoothly Draggable
local dragging = false
local dragInput, dragStart, startPos

hudFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = hudFrame.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

hudFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UIS.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        hudFrame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

-- ── 9. Fluent UI Construction ───────────────────────────────
local Window = Fluent:CreateWindow({
    Title       = "AA Macro Studio v2.0",
    SubTitle    = "by cook45 & clack",
    TabWidth    = 140,
    Size        = UDim2.fromOffset(620, 560),
    Acrylic     = true,
    Theme       = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl,
})
_G.AAMacroUI = Window

local Tabs = {
    Macro       = Window:AddTab({ Title = "Macro",       Icon = "play" }),
    Event       = Window:AddTab({ Title = "Event",       Icon = "sparkles" }),
    Battlefield = Window:AddTab({ Title = "Battlefield", Icon = "gauge" }),
    Webhook     = Window:AddTab({ Title = "Webhook",     Icon = "bell" }),
    Log         = Window:AddTab({ Title = "Action Log",  Icon = "list" }),
    Debug       = Window:AddTab({ Title = "Debug",       Icon = "search" }),
    Settings    = Window:AddTab({ Title = "Settings",    Icon = "settings" }),
}
macro.Tabs = Tabs

-- ────────────────────────────────────────────────────────────
-- ── 10. MACRO TAB (Merged: Dashboard + Controls + Profiles) ─
-- ────────────────────────────────────────────────────────────

-- ── Section 1: Live Status ───────────────────────────────────
Tabs.Macro:AddSection("⚡ STATUS")

local DashStatusCard = Tabs.Macro:AddParagraph({
    Title   = "⏹️ STANDBY",
    Content = "กำลังเชื่อมต่อระบบ...",
})

local DashProgressCard = Tabs.Macro:AddParagraph({
    Title   = "📈 PROGRESSION  •  0%",
    Content = "░░░░░░░░░░░░░░  0%\nคิวงานทั้งหมด: 0 รายการ",
})

local DashNextActionCard = Tabs.Macro:AddParagraph({
    Title   = "🎯 NEXT ACTION",
    Content = "💤 ไม่มีคำสั่งในคิว — กด Record หรือโหลดโปรไฟล์",
})

-- ── Section 2: Controls ──────────────────────────────────────
Tabs.Macro:AddSection("🕹️ CONTROLS")

Tabs.Macro:AddButton({
    Title       = "⏺  Record",
    Description = "เริ่มบันทึกการกระทำใหม่ (ล้างประวัติเดิมในหน่วยความจำ)",
    Callback    = function()
        if macro.playing then
            Fluent:Notify({ Title = "Error", Content = "กำลังรัน Macro อยู่ กรุณากด Stop ก่อน", Duration = 2 })
            return
        end
        macro.StartRecording()
        Fluent:Notify({ Title = "🔴 Recording", Content = "เริ่มบันทึก — วาง/อัปเกรดตัวละครได้เลย", Duration = 3 })
    end,
})

Tabs.Macro:AddButton({
    Title       = "⏹  Stop",
    Description = "หยุดการบันทึก หรือหยุดการรัน",
    Callback    = function()
        if macro.recording then
            macro.StopRecording()
            Fluent:Notify({ Title = "✅ Saved", Content = string.format("บันทึกเสร็จสิ้น: %d ขั้นตอน", #macro.macro), Duration = 3 })
        elseif macro.playing then
            macro.StopPlay()
            Fluent:Notify({ Title = "⏹ Stopped", Content = "หยุดการทำงาน Macro เรียบร้อย", Duration = 2 })
        else
            Fluent:Notify({ Title = "Info", Content = "ไม่มีระบบใดทำงานอยู่", Duration = 2 })
        end
    end,
})

Tabs.Macro:AddButton({
    Title       = "▶️  Play",
    Description = "รันการวางและอัปเกรดอัตโนมัติตามโหมดที่เลือก",
    Callback    = function()
        if #macro.macro == 0 then
            Fluent:Notify({ Title = "Error", Content = "ยังไม่มีข้อมูล Macro กรุณาอัดหรือโหลดโปรไฟล์", Duration = 2 })
            return
        end
        if macro.recording then
            Fluent:Notify({ Title = "Error", Content = "กำลังบันทึกอยู่ กรุณากด Stop ก่อน", Duration = 2 })
            return
        end
        macro.Play()
        Fluent:Notify({
            Title   = "▶️ Playing",
            Content = string.format("เริ่ม %d รายการ | โหมด: %s", #macro.macro, macro.playMode),
            Duration = 3,
        })
    end,
})

Tabs.Macro:AddButton({
    Title       = "🗑️  Reset",
    Description = "ล้างข้อมูลมาโครในหน่วยความจำ",
    Callback    = function()
        Window:Dialog({
            Title   = "ยืนยันการล้างข้อมูล",
            Content = string.format("ต้องการล้าง %d รายการ ใช่หรือไม่?", #macro.macro),
            Buttons = {
                { Title = "ยืนยัน", Callback = function() macro.Reset(); Fluent:Notify({ Title = "Reset", Content = "ล้างแล้ว", Duration = 2 }) end },
                { Title = "ยกเลิก", Callback = function() end },
            },
        })
    end,
})

-- ── Section 3: Playback Config ───────────────────────────────
Tabs.Macro:AddSection("⚙️ CONFIG")

Tabs.Macro:AddDropdown("MacroPlayMode", {
    Title       = "Playback Mode",
    Description = "Wave+Delay = อิงตาม Wave + ดีเลย์วินาที | Strict Time = อิงเวลาสัมบูรณ์นับจากกด Play",
    Values      = { "Wave+Delay", "Strict Time" },
    Default     = macro.playMode,
    Callback    = function(val)
        macro.playMode = val
        macro.SaveSettings()
        Fluent:Notify({ Title = "Mode", Content = "โหมด: " .. val .. " (บันทึกแล้ว)", Duration = 2 })
    end,
})

Tabs.Macro:AddSlider("MacroActionDelay", {
    Title       = "Action Delay (วินาที)",
    Description = "ระยะเวลาหน่วงระหว่างแต่ละการกระทำ",
    Default     = macro.actionDelay or 0.15,
    Min         = 0.05,
    Max         = 1.0,
    Rounding    = 2,
    Callback    = function(val)
        macro.actionDelay = val
        macro.SaveSettings()
    end,
})

Tabs.Macro:AddToggle("MacroAutoReplay", {
    Title       = "Auto Replay (โหวตเริ่มใหม่เมื่อจบด่าน)",
    Description = "ตรวจจับ ResultsUI กดข้าม XP + โหวต Replay + ตั้งคิว script ในห้องใหม่อัตโนมัติ",
    Default     = macro.autoReplay,
    Callback    = function(val)
        macro.autoReplay = val
        macro.SaveSettings()
        Fluent:Notify({ Title = "Auto Replay", Content = val and "🟢 เปิดใช้งาน (บันทึกแล้ว)" or "🔴 ปิด (บันทึกแล้ว)", Duration = 2 })
    end,
})

Tabs.Macro:AddSlider("MacroReplayDelay", {
    Title       = "Replay Delay (วินาที)",
    Description = "หน่วงเวลาก่อนกด Replay เพื่อให้เห็นของดรอป",
    Default     = macro.replayDelay or 2.0,
    Min         = 0.5,
    Max         = 8.0,
    Rounding    = 1,
    Callback    = function(val)
        macro.replayDelay = val
        macro.SaveSettings()
    end,
})

Tabs.Macro:AddToggle("MacroAutoVoteStart", {
    Title       = "Auto Vote Start (โหวตเริ่มเกมทันที)",
    Description = "โหวตเริ่มเกม (VoteStart Yes) ทันทีที่เข้าด่านใหม่ (ไม่เกี่ยวกับมาโคร ไม่สั่งรันมาโครเอง)",
    Default     = macro.autoVoteStart ~= false,
    Callback    = function(val)
        macro.autoVoteStart = val
        macro.autoStartOnMatch = val -- backward compatibility
        macro.SaveSettings()
        if val then
            macro.CheckAndVoteStart()
        end
        Fluent:Notify({ Title = "Auto Vote Start", Content = val and "🟢 เปิดใช้งาน (บันทึกแล้ว)" or "🔴 ปิด (บันทึกแล้ว)", Duration = 2 })
    end,
})

Tabs.Macro:AddToggle("MacroAutoPlayOnStart", {
    Title       = "Auto Play Macro on Wave 1 (เล่นมาโครอัตโนมัติ)",
    Description = "สั่งกด Play เล่นโปรไฟล์มาโครอัตโนมัติเมื่อ Wave 1 เริ่มต้น (ปิดไว้ถ้าเล่นโหมดสุ่มตัวละคร/AI)",
    Default     = macro.autoPlayMacroOnMatch == true,
    Callback    = function(val)
        macro.autoPlayMacroOnMatch = val
        macro.SaveSettings()
        Fluent:Notify({ Title = "Auto Play Macro", Content = val and "🟢 เปิดใช้งาน (บันทึกแล้ว)" or "🔴 ปิด (บันทึกแล้ว)", Duration = 2 })
    end,
})

Tabs.Macro:AddToggle("MacroFloatingHUD", {
    Title       = "🖥️ Floating HUD",
    Description = "แสดง HUD Overlay บนหน้าจอ (ลากย้ายได้)",
    Default     = (macro.showHUD ~= false),
    Callback    = function(val)
        macro.showHUD = val
        macro.SaveSettings()
        hudGui.Enabled = val
    end,
})

-- ── Section 4: Profile Manager ───────────────────────────────
Tabs.Macro:AddSection("📁 PROFILES")

local inputProfileName = "My_Macro_1"

local ProfileNameInput = Tabs.Macro:AddInput("MacroProfileInput", {
    Title       = "ชื่อโปรไฟล์",
    Default     = inputProfileName,
    Placeholder = "เช่น Infinity_Run, Act1_Full",
    Numeric     = false,
    Finished    = false,
    Callback    = function(val)
        if val and val ~= "" then inputProfileName = val end
    end,
})

local ProfileDropdown = nil

Tabs.Macro:AddButton({
    Title       = "💾  Save Profile",
    Description = "บันทึกมาโครปัจจุบันลงเป็นไฟล์ตามชื่อด้านบน",
    Callback    = function()
        if #macro.macro == 0 then
            Fluent:Notify({ Title = "Error", Content = "ไม่มีข้อมูลมาโครให้บันทึก", Duration = 2 })
            return
        end
        local savedName = macro.SaveProfile(inputProfileName)
        macro.currentProfileName = savedName
        macro.SaveSettings()
        if ProfileDropdown then
            ProfileDropdown:SetValues(macro.GetProfiles())
            ProfileDropdown:SetValue(savedName)
        end
        Fluent:Notify({ Title = "💾 Saved", Content = string.format("'%s' — %d ขั้นตอน (บันทึกแล้ว)", savedName, #macro.macro), Duration = 3 })
    end,
})

local profileList = macro.GetProfiles()
local selectedProfile = macro.currentProfileName or profileList[1] or "(No saved profiles)"
if not table.find(profileList, selectedProfile) then
    selectedProfile = profileList[1] or "(No saved profiles)"
end

ProfileDropdown = Tabs.Macro:AddDropdown("MacroProfileList", {
    Title    = "เลือกโปรไฟล์",
    Values   = profileList,
    Default  = selectedProfile,
    Callback = function(val)
        selectedProfile = val
        if val and val ~= "(No saved profiles)" then
            macro.currentProfileName = val
            macro.SaveSettings()
        end
    end,
})

Tabs.Macro:AddButton({
    Title       = "📂  Load Profile",
    Description = "โหลดโปรไฟล์ที่เลือกเข้าสู่ระบบ",
    Callback    = function()
        if not selectedProfile or selectedProfile == "(No saved profiles)" then
            Fluent:Notify({ Title = "Error", Content = "กรุณาเลือกโปรไฟล์", Duration = 2 })
            return
        end
        local ok = macro.LoadProfile(selectedProfile)
        if ok then
            macro.currentProfileName = selectedProfile
            macro.SaveSettings()
        end
        Fluent:Notify({
            Title   = ok and "📂 Loaded" or "❌ Error",
            Content = ok and string.format("'%s' — %d ขั้นตอน (บันทึกเป็นโปรไฟล์หลักแล้ว)", selectedProfile, #macro.macro) or "โหลดไม่สำเร็จ",
            Duration = 3,
        })
    end,
})

Tabs.Macro:AddButton({
    Title       = "🗑️  Delete Profile",
    Description = "ลบโปรไฟล์ที่เลือกออกถาวร",
    Callback    = function()
        if not selectedProfile or selectedProfile == "(No saved profiles)" then
            Fluent:Notify({ Title = "Error", Content = "กรุณาเลือกโปรไฟล์ที่จะลบ", Duration = 2 })
            return
        end
        Window:Dialog({
            Title   = "ยืนยันการลบ",
            Content = "ลบโปรไฟล์ '" .. selectedProfile .. "' ถาวรหรือไม่?",
            Buttons = {
                {
                    Title    = "ลบถาวร",
                    Callback = function()
                        macro.DeleteProfile(selectedProfile)
                        local updated = macro.GetProfiles()
                        ProfileDropdown:SetValues(updated)
                        selectedProfile = updated[1] or "(No saved profiles)"
                        ProfileDropdown:SetValue(selectedProfile)
                        Fluent:Notify({ Title = "Deleted", Content = "ลบไฟล์เรียบร้อยแล้ว", Duration = 2 })
                    end,
                },
                { Title = "ยกเลิก", Callback = function() end },
            },
        })
    end,
})

Tabs.Macro:AddButton({
    Title       = "🔄  Refresh List",
    Description = "สแกนหาไฟล์โปรไฟล์ใหม่",
    Callback    = function()
        local list = macro.GetProfiles()
        ProfileDropdown:SetValues(list)
        selectedProfile = list[1] or "(No saved profiles)"
        ProfileDropdown:SetValue(selectedProfile)
        Fluent:Notify({ Title = "Refreshed", Content = string.format("พบ %d โปรไฟล์", #list), Duration = 2 })
    end,
})

-- ── Section 5: Cloud Share & Import ───────────────────────────
Tabs.Macro:AddSection("🌐 CLOUD SHARE & IMPORT")

Tabs.Macro:AddButton({
    Title       = "🔗 สร้างลิงก์แชร์โปรไฟล์ (Share Profile to Link)",
    Description = "อัปโหลดขึ้น Cloud และสร้างลิงก์แชร์ สามารถนำไปเปิดในอีกเครื่องได้ทันที",
    Callback    = function()
        local ok, url, key, count, pName = macro.ShareProfile(selectedProfile)
        if ok then
            Window:Dialog({
                Title   = "🔗 สร้างลิงก์แชร์สำเร็จ!",
                Content = string.format("โปรไฟล์ : %s (%d ขั้นตอน)\n\nลิงก์แชร์ (คัดลอกลงคลิปบอร์ดแล้ว):\n%s\n\nรหัสแชร์ (Key): %s", pName, count, url, key),
                Buttons = {
                    {
                        Title    = "📋 คัดลอกลิงก์อีกครั้ง",
                        Callback = function()
                            if typeof(setclipboard) == "function" then setclipboard(url) end
                            Fluent:Notify({ Title = "Copied", Content = "คัดลอกลิงก์ลงคลิปบอร์ดเรียบร้อย!", Duration = 2 })
                        end,
                    },
                    { Title = "เรียบร้อย", Callback = function() end },
                },
            })
            Fluent:Notify({
                Title    = "Share Link Created",
                Content  = string.format("คัดลอกลิงก์แล้ว: %s", url),
                Duration = 4,
            })
        else
            Fluent:Notify({
                Title    = "Share Failed",
                Content  = tostring(url),
                Duration = 4,
            })
        end
    end,
})

local importLinkInput = ""
Tabs.Macro:AddInput("MacroImportLinkInput", {
    Title       = "วางลิงก์ หรือ รหัสแชร์ (Link / Share Key)",
    Default     = "",
    Placeholder = "เช่น https://pastes.dev/... หรือรหัสแชร์",
    Numeric     = false,
    Finished    = false,
    Callback    = function(val)
        if val then importLinkInput = val end
    end,
})

local importNameInput = ""
Tabs.Macro:AddInput("MacroImportNameInput", {
    Title       = "ตั้งชื่อโปรไฟล์ใหม่ (ปล่อยว่างเพื่อใช้ชื่อเดิม)",
    Default     = "",
    Placeholder = "เช่น My_Imported_Macro",
    Numeric     = false,
    Finished    = false,
    Callback    = function(val)
        if val then importNameInput = val end
    end,
})

Tabs.Macro:AddButton({
    Title       = "📥 ดาวน์โหลดและนำเข้าโปรไฟล์ (Import from Link)",
    Description = "ดึงข้อมูลจากลิงก์ บันทึกเป็นโปรไฟล์ และโหลดเข้าสู่ระบบทันที",
    Callback    = function()
        if not importLinkInput or importLinkInput:gsub("%s+", "") == "" then
            Fluent:Notify({
                Title    = "Import Error",
                Content  = "กรุณาวางลิงก์หรือรหัสแชร์ก่อนกดนำเข้า",
                Duration = 3,
            })
            return
        end

        local ok, pName, count = macro.ImportFromLink(importLinkInput, importNameInput ~= "" and importNameInput or nil)
        if ok then
            local updated = macro.GetProfiles()
            if ProfileDropdown then
                ProfileDropdown:SetValues(updated)
                ProfileDropdown:SetValue(pName)
            end
            Window:Dialog({
                Title   = "✅ นำเข้าโปรไฟล์สำเร็จ!",
                Content = string.format("โหลดโปรไฟล์: '%s'\nจำนวนขั้นตอน: %d ขั้นตอน\n\nพร้อมกด Play เพื่อรันได้ทันที!", pName, count),
                Buttons = {
                    { Title = "เริ่มเล่นเลย", Callback = function() macro.Play() end },
                    { Title = "เรียบร้อย", Callback = function() end },
                },
            })
            Fluent:Notify({
                Title    = "Import Success",
                Content  = string.format("นำเข้า '%s' (%d ขั้นตอน) สำเร็จ!", pName, count),
                Duration = 4,
            })
        else
            Fluent:Notify({
                Title    = "Import Failed",
                Content  = tostring(pName),
                Duration = 4,
            })
        end
    end,
})

-- ────────────────────────────────────────────────────────────
-- ── 11. EVENT TAB (April Fool's Event Auto Play) ─────────────
-- ────────────────────────────────────────────────────────────
Tabs.Event:AddSection("⚡ EVENT LIVE STATUS")

local EventStatusCard = Tabs.Event:AddParagraph({
    Title   = "🎪 สถานะ April Fool's Event",
    Content = macro.eventStatusText,
})

local function updateEventStatus(txt)
    macro.eventStatusText = txt
    if EventStatusCard then
        EventStatusCard:SetDesc(txt .. "\nรอบที่พยายาม: " .. tostring(macro.eventAttempts) .. " | Captcha ล่าสุด: " .. tostring(macro.eventLastCaptcha))
    end
    print("[AA Event] " .. txt)
end

Tabs.Event:AddSection("🎮 EVENT CONTROLS")

local EventToggle = Tabs.Event:AddToggle("AutoPlayEventToggle", {
    Title   = "Auto Play April Fool's Event",
    Default = false,
    Description = "กดปุ่ม EventTeleport -> เดินเข้าประตู Event3 -> กด Find Match -> ออโต้แก้ Captcha & Submit",
})

EventToggle:OnChanged(function()
    macro.eventAutoPlay = Fluent.Options.AutoPlayEventToggle.Value
    if macro.eventAutoPlay then
        if isLobby then
            updateEventStatus("🟢 เริ่มต้นทำงาน Auto Play April Fool's Event")
        else
            updateEventStatus("⏸️ เปิดระบบไว้แล้ว แต่คุณอยู่ในห้องต่อสู้ (จะเริ่มทำงานอัตโนมัติเมื่อกลับสู่ Lobby)")
            Fluent:Notify({
                Title    = "April Fool's Event",
                Content  = "⏸️ อยู่ในห้องต่อสู้ ระบบจะรอทำงานเมื่อกลับสู่ Lobby อัตโนมัติ",
                Duration = 3.5,
            })
        end
    else
        updateEventStatus("⏹️ หยุดการทำงาน Auto Play")
    end
end)

Tabs.Event:AddSlider("EventIntervalSlider", {
    Title = "ระยะห่างการตรวจสอบ (วินาที)",
    Default = 3,
    Min = 1,
    Max = 10,
    Rounding = 1,
    Callback = function(val)
        macro.eventInterval = val
    end,
})

local function runEventSequence()
    if not isLobby then
        return false
    end

    macro.eventAttempts = macro.eventAttempts + 1

    local playerGui = plr:WaitForChild("PlayerGui", 10)
    if not playerGui then
        updateEventStatus("❌ ไม่พบ PlayerGui")
        return false
    end

    -- ขั้นตอนที่ 1: กดปุ่ม EventTeleport ใน LeftUI_test
    updateEventStatus("📍 [1/4] ตรวจสอบปุ่ม EventTeleport...")
    local leftUI = playerGui:FindFirstChild("LeftUI_test")
    local eventBtn = leftUI and leftUI:FindFirstChild("Buttons") and leftUI.Buttons:FindFirstChild("EventTeleport")

    if eventBtn then
        updateEventStatus("👉 [1/4] กดปุ่ม EventTeleport สำเร็จ")
        if firesignal then
            firesignal(eventBtn.Activated)
            pcall(function() firesignal(eventBtn.MouseButton1Click) end)
        end
        task.wait(1.5)
    else
        updateEventStatus("⚠️ [1/4] ไม่พบปุ่ม LeftUI_test.Buttons.EventTeleport (อาจอยู่ที่โซนแล้ว)")
    end

    -- ขั้นตอนที่ 2: เดินไปที่ประตู Event ด้วย WalkTo (ไม่ใช้วาร์ป CFrame เพื่อความปลอดภัย)
    updateEventStatus("🚶 [2/4] กำลังเดินไปยังประตู _lobbytemplate_event3.Door (WalkTo)...")
    local lobbies = workspace:FindFirstChild("_EVENT_CHALLENGES") and workspace._EVENT_CHALLENGES:FindFirstChild("Lobbies")
    local lobby3 = lobbies and lobbies:FindFirstChild("_lobbytemplate_event3")
    local door = lobby3 and lobby3:FindFirstChild("Door")

    local char = plr.Character or plr.CharacterAdded:Wait()
    local root = char and char:WaitForChild("HumanoidRootPart", 5)
    local hum  = char and (char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5))

    if not door or not root or not hum then
        updateEventStatus("❌ [2/4] ไม่พบประตู Event หรือ Humanoid")
        return false
    end

    -- พิกัดเป้าหมาย ปรับระดับ Y ให้ตรงกับเท้าผู้เล่นเพื่อไม่ให้วิ่งสะดุด
    local targetPos = Vector3.new(door.Position.X, root.Position.Y, door.Position.Z)
    local walkStart = tick()
    local walkTimeout = 25

    while (tick() - walkStart) < walkTimeout do
        if not root or not hum or not door then break end

        -- คำนวณระยะห่างระนาบ XZ
        local distXZ = Vector2.new(root.Position.X - door.Position.X, root.Position.Z - door.Position.Z).Magnitude

        -- ตรวจสอบว่าหน้าต่าง MatchmakingPrompt เด้งขึ้นมาแล้วหรือยัง
        local notif = playerGui:FindFirstChild("NotificationWindows")
        local popups = notif and notif:FindFirstChild("Popups")
        if popups and popups:FindFirstChild("MatchmakingPrompt") then
            updateEventStatus("🎯 [2/4] ตรวจพบหน้าต่าง MatchmakingPrompt แล้ว! หยุดเดิน")
            break
        end

        -- ถ้าเดินมาชนหรือชิดประตูแล้ว (ระยะ <= 3.5 studs)
        if distXZ <= 3.5 then
            updateEventStatus("🚪 [2/4] เดินถึงประตูแล้ว สัมผัสประตู...")
            if firetouchinterest then
                firetouchinterest(root, door, 0)
                task.wait(0.05)
                firetouchinterest(root, door, 1)
            end
            break
        end

        -- สั่งให้ Humanoid เดินไปยังตำแหน่งเป้าหมาย
        hum:MoveTo(targetPos)
        task.wait(0.15)
    end

    -- สัมผัสประตูซ้ำเพื่อความชัวร์ 100% ว่าเซิร์ฟเวอร์ตอบรับ
    if firetouchinterest and root and door then
        firetouchinterest(root, door, 0)
        task.wait(0.05)
        firetouchinterest(root, door, 1)
    end

    updateEventStatus("✨ [2/4] เข้าถึงประตูเรียบร้อย กำลังรอ MatchmakingPrompt...")
    task.wait(0.8)

    -- ขั้นตอนที่ 3: รอและกดปุ่ม Find Match
    local notif = playerGui:FindFirstChild("NotificationWindows")
    local popups = notif and notif:FindFirstChild("Popups")
    if not popups then
        updateEventStatus("❌ ไม่พบ NotificationWindows.Popups")
        return false
    end

    local prompt = popups:FindFirstChild("MatchmakingPrompt") or popups:WaitForChild("MatchmakingPrompt", 5)
    if prompt and prompt:FindFirstChild("Main") and prompt.Main:FindFirstChild("Buttons") then
        local matchBtn = prompt.Main.Buttons:FindFirstChild("Matchmaking")
        if matchBtn then
            updateEventStatus("🔍 [3/4] ตรวจพบปุ่ม 'Find Match' -> กำลังกดค้นหาห้อง...")
            task.wait(0.3)
            if firesignal then
                firesignal(matchBtn.Activated)
                pcall(function() firesignal(matchBtn.MouseButton1Click) end)
            end
        end
    else
        updateEventStatus("⚠️ [3/4] ไม่พบหน้าต่าง MatchmakingPrompt (อาจติดคิวอยู่แล้วหรือแก้ Captcha ไปแล้ว)")
    end

    task.wait(0.8)

    -- ขั้นตอนที่ 4: ตรวจสอบ Captcha และ Auto Fill + Submit
    local captchaWin = popups:FindFirstChild("CaptchaWindow") or popups:WaitForChild("CaptchaWindow", 3)
    if captchaWin then
        updateEventStatus("🧩 [4/4] ตรวจพบหน้าต่าง Captcha! กำลังดึงรหัส...")
        task.wait(0.2)

        local captchaLabel = captchaWin:FindFirstChild("Captcha")
        local typeBox = captchaWin:FindFirstChildWhichIsA("TextBox", true)
        local submitBtn = captchaWin:FindFirstChild("Yes", true) or (captchaWin:FindFirstChild("ButtonHolder") and captchaWin.ButtonHolder:FindFirstChild("Yes"))

        if captchaLabel and typeBox and submitBtn then
            local code = captchaLabel.Text
            macro.eventLastCaptcha = tostring(code)
            updateEventStatus("🔢 [4/4] ถอดรหัส Captcha ได้: '" .. tostring(code) .. "' -> กำลังพิมพ์ลงกล่องข้อความ...")

            typeBox.Text = tostring(code)
            task.wait(0.25)

            updateEventStatus("📩 [4/4] กำลังกดปุ่ม Submit...")
            if firesignal then
                firesignal(submitBtn.Activated)
                pcall(function() firesignal(submitBtn.MouseButton1Click) end)
            end

            updateEventStatus("🎉 [4/4] กด Submit เรียบร้อย! รอเซิร์ฟเวอร์ดึงเข้าเกม...")
            return true
        else
            updateEventStatus("❌ [4/4] องค์ประกอบใน CaptchaWindow ไม่ครบ")
        end
    else
        updateEventStatus("⚡ [4/4] ข้าม Captcha (ระบบจดจำสถานะ Captcha เดิม หรือไม่ต้องกรอก)")
        return true
    end

    return false
end

Tabs.Event:AddButton({
    Title = "⚡ ทดสอบยิงรอบเดียวทันที (Run Once)",
    Description = "รันขั้นตอนเทเลพอร์ต -> เข้าประตู -> Find Match -> Captcha หนึ่งรอบ (เฉพาะใน Lobby)",
    Callback = function()
        if not isLobby then
            Fluent:Notify({
                Title   = "April Fool's Event",
                Content = "⚠️ ฟังก์ชันนี้ทำงานได้เฉพาะใน Lobby เท่านั้น!",
                Duration = 3,
            })
            return
        end
        task.spawn(function()
            updateEventStatus("🚀 กำลังรันแบบ Manual ทันที...")
            runEventSequence()
        end)
    end,
})

task.spawn(function()
    while true do
        if isLobby and macro.eventAutoPlay then
            pcall(function()
                runEventSequence()
            end)
            task.wait(macro.eventInterval or 3)
        else
            task.wait(1.5)
        end
    end
end)

-- ────────────────────────────────────────────────────────────
-- ── 11.2. AI AUTOPLAY ENGINE (โหมดสุ่มตัวละคร / April Fool's)
-- ────────────────────────────────────────────────────────────
local function isPositionOccupied(targetPos, maxDist)
    maxDist = maxDist or 3.8
    local unitsFolder = workspace:FindFirstChild("_UNITS")
    if not unitsFolder then return false end
    for _, u in ipairs(unitsFolder:GetChildren()) do
        local stats = u:FindFirstChild("_stats")
        if stats and stats:FindFirstChild("player") and stats.player.Value == plr then
            local pos = nil
            pcall(function()
                local pPart = u.PrimaryPart or u:FindFirstChild("HumanoidRootPart")
                if pPart then
                    pos = pPart.Position
                elseif u:IsA("Model") then
                    pos = u:GetPivot().Position
                end
            end)
            if pos and (pos - targetPos).Magnitude < maxDist then
                return true
            end
        end
    end
    return false
end

macro.blacklistedSpots = macro.blacklistedSpots or {}

local function isSpotBlacklisted(targetPos, threshold)
    threshold = threshold or 3.2
    local now = tick()
    for i = #macro.blacklistedSpots, 1, -1 do
        local b = macro.blacklistedSpots[i]
        if now >= b.expires then
            table.remove(macro.blacklistedSpots, i)
        elseif (Vector2.new(b.pos.X, b.pos.Z) - Vector2.new(targetPos.X, targetPos.Z)).Magnitude < threshold then
            return true
        end
    end
    return false
end

local function getActiveMobPositions()
    local positions = {}
    local unitsFolder = workspace:FindFirstChild("_UNITS")
    if not unitsFolder then return positions end
    for _, u in ipairs(unitsFolder:GetChildren()) do
        local stats = u:FindFirstChild("_stats")
        -- ถ้าไม่ใช่ยูนิตของผู้เล่น แสดงว่าเป็นมอนสเตอร์ศัตรู
        if not (stats and stats:FindFirstChild("player") and stats.player.Value) then
            pcall(function()
                local pos = u:GetPivot().Position
                if pos.Y > 300 and pos.Y < 700 and pos.Magnitude < 15000 then
                    table.insert(positions, pos)
                end
            end)
        end
    end
    return positions
end

local function getMobProximityScore(spotPos, mobPositions)
    if #mobPositions == 0 then
        -- ถ้ายังไม่มีมอนเกิด ให้อิงจากต้นทางเดินมอนสเตอร์ (จุดเกิดตามแนว road)
        local road = workspace:FindFirstChild("_road")
        local firstNode = road and road:GetChildren()[1]
        if firstNode and firstNode:IsA("BasePart") then
            return (Vector2.new(spotPos.X, spotPos.Z) - Vector2.new(firstNode.Position.X, firstNode.Position.Z)).Magnitude
        end
        return 999
    end

    local minDist = 999999
    for _, mPos in ipairs(mobPositions) do
        local d = (Vector2.new(spotPos.X, spotPos.Z) - Vector2.new(mPos.X, mPos.Z)).Magnitude
        if d < minDist then
            minDist = d
        end
    end
    return minDist
end

local function getNearestRoadPart(pos)
    local road = workspace:FindFirstChild("_road")
    if not road then return nil end
    local nearestPart = nil
    local minDist = 999999
    for _, rp in ipairs(road:GetChildren()) do
        if rp:IsA("BasePart") then
            local d = (Vector2.new(rp.Position.X, rp.Position.Z) - Vector2.new(pos.X, pos.Z)).Magnitude
            if d < minDist then
                minDist = d
                nearestPart = rp
            end
        end
    end
    return nearestPart
end

function macro.GetEquippedUnits()
    local units = {}
    if not unitsFrame then return units end
    local allUnitsData = getUnitsData()

    for _, ch in ipairs(unitsFrame:GetChildren()) do
        if ch:IsA("ImageButton") and ch.Name ~= "GameSpellFrame" then
            local view = ch:FindFirstChild("Main") and ch.Main:FindFirstChild("View")
            local wm = view and view:FindFirstChild("WorldModel")
            local m = wm and wm:GetChildren()[1]
            local modelName = m and m.Name or nil

            if modelName and modelName ~= "unselected_unit" then
                local uuid = ch:GetAttribute("_equipped_frame_unit_uuid")
                if uuid and uuid ~= "" then
                    local unitId = modelName:gsub("_unit$", "")
                    local data = allUnitsData and (allUnitsData[unitId] or allUnitsData[modelName])

                    local costFrame = ch:FindFirstChild("Cost")
                    local costText = costFrame and costFrame:FindFirstChild("text") and costFrame.text.Text
                    local cost = tonumber((tostring(costText):gsub("[^%d]", ""))) or (data and data.cost or 0)

                    -- ตรวจสอบคุณสมบัติ hill_unit (ถ้าเป็น true คือตัววางบนอาคาร/สิ่งก่อสร้าง/Hill)
                    local isHill = (data and data.hill_unit == true) or false

                    -- ตรวจสอบยูนิตฟาร์มเงิน (Speedwagon / Bulma / farm_amount > 0)
                    local farmAmount = (data and tonumber(data.farm_amount)) or 0
                    local nameLower = (data and data.name or modelName):lower()
                    local isFarm = (farmAmount > 0) or nameLower:find("speedwagon") or nameLower:find("bulma") or nameLower:find("farm")

                    table.insert(units, {
                        slot          = ch.Name,
                        slotNum       = tonumber(ch.Name) or 99,
                        uuid          = uuid,
                        unitId        = unitId,
                        modelName     = modelName,
                        displayName   = data and data.name or modelName,
                        cost          = cost,
                        isHill        = isHill,
                        isFarm        = isFarm,
                        placementType = isHill and "HILL (บนสิ่งก่อสร้าง)" or (isFarm and "FARM (ตัวฟาร์มเงิน)" or "GROUND (วางพื้น)"),
                    })
                end
            end
        end
    end

    table.sort(units, function(a, b) return a.slotNum < b.slotNum end)
    return units
end

function macro.GetAvailableSpot(isHill, isFarm)
    local mobPositions = getActiveMobPositions()
    local candidates = {}

    if isHill then
        -- 1. ค้นหาจุดวาง HILL: วางบนสิ่งก่อสร้าง / หลังคา / อาคาร (workspace._terrain.hill)
        local hillFolder = workspace:FindFirstChild("_terrain") and workspace._terrain:FindFirstChild("hill")
        if hillFolder then
            for _, p in ipairs(hillFolder:GetChildren()) do
                if p:IsA("BasePart") then
                    local params = RaycastParams.new()
                    params.FilterType = Enum.RaycastFilterType.Include
                    params.FilterDescendantsInstances = { p }

                    local step = 3.6
                    local halfX = math.max(0, (p.Size.X / 2) - 1.8)
                    local halfZ = math.max(0, (p.Size.Z / 2) - 1.8)
                    local nearestRoad = getNearestRoadPart(p.Position)

                    for ox = -halfX, halfX, step do
                        for oz = -halfZ, halfZ, step do
                            local rayPos = (p.CFrame * CFrame.new(ox, 8, oz)).Position
                            local hit = workspace:Raycast(rayPos, Vector3.new(0, -18, 0), params)
                            if hit and hit.Instance and hit.Normal.Y > 0.72 then
                                local spotPos = hit.Position + Vector3.new(0, 0.05, 0)
                                if not isPositionOccupied(spotPos, 3.6) and not isSpotBlacklisted(spotPos) then
                                    local score = getMobProximityScore(spotPos, mobPositions)
                                    local lookTarget = nearestRoad and Vector3.new(nearestRoad.Position.X, spotPos.Y, nearestRoad.Position.Z) or (spotPos + p.CFrame.LookVector)
                                    local facingCF = ((lookTarget - spotPos).Magnitude > 0.5) and CFrame.lookAt(spotPos, lookTarget) or CFrame.new(spotPos)
                                    table.insert(candidates, {
                                        cf = facingCF,
                                        part = p,
                                        score = score,
                                        pos = spotPos,
                                        isHill = true,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    else
        -- 2. ค้นหาจุดวาง GROUND: วางบนพื้นดิน (workspace._terrain.ground)
        local groundFolder = workspace:FindFirstChild("_terrain") and workspace._terrain:FindFirstChild("ground")
        local road = workspace:FindFirstChild("_road")

        if groundFolder and road then
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Include
            params.FilterDescendantsInstances = { groundFolder }

            local roadParts = road:GetChildren()

            -- แยก Rings ตามบทบาทของยูนิต (Farm vs Combat DPS)
            -- ตัวเงินวางวงกว้าง (18-30 studs) ด้านหลัง/ขอบแมพ เพื่อเปิดทางให้ตัว DPS ยืนชิดขอบถนน
            local distRings = isFarm and { 18.0, 22.0, 26.0, 30.0 } or { 5.2, 7.8, 10.4, 13.0, 15.8 }
            local longitudinalOffsets = isFarm and { -5.0, 0, 5.0 } or { -3.5, 0, 3.5 }

            for i = 1, #roadParts do
                local rp = roadParts[i]
                if rp:IsA("BasePart") then
                    for _, side in ipairs({ -1, 1 }) do
                        for _, dist in ipairs(distRings) do
                            for _, longOff in ipairs(longitudinalOffsets) do
                                local sampleCF = rp.CFrame * CFrame.new(side * dist, 8, longOff)
                                local rayStart = sampleCF.Position
                                local hit = workspace:Raycast(rayStart, Vector3.new(0, -28, 0), params)

                                if hit and hit.Instance and hit.Normal.Y > 0.72 then
                                    local groundPos = hit.Position + Vector3.new(0, 0.05, 0)
                                    if not isPositionOccupied(groundPos, 3.6) and not isSpotBlacklisted(groundPos) then
                                        local mobDist = getMobProximityScore(groundPos, mobPositions)
                                        local score
                                        if isFarm then
                                            -- ตัวฟาร์ม: ชอบที่ห่างฝูงมอนสเตอร์ ไม่แย่งพื้นที่ตัวต่อสู้
                                            score = -mobDist + (dist * 0.8)
                                        else
                                            -- ตัวต่อสู้: ชอบที่ใกล้เส้นทางมอนสเตอร์และใกล้ขอบถนน
                                            score = mobDist + (dist * 1.5)
                                        end

                                        -- หันหน้ายูนิตเข้าหากลางถนน (LookAt Road Node)
                                        local lookTarget = Vector3.new(rp.Position.X, groundPos.Y, rp.Position.Z)
                                        local facingCF
                                        if (lookTarget - groundPos).Magnitude > 0.5 then
                                            facingCF = CFrame.lookAt(groundPos, lookTarget)
                                        else
                                            facingCF = CFrame.new(groundPos)
                                        end

                                        table.insert(candidates, {
                                            cf = facingCF,
                                            part = hit.Instance,
                                            score = score,
                                            pos = groundPos,
                                            isHill = false,
                                            dist = dist,
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- สำรอง: ค้นหาใน workspace._terrain.ground โดยตรงถ้าตามแนวถนนไม่มี
        if #candidates == 0 and groundFolder then
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Include
            params.FilterDescendantsInstances = { groundFolder }

            for _, gp in ipairs(groundFolder:GetChildren()) do
                if gp:IsA("BasePart") then
                    local sx = math.clamp(gp.Size.X * 0.3, 3, 15)
                    local sz = math.clamp(gp.Size.Z * 0.3, 3, 15)
                    local nearestRoad = getNearestRoadPart(gp.Position)

                    for _, off in ipairs({{0,0}, {sx, 0}, {-sx, 0}, {0, sz}, {0, -sz}, {sx, sz}, {-sx, -sz}}) do
                        local rayPos = (gp.CFrame * CFrame.new(off[1], 8, off[2])).Position
                        local hit = workspace:Raycast(rayPos, Vector3.new(0, -28, 0), params)
                        if hit and hit.Instance and hit.Normal.Y > 0.72 then
                            local spotPos = hit.Position + Vector3.new(0, 0.05, 0)
                            if not isPositionOccupied(spotPos, 3.6) and not isSpotBlacklisted(spotPos) then
                                local score = getMobProximityScore(spotPos, mobPositions)
                                local lookTarget = nearestRoad and Vector3.new(nearestRoad.Position.X, spotPos.Y, nearestRoad.Position.Z) or (spotPos + gp.CFrame.LookVector)
                                local facingCF = ((lookTarget - spotPos).Magnitude > 0.5) and CFrame.lookAt(spotPos, lookTarget) or CFrame.new(spotPos)
                                table.insert(candidates, {
                                    cf = facingCF,
                                    part = gp,
                                    score = score,
                                    pos = spotPos,
                                    isHill = false,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    if #candidates > 0 then
        -- เรียงลำดับตามคะแนนความเหมาะสม (คะแนนต่ำสุด = ดีที่สุด)
        table.sort(candidates, function(a, b) return a.score < b.score end)
        return candidates[1].cf, candidates[1].part, candidates[1].score, candidates
    end

    return nil, nil, nil, {}
end

macro.failedUnitPlacements = macro.failedUnitPlacements or {}

macro.unitBuffRecords = macro.unitBuffRecords or {
    merge = {},       -- [unitKey] = true
    random_buff = {}, -- [unitKey] = true
}

local function getUnitKey(u)
    if not u then return nil end
    local attr = u:GetAttribute("_SPAWN_UNIT_UUID")
    if attr then return "attr_" .. tostring(attr) end
    local stats = u:FindFirstChild("_stats")
    local uid = stats and stats:FindFirstChild("uuid") and stats.uuid.Value
    if uid and uid ~= "" then return "uuid_" .. tostring(uid) end
    return "inst_" .. tostring(u:GetDebugId(0))
end

local function getLivePlayerUnits()
    local list = {}
    local unitsFolder = workspace:FindFirstChild("_UNITS")
    if not unitsFolder then return list end

    for _, u in ipairs(unitsFolder:GetChildren()) do
        local stats = u:FindFirstChild("_stats")
        if stats and stats:FindFirstChild("player") and stats.player.Value == plr then
            local dmgObj = stats:FindFirstChild("damage")
            local farmObj = stats:FindFirstChild("farm_amount")
            local dmg = (dmgObj and tonumber(dmgObj.Value)) or 0
            local farmAmt = (farmObj and tonumber(farmObj.Value)) or 0
            local isFarm = (farmAmt > 0)
            local uKey = getUnitKey(u)

            table.insert(list, {
                model   = u,
                name    = u.Name,
                key     = uKey,
                damage  = dmg,
                isFarm  = isFarm,
            })
        end
    end
    return list
end

macro.autoHandleSpells = macro.autoHandleSpells ~= false

function macro.HandleInGameSpells()
    if isLobby or not unitsFrame or macro.autoHandleSpells == false then return 0 end

    local playerUnits = getLivePlayerUnits()

    -- ล้างประวัติยูนิตที่หายไปหรือตายแล้วออกจากตารางเก็บบัพ
    local liveKeys = {}
    for _, item in ipairs(playerUnits) do
        liveKeys[item.key] = true
    end
    for k in pairs(macro.unitBuffRecords.merge) do
        if not liveKeys[k] then macro.unitBuffRecords.merge[k] = nil end
    end
    for k in pairs(macro.unitBuffRecords.random_buff) do
        if not liveKeys[k] then macro.unitBuffRecords.random_buff[k] = nil end
    end

    local currentActive = getActiveUnitsCount()
    local maxLimit = tonumber(macro.aiMaxUnits) or 20

    -- ถ้าวางครบ 20 ตัวแล้ว ให้กดกากบาท (X) ลบการ์ดตัวละครออกจากช่อง เพื่อหาการ์ด Spell ทันที!
    if currentActive >= maxLimit and macro.autoDiscardUnitsWhenMax ~= false then
        for _, ch in ipairs(unitsFrame:GetChildren()) do
            if ch:IsA("ImageButton") then
                local isSpell = (ch:FindFirstChild("SpellName") ~= nil) or (ch.Name == "GameSpellFrame")
                local unitUuid = ch:GetAttribute("_equipped_frame_unit_uuid")
                local isUnitCard = (not isSpell) and (unitUuid ~= nil or tonumber(ch.Name) ~= nil)

                if isUnitCard then
                    local slotKey = (tonumber(ch.Name) and tostring(ch.Name)) or (ch.LayoutOrder and tostring(ch.LayoutOrder)) or tostring(ch.Name)
                    local delBtn = ch:FindFirstChild("Delete")
                    local deleted = false

                    if delBtn and delBtn.Visible and firesignal then
                        pcall(function()
                            firesignal(delBtn.Activated)
                            pcall(function() firesignal(delBtn.MouseButton1Click) end)
                        end)
                        deleted = true
                    end

                    if deleteTempUnitRemote then
                        pcall(function()
                            deleteTempUnitRemote:InvokeServer(slotKey)
                        end)
                        deleted = true
                    end

                    if deleted then
                        actionsDone = actionsDone + 1
                        Fluent:Notify({
                            Title    = "🗑️ Clear Hand Unit (20/20)",
                            Content  = string.format("ลบตัวละครออกจากช่อง %s เพื่อเปิดทางหา Spell!", slotKey),
                            Duration = 2.0,
                        })
                    end
                end
            end
        end
    end

    local gold = getGold()
    local actionsDone = 0

    for _, ch in ipairs(unitsFrame:GetChildren()) do
        if ch:IsA("ImageButton") then
            local sn = ch:FindFirstChild("SpellName")
            local spellName = sn and sn.Text or ""
            local spellLower = spellName:lower()
            local delBtn = ch:FindFirstChild("Delete")

            -- ถ้าไม่มี SpellName แต่เป็น GameSpellFrame ให้เช็คข้อความใน DescriptionFrame
            if spellName == "" and ch.Name == "GameSpellFrame" then
                local descLabel = ch:FindFirstChild("DescriptionFrame", true)
                if descLabel and descLabel:IsA("TextLabel") then
                    spellLower = descLabel.Text:lower()
                end
            end

            local isSpell = (sn ~= nil) or (ch.Name == "GameSpellFrame")
            if isSpell and (spellName ~= "" or spellLower ~= "") then
                local slotKey = (ch.LayoutOrder and ch.LayoutOrder > 0 and tostring(ch.LayoutOrder)) or (tonumber(ch.Name) and tostring(ch.Name)) or tostring(ch.Name)

                local function discardSpell(reason)
                    local deleted = false
                    if delBtn and delBtn.Visible and firesignal then
                        pcall(function()
                            firesignal(delBtn.Activated)
                            pcall(function() firesignal(delBtn.MouseButton1Click) end)
                        end)
                        deleted = true
                    end
                    if deleteSpellRemote then
                        pcall(function()
                            deleteSpellRemote:InvokeServer(slotKey)
                        end)
                        deleted = true
                    end
                    if deleted then
                        actionsDone = actionsDone + 1
                        Fluent:Notify({
                            Title    = "🗑️ Auto Discard Spell",
                            Content  = string.format("ทิ้งการ์ด %s [ช่อง %s]\nเหตุผล: %s", spellName ~= "" and spellName or "Spell", slotKey, reason or "ไม่จำเป็น"),
                            Duration = 2.5,
                        })
                    end
                    return deleted
                end

                -- 1. บัพ Refund: กดทิ้งทันทีเสมอ
                if spellLower:find("refund") then
                    if macro.autoDeleteRefund ~= false then
                        discardSpell("เก็บบัพ Refund ไว้เปลืองช่อง")
                    end

                -- 2. บัพ Merge:
                -- กฎ: ใส่ให้ทีละตัวจนครบทุกตัว ถ้าครบแล้วหรือไม่มีตัวให้ใส่ ➔ กดทิ้งทันที
                -- Merge กับ Random Buff ทับกันได้!
                elseif spellLower:find("merge") or spellLower:find("sacrifice") then
                    local eligibleList = {}
                    for _, uItem in ipairs(playerUnits) do
                        local hasMerge = macro.unitBuffRecords.merge[uItem.key]
                        -- ตัวไหนยังไม่ได้ Merge ก็มีสิทธิ์รับได้ แม้จะมี Random Buff แล้วก็ตาม (ทับกันได้)
                        if not hasMerge then
                            table.insert(eligibleList, uItem)
                        end
                    end

                    if #eligibleList == 0 then
                        -- ยูนิตทุกตัวในสนามได้รับบัพ Merge ครบหมดแล้ว ➔ กดทิ้งทันที!
                        discardSpell("ยูนิตทุกตัวในสนามได้รับบัพ Merge ครบหมดแล้ว")
                    else
                        -- เรียงลำดับ: ให้ตัวดาเมจก่อนตัวเงิน -> ดาเมจสูงสุดก่อน
                        table.sort(eligibleList, function(a, b)
                            if a.isFarm ~= b.isFarm then
                                return not a.isFarm
                            end
                            return a.damage > b.damage
                        end)

                        local target = eligibleList[1]
                        if gold >= 1000 then
                            if useSpellRemote then
                                local ok = pcall(function()
                                    useSpellRemote:InvokeServer(slotKey, target.model)
                                end)
                                if ok then
                                    macro.unitBuffRecords.merge[target.key] = true
                                    actionsDone = actionsDone + 1
                                    Fluent:Notify({
                                        Title    = "🔮 Used Spell: Merge",
                                        Content  = string.format("ใส่ Merge ให้ %s (DPS: %.0f) [ช่อง %s]\nตัวที่ยังไม่มี Merge เหลือ: %d ตัว", target.name, target.damage, slotKey, #eligibleList - 1),
                                        Duration = 3,
                                    })
                                    macro.aiStatusText = string.format("🔮 ใส่ Merge ให้ %s", target.name)
                                end
                            end
                        else
                            macro.aiStatusText = string.format("⏳ รอเงิน 1,000 ¥ ใส่ Merge ให้ %s (มี %d ¥)", target.name, gold)
                        end
                    end

                -- 3. บัพ Random Buff:
                -- กฎ: ใส่ให้ทีละตัวจนครบทุกตัว ถ้าครบแล้ว ➔ กดทิ้งทันที
                -- Merge กับ Random Buff ทับกันได้!
                elseif spellLower:find("random buff") or spellLower:find("random_buff") then
                    local eligibleList = {}
                    for _, uItem in ipairs(playerUnits) do
                        local hasRandBuff = macro.unitBuffRecords.random_buff[uItem.key]
                        -- ตัวไหนยังไม่ได้ Random Buff ก็มีสิทธิ์รับได้ แม้จะมี Merge แล้วก็ตาม (ทับกันได้)
                        if not hasRandBuff then
                            table.insert(eligibleList, uItem)
                        end
                    end

                    if #eligibleList == 0 then
                        -- ยูนิตทุกตัวในสนามได้รับ Random Buff ครบหมดแล้ว ➔ กดทิ้งทันที!
                        discardSpell("ยูนิตทุกตัวในสนามได้รับ Random Buff ครบหมดแล้ว")
                    else
                        -- เรียงลำดับ: ให้ตัวดาเมจก่อนตัวเงิน -> ดาเมจสูงสุดก่อน
                        table.sort(eligibleList, function(a, b)
                            if a.isFarm ~= b.isFarm then
                                return not a.isFarm
                            end
                            return a.damage > b.damage
                        end)

                        local target = eligibleList[1]
                        if gold >= 1000 then
                            if useSpellRemote then
                                local ok = pcall(function()
                                    useSpellRemote:InvokeServer(slotKey, target.model)
                                end)
                                if ok then
                                    macro.unitBuffRecords.random_buff[target.key] = true
                                    actionsDone = actionsDone + 1
                                    Fluent:Notify({
                                        Title    = "✨ Used Spell: Random Buff",
                                        Content  = string.format("ใส่ Random Buff ให้ %s (DPS: %.0f) [ช่อง %s]\nตัวที่ยังไม่มี Random Buff เหลือ: %d ตัว", target.name, target.damage, slotKey, #eligibleList - 1),
                                        Duration = 3,
                                    })
                                    macro.aiStatusText = string.format("✨ ใส่ Random Buff ให้ %s", target.name)
                                end
                            end
                        else
                            macro.aiStatusText = string.format("⏳ รอเงิน 1,000 ¥ ใส่ Random Buff ให้ %s (มี %d ¥)", target.name, gold)
                        end
                    end

                -- 4. บัพ Clone:
                -- กฎ: ให้ Clone ตัวที่ดาเมจสูงที่สุดเสมอ! (ไม่โคลนตัวฟาร์มเงิน)
                elseif spellLower:find("clone") then
                    local combatUnits = {}
                    for _, uItem in ipairs(playerUnits) do
                        if not uItem.isFarm and uItem.damage > 0 then
                            table.insert(combatUnits, uItem)
                        end
                    end

                    if #combatUnits > 0 then
                        table.sort(combatUnits, function(a, b)
                            return a.damage > b.damage
                        end)

                        local bestTarget = combatUnits[1]
                        if gold >= 5000 then
                            if useSpellRemote then
                                local ok = pcall(function()
                                    useSpellRemote:InvokeServer(slotKey, bestTarget.model)
                                end)
                                if ok then
                                    actionsDone = actionsDone + 1
                                    Fluent:Notify({
                                        Title    = "👥 Used Spell: Clone",
                                        Content  = string.format("โคลนยูนิตที่ดาเมจสูงสุด: %s\nดาเมจปัจจุบัน: %.0f", bestTarget.name, bestTarget.damage),
                                        Duration = 3.5,
                                    })
                                    macro.aiStatusText = string.format("👥 โคลนตัวดาเมจสูงสุด %s (%.0f dmg)", bestTarget.name, bestTarget.damage)
                                end
                            end
                        else
                            macro.aiStatusText = string.format("⏳ รอเงิน 5,000 ¥ โคลน %s (มี %d ¥)", bestTarget.name, gold)
                        end
                    end

                -- 5. บัพ Astral Gate:
                -- ค่าร่าย 2,500 ¥ (Instant)
                elseif spellLower:find("gate") or spellLower:find("astral gate") then
                    if gold >= 2500 then
                        if useSpellRemote then
                            pcall(function()
                                useSpellRemote:InvokeServer(slotKey)
                            end)
                            actionsDone = actionsDone + 1
                            Fluent:Notify({
                                Title    = "🌌 Used Spell: Astral Gate",
                                Content  = "เปิดใช้งาน Astral Gate สำเร็จ!",
                                Duration = 3,
                            })
                        end
                    end

                -- 6. บัพ Astral Summon:
                -- ค่าร่าย 10,000 ¥ (Instant)
                elseif spellLower:find("summon") or spellLower:find("astral summon") then
                    if gold >= 10000 then
                        if useSpellRemote then
                            pcall(function()
                                useSpellRemote:InvokeServer(slotKey)
                            end)
                            actionsDone = actionsDone + 1
                            Fluent:Notify({
                                Title    = "🌟 Used Spell: Astral Summon",
                                Content  = "อัญเชิญยูนิตสุ่มระดับสูงลงช่องสำเร็จ!",
                                Duration = 3.5,
                            })
                        end
                    end
                end
            end
        end
    end

    return actionsDone
end

function macro.HandleRefundSpells()
    return macro.HandleInGameSpells()
end

function macro.RunAIPlacementStep()
    if isLobby or not spawnRemote then return false end

    -- ลบบัพ Refund ออกอัตโนมัติก่อนวาง
    if macro.autoDeleteRefund then
        pcall(function() macro.HandleRefundSpells() end)
    end

    local currentActive = getActiveUnitsCount()
    local maxLimit = tonumber(macro.aiMaxUnits) or 20
    if currentActive >= maxLimit then
        macro.aiStatusText = string.format("✅ วางครบโควตาแล้ว (%d/%d ตัว)", currentActive, maxLimit)
        return false
    end

    local gold = getGold()
    local units = macro.GetEquippedUnits()
    if #units == 0 then
        macro.aiStatusText = "⚠️ ยังตรวจไม่พบยูนิตในช่องวาง"
        return false
    end

    -- คัดกรองยูนิตที่เงินพอ และยังไม่เคยเฟลครบ 3 ครั้ง
    local eligibleUnits = {}
    for _, u in ipairs(units) do
        local failCount = macro.failedUnitPlacements[u.uuid] or 0
        local uCost = tonumber(u.cost) or 0
        if failCount < 3 and gold >= uCost and u.uuid then
            table.insert(eligibleUnits, u)
        end
    end

    if #eligibleUnits == 0 then
        -- ตรวจสอบว่ามียูนิตที่ถูกข้ามเพราะเฟลครบ 3 ครั้งหรือไม่
        local allSkipped = true
        for _, u in ipairs(units) do
            local failCount = macro.failedUnitPlacements[u.uuid] or 0
            if failCount < 3 then
                allSkipped = false
                break
            end
        end

        if allSkipped and #units > 0 then
            macro.aiStatusText = "⏭️ ยูนิตในมือวางไม่ผ่านครบ 3 ครั้งทุกตัว (ข้ามไปรอเงิน/บัพ)"
            return false
        end

        local minCost = 999999
        for _, u in ipairs(units) do
            local failCount = macro.failedUnitPlacements[u.uuid] or 0
            if failCount < 3 then
                local uc = tonumber(u.cost) or 0
                if uc > 0 and uc < minCost then minCost = uc end
            end
        end
        macro.aiStatusText = string.format("⏳ รอเงิน... (มี %d ¥ │ ขั้นต่ำ %d ¥)", gold, minCost ~= 999999 and minCost or 0)
        return false
    end

    -- เรียงลำดับความสำคัญของยูนิต:
    -- 1. ตัวฟาร์มเงิน (isFarm == true) มาก่อนเสมอถ้าเงินพอ!
    -- 2. จำนวนครั้งที่เคยเฟลน้อยกว่ามาก่อน (failCount น้อยสุด)
    -- 3. ราคาถูกกว่ามาก่อน
    table.sort(eligibleUnits, function(a, b)
        if a.isFarm ~= b.isFarm then
            return a.isFarm == true
        end
        local fa = macro.failedUnitPlacements[a.uuid] or 0
        local fb = macro.failedUnitPlacements[b.uuid] or 0
        if fa ~= fb then
            return fa < fb
        end
        return (tonumber(a.cost) or 0) < (tonumber(b.cost) or 0)
    end)

    local targetUnit = eligibleUnits[1]

    -- ค้นหาพิกัดตามประเภท Ground หรือ Hill โดยส่ง isFarm เข้าไปแยกโซน
    local bestCF, bestPart, bestScore, candidates = macro.GetAvailableSpot(targetUnit.isHill, targetUnit.isFarm)
    if not bestCF or #candidates == 0 then
        macro.failedUnitPlacements[targetUnit.uuid] = (macro.failedUnitPlacements[targetUnit.uuid] or 0) + 1
        local currentFails = macro.failedUnitPlacements[targetUnit.uuid]
        if currentFails >= 3 then
            macro.aiStatusText = string.format("⏭️ ไม่พบจุดวาง %s ครบ 3 ครั้ง ➔ ข้ามไปตัวถัดไป", targetUnit.displayName)
            Fluent:Notify({
                Title    = "⚠️ Skip Unit (3/3 Fails)",
                Content  = string.format("ไม่พบจุดวาง %s ครบ 3 ครั้ง\nข้ามไปวางตัวละครตัวถัดไปในมือทันที!", targetUnit.displayName),
                Duration = 3,
            })
        else
            macro.aiStatusText = string.format("⚠️ ไม่พบจุดว่างสำหรับ %s (%d/3 ครั้ง)", targetUnit.displayName, currentFails)
        end
        return false
    end

    -- กลยุทธ์ Micro-Spiral Retries แบบ Hub Scripts:
    -- ลอง Candidate สูงสุด 3 จุดแรก
    -- แต่ละจุดลองขยับ Micro-Offset เผื่อติดขอบชนเล็กน้อย (0, +1.8X, -1.8X, +1.8Z, -1.8Z)
    local microOffsets = {
        Vector3.new(0, 0, 0),
        Vector3.new(1.8, 0, 0),
        Vector3.new(-1.8, 0, 0),
        Vector3.new(0, 0, 1.8),
        Vector3.new(0, 0, -1.8),
    }

    local maxCandidatesToTry = math.min(3, #candidates)
    local placedSuccessfully = false
    local placedCF = nil
    local placedPart = nil

    local currentAttempt = (macro.failedUnitPlacements[targetUnit.uuid] or 0) + 1
    macro.aiStatusText = string.format("🚀 กำลังวาง %s [%s] บน %s (ครั้งที่ %d/3)",
        targetUnit.displayName,
        targetUnit.isHill and "HILL" or (targetUnit.isFarm and "FARM" or "GROUND"),
        bestPart and bestPart.Name or "Spot",
        currentAttempt
    )

    local prevActiveCount = getActiveUnitsCount()

    for candIdx = 1, maxCandidatesToTry do
        local cand = candidates[candIdx]
        for _, mOff in ipairs(microOffsets) do
            local testPos = cand.pos + mOff
            if not isPositionOccupied(testPos, 3.4) and not isSpotBlacklisted(testPos, 2.5) then
                local testCF = cand.cf + mOff

                pcall(function()
                    spawnRemote:InvokeServer(targetUnit.uuid, testCF)
                end)

                -- Fast confirmation check (0.6s)
                local checkStart = tick()
                while (tick() - checkStart) < 0.6 do
                    if getActiveUnitsCount() > prevActiveCount or findLivePlayerUnit(testCF.Position, targetUnit.displayName, 5) then
                        placedSuccessfully = true
                        placedCF = testCF
                        placedPart = cand.part
                        break
                    end
                    task.wait(0.08)
                end

                if placedSuccessfully then break end
            end
        end

        if placedSuccessfully then break end

        -- ถ้า Candidate นี้วางไม่ได้ ให้ blacklist จุดนี้ไว้ชั่วคราว
        macro.blacklistedSpots = macro.blacklistedSpots or {}
        table.insert(macro.blacklistedSpots, {
            pos = cand.pos,
            expires = tick() + 30
        })
    end

    if placedSuccessfully then
        macro.failedUnitPlacements[targetUnit.uuid] = nil
        Fluent:Notify({
            Title    = "🤖 AI Placed Unit",
            Content  = string.format("วาง %s (%s)\nตำแหน่ง: %s\nค่าตัว: %d ¥",
                targetUnit.displayName,
                targetUnit.isHill and "บนสิ่งก่อสร้าง 🏢" or (targetUnit.isFarm and "โซนฟาร์มเงิน 💰" or "บนพื้น 🌿"),
                placedPart and placedPart.Name or "Ground",
                targetUnit.cost),
            Duration = 3,
        })
        macro.aiStatusText = string.format("✅ วาง %s สำเร็จ!", targetUnit.displayName)
        return true
    else
        -- ถ้าลองทั้ง 3 Candidate + Micro offsets แล้วยังวางไม่ผ่าน ให้นับเฟล 1 ครั้ง
        macro.failedUnitPlacements[targetUnit.uuid] = (macro.failedUnitPlacements[targetUnit.uuid] or 0) + 1
        local fails = macro.failedUnitPlacements[targetUnit.uuid]

        if fails >= 3 then
            macro.aiStatusText = string.format("⏭️ ข้าม %s (วางไม่ผ่าน 3 ครั้ง ➔ ข้ามไปตัวถัดไป)", targetUnit.displayName)
            Fluent:Notify({
                Title    = "⚠️ Skip Unit (3/3 Fails)",
                Content  = string.format("วาง %s ไม่ผ่านครบ 3 ครั้ง!\nระบบข้ามไปวางยูนิตตัวถัดไปในมือทันที", targetUnit.displayName),
                Duration = 3.5,
            })
        else
            macro.aiStatusText = string.format("⚠️ วาง %s ไม่ผ่าน (%d/3 ครั้ง) กำลังลองรอบหน้า...", targetUnit.displayName, fails)
        end
        return false
    end
end

function macro.UpgradeFarmUnits()
    if isLobby or not upgradeRemote or not macro.aiAutoUpgrade then return 0 end

    local gold = getGold()
    if gold <= 0 then return 0 end

    local unitsFolder = workspace:FindFirstChild("_UNITS")
    if not unitsFolder then return 0 end

    local allUnitsData = getUnitsData()
    local farmUnits = {}

    for _, u in ipairs(unitsFolder:GetChildren()) do
        local stats = u:FindFirstChild("_stats")
        if stats and stats:FindFirstChild("player") and stats.player.Value == plr then
            local upgObj = stats:FindFirstChild("upgrade")
            local maxUpgObj = stats:FindFirstChild("max_upgrade")
            local curLvl = upgObj and tonumber(upgObj.Value) or 0
            local maxLvl = maxUpgObj and tonumber(maxUpgObj.Value) or 0

            if curLvl < maxLvl then
                local farmVal = stats:FindFirstChild("farm_amount")
                local farmAmount = (farmVal and tonumber(farmVal.Value)) or 0
                local cleanId = u.Name:gsub("_unit$", "")
                local uData = allUnitsData and (allUnitsData[u.Name] or allUnitsData[cleanId])

                if farmAmount == 0 and uData and uData.farm_amount and tonumber(uData.farm_amount) then
                    farmAmount = tonumber(uData.farm_amount)
                end

                local nameLower = u.Name:lower()
                local isFarm = (farmAmount > 0) or nameLower:find("speedwagon") or nameLower:find("bulma") or nameLower:find("farm")

                if isFarm then
                    local nextCost = getUnitUpgradeCostFromData(cleanId, curLvl + 1)
                        or getUnitUpgradeCostFromData(u.Name, curLvl + 1)
                        or 1000

                    table.insert(farmUnits, {
                        model       = u,
                        name        = u.Name,
                        displayName = (uData and uData.name) or u.Name,
                        curLvl      = curLvl,
                        maxLvl      = maxLvl,
                        nextCost    = nextCost,
                        farmAmount  = farmAmount,
                    })
                end
            end
        end
    end

    if #farmUnits == 0 then return 0 end

    -- ลำดับการอัปเกรดตัวฟาร์มเงิน: เลเวลต่ำสุดก่อน -> ราคาถูกสุดก่อน
    table.sort(farmUnits, function(a, b)
        if a.curLvl == b.curLvl then
            return a.nextCost < b.nextCost
        end
        return a.curLvl < b.curLvl
    end)

    local totalUpgrades = 0
    -- ทำการ Burst Upgrade ตัวฟาร์มเงินทันทีจนกว่าจะเต็ม Max Level หรือเงินหมด
    for _, farm in ipairs(farmUnits) do
        local currentLvl = farm.curLvl
        while currentLvl < farm.maxLvl do
            gold = getGold()
            local cleanId = farm.name:gsub("_unit$", "")
            local cost = getUnitUpgradeCostFromData(cleanId, currentLvl + 1)
                or getUnitUpgradeCostFromData(farm.name, currentLvl + 1)
                or farm.nextCost

            if gold < cost then
                macro.aiStatusText = string.format("⏳ รอเงินอัปเกรดยูนิตฟาร์มเงิน %s [Lv.%d ➔ %d/%d] (มี %d ¥ │ ขาด %d ¥)",
                    farm.displayName, currentLvl, currentLvl + 1, farm.maxLvl, gold, cost - gold)
                break
            end

            local okInvoke = pcall(function()
                return upgradeRemote:InvokeServer(farm.model)
            end)

            task.wait(0.08)

            local stats = farm.model:FindFirstChild("_stats")
            local newLvl = stats and stats:FindFirstChild("upgrade") and tonumber(stats.upgrade.Value) or currentLvl
            if newLvl > currentLvl then
                currentLvl = newLvl
                totalUpgrades = totalUpgrades + 1
                Fluent:Notify({
                    Title    = "💰 AI Auto Upgraded [ตัวฟาร์มเงิน]",
                    Content  = string.format("อัปเกรด %s ขึ้น Lv.%d/%d\nค่าอัปเกรด: %d ¥",
                        farm.displayName, currentLvl, farm.maxLvl, cost),
                    Duration = 2.5,
                })
                macro.aiStatusText = string.format("💰 อัปเกรดตัวฟาร์มเงิน %s [Lv.%d/%d]", farm.displayName, currentLvl, farm.maxLvl)
            else
                break
            end
        end
    end

    return totalUpgrades
end

function macro.RunAIUpgradeStep(burstLimit)
    if isLobby or not upgradeRemote or not macro.aiAutoUpgrade then return 0 end

    local maxBurst = tonumber(burstLimit) or 5
    local gold = getGold()
    if gold <= 0 then return 0 end

    local unitsFolder = workspace:FindFirstChild("_UNITS")
    if not unitsFolder then return 0 end

    local allUnitsData = getUnitsData()
    local burstDone = 0

    while burstDone < maxBurst do
        gold = getGold()
        if gold < 300 then break end

        local combatUpgradable = {}

        for _, u in ipairs(unitsFolder:GetChildren()) do
            local stats = u:FindFirstChild("_stats")
            if stats and stats:FindFirstChild("player") and stats.player.Value == plr then
                local upgObj = stats:FindFirstChild("upgrade")
                local maxUpgObj = stats:FindFirstChild("max_upgrade")
                local curLvl = upgObj and tonumber(upgObj.Value) or 0
                local maxLvl = maxUpgObj and tonumber(maxUpgObj.Value) or 0

                if curLvl < maxLvl then
                    local farmVal = stats:FindFirstChild("farm_amount")
                    local farmAmount = (farmVal and tonumber(farmVal.Value)) or 0
                    local cleanId = u.Name:gsub("_unit$", "")
                    local uData = allUnitsData and (allUnitsData[u.Name] or allUnitsData[cleanId])

                    if farmAmount == 0 and uData and uData.farm_amount and tonumber(uData.farm_amount) then
                        farmAmount = tonumber(uData.farm_amount)
                    end

                    local nameLower = u.Name:lower()
                    local isFarm = (farmAmount > 0) or nameLower:find("speedwagon") or nameLower:find("bulma") or nameLower:find("farm")

                    -- เน้นอัปเกรดยูนิตดาเมจต่อสู้ (เพราะตัวฟาร์มเงินถูกจัดการแยกโดย UpgradeFarmUnits แล้ว)
                    if not isFarm then
                        local nextCost = getUnitUpgradeCostFromData(cleanId, curLvl + 1)
                            or getUnitUpgradeCostFromData(u.Name, curLvl + 1)
                            or 500

                        local displayName = (uData and uData.name) or u.Name
                        if gold >= nextCost then
                            table.insert(combatUpgradable, {
                                model       = u,
                                name        = u.Name,
                                displayName = displayName,
                                curLvl      = curLvl,
                                maxLvl      = maxLvl,
                                nextCost    = nextCost,
                            })
                        end
                    end
                end
            end
        end

        if #combatUpgradable == 0 then
            break
        end

        -- เรียงลำดับ: เลเวลต่ำสุดก่อน -> ราคาถูกสุดก่อน เพื่อกระจายดาเมจให้ทั่วถึงและคุ้มเงินที่สุด
        table.sort(combatUpgradable, function(a, b)
            if a.curLvl == b.curLvl then
                return a.nextCost < b.nextCost
            end
            return a.curLvl < b.curLvl
        end)

        local target = combatUpgradable[1]
        local beforeLvl = target.curLvl
        local okInvoke = pcall(function()
            return upgradeRemote:InvokeServer(target.model)
        end)

        task.wait(0.08)

        local stats = target.model:FindFirstChild("_stats")
        local newLvl = stats and stats:FindFirstChild("upgrade") and tonumber(stats.upgrade.Value) or beforeLvl
        if newLvl > beforeLvl then
            burstDone = burstDone + 1
            Fluent:Notify({
                Title    = "⚡ AI Auto Upgraded [ดาเมจ]",
                Content  = string.format("อัปเกรด %s ขึ้น Lv.%d/%d\nค่าอัปเกรด: %d ¥",
                    target.displayName, newLvl, target.maxLvl, target.nextCost),
                Duration = 2,
            })
            macro.aiStatusText = string.format("⚡ อัปเกรดยูนิต %s [Lv.%d ➔ %d/%d]", target.displayName, beforeLvl, newLvl, target.maxLvl)
        else
            break
        end
    end

    return burstDone
end

Tabs.Event:AddSection("🤖 AI AUTOPLAY (โหมดสุ่มตัวละคร / MAP)")

local AIStatusCard = Tabs.Event:AddParagraph({
    Title   = "🤖 AI AUTOPLAY LIVE STATUS",
    Content = "กำลังเริ่มต้นระบบ...",
})

local function updateAIStatus()
    if not AIStatusCard then return end
    local gold = getGold()
    local active = getActiveUnitsCount()
    local maxLimit = tonumber(macro.aiMaxUnits) or 20
    local units = macro.GetEquippedUnits()
    local unitListStr = {}
    for _, u in ipairs(units) do
        table.insert(unitListStr, string.format("• [ช่อง %s] %s: %s (%d ¥)", u.slot, u.displayName, u.isHill and "HILL 🏢" or (u.isFarm and "FARM 💰" or "GROUND 🌿"), u.cost))
    end
    local unitSummary = #unitListStr > 0 and table.concat(unitListStr, "\n") or "ไม่มีข้อมูลยูนิตในมือ"

    local upgradableCount = 0
    local farmUpgradableCount = 0
    local unitsFolder = workspace:FindFirstChild("_UNITS")
    if unitsFolder then
        for _, u in ipairs(unitsFolder:GetChildren()) do
            local stats = u:FindFirstChild("_stats")
            if stats and stats:FindFirstChild("player") and stats.player.Value == plr then
                local upgObj = stats:FindFirstChild("upgrade")
                local maxUpgObj = stats:FindFirstChild("max_upgrade")
                if upgObj and maxUpgObj and upgObj.Value < maxUpgObj.Value then
                    upgradableCount = upgradableCount + 1
                    local farmVal = stats:FindFirstChild("farm_amount")
                    local farmAmount = (farmVal and tonumber(farmVal.Value)) or 0
                    if farmAmount > 0 then
                        farmUpgradableCount = farmUpgradableCount + 1
                    end
                end
            end
        end
    end

    local phaseText = ""
    if active < maxLimit then
        phaseText = string.format("🏗️ วางตัวละครให้ครบก่อน (%d/%d ตัว) [งดอัปเกรด]", active, maxLimit)
    elseif farmUpgradableCount > 0 then
        phaseText = string.format("💰 อัปเกรดยูนิตฟาร์มเงินก่อน (เหลือ %d ตัว)", farmUpgradableCount)
    elseif upgradableCount > 0 then
        phaseText = string.format("⚡ อัปเกรดยูนิตดาเมจทั่วไป (เหลือ %d ตัว)", upgradableCount)
    else
        phaseText = "🌟 ยูนิตทุกตัวอัปเกรดเต็ม Max Level แล้ว"
    end

    AIStatusCard:SetDesc(string.format("• สถานะ AI      : %s\n• ลำดับการทำงาน : %s\n• จำนวนที่วาง    : %d / %d ตัว (Max 20)\n• ตัวรออัปเกรด   : ⚡ %d ตัว (ตัวเงิน 💰 %d ตัว)\n• Auto Upgrade   : %s\n• เงินปัจจุบัน   : 💰 %d ¥\n• ยูนิตในมือ :\n%s",
        macro.aiStatusText or "Standby",
        phaseText,
        active, maxLimit,
        upgradableCount, farmUpgradableCount,
        macro.aiAutoUpgrade and "🟢 ON" or "🔴 OFF",
        gold, unitSummary
    ))
end

local AIAutoplayToggle = Tabs.Event:AddToggle("AIAutoplayToggle", {
    Title       = "เปิดใช้งาน AI Autoplay (วางตัวละครอัตโนมัติ)",
    Description = "ตรวจจับยูนิตในมือ -> แยกแยะ Ground vs Hill -> เล็งวางบริเวณที่มีมอนสเตอร์อัตโนมัติ",
    Default     = macro.aiAutoplay,
})

AIAutoplayToggle:OnChanged(function()
    macro.aiAutoplay = Fluent.Options.AIAutoplayToggle.Value
    macro.SaveSettings()
    if macro.aiAutoplay then
        macro.aiStatusText = "🟢 เริ่มทำงาน AI Autoplay"
    else
        macro.aiStatusText = "⏹️ ปิดการทำงาน AI Autoplay"
    end
    updateAIStatus()
    Fluent:Notify({
        Title   = "AI Autoplay",
        Content = macro.aiAutoplay and "🟢 เปิดใช้งาน AI Autoplay แล้ว!" or "🔴 ปิดใช้งาน AI Autoplay",
        Duration = 3,
    })
end)

local AIAutoUpgradeToggle = Tabs.Event:AddToggle("AIAutoUpgradeToggle", {
    Title       = "เปิดใช้งาน AI Auto Upgrade (อัปเกรดยูนิตทุกตัว)",
    Description = "ตรวจจับยูนิตทั้งหมดที่วางในสนาม -> ทำการอัปเกรดยูนิตทุกตัวให้อัตโนมัติทันทีที่เงินพอจนเต็ม Max Level",
    Default     = macro.aiAutoUpgrade ~= false,
})

AIAutoUpgradeToggle:OnChanged(function()
    macro.aiAutoUpgrade = Fluent.Options.AIAutoUpgradeToggle.Value
    macro.SaveSettings()
    updateAIStatus()
    Fluent:Notify({
        Title   = "AI Auto Upgrade",
        Content = macro.aiAutoUpgrade and "🟢 เปิดใช้งาน Auto Upgrade แล้ว!" or "🔴 ปิดใช้งาน Auto Upgrade",
        Duration = 3,
    })
end)

Tabs.Event:AddSlider("AIMaxUnitsSlider", {
    Title       = "จำกัดจำนวนยูนิตสูงสุดที่วาง (Max Units)",
    Description = "รองรับการวางสูงสุดถึง 20 ตัวละครตามที่กำหนด",
    Default     = tonumber(macro.aiMaxUnits) or 20,
    Min         = 1,
    Max         = 20,
    Rounding    = 1,
    Callback    = function(val)
        macro.aiMaxUnits = tonumber(val) or 20
        macro.SaveSettings()
        updateAIStatus()
    end,
})

Tabs.Event:AddButton({
    Title       = "⚡ สแกนยูนิตในมือ (Scan Hand Units)",
    Description = "ตรวจสอบยูนิตที่เกมสุ่มมาให้ พร้อมระบุประเภท Ground หรือ Hill และราคา",
    Callback    = function()
        local units = macro.GetEquippedUnits()
        if #units == 0 then
            Fluent:Notify({ Title = "Scan Units", Content = "⚠️ ไม่พบยูนิตในช่องวางตัวละคร", Duration = 3 })
            return
        end
        local list = {}
        for _, u in ipairs(units) do
            table.insert(list, string.format("ช่อง %s: %s\n  ➔ ประเภท: %s\n  ➔ ค่าตัว: %d ¥", u.slot, u.displayName, u.placementType, u.cost))
        end
        Window:Dialog({
            Title   = "📋 ผลการสแกนยูนิตในมือ",
            Content = table.concat(list, "\n\n"),
            Buttons = {
                { Title = "ยอดเยี่ยม", Callback = function() end }
            }
        })
    end,
})

Tabs.Event:AddButton({
    Title       = "🎯 วางตัวละคร AI ทันที (Force Place 1 Unit)",
    Description = "สั่งให้ AI ตรวจสอบเงินและวางตัวละครที่เงินพอลงจุดที่ถูกต้องทันที 1 ตัว",
    Callback    = function()
        task.spawn(function()
            local success = macro.RunAIPlacementStep()
            updateAIStatus()
            if not success then
                Fluent:Notify({
                    Title    = "AI Place Result",
                    Content  = macro.aiStatusText or "วางไม่สำเร็จ",
                    Duration = 3,
                })
            end
        end)
    end,
})

Tabs.Event:AddButton({
    Title       = "⚡ อัปเกรดยูนิต AI ทันที (Force Burst Upgrade)",
    Description = "สั่งให้ AI อัปเกรดยูนิตฟาร์มเงินทันที และ Burst อัปเกรดยูนิตดาเมจ 5 เลเวลรวด",
    Callback    = function()
        task.spawn(function()
            local farmDone = macro.UpgradeFarmUnits()
            local combatDone = macro.RunAIUpgradeStep(5)
            updateAIStatus()
            if farmDone == 0 and combatDone == 0 then
                Fluent:Notify({
                    Title    = "AI Upgrade Result",
                    Content  = macro.aiStatusText or "เงินไม่พอหรือยูนิตทุกตัวตันแล้ว",
                    Duration = 3,
                })
            else
                Fluent:Notify({
                    Title    = "AI Upgrade Result",
                    Content  = string.format("อัปเกรดสำเร็จ! (ตัวเงิน %d ครั้ง │ ตัวดาเมจ %d ครั้ง)", farmDone, combatDone),
                    Duration = 3,
                })
            end
        end)
    end,
})

local AutoHandleSpellsToggle = Tabs.Event:AddToggle("AutoHandleSpellsToggle", {
    Title       = "จัดการสเปลและบัพอัตโนมัติ (Auto Handle Spells)",
    Description = "Merge ทีละตัวจนครบ (ทับกับ Random Buff ได้) / Clone ตัวดาเมจสูงสุด / ลบยูนิตเมื่อครบ 20 ตัวเพื่อหา Spell",
    Default     = macro.autoHandleSpells ~= false,
})

AutoHandleSpellsToggle:OnChanged(function()
    macro.autoHandleSpells = Fluent.Options.AutoHandleSpellsToggle.Value
    macro.SaveSettings()
    updateAIStatus()
    Fluent:Notify({
        Title   = "Auto Handle Spells",
        Content = macro.autoHandleSpells and "🟢 เปิดใช้งานจัดการ Spells อัตโนมัติ" or "🔴 ปิดใช้งานจัดการ Spells",
        Duration = 3,
    })
end)

local AutoDiscardUnitsToggle = Tabs.Event:AddToggle("AutoDiscardUnitsToggle", {
    Title       = "ลบยูนิตในมือเมื่อครบ 20 ตัวเพื่อหา Spell (Clear Hand for Spells)",
    Description = "เมื่อวางครบ 20 ตัวแล้ว จะกดกากบาท (X) ลบตัวละครออกจากช่องมือเพื่อเปิดทางให้การ์ด Spell เกิด",
    Default     = macro.autoDiscardUnitsWhenMax ~= false,
})

AutoDiscardUnitsToggle:OnChanged(function()
    macro.autoDiscardUnitsWhenMax = Fluent.Options.AutoDiscardUnitsToggle.Value
    macro.SaveSettings()
    updateAIStatus()
    Fluent:Notify({
        Title   = "Auto Clear Hand Units",
        Content = macro.autoDiscardUnitsWhenMax and "🟢 เปิดใช้งานลบยูนิตในมือเมื่อครบ 20 ตัว" or "🔴 ปิดใช้งานลบยูนิตในมือ",
        Duration = 3,
    })
end)

Tabs.Event:AddButton({
    Title       = "🔮 จัดการสเปลทันที (Force Handle Spells Now)",
    Description = "สั่งให้ AI ใช้งาน Merge / Clone / Random Buff หรือกดทิ้งใบที่ไม่จำเป็นทันที",
    Callback    = function()
        local count = macro.HandleInGameSpells()
        Fluent:Notify({
            Title   = "Spells Result",
            Content = count > 0 and string.format("ดำเนินการจัดการสเปลเรียบร้อย (%d รายการ)", count) or "ไม่พบสเปลที่ดำเนินการได้ในขณะนี้",
            Duration = 2.5,
        })
    end,
})

Tabs.Event:AddButton({
    Title       = "🗑️ เคลียร์ยูนิตในมือทันที (Force Clear Hand Units)",
    Description = "กดกากบาท (X) ลบการ์ดตัวละครทั้งหมดออกจากช่องมือทันที เพื่อหาการ์ด Spell",
    Callback    = function()
        local cleared = 0
        for _, ch in ipairs(unitsFrame:GetChildren()) do
            if ch:IsA("ImageButton") then
                local isSpell = (ch:FindFirstChild("SpellName") ~= nil) or (ch.Name == "GameSpellFrame")
                local unitUuid = ch:GetAttribute("_equipped_frame_unit_uuid")
                local isUnitCard = (not isSpell) and (unitUuid ~= nil or tonumber(ch.Name) ~= nil)
                if isUnitCard then
                    local slotKey = (tonumber(ch.Name) and tostring(ch.Name)) or (ch.LayoutOrder and tostring(ch.LayoutOrder)) or tostring(ch.Name)
                    local delBtn = ch:FindFirstChild("Delete")
                    if delBtn and delBtn.Visible and firesignal then
                        pcall(function()
                            firesignal(delBtn.Activated)
                            pcall(function() firesignal(delBtn.MouseButton1Click) end)
                        end)
                    end
                    if deleteTempUnitRemote then
                        pcall(function()
                            deleteTempUnitRemote:InvokeServer(slotKey)
                        end)
                    end
                    cleared = cleared + 1
                end
            end
        end
        Fluent:Notify({
            Title   = "Clear Hand Result",
            Content = cleared > 0 and string.format("ลบตัวละครออกจากมือ %d ช่องเรียบร้อย!", cleared) or "ไม่พบการ์ดตัวละครในมือ",
            Duration = 2.5,
        })
    end,
})

local AutoDeleteRefundToggle = Tabs.Event:AddToggle("AutoDeleteRefundToggle", {
    Title       = "ลบบัพ Refund อัตโนมัติ (Auto Delete Refund Spells)",
    Description = "เมื่อได้รับบัพ Refund จะกดปุ่มกากบาท (X) ลบทิ้งทันที เพื่อเปิดทางให้บัพอื่น",
    Default     = macro.autoDeleteRefund ~= false,
})

AutoDeleteRefundToggle:OnChanged(function()
    macro.autoDeleteRefund = Fluent.Options.AutoDeleteRefundToggle.Value
    macro.SaveSettings()
    updateAIStatus()
    Fluent:Notify({
        Title   = "Auto Delete Refund",
        Content = macro.autoDeleteRefund and "🟢 เปิดใช้งานลบบัพ Refund อัตโนมัติ" or "🔴 ปิดใช้งานลบบัพ Refund",
        Duration = 3,
    })
end)

Tabs.Event:AddButton({
    Title       = "🗑️ กดกากบาทลบบัพ Refund ทันที (Delete Refund Spells)",
    Description = "สแกนหาการ์ดบัพ Refund ในช่องแล้วกดปุ่มกากบาท (X) ลบทิ้งทันที",
    Callback    = function()
        local count = macro.HandleRefundSpells()
        if count == 0 then
            Fluent:Notify({ Title = "Delete Refund", Content = "ไม่พบบัพ Refund ในช่อง", Duration = 2.5 })
        end
    end,
})

-- AI Background Worker Loop
task.spawn(function()
    while true do
        if not isLobby then
            pcall(function()
                -- 1. จัดการ Spells & Buffs (Merge / Clone / Random Buff / ทิ้งยูนิตเมื่อครบ 20 ตัว)
                if macro.autoHandleSpells ~= false or macro.autoDeleteRefund then
                    macro.HandleInGameSpells()
                end

                -- 2. กฎเหล็ก: อัปเกรดยูนิตฟาร์มเงิน (Speedwagon / Bulma) ให้ตันก่อนเสมอทุกรอบที่มีเงิน!
                if macro.aiAutoUpgrade then
                    macro.UpgradeFarmUnits()
                end

                -- 3. ตรวจสอบการวางยูนิต และอัปเกรดยูนิตต่อสู้
                if macro.aiAutoplay or macro.aiAutoUpgrade then
                    local currentActive = getActiveUnitsCount()
                    local maxLimit = tonumber(macro.aiMaxUnits) or 20

                    if macro.aiAutoplay and currentActive < maxLimit then
                        -- พยายามวางตัวละครให้ครบโควตา 20 ตัว
                        local placed = macro.RunAIPlacementStep()
                        -- ถ้ารอบนี้วางไม่ได้ (เช่น รอคูลดาวน์จุด, ยูนิตในมือไม่มี, หรือติดสเปล)
                        -- และเงินเหลือเกิน 1,200 ¥ ให้อัปเกรดยูนิตดาเมจช่วยป้องกันฐานทันที อย่าปล่อยให้เงินค้างจนฐานแตก!
                        if not placed and macro.aiAutoUpgrade and getGold() >= 1200 then
                            macro.RunAIUpgradeStep(3)
                        end
                    elseif macro.aiAutoUpgrade then
                        -- วางครบ 20 ตัวแล้ว: Burst Upgrade อัปเกรดยูนิตดาเมจรวดเร็ว สูงสุด 10 เลเวลต่อรอบ
                        macro.RunAIUpgradeStep(10)
                    end
                    updateAIStatus()
                end
            end)
            task.wait(macro.aiInterval or 1.0)
        else
            task.wait(1.0)
        end
    end
end)

-- ────────────────────────────────────────────────────────────
-- ── 12. BATTLEFIELD TAB (Live Game Telemetry) ───────────────
-- ────────────────────────────────────────────────────────────
Tabs.Battlefield:AddSection("🌊 LIVE BATTLEFIELD TELEMETRY")

local DashResourceCard = Tabs.Battlefield:AddParagraph({
    Title   = "🌊 BATTLEFIELD STATUS",
    Content = "กำลังอ่านข้อมูลแมตช์...",
})

-- ────────────────────────────────────────────────────────────
-- ── 12. WEBHOOK TAB (Discord Notification System) ───────────
-- ────────────────────────────────────────────────────────────
Tabs.Webhook:AddSection("📡 DISCORD WEBHOOK CONFIG")

Tabs.Webhook:AddInput("WebhookURLInput", {
    Title       = "Discord Webhook URL",
    Default     = macro.webhookUrl,
    Placeholder = "https://discord.com/api/webhooks/...",
    Numeric     = false,
    Finished    = true,
    Callback    = function(val)
        if val then
            macro.webhookUrl = val:gsub("%s+", "")
            macro.SaveWebhookConfig()
            Fluent:Notify({
                Title    = "Webhook URL",
                Content  = "บันทึก URL เรียบร้อยแล้ว",
                Duration = 2,
            })
        end
    end,
})

Tabs.Webhook:AddToggle("WebhookToggleEnabled", {
    Title       = "เปิดใช้งาน Webhook แจ้งเตือน",
    Description = "ส่งการแจ้งเตือนสถิติการเล่นไปยัง Discord Channel ของคุณ",
    Default     = macro.webhookEnabled,
    Callback    = function(val)
        macro.webhookEnabled = val
        macro.SaveWebhookConfig()
        Fluent:Notify({
            Title    = "Webhook",
            Content  = val and "🟢 เปิดใช้งาน Webhook แล้ว" or "🔴 ปิดใช้งาน Webhook",
            Duration = 2,
        })
    end,
})

Tabs.Webhook:AddToggle("WebhookToggleFinish", {
    Title       = "แจ้งเตือนเมื่อจบแมตช์ (Match Finished)",
    Description = "ส่งสรุปผลการเล่นทันทีเมื่อชนะ (Victory) หรือแพ้ (Defeat)",
    Default     = macro.webhookNotifyOnFinish,
    Callback    = function(val)
        macro.webhookNotifyOnFinish = val
        macro.SaveWebhookConfig()
    end,
})

Tabs.Webhook:AddToggle("WebhookToggleCensor", {
    Title       = "🔒 เซนเซอร์ชื่อผู้เล่น (Censor Username)",
    Description = "ซ่อนชื่อผู้เล่นบางส่วนใน Webhook (เช่น J***7) เพื่อความปลอดภัย",
    Default     = macro.webhookCensorUser,
    Callback    = function(val)
        macro.webhookCensorUser = val
        macro.SaveWebhookConfig()
    end,
})

Tabs.Webhook:AddSection("🧪 TEST & PREVIEW")

local WebhookStatusCard = Tabs.Webhook:AddParagraph({
    Title   = "สถานะ Webhook",
    Content = "กำลังตรวจสอบการเชื่อมต่อ...",
})

Tabs.Webhook:AddButton({
    Title       = "📡 ส่งข้อความทดสอบ (Test Webhook)",
    Description = "ทดลองส่งข้อมูลสถิติปัจจุบันไปยัง Discord ทันที",
    Callback    = function()
        if not macro.webhookUrl or macro.webhookUrl == "" then
            Fluent:Notify({
                Title    = "Webhook Error",
                Content  = "กรุณากรอก Discord Webhook URL ก่อนกดทดสอบ",
                Duration = 4,
            })
            return
        end
        macro.SendTestWebhook()
    end,
})

local WebhookPreviewCard = Tabs.Webhook:AddParagraph({
    Title   = "📊 ข้อมูลที่จะถูกส่งในรอบนี้ (Live Preview)",
    Content = "กำลังอ่านข้อมูลด่าน...",
})


-- ────────────────────────────────────────────────────────────
-- ── 13. ACTION LOG TAB ──────────────────────────────────────
-- ────────────────────────────────────────────────────────────
local LogPara = Tabs.Log:AddParagraph({
    Title   = "📋 Recorded Steps (0)",
    Content = "(ยังไม่มีรายการที่บันทึกไว้)",
})

local function refreshLogView()
    if #macro.macro == 0 then
        LogPara:SetTitle("📋 Recorded Steps (0)")
        LogPara:SetDesc("(ยังไม่มีรายการที่บันทึกไว้)")
        return
    end
    local lines = {}
    table.insert(lines, string.format("%-4s │ %-6s │ %-10s │ %-8s │ %-4s │ %s",
        "STEP", "ACTION", "UNIT", "WAVE", "TIME", "POSITION"))
    table.insert(lines, string.rep("─", 56))

    for i, v in ipairs(macro.macro) do
        local ps = v.position
            and string.format("(%.0f, %.0f, %.0f)", v.position.X, v.position.Y, v.position.Z)
            or "N/A"
        local actIcon = v.type == "spawn" and "SPAWN"
            or v.type == "sell" and "SELL"
            or (v.targetUpgrade and string.format("UPG:%d", v.targetUpgrade) or "UPG")
        local uName = tostring(v.unitName or "Unit"):sub(1, 10)
        local waveTxt = string.format("W%d+%ds", v.wave or 0, v.waveOffset or 0)
        table.insert(lines, string.format(
            "[%02d] │ %-6s │ %-10s │ %-8s │ %-3ds │ %s",
            i, actIcon, uName, waveTxt, v.timestamp, ps
        ))
    end
    LogPara:SetTitle(string.format("📋 Recorded Steps (%d)", #macro.macro))
    LogPara:SetDesc(table.concat(lines, "\n"))
end

Tabs.Log:AddButton({
    Title       = "🔄  รีเฟรชประวัติ (Refresh Log)",
    Description = "อัปเดตตารางแสดงรายการขั้นตอนทั้งหมด",
    Callback    = refreshLogView,
})

Tabs.Log:AddButton({
    Title       = "📋  คัดลอกประวัติ (Copy to Clipboard)",
    Description = "คัดลอกตารางขั้นตอนทั้งหมดลงคลิปบอร์ด",
    Callback    = function()
        if #macro.macro == 0 then
            Fluent:Notify({ Title = "Info", Content = "ไม่มีข้อมูลให้คัดลอก", Duration = 2 })
            return
        end
        local lines = {}
        for i, v in ipairs(macro.macro) do
            local ps = v.position and string.format("(%.0f, %.0f, %.0f)", v.position.X, v.position.Y, v.position.Z) or "N/A"
            table.insert(lines, string.format("[%02d] %s | %s | Wave: %d | Cost: %d | Time: %ds | Pos: %s",
                i, v.type:upper(), v.unitName or "Unit", v.wave, v.gold, v.timestamp, ps))
        end
        local fullText = table.concat(lines, "\n")
        if typeof(setclipboard) == "function" then
            setclipboard(fullText)
            Fluent:Notify({ Title = "Copied", Content = "คัดลอกรายการลงคลิปบอร์ดสำเร็จ!", Duration = 2 })
        end
    end,
})

-- ────────────────────────────────────────────────────────────
-- ── 14. DEBUG TAB ───────────────────────────────────────────
-- ────────────────────────────────────────────────────────────
local DebugPara = Tabs.Debug:AddParagraph({
    Title   = "🔍 Debug Telemetry",
    Content = "(กด Dump Slots เพื่อดูข้อมูล)",
})

Tabs.Debug:AddButton({
    Title       = "📋  Dump Slots (UUID ทุก Slot)",
    Description = "แสดง UUID และชื่อตัวละครใน spawn_units ทุก Slot",
    Callback    = function()
        local lines = {}
        for si = 1, 6 do
            local slot = unitsFrame:FindFirstChild(tostring(si))
            if slot then
                local uuid = slot:GetAttribute("_equipped_frame_unit_uuid")
                local name = getSlotUnitName(si)
                local cost = getSlotSpawnCost(si)
                table.insert(lines, string.format(
                    "Slot %d: name=%-12s uuid=%-30s cost=%d",
                    si, tostring(name), tostring(uuid), cost
                ))
            else
                table.insert(lines, "Slot " .. si .. ": (ไม่มี)")
            end
        end
        local txt = table.concat(lines, "\n")
        DebugPara:SetTitle("📋 Slot Dump")
        DebugPara:SetDesc(txt)
        Fluent:Notify({ Title = "Slot Dump", Content = "ดูผลใน Debug tab", Duration = 2 })
        if typeof(setclipboard) == "function" then setclipboard(txt) end
    end,
})

Tabs.Debug:AddButton({
    Title       = "📊  Dump Macro State",
    Description = "แสดงว่า macro มีกี่ entry และ recording/playing state เป็นอะไร",
    Callback    = function()
        local lines = {
            "recording: " .. tostring(macro.recording),
            "playing:   " .. tostring(macro.playing),
            "entries:   " .. tostring(#macro.macro),
            "playMode:  " .. tostring(macro.playMode),
            "hook:      " .. tostring(_G.__AAMacroHooked),
            "startTime: " .. tostring(macro.startTime),
            "",
        }
        for i, e in ipairs(macro.macro) do
            local pos = e.position and string.format("(%.0f,%.0f,%.0f)", e.position.X, e.position.Y, e.position.Z) or "nil"
            local cfOk = (e.args and typeof(e.args[2]) == "CFrame") and "YES" or "NO"
            table.insert(lines, string.format(
                "[%02d] %s | %s | slot=%s | uuid=%s | cf=%s | pos=%s",
                i, e.type, tostring(e.unitName):sub(1,12),
                tostring(e.slotIndex),
                tostring(e.unitId):sub(1,16),
                cfOk, pos
            ))
        end
        local txt = table.concat(lines, "\n")
        DebugPara:SetTitle("📊 Macro State (" .. #macro.macro .. " entries)")
        DebugPara:SetDesc(txt)
        if typeof(setclipboard) == "function" then setclipboard(txt) end
        Fluent:Notify({ Title = "State Dumped", Content = #macro.macro .. " entries | ดูใน Debug tab", Duration = 3 })
    end,
})

Tabs.Debug:AddButton({
    Title       = "🎯  Test Spawn Entry #1 (Force)",
    Description = "ยิง spawn entry แรกใน macro โดยตรง ไม่ผ่านการเช็คเงื่อนไข เพื่อทดสอบว่า remote ทำงานได้ไหม",
    Callback    = function()
        if #macro.macro == 0 then
            Fluent:Notify({ Title = "Error", Content = "ไม่มี macro entry กด Record แล้ววางตัวก่อน", Duration = 3 })
            return
        end
        local entry = nil
        for _, e in ipairs(macro.macro) do
            if e.type == "spawn" then entry = e; break end
        end
        if not entry then
            Fluent:Notify({ Title = "Error", Content = "ไม่มี spawn entry ในมาโคร", Duration = 3 })
            return
        end

        local liveUuid = findCurrentUuidForSpawn(entry)
        local cf = nil
        if entry.args and typeof(entry.args[2]) == "CFrame" then
            cf = entry.args[2]
        elseif entry.cframe then
            cf = CFrame.new(table.unpack(entry.cframe))
        elseif entry.position then
            cf = CFrame.new(entry.position)
        end

        Fluent:Notify({
            Title   = "🎯 Force Spawn Test",
            Content = string.format("UUID: %s\nCF: %s\nUnit: %s / Slot: %s",
                tostring(liveUuid):sub(1, 36),
                cf and tostring(cf.Position) or "nil",
                tostring(entry.unitName),
                tostring(entry.slotIndex)
            ),
            Duration = 6,
        })

        if not liveUuid then
            Fluent:Notify({ Title = "❌ UUID nil", Content = "ไม่มี UUID — ดูผล Dump Slots ว่า slot มี attribute ไหม", Duration = 5 })
            return
        end
        if not cf then
            Fluent:Notify({ Title = "❌ CFrame nil", Content = "ไม่มี CFrame ใน entry.args[2]", Duration = 5 })
            return
        end

        local ok, res = pcall(function()
            return spawnRemote:InvokeServer(liveUuid, cf)
        end)
        Fluent:Notify({
            Title   = ok and "✅ Invoke OK" or "❌ Invoke Error",
            Content = "Result: " .. tostring(res):sub(1, 100),
            Duration = 6,
        })
    end,
})

Tabs.Debug:AddButton({
    Title       = "🔬  Inspect spawnRemote",
    Description = "ดูว่า RS.endpoints.client_to_server.spawn_unit มีอยู่จริงไหม",
    Callback    = function()
        local ok, res = pcall(function()
            local r = RS.endpoints.client_to_server.spawn_unit
            return string.format("Class: %s | Name: %s | Parent: %s",
                r.ClassName, r.Name, tostring(r.Parent))
        end)
        Fluent:Notify({
            Title   = ok and "✅ Remote Found" or "❌ Remote Missing",
            Content = tostring(res):sub(1,120),
            Duration = 5,
        })
    end,
})

-- ── 15. SETTINGS TAB ────────────────────────────────────────
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
InterfaceManager:SetFolder("AA_Macro")
SaveManager:SetFolder("AA_Macro/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

-- ────────────────────────────────────────────────────────────
-- ── 16. REAL-TIME TELEMETRY & HUD UPDATE LOOP ───────────────
-- ────────────────────────────────────────────────────────────
task.spawn(function()
    while true do
        pcall(function()
            local isRec  = macro.recording
            local isPlay = macro.playing
            local stateStr = isRec  and "🔴 RECORDING"
                          or isPlay and ("⚡ EXECUTING [" .. macro.playMode .. "]")
                          or "⏹️ IDLE / STANDBY"

            local elapsed = 0
            if macro.startTime and (isRec or isPlay) then
                elapsed = math.floor(tick() - macro.startTime)
            end
            local elapsedStr = string.format("%02d:%02d", math.floor(elapsed / 60), elapsed % 60)

            local total = #macro.macro
            local current = isPlay and macro.currentStep or (isRec and total or 0)
            local pct = total > 0 and math.clamp(current / total, 0, 1) or 0
            local progBar = generateProgressBar(current, total, 16)

            local spawns = 0
            local upgrades = 0
            local sells = 0
            for _, e in ipairs(macro.macro) do
                if e.type == "spawn" then spawns = spawns + 1
                elseif e.type == "upgrade" then upgrades = upgrades + 1
                elseif e.type == "sell" then sells = sells + 1 end
            end

            local curWave = getWave()
            local activeUnits = getActiveUnitsCount()

            -- ── Macro Tab: Status Card ───────────────────────
            DashStatusCard:SetTitle(isRec and "🔴 RECORDING  •  ACTIVE"
                                or isPlay and ("⚡ EXECUTING  •  " .. macro.playMode)
                                or "⏹️ STANDBY")
            DashStatusCard:SetDesc(table.concat({
                string.format("• สถานะ      :  %s", stateStr),
                string.format("• เวลา        :  ⏱️ %s", elapsedStr),
                string.format("• โปรไฟล์    :  📁 %s", macro.currentProfileName or "Default_Macro"),
                string.format("• Auto Replay :  %s  (หน่วง %.1fs)", macro.autoReplay and "🟢 เปิด" or "🔴 ปิด", macro.replayDelay or 2.0),
            }, "\n"))

            -- ── Battlefield Tab: Resource Card ───────────────
            DashResourceCard:SetTitle(string.format("🌊 Wave %d  │  💰 %s ¥  │  🛡️ %d", curWave, moneyLabel.Text, activeUnits))
            DashResourceCard:SetDesc(table.concat({
                string.format("• ด่านปัจจุบัน   :  🌊 Wave %d", curWave),
                string.format("• ยอดเงินสด     :  💰 %s ¥", moneyLabel.Text),
                string.format("• ยูนิตในสนาม   :  🛡️ %d ตัวของผู้เล่น", activeUnits),
                string.format("• Unit Database  :  %s", UnitsData and "🟢 โหลดสำเร็จ (Realtime Costs)" or "🟡 ใช้ค่าสำรอง"),
                "",
                string.format("• สถานะมาโคร    :  %s", stateStr),
                string.format("• ความคืบหน้า   :  %s", progBar),
            }, "\n"))

            -- ── Macro Tab: Progress Card ─────────────────────
            DashProgressCard:SetTitle(string.format("📈 PROGRESSION  •  %d%%  (%d/%d)", math.floor(pct * 100), current, total))
            DashProgressCard:SetDesc(table.concat({
                string.format("%s", progBar),
                string.format("🎯 Spawn: %d  │  ⬆️ Upg: %d  │  💰 Sell: %d  │  📦 รวม: %d", spawns, upgrades, sells, total),
            }, "\n"))

            -- ── Macro Tab: Next Action Card ──────────────────
            local hudNextStr = "🎯 Next: รอคำสั่ง..."
            if isPlay and macro.currentStep > 0 and macro.currentStep <= total then
                local nextEntry = macro.macro[macro.currentStep]
                local actIcon = nextEntry.type == "spawn" and "🎯 SPAWN" or nextEntry.type == "sell" and "💰 SELL" or "⬆️ UPGRADE"
                local affordable = canAfford(nextEntry)
                local affStatus = nextEntry.type == "sell" and "🟢 ขายคืนเงิน — พร้อมทำงาน" or (affordable and "🟢 เงินพอ — พร้อมทำงาน" or "⏳ รอเงินสะสม...")
                local posStr = nextEntry.position and string.format("(%.0f, %.0f, %.0f)", nextEntry.position.X, nextEntry.position.Y, nextEntry.position.Z) or "N/A"
                local timingStr = macro.playMode == "Wave+Delay"
                    and string.format("Wave ≥ %d + %ds", nextEntry.wave or 0, nextEntry.waveOffset or 0)
                    or  string.format("T ≥ %ds", nextEntry.timestamp or 0)

                local unitInfo = tostring(nextEntry.unitName or "Unit")
                if nextEntry.type == "upgrade" and nextEntry.targetUpgrade then
                    unitInfo = string.format("%s (→ Lvl %d)", unitInfo, nextEntry.targetUpgrade)
                elseif nextEntry.type == "spawn" then
                    unitInfo = string.format("%s (Slot %s)", unitInfo, tostring(nextEntry.slotIndex or "-"))
                end

                DashNextActionCard:SetTitle(string.format("🎯 NEXT  [%d/%d]  %s", macro.currentStep, total, actIcon))
                DashNextActionCard:SetDesc(table.concat({
                    string.format("• Unit     :  %s", unitInfo),
                    string.format("• Position :  📍 %s", posStr),
                    string.format("• Trigger  :  ⏱️ %s", timingStr),
                    string.format("• Action   :  %s", affStatus),
                }, "\n"))

                hudNextStr = string.format("[%d/%d] %s: %s\n%s", macro.currentStep, total, actIcon, tostring(nextEntry.unitName or "Unit"):sub(1,14), affStatus)
            elseif isRec then
                DashNextActionCard:SetTitle("🔴 RECORDING")
                DashNextActionCard:SetDesc(string.format("ดักจับ Remote อยู่... บันทึกแล้ว %d คำสั่ง\nวางตัวละครหรืออัปเกรดได้เลย", total))
                hudNextStr = string.format("🔴 Recording: %d steps", total)
            else
                DashNextActionCard:SetTitle("💤 STANDBY")
                DashNextActionCard:SetDesc(total > 0
                    and string.format("✅ มาโครพร้อมทำงาน %d ขั้นตอน — กด Play เพื่อเริ่ม", total)
                    or "กด Record เพื่ออัดมาโคร หรือโหลดโปรไฟล์จาก PROFILES ด้านล่าง")
                hudNextStr = total > 0 and string.format("Ready (%d steps) — Press Play", total) or "Standing by..."
            end

            -- 5. อัปเดต Floating Cyberpunk HUD Overlay
            if macro.showHUD and hudGui.Enabled then
                hudStats.Text = string.format("🌊 Wave %d   │   💰 %s ¥   │   🛡️ %d", curWave, moneyLabel.Text, activeUnits)
                hudProgFill.Size = UDim2.new(pct, 0, 1, 0)
                hudProgText.Text = string.format("%d%% (%d/%d)", math.floor(pct * 100), current, total)
                hudNext.Text = hudNextStr

                if isRec then
                    hudBadge.Text = "REC"
                    hudBadge.BackgroundColor3 = Color3.fromRGB(220, 40, 50)
                    hudBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
                    hudStroke.Color = Color3.fromRGB(255, 60, 70)
                    hudProgFill.BackgroundColor3 = Color3.fromRGB(255, 60, 70)
                elseif isPlay then
                    hudBadge.Text = "PLAYING"
                    hudBadge.BackgroundColor3 = Color3.fromRGB(0, 170, 220)
                    hudBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
                    hudStroke.Color = Color3.fromRGB(0, 200, 255)
                    hudProgFill.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
                else
                    hudBadge.Text = "IDLE"
                    hudBadge.BackgroundColor3 = Color3.fromRGB(45, 52, 70)
                    hudBadge.TextColor3 = Color3.fromRGB(160, 175, 200)
                    hudStroke.Color = Color3.fromRGB(55, 65, 95)
                    hudProgFill.BackgroundColor3 = Color3.fromRGB(80, 95, 130)
                end
            end

            -- เช็ค Auto Replay & Webhook เมื่อจบเกม
            local resUI = plr.PlayerGui:FindFirstChild("ResultsUI")
            if resUI and resUI.Enabled then
                if macro.webhookEnabled and macro.webhookNotifyOnFinish and not macro._hasSentMatchWebhook then
                    macro._hasSentMatchWebhook = true
                    task.spawn(function()
                        task.wait(1.5)
                        macro.SendMatchWebhook()
                    end)
                end
                if macro.autoReplay and not macro._replaying then
                    macro.TriggerReplayVote()
                end
            end

            -- รีเซ็ตสถานะเมื่อเริ่มเกมใหม่ / ก่อนเข้าเวฟ
            if curWave == 0 then
                macro._hasAutoStarted = false
                macro._hasSentMatchWebhook = false
                macro._matchStartTime = nil
            else
                if not macro._matchStartTime then
                    macro._matchStartTime = tick()
                end
            end

            -- อัปเดตการ์ดสถานะ Webhook Live Preview
            pcall(function()
                if WebhookStatusCard and WebhookPreviewCard then
                    local statusTxt = string.format("• ระบบแจ้งเตือน :  %s\n• Webhook URL  :  %s\n• ผลส่งล่าสุด   :  %s",
                        macro.webhookEnabled and "🟢 เปิดใช้งาน (Active)" or "🔴 ปิดอยู่ (Disabled)",
                        (macro.webhookUrl and macro.webhookUrl ~= "") and "✅ ตั้งค่าแล้ว" or "⚠️ ยังไม่ได้ระบุ URL",
                        macro._lastWebhookStatus or "ยังไม่มีการส่ง"
                    )
                    WebhookStatusCard:SetDesc(statusTxt)

                    local d = macro.GetMatchData()
                    local prevTxt = string.format(
                        "• ผู้เล่น   :  👤 %s (Lvl %s)\n• ด่าน     :  🗺️ %s │ %s (%s)\n• เวฟ      :  🌊 Wave %s │ ⏱️ %s\n• ทรัพยากร :  💎 %s Gems │ ⭐ %s XP │ 💰 %s ¥\n• สถิติ    :  💥 %s DMG │ 💀 %s Kills",
                        d.displayName or d.name, tostring(d.level),
                        d.worldFriendly or d.locationName, d.levelName or "Standard", d.difficulty or "Normal",
                        tostring(d.wave), d.timeTaken or "00:00",
                        formatNumber(d.gems), formatNumber(d.xp), formatNumber(d.gold),
                        formatShort(d.damage), formatNumber(d.kills)
                    )
                    WebhookPreviewCard:SetDesc(prevTxt)
                end
            end)

            -- เช็ค Auto Vote Start เมื่อตรวจพบ VoteStart
            if macro.autoVoteStart then
                local vs = plr.PlayerGui:FindFirstChild("VoteStart")
                if vs and vs.Enabled then
                    if not macro._hasVotedStart then
                        macro._hasVotedStart = true
                        task.spawn(function()
                            macro.VoteGameStart()
                            Fluent:Notify({
                                Title    = "Auto Vote Start",
                                Content  = "⚡ กดโหวตเริ่มเกม (VoteStart Yes) ให้อัตโนมัติแล้ว!",
                                Duration = 3,
                            })
                        end)
                    end
                else
                    macro._hasVotedStart = false
                end
            end

            -- เช็ค Auto Play Macro เมื่อ Wave >= 1 (แยกออกมาต่างหาก ไม่รวมกับ Auto Start)
            if macro.autoPlayMacroOnMatch and not macro.playing and not macro.recording and #macro.macro > 0 then
                if curWave >= 1 and not macro._hasAutoStarted then
                    macro._hasAutoStarted = true
                    task.delay(1, function()
                        macro.Play()
                        Fluent:Notify({
                            Title   = "Auto Play Macro",
                            Content = "เริ่มเล่น Macro อัตโนมัติในด่านใหม่แล้ว!",
                            Duration = 3,
                        })
                    end)
                end
            end
        end)
        task.wait(0.35)
    end
end)

-- ── 9. VoteStart Event Listener (ตอบสนองเสี้ยววินาที) ──────────
task.spawn(function()
    local function hookVoteStart(vs)
        if not vs or not vs:IsA("ScreenGui") then return end
        vs:GetPropertyChangedSignal("Enabled"):Connect(function()
            if vs.Enabled and macro.autoVoteStart and not macro._hasVotedStart then
                macro._hasVotedStart = true
                task.delay(0.1, function()
                    macro.VoteGameStart()
                    Fluent:Notify({
                        Title    = "Auto Vote Start",
                        Content  = "⚡ โหวตเริ่มเกม (VoteStart Yes) ทันที!",
                        Duration = 3,
                    })
                end)
            elseif not vs.Enabled then
                macro._hasVotedStart = false
            end
        end)
    end

    local existingVS = plr.PlayerGui:FindFirstChild("VoteStart")
    if existingVS then hookVoteStart(existingVS) end

    plr.PlayerGui.ChildAdded:Connect(function(child)
        if child.Name == "VoteStart" then
            hookVoteStart(child)
            if child:IsA("ScreenGui") and child.Enabled and macro.autoVoteStart and not macro._hasVotedStart then
                macro._hasVotedStart = true
                task.delay(0.1, function()
                    macro.VoteGameStart()
                    Fluent:Notify({
                        Title    = "Auto Vote Start",
                        Content  = "⚡ โหวตเริ่มเกม (VoteStart Yes) ทันที!",
                        Duration = 3,
                    })
                end)
            end
        end
    end)
end)

-- ── Anti-AFK Worker ─────────────────────────────────────────
pcall(function()
    local vu = game:GetService("VirtualUser")
    plr.Idled:Connect(function()
        vu:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        vu:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        print("[AA Macro Anti-AFK] Prevented idle disconnect.")
    end)
end)

-- ── Finished Initialization ─────────────────────────────────
if isLobby then
    pcall(function() Tabs.Event:Select() end)
else
    pcall(function() Tabs.Macro:Select() end)
end

Fluent:Notify({
    Title    = "AA Macro Studio v2.0",
    Content  = isLobby and "🏠 โหมด Lobby (April Fool's Event พร้อมใช้งาน)"
        or string.format("💾 โหมด Combat | AutoVote: %s | AutoPlay: %s | AIAutoplay: %s",
            macro.autoVoteStart and "ON" or "OFF",
            macro.autoPlayMacroOnMatch and "ON" or "OFF",
            macro.aiAutoplay and "ON" or "OFF"
        ),
    Duration = 5,
})
