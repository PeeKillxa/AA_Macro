-- ============================================================
--  AA Macro Recorder & Command Center  |  by cook45 & clack
--  File: AA_Macro/main.lua
-- ============================================================

-- ── 0. Cleanup Previous Window ──────────────────────────────
if _G.AAMacroUI and typeof(_G.AAMacroUI.Destroy) == "function" then
    pcall(function() _G.AAMacroUI:Destroy() end)
    _G.AAMacroUI = nil
end
for _, ch in ipairs(game:GetService("CoreGui"):GetChildren()) do
    if ch:IsA("ScreenGui") and ch.Name == "ScreenGui" then
        pcall(function() ch:Destroy() end)
    end
end

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
local plr         = game:GetService("Players").LocalPlayer

local spawnRemote   = RS.endpoints.client_to_server.spawn_unit
local upgradeRemote = RS.endpoints.client_to_server.upgrade_unit_ingame
local moneyLabel    = plr.PlayerGui.spawn_units.Lives.Frame.Resource.Money.text
local unitsFrame    = plr.PlayerGui.spawn_units.Lives.Frame.Units

-- โหลดฐานข้อมูล Units ผ่าน Loader ของเกม เพื่อดึงราคา Upgrade จริงทุกเลเวล
local UnitsData = nil
pcall(function()
    local loader = require(RS.src.Loader)
    UnitsData = loader:load_data("Units")
end)

-- โฟลเดอร์จัดเก็บข้อมูล
if not isfolder("AA_Macro") then makefolder("AA_Macro") end
if not isfolder("AA_Macro/profiles") then makefolder("AA_Macro/profiles") end
if not isfolder("AA_Macro/configs") then makefolder("AA_Macro/configs") end

-- ── 3. Helper Functions ─────────────────────────────────────
-- คืนเงินปัจจุบัน
local function getGold()
    local ok, val = pcall(function()
        return tonumber((moneyLabel.Text:gsub("[^%d]", ""))) or 0
    end)
    return ok and val or 0
end

-- คืน wave ปัจจุบัน
local function getWave()
    local ok, val = pcall(function()
        return workspace._wave_num.Value
    end)
    return ok and val or 0
end

-- คืนราคา spawn ของ slot ที่กำหนด (slot 1-6)
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

-- หาชื่อตัวละครใน Slot (1-6) จาก WorldModel Viewport
local function getSlotUnitName(slotIndex)
    local ok, name = pcall(function()
        local slot = unitsFrame:FindFirstChild(tostring(slotIndex))
        local wm = slot.Main.View.WorldModel
        local ch = wm:GetChildren()[1]
        return ch and ch.Name or "Unit"
    end)
    return ok and name or "Unit"
end

-- หา slot index (1-6) จาก unit UUID ที่ equip อยู่
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

-- ค้นหา UUID จริงใน Slot ปัจจุบันที่พร้อมวาง (แก้ปัญหา UUID เปลี่ยนเมื่อสลับไอดี/ถอดใส่ตัวละครใหม่)
local function findCurrentUuidForSpawn(entry)
    if not entry then return nil end

    -- dump ทุก slot attr เพื่อ debug
    local slotDump = {}
    for si = 1, 6 do
        local slot = unitsFrame:FindFirstChild(tostring(si))
        if slot then
            local attrUuid = slot:GetAttribute("_equipped_frame_unit_uuid")
            local slotName = getSlotUnitName(si)
            slotDump[si] = string.format("Slot%d: uuid=%s name=%s", si, tostring(attrUuid), tostring(slotName))
        end
    end
    print("[UUID Dump] entry.unitName="..tostring(entry.unitName).." entry.slotIndex="..tostring(entry.slotIndex))
    for _, v in pairs(slotDump) do print("  " .. v) end

    -- 1. ตรวจสอบว่า UUID เดิมยัง equip อยู่ใน slot ไหนหรือไม่
    if entry.unitId then
        for si = 1, 6 do
            local slot = unitsFrame:FindFirstChild(tostring(si))
            if slot then
                local attrUuid = slot:GetAttribute("_equipped_frame_unit_uuid")
                if attrUuid and attrUuid == entry.unitId then
                    print("[UUID] matched by unitId at slot " .. si)
                    return attrUuid
                end
            end
        end
    end

    -- 2. ค้นหาจากชื่อตัวละคร (unitName) ใน Slot 1-6 ปัจจุบัน
    if entry.unitName and entry.unitName ~= "" and entry.unitName ~= "Unit" then
        local target = entry.unitName:lower()
        for si = 1, 6 do
            local name = getSlotUnitName(si)
            if name and (name:lower() == target or name:lower():find(target, 1, true) or target:find(name:lower(), 1, true)) then
                local slot = unitsFrame:FindFirstChild(tostring(si))
                local attrUuid = slot and slot:GetAttribute("_equipped_frame_unit_uuid")
                if attrUuid then
                    print("[UUID] matched by unitName '"..entry.unitName.."' at slot " .. si .. " → " .. attrUuid)
                    return attrUuid
                end
            end
        end
    end

    -- 3. ค้นหาจาก slotIndex เดิมที่เคยอัดไว้
    if entry.slotIndex then
        local slot = unitsFrame:FindFirstChild(tostring(entry.slotIndex))
        local attrUuid = slot and slot:GetAttribute("_equipped_frame_unit_uuid")
        if attrUuid then
            print("[UUID] fallback to slotIndex " .. entry.slotIndex .. " → " .. attrUuid)
            return attrUuid
        end
    end

    -- 4. ลองหาจาก _equipped_frame_unit_uuid ใน PlayerGui.spawn_units โดยตรง
    local ok5, uuid5 = pcall(function()
        local spawnGui = plr.PlayerGui:FindFirstChild("spawn_units")
        if not spawnGui then return nil end
        local livesFrame = spawnGui:FindFirstChild("Lives")
        local frameFrame = livesFrame and livesFrame:FindFirstChild("Frame")
        local unitsF = frameFrame and frameFrame:FindFirstChild("Units")
        if not unitsF then return nil end
        -- ลองทุก slot ใน GUI spawn_units อีกครั้งโดยใช้ path เต็ม
        for _, child in ipairs(unitsF:GetChildren()) do
            local attr = child:GetAttribute("_equipped_frame_unit_uuid")
            if attr then
                local slotName2 = pcall(function()
                    return child.Main.View.WorldModel:GetChildren()[1].Name
                end)
                print("[UUID alt] child=" .. child.Name .. " uuid=" .. tostring(attr))
            end
        end
        return nil
    end)

    -- 5. Last resort fallback
    warn("[UUID] ไม่พบ UUID สำหรับ " .. tostring(entry.unitName) .. " / slot " .. tostring(entry.slotIndex))
    return entry.unitId
end

-- จำนวนตัวละครของผู้เล่นที่อยู่ในสนามขณะนี้
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

-- หา Unit Model ใน workspace._UNITS ที่ผู้เล่นเป็นเจ้าของและอยู่ใกล้พิกัด targetPos
local function getLiveUnitByPosition(targetPos, maxDist)
    if not targetPos then return nil end
    maxDist = maxDist or 5
    local unitsFolder = workspace:FindFirstChild("_UNITS")
    if not unitsFolder then return nil end
    local closestUnit = nil
    local closestDist = maxDist
    for _, u in ipairs(unitsFolder:GetChildren()) do
        local stats = u:FindFirstChild("_stats")
        if stats and stats:FindFirstChild("player") and stats.player.Value == plr then
            local pPart = u.PrimaryPart or u:FindFirstChild("HumanoidRootPart")
            local pos = pPart and pPart.Position or u:GetPivot().Position
            local d = (pos - targetPos).Magnitude
            if d < closestDist then
                closestDist = d
                closestUnit = u
            end
        end
    end
    return closestUnit
end

-- อ่านราคา Upgrade ของตัวละครนั้นๆ จาก UnitOverview GUI โดยตรง
-- path: PlayerGui.UnitOverview.OuterOuter.Outer.ScrollingFrame -> child._unit_char_ref == liveUnit -> Outer.buttons.Upgrade.Main.Text
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

-- คำนวณราคา Upgrade จริง
-- 1. จาก UnitOverview GUI (ตรงกับ Unit ตัวนั้น realtime ผ่าน _unit_char_ref)
-- 2. จาก Units Data + Level ปัจจุบันของ Unit ในเกม
-- 3. จาก UnitUpgrade GUI ("Upgrade: 400¥") ถ้าเปิดอยู่
-- 4. Fallback ใช้ gold ที่ record ไว้
local function getUpgradeCost(entry)
    local liveUnit = entry and entry.position and getLiveUnitByPosition(entry.position, 6)

    -- 1. จาก UnitOverview GUI (แม่นยำที่สุด ไม่ต้องกดเปิดหน้า Upgrade)
    if liveUnit then
        local ovCost = getUpgradeCostFromOverview(liveUnit)
        if ovCost and ovCost > 0 then
            return ovCost
        end
    end

    -- 2. จาก Units Database ของเกม (Loader) เทียบกับ Level ปัจจุบันของ Unit
    if liveUnit then
        local stats = liveUnit:FindFirstChild("_stats")
        local uId = stats and stats:FindFirstChild("id") and stats.id.Value
        local curUpg = stats and stats:FindFirstChild("upgrade") and stats.upgrade.Value or 0
        if UnitsData and uId and UnitsData[uId] and UnitsData[uId].upgrade then
            local nextInfo = UnitsData[uId].upgrade[curUpg + 1]
            if nextInfo and nextInfo.cost then
                return nextInfo.cost
            end
        end
    end

    -- 3. เช็คจาก UnitUpgrade GUI ถ้าเปิดอยู่
    local ok, val = pcall(function()
        local txt = plr.PlayerGui.UnitUpgrade.Primary.Container.Main.Main.Buttons.Upgrade.Main.Text.Text
        return tonumber((txt:gsub("[^%d]", ""))) or 0
    end)
    if ok and val and val > 0 then return val end

    -- 4. Fallback
    return (entry and entry.gold) or 0
end

-- ตรวจสอบว่าเงินปัจจุบันพอสำหรับ entry หรือไม่
local function canAfford(entry)
    local gold = getGold()
    if entry.type == "spawn" then
        local slot = findSlotByUnitId(entry.unitId)
        local cost = slot and getSlotSpawnCost(slot) or 0
        if cost == 0 then
            cost = entry.gold or 0
        end
        return gold >= cost
    elseif entry.type == "upgrade" then
        local cost = getUpgradeCost(entry)
        return gold >= cost
    end
    return true
end

-- สร้าง Progress Bar สวยงาม
local function generateProgressBar(current, total, barLength)
    barLength = barLength or 16
    if total == 0 then
        return "[" .. string.rep("-", barLength) .. "] 0%"
    end
    local pct = math.clamp(current / total, 0, 1)
    local filled = math.floor(pct * barLength)
    local empty = barLength - filled
    return string.format("[%s%s] %.0f%%", string.rep("=", filled), string.rep("-", empty), pct * 100)
end

-- ── 4. Macro Core State ─────────────────────────────────────
if _G.AAMacro and _G.AAMacro._orig then
    local mtOld = getrawmetatable(game)
    setreadonly(mtOld, false)
    mtOld.__namecall = _G.AAMacro._orig
    setreadonly(mtOld, true)
end

local savedMacro   = _G.AAMacro and _G.AAMacro.macro or {}
local savedProfile = _G.AAMacro and _G.AAMacro.currentProfileName or "Unsaved"
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
    autoStartOnMatch   = false,
    _replaying         = false,
    _hasAutoStarted    = false,
    _hasVotedStart     = false,
    currentProfileName = savedProfile,
    -- ── Webhook Configuration ───────────────────
    webhookUrl             = "",
    webhookEnabled         = false,
    webhookNotifyOnFinish  = true,
    webhookCensorUser      = false,
    _matchStartTime        = nil,
    _hasSentMatchWebhook   = false,
    _lastWebhookStatus     = "ยังไม่มีการส่ง",
}
local macro = _G.AAMacro

-- ติดตาม wave start time เพื่อคำนวณ waveOffset
local _waveStartTimes = {} -- [waveNum] = tick()
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

-- Hook __namecall ด้วย hookmetamethod เพื่อความเสถียร 100% ไม่ดรอปแพ็กเก็ต Remote
if not _G.__AAMacroHooked then
    _G.__AAMacroHooked = true
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local macroState = _G.AAMacro
        if macroState and macroState.recording and (method == "InvokeServer" or method == "FireServer") then
            local name = self and self.Name or ""
            if name == "spawn_unit" then
                local args  = {...}
                local cf    = args[2]
                local pos   = typeof(cf) == "CFrame" and cf.Position
                           or typeof(cf) == "Vector3" and cf or nil
                local uUuid = args[1]
                local slot  = findSlotByUnitId(uUuid)
                local uName = slot and getSlotUnitName(slot) or "Unit"
                local entryData = {
                    type        = "spawn",
                    timestamp   = macroState.startTime and math.floor(tick() - macroState.startTime) or 0,
                    wave        = getWave(),
                    waveOffset  = math.floor(getWaveElapsed()),  -- วินาทีนับจาก wave นี้เริ่ม
                    gold        = getGold(),
                    position    = pos,
                    unitId      = uUuid,
                    unitName    = uName,
                    slotIndex   = slot,
                    args        = args,
                }
                table.insert(macroState.macro, entryData)
                -- Feedback ให้ผู้เล่นเห็นว่า record จับได้
                task.defer(function()
                    pcall(function()
                        Fluent:Notify({
                            Title    = string.format("🔴 Recorded #%d: SPAWN", #macroState.macro),
                            Content  = string.format("%s (Slot %s)\nWave: %d | Gold: %d¥\nPos: %s",
                                uName, tostring(slot),
                                entryData.wave, entryData.gold,
                                pos and string.format("(%.0f,%.0f,%.0f)", pos.X, pos.Y, pos.Z) or "nil"),
                            Duration = 3,
                        })
                    end)
                end)
            elseif name == "upgrade_unit_ingame" then
                local args = {...}
                local unitModel = args[1]
                local pos   = nil
                local uId   = nil
                local uName = "Unit"
                if typeof(unitModel) == "Instance" then
                    local pPart = unitModel.PrimaryPart or unitModel:FindFirstChild("HumanoidRootPart")
                    pos = pPart and pPart.Position or unitModel:GetPivot().Position
                    local stats = unitModel:FindFirstChild("_stats")
                    uId = stats and stats:FindFirstChild("id") and stats.id.Value or unitModel.Name
                    uName = uId or unitModel.Name
                end
                local entryData2 = {
                    type        = "upgrade",
                    timestamp   = macroState.startTime and math.floor(tick() - macroState.startTime) or 0,
                    wave        = getWave(),
                    waveOffset  = math.floor(getWaveElapsed()),
                    gold        = getGold(),
                    position    = pos,
                    unitId      = uId,
                    unitName    = uName,
                    args        = args,
                }
                table.insert(macroState.macro, entryData2)
                task.defer(function()
                    pcall(function()
                        Fluent:Notify({
                            Title    = string.format("🔴 Recorded #%d: UPGRADE", #macroState.macro),
                            Content  = string.format("%s\nWave: %d | Gold: %d¥",
                                uName, entryData2.wave, entryData2.gold),
                            Duration = 3,
                        })
                    end)
                end)
            end
        end
        -- !! CRITICAL: คืนค่า namecall method กลับเป็นต้นฉบับ
        -- helper functions ข้างบน (FindFirstChild, GetChildren, GetAttribute ฯลฯ)
        -- เรียก __namecall ซ้อน ทำให้ method register เปลี่ยนจาก "InvokeServer" → อย่างอื่น
        -- ถ้าไม่ set กลับ oldNamecall จะส่ง call ผิด method → server ignore
        setnamecallmethod(method)
        return oldNamecall(self, ...)
    end))
end

-- ── 5. Timing & Trigger Check ───────────────────────────────
-- ── 5. Timing & Trigger Check ───────────────────────────────
--
-- Wave+Delay:
--   รอจนกว่า wave ปัจจุบัน >= entry.wave
--   แล้วรออีก entry.waveOffset วินาทีนับจาก wave นั้นเริ่ม
--   + เช็คว่าเงินพอ (canAfford)
--
-- Strict Time:
--   รอจนกว่า tick() - startT >= entry.timestamp (เวลาสัมบูรณ์นับจากกด Play)
--   + เช็คว่าเงินพอ (canAfford)
--
local function shouldTrigger(entry, startT)
    if not canAfford(entry) then return false end

    local mode = macro.playMode
    if mode == "Wave+Delay" then
        if getWave() < (entry.wave or 0) then return false end
        -- wave ถึงแล้ว รอ offset นับจาก wave นั้นเริ่ม
        local wst = _waveStartTimes[entry.wave or 0] or _waveStartTimes[getWave()]
        if not wst then return true end  -- ไม่มีข้อมูล wave start → ยิงเลย
        return (tick() - wst) >= (entry.waveOffset or 0)
    elseif mode == "Strict Time" then
        return (tick() - startT) >= (entry.timestamp or 0)
    end
    return false
end

-- ── 6. Macro Control API ────────────────────────────────────
function macro.StartRecording()
    macro.macro       = {}
    macro.recording   = true
    macro.playing     = false
    macro.currentStep = 0
    macro.startTime   = tick()
end

function macro.StopRecording()
    macro.recording = false
end

function macro.StopPlay()
    macro.playing     = false
    macro.currentStep = 0
end

function macro.Reset()
    macro.recording   = false
    macro.playing     = false
    macro.currentStep = 0
    macro.macro       = {}
    macro.startTime   = nil
    macro.currentProfileName = "Unsaved"
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

            -- รอจนกว่าเงื่อนไข Mode และเงินจะผ่าน
            while macro.playing do
                if shouldTrigger(entry, startT) then break end
                task.wait(0.1)
            end
            if not macro.playing then break end

            if entry.type == "spawn" then
                local liveUuid = findCurrentUuidForSpawn(entry)

                -- แจ้งเตือน UI ว่ากำลัง spawn step ไหน
                Fluent:Notify({
                    Title   = "[Play] Spawn #" .. i,
                    Content = string.format("UUID: %s\nUnit: %s | Slot: %s",
                        tostring(liveUuid):sub(1,32),
                        tostring(entry.unitName),
                        tostring(entry.slotIndex)),
                    Duration = 4,
                })

                -- สร้าง CFrame จากแหล่งที่ดีที่สุด
                local cf = nil
                if entry.args and typeof(entry.args[2]) == "CFrame" then
                    cf = entry.args[2]  -- ใช้ CFrame จาก hook โดยตรง (แม่นยำที่สุด)
                elseif entry.cframe then
                    cf = CFrame.new(table.unpack(entry.cframe))
                elseif entry.position then
                    cf = CFrame.new(entry.position)
                end

                if not liveUuid then
                    Fluent:Notify({ Title = "❌ UUID nil", Content = "Spawn #"..i..": ไม่พบ UUID ให้ตรวจ Debug tab", Duration = 5 })
                elseif not cf then
                    Fluent:Notify({ Title = "❌ CFrame nil", Content = "Spawn #"..i..": ไม่มี CFrame ตรวจ args", Duration = 5 })
                else
                    local ok2, res2 = pcall(function()
                        return spawnRemote:InvokeServer(liveUuid, cf)
                    end)
                    if not ok2 then
                        Fluent:Notify({ Title = "❌ Invoke Error", Content = "Spawn #"..i..": "..tostring(res2):sub(1,80), Duration = 6 })
                    else
                        Fluent:Notify({ Title = "✅ Spawned #"..i, Content = "Result: "..tostring(res2):sub(1,60), Duration = 3 })
                    end
                end

            elseif entry.type == "upgrade" then
                -- หา unit model ในแมตช์ปัจจุบันตามพิกัด
                local liveUnit = entry.position and getLiveUnitByPosition(entry.position, 6)
                if liveUnit then
                    local ok2, res2 = pcall(function()
                        return upgradeRemote:InvokeServer(liveUnit)
                    end)
                    if not ok2 then
                        warn("[AA Macro] upgrade #" .. i .. " error: " .. tostring(res2))
                    end
                else
                    warn("[AA Macro] upgrade #" .. i .. ": unit not found near pos, skipping")
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
            type      = entry.type,
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
        if entry.type == "spawn" and entry.args then
            item.unitUuid = entry.args[1]
            local cf = entry.args[2]
            if typeof(cf) == "CFrame" then
                item.cframe = { cf:GetComponents() }
            end
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
            type        = t.type,
            timestamp   = t.timestamp or 0,
            wave        = t.wave or 0,
            waveOffset  = t.waveOffset or 0,
            gold        = t.gold or 0,
            unitId      = t.unitId or t.unitUuid,
            unitName    = t.unitName or "Unit",
            slotIndex   = t.slotIndex,
        }
        if t.position then
            entry.position = Vector3.new(t.position[1], t.position[2], t.position[3])
        end
        if t.type == "spawn" then
            local cf = nil
            if t.cframe then
                cf = CFrame.new(table.unpack(t.cframe))
            elseif entry.position then
                cf = CFrame.new(entry.position)
            end
            entry.args = { t.unitUuid or entry.unitId, cf }
        elseif t.type == "upgrade" then
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
        end
        return true
    end
    return false
end

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
            if qot and isfile("AA_Macro/main.lua") then
                qot([[task.wait(3); if isfile("AA_Macro/main.lua") then loadstring(readfile("AA_Macro/main.lua"))() end]])
            end
        end)

        -- 3. ยิง Remote Vote Replay เข้า Server
        local okVote, errVote = pcall(function()
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


-- ── 8. Fluent UI Construction ───────────────────────────────
local Window = Fluent:CreateWindow({
    Title       = "AA Macro Studio",
    SubTitle    = "by cook45 & clack",
    TabWidth    = 150,
    Size        = UDim2.fromOffset(620, 540),
    Acrylic     = true,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})
_G.AAMacroUI = Window

local Tabs = {
    Dashboard = Window:AddTab({ Title = "Dashboard", Icon = "gauge" }),
    Controls  = Window:AddTab({ Title = "Controls",  Icon = "play" }),
    Profiles  = Window:AddTab({ Title = "Profiles",  Icon = "folder" }),
    Webhook   = Window:AddTab({ Title = "Webhook",   Icon = "bell" }),
    Log       = Window:AddTab({ Title = "Action Log",Icon = "list" }),
    Debug     = Window:AddTab({ Title = "Debug",     Icon = "search" }),
    Settings  = Window:AddTab({ Title = "Settings",  Icon = "settings" }),
}

-- ────────────────────────────────────────────────────────────
-- ── 9. DASHBOARD TAB ────────────────────────────────────────
-- ────────────────────────────────────────────────────────────
local DashboardPara = Tabs.Dashboard:AddParagraph({
    Title   = "⚡ COMMAND CENTER",
    Content = "กำลังโหลดข้อมูล...",
})

Tabs.Dashboard:AddButton({
    Title       = "▶️  Quick Play",
    Description = "เริ่มการทำงานทันทีตามโปรไฟล์ที่โหลดอยู่",
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
            Title    = "Executing",
            Content  = string.format("▶️ เริ่มทำงาน %d รายการ | โหมด: %s", #macro.macro, macro.playMode),
            Duration = 3,
        })
    end,
})

Tabs.Dashboard:AddButton({
    Title       = "⏹️  Quick Stop",
    Description = "หยุดการทำงานทันที (ทั้ง Playback และ Recording)",
    Callback    = function()
        if macro.recording then
            macro.StopRecording()
            Fluent:Notify({ Title = "Stopped", Content = "หยุดการบันทึก", Duration = 2 })
        elseif macro.playing then
            macro.StopPlay()
            Fluent:Notify({ Title = "Stopped", Content = "หยุดการทำงาน Macro เรียบร้อย", Duration = 2 })
        else
            Fluent:Notify({ Title = "Info", Content = "ไม่มีระบบใดทำงานอยู่", Duration = 2 })
        end
    end,
})

Tabs.Dashboard:AddDropdown("DashQuickMode", {
    Title       = "Quick Playback Mode",
    Description = "Wave+Delay = อิงตาม Wave + เวลานับจาก Wave นั้นเริ่ม | Strict Time = อิงเวลาสัมบูรณ์นับจากกด Play",
    Values      = { "Wave+Delay", "Strict Time" },
    Default     = macro.playMode,
    Callback    = function(val)
        macro.playMode = val
        Fluent:Notify({ Title = "Mode Changed", Content = "โหมด: " .. val, Duration = 2 })
    end,
})

Tabs.Dashboard:AddToggle("DashAutoReplay", {
    Title       = "Auto Replay (จบเกมโหวตเริ่มใหม่ทันที)",
    Default     = macro.autoReplay,
    Callback    = function(val)
        macro.autoReplay = val
        Fluent:Notify({
            Title   = "Auto Replay",
            Content = val and "เปิดใช้งาน Auto Replay" or "ปิดการใช้งาน Auto Replay",
            Duration = 2,
        })
    end,
})

-- ────────────────────────────────────────────────────────────
-- ── 10. CONTROLS TAB ────────────────────────────────────────
-- ────────────────────────────────────────────────────────────
Tabs.Controls:AddParagraph({
    Title   = "🕹️ วิธีใช้งานระบบ Macro",
    Content = "1. กด Record เพื่อเริ่มจำลองการวางตัวละครและอัปเกรด\n2. วางตัวละครหรือกดอัปเกรดตามปกติ จากนั้นกด Stop\n3. เมื่อเข้าแมตช์ใหม่ ให้กด Play เพื่อให้ระบบวางตัวและอัปเกรดอัตโนมัติ",
})

Tabs.Controls:AddButton({
    Title       = "⏺  Record Macro",
    Description = "เริ่มบันทึกการกระทำใหม่ทั้งหมด (ล้างประวัติเดิมในหน่วยความจำ)",
    Callback    = function()
        if macro.playing then
            Fluent:Notify({ Title = "Error", Content = "กำลังรัน Macro อยู่ กรุณากด Stop ก่อน", Duration = 2 })
            return
        end
        macro.StartRecording()
        Fluent:Notify({ Title = "Recording Started", Content = "🔴 เริ่มบันทึก — เริ่มวาง/อัปเกรดตัวละครได้เลย", Duration = 3 })
    end,
})

Tabs.Controls:AddButton({
    Title       = "⏹  Stop Macro",
    Description = "หยุดการบันทึก หรือหยุดการทำงาน",
    Callback    = function()
        if macro.recording then
            macro.StopRecording()
            Fluent:Notify({
                Title    = "Recording Saved",
                Content  = string.format("บันทึกเสร็จสิ้น: ทั้งหมด %d ขั้นตอน", #macro.macro),
                Duration = 3,
            })
        elseif macro.playing then
            macro.StopPlay()
            Fluent:Notify({ Title = "Stopped", Content = "หยุดการทำงาน Macro เรียบร้อย", Duration = 2 })
        else
            Fluent:Notify({ Title = "Info", Content = "ไม่มีระบบใดทำงานอยู่", Duration = 2 })
        end
    end,
})

Tabs.Controls:AddButton({
    Title       = "▶️  Play Macro",
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
            Title    = "Playing",
            Content  = string.format("▶️ เริ่มทำงาน %d รายการ | โหมด: %s", #macro.macro, macro.playMode),
            Duration = 3,
        })
    end,
})

Tabs.Controls:AddButton({
    Title       = "🗑️  Reset Memory",
    Description = "ล้างข้อมูลมาโครที่ค้างอยู่ในหน่วยความจำ",
    Callback    = function()
        Window:Dialog({
            Title   = "ยืนยันการล้างข้อมูล",
            Content = "ต้องการล้างข้อมูลมาโครปัจจุบันทั้งหมด (" .. #macro.macro .. " รายการ) ใช่หรือไม่?",
            Buttons = {
                {
                    Title    = "ยืนยัน",
                    Callback = function()
                        macro.Reset()
                        Fluent:Notify({ Title = "Reset", Content = "ล้างข้อมูลเรียบร้อยแล้ว", Duration = 2 })
                    end,
                },
                { Title = "ยกเลิก", Callback = function() end },
            },
        })
    end,
})

Tabs.Controls:AddSlider("ActionDelay", {
    Title       = "Action Delay (วินาที)",
    Description = "ระยะเวลาหน่วงระหว่างแต่ละการกระทำ",
    Default     = 0.15,
    Min         = 0.05,
    Max         = 1.0,
    Rounding    = 2,
    Callback    = function(val)
        macro.actionDelay = val
    end,
})

Tabs.Controls:AddToggle("CtrlAutoReplay", {
    Title       = "Auto Replay เมื่อจบเกม",
    Description = "ตรวจจับหน้า ResultsUI แล้วกดข้าม XP + โหวต Replay อัตโนมัติ",
    Default     = macro.autoReplay,
    Callback    = function(val)
        macro.autoReplay = val
    end,
})

Tabs.Controls:AddSlider("ReplayDelay", {
    Title       = "Replay Delay (วินาที)",
    Description = "หน่วงเวลาก่อนกด Replay เพื่อให้เห็นของดรอป",
    Default     = 2.0,
    Min         = 0.5,
    Max         = 8.0,
    Rounding    = 1,
    Callback    = function(val)
        macro.replayDelay = val
    end,
})

Tabs.Controls:AddToggle("AutoStartMatch", {
    Title       = "Auto Start เมื่อเริ่มด่านใหม่",
    Description = "โหวตเริ่มเกมอัตโนมัติ (VoteStart Yes) + เริ่มเล่น Macro อัตโนมัติเมื่อเข้าด่าน",
    Default     = macro.autoStartOnMatch,
    Callback    = function(val)
        macro.autoStartOnMatch = val
        if val then
            macro.CheckAndVoteStart()
        end
    end,
})

Tabs.Controls:AddButton({
    Title       = "⚡  ทดสอบ Vote Replay ทันที",
    Description = "ยิงคำสั่ง set_game_finished_vote ทันที (สำหรับทดสอบ)",
    Callback    = function()
        local ok, res = pcall(function()
            return RS.endpoints.client_to_server.set_game_finished_vote:InvokeServer("replay")
        end)
        Fluent:Notify({
            Title   = "Vote Replay",
            Content = ok and ("ส่งคำสั่งแล้ว: " .. tostring(res)) or ("เกิดข้อผิดพลาด: " .. tostring(res)),
            Duration = 3,
        })
    end,
})

Tabs.Controls:AddParagraph({
    Title   = "🛡️ Smart Safeguard System",
    Content = "• เช็คราคา Unit จริงก่อน Spawn และ Upgrade เสมอ\n• หากเงินไม่พอ ระบบจะรอจนกว่าเงินจะถึงตามราคาจริง\n• รองรับการเริ่มเกมใหม่ โดยอิงพิกัดเดิมเพื่อค้นหา Unit ในแมตช์ใหม่อัตโนมัติ",
})

-- ────────────────────────────────────────────────────────────
-- ── 11. PROFILES & CONFIGS TAB ──────────────────────────────
-- ────────────────────────────────────────────────────────────
local inputProfileName = "My_Macro_1"

Tabs.Profiles:AddParagraph({
    Title   = "📁 ระบบจัดการโปรไฟล์ Macro (Config Manager)",
    Content = "ตั้งชื่อ บันทึก โหลด และลบโปรไฟล์มาโครลงในเครื่องของคุณ\nไฟล์จะถูกบันทึกไว้ที่: AA_Macro/profiles/<ชื่อ>.json",
})

local ProfileNameInput = Tabs.Profiles:AddInput("ProfileInput", {
    Title       = "ชื่อโปรไฟล์มาโคร",
    Default     = inputProfileName,
    Placeholder = "เช่น Infinity_Run, Story_Act1",
    Numeric     = false,
    Finished    = false,
    Callback    = function(val)
        if val and val ~= "" then
            inputProfileName = val
        end
    end,
})

local ProfileDropdown = nil

Tabs.Profiles:AddButton({
    Title       = "💾  บันทึกโปรไฟล์ (Save Profile)",
    Description = "บันทึกข้อมูลมาโครปัจจุบันลงเป็นไฟล์คอนฟิก",
    Callback    = function()
        if #macro.macro == 0 then
            Fluent:Notify({ Title = "Error", Content = "ไม่มีข้อมูลมาโครให้บันทึก", Duration = 2 })
            return
        end
        local savedName = macro.SaveProfile(inputProfileName)
        if ProfileDropdown then
            ProfileDropdown:SetValues(macro.GetProfiles())
            ProfileDropdown:SetValue(savedName)
        end
        Fluent:Notify({
            Title    = "Profile Saved",
            Content  = string.format("บันทึก '%s' (%d ขั้นตอน) สำเร็จ!", savedName, #macro.macro),
            Duration = 3,
        })
    end,
})

local selectedProfile = macro.GetProfiles()[1] or "(No saved profiles)"

ProfileDropdown = Tabs.Profiles:AddDropdown("ProfileList", {
    Title       = "เลือกโปรไฟล์ที่บันทึกไว้",
    Description = "รายชื่อไฟล์มาโครทั้งหมดในโฟลเดอร์ AA_Macro/profiles",
    Values      = macro.GetProfiles(),
    Default     = selectedProfile,
    Callback    = function(val)
        selectedProfile = val
    end,
})

Tabs.Profiles:AddButton({
    Title       = "📂  โหลดโปรไฟล์ (Load Profile)",
    Description = "โหลดข้อมูลมาโครจากไฟล์ที่เลือกเข้าสู่ระบบ",
    Callback    = function()
        if not selectedProfile or selectedProfile == "(No saved profiles)" then
            Fluent:Notify({ Title = "Error", Content = "กรุณาเลือกโปรไฟล์ที่ถูกต้อง", Duration = 2 })
            return
        end
        local ok = macro.LoadProfile(selectedProfile)
        if ok then
            Fluent:Notify({
                Title    = "Profile Loaded",
                Content  = string.format("โหลดโปรไฟล์ '%s' (%d ขั้นตอน) สำเร็จ!", selectedProfile, #macro.macro),
                Duration = 3,
            })
        else
            Fluent:Notify({ Title = "Error", Content = "โหลดโปรไฟล์ไม่สำเร็จ", Duration = 2 })
        end
    end,
})

Tabs.Profiles:AddButton({
    Title       = "🗑️  ลบโปรไฟล์ (Delete Profile)",
    Description = "ลบไฟล์คอนฟิกที่เลือกออกจากเครื่องอย่างถาวร",
    Callback    = function()
        if not selectedProfile or selectedProfile == "(No saved profiles)" then
            Fluent:Notify({ Title = "Error", Content = "กรุณาเลือกโปรไฟล์ที่จะลบ", Duration = 2 })
            return
        end
        Window:Dialog({
            Title   = "ยืนยันการลบไฟล์",
            Content = "คุณต้องการลบโปรไฟล์ '" .. selectedProfile .. "' ถาวรหรือไม่?",
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

Tabs.Profiles:AddButton({
    Title       = "🔄  รีเฟรชรายชื่อโปรไฟล์",
    Description = "สแกนหาไฟล์โปรไฟล์ใหม่ในโฟลเดอร์",
    Callback    = function()
        local list = macro.GetProfiles()
        ProfileDropdown:SetValues(list)
        selectedProfile = list[1] or "(No saved profiles)"
        ProfileDropdown:SetValue(selectedProfile)
        Fluent:Notify({ Title = "Refreshed", Content = string.format("พบ %d โปรไฟล์", #list), Duration = 2 })
    end,
})

-- ── Section: Cloud Share & Import ─────────────────────────────
Tabs.Profiles:AddSection("🌐 CLOUD SHARE & IMPORT")

Tabs.Profiles:AddButton({
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
Tabs.Profiles:AddInput("MacroImportLinkInput", {
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
Tabs.Profiles:AddInput("MacroImportNameInput", {
    Title       = "ตั้งชื่อโปรไฟล์ใหม่ (ปล่อยว่างเพื่อใช้ชื่อเดิม)",
    Default     = "",
    Placeholder = "เช่น My_Imported_Macro",
    Numeric     = false,
    Finished    = false,
    Callback    = function(val)
        if val then importNameInput = val end
    end,
})

Tabs.Profiles:AddButton({
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
-- ── WEBHOOK TAB (Discord Notification System) ───────────────
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
-- ── 12. ACTION LOG TAB ──────────────────────────────────────
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
    table.insert(lines, string.format("%-4s | %-6s | %-10s | %-5s | %-7s | %-4s | %s",
        "STEP", "ACTION", "UNIT", "WAVE", "COST", "TIME", "POSITION"))
    table.insert(lines, string.rep("─", 58))

    for i, v in ipairs(macro.macro) do
        local ps = v.position
            and string.format("(%.0f, %.0f, %.0f)", v.position.X, v.position.Y, v.position.Z)
            or "N/A"
        local actIcon = v.type == "spawn" and "SPAWN" or "UPG"
        local uName = tostring(v.unitName or "Unit"):sub(1, 10)
        local waveTxt = string.format("W%d+%ds", v.wave or 0, v.waveOffset or 0)
        table.insert(lines, string.format(
            "[%02d] | %-6s | %-10s | %-8s | %-3ds | %s",
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
-- ── 13. DEBUG TAB ───────────────────────────────────────────
-- ────────────────────────────────────────────────────────────
local DebugPara = Tabs.Debug:AddParagraph({
    Title   = "🔍 Debug Info",
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
        -- copy to clipboard ด้วย
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

        -- หา UUID ปัจจุบัน
        local liveUuid = findCurrentUuidForSpawn(entry)
        -- หา CFrame
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

-- ────────────────────────────────────────────────────────────
-- ── 14. SETTINGS TAB ────────────────────────────────────────
-- ────────────────────────────────────────────────────────────
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
InterfaceManager:SetFolder("AA_Macro")
SaveManager:SetFolder("AA_Macro/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

-- ────────────────────────────────────────────────────────────
-- ── 14. REAL-TIME DASHBOARD TELEMETRY LOOP ──────────────────
-- ────────────────────────────────────────────────────────────
task.spawn(function()
    while true do
        pcall(function()
            local state = macro.recording and "🔴 RECORDING"
                       or macro.playing   and ("▶️ PLAYING [" .. macro.playMode .. "]")
                       or "⏹️ IDLE"

            local elapsed = 0
            if macro.startTime and (macro.recording or macro.playing) then
                elapsed = math.floor(tick() - macro.startTime)
            end
            local elapsedStr = string.format("%02d:%02d", math.floor(elapsed / 60), elapsed % 60)

            local total = #macro.macro
            local current = macro.playing and macro.currentStep or (macro.recording and total or 0)
            local progBar = generateProgressBar(current, total, 16)

            local spawns = 0
            local upgrades = 0
            for _, e in ipairs(macro.macro) do
                if e.type == "spawn" then spawns = spawns + 1
                elseif e.type == "upgrade" then upgrades = upgrades + 1 end
            end

            local nextText = "—"
            if macro.playing and macro.currentStep > 0 and macro.currentStep <= total then
                local nextEntry = macro.macro[macro.currentStep]
                local actIcon = nextEntry.type == "spawn" and "🎯 SPAWN" or "⬆️ UPGRADE"
                local affordable = canAfford(nextEntry)
                local affStatus = affordable and "✅ เงินพอแล้ว พร้อมกด" or "⏳ กำลังรอเงินสะสมให้พอ..."
                local posStr = nextEntry.position and string.format("(%.0f, %.0f, %.0f)", nextEntry.position.X, nextEntry.position.Y, nextEntry.position.Z) or "N/A"
                nextText = string.format("[%d/%d] %s  →  %s\n  • พิกัด: %s\n  • เงื่อนไข: Wave ≥ %d  |  Gold ≥ %d¥\n  • ความพร้อม: %s",
                    macro.currentStep, total, actIcon, nextEntry.unitName or "Unit",
                    posStr, nextEntry.wave, nextEntry.gold, affStatus
                )
            elseif macro.recording then
                nextText = string.format("🔴 กำลังบันทึกการกระทำ... (บันทึกแล้ว %d รายการ)", total)
            else
                nextText = total > 0
                    and string.format("✅ มาโครพร้อมทำงาน (%d ขั้นตอน) — กด Play เพื่อเริ่ม", total)
                    or "💤 ยังไม่มีข้อมูลมาโคร — กด Record หรือเลือก Profile ด้านบน"
            end

            local dashLines = {
                "==================================================",
                "             ⚡ AA MACRO COMMAND CENTER",
                "==================================================",
                string.format("• สถานะ        :  %s  (⏱️ %s)", state, elapsedStr),
                string.format("• โปรไฟล์      :  📁 %s", macro.currentProfileName or "Unsaved"),
                string.format("• ด่านปัจจุบัน :  🌊 Wave %d", getWave()),
                string.format("• ยอดเงินสด    :  💰 %s ¥", moneyLabel.Text),
                string.format("• ตัวในสนาม   :  🛡️ %d ตัว", getActiveUnitsCount()),
                string.format("• ออโต้รีเพลย์ :  %s (ดีเลย์: %.1fs)", macro.autoReplay and "🟢 เปิด" or "🔴 ปิด", macro.replayDelay or 2.0),
                string.format("• จำนวนคิว     :  📝 %d ขั้นตอน (Spawn: %d | Upg: %d)", total, spawns, upgrades),
                "--------------------------------------------------",
                string.format("• ความคืบหน้า  :  %s  (%d/%d)", progBar, current, total),
                "--------------------------------------------------",
                "• ขั้นตอนถัดไป :",
                nextText,
            }

            DashboardPara:SetDesc(table.concat(dashLines, "\n"))

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
            local curWave = getWave()
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

            -- เช็ค Auto Start เมื่อเริ่มด่านใหม่
            if macro.autoStartOnMatch then
                -- 1) ตรวจจับ VoteStart แล้วกด Yes ทันที
                local vs = plr.PlayerGui:FindFirstChild("VoteStart")
                if vs and vs.Enabled then
                    if not macro._hasVotedStart then
                        macro._hasVotedStart = true
                        task.spawn(function()
                            macro.VoteGameStart()
                            Fluent:Notify({
                                Title    = "Auto Start",
                                Content  = "⚡ กดโหวตเริ่มเกม (VoteStart Yes) ให้อัตโนมัติแล้ว!",
                                Duration = 3,
                            })
                        end)
                    end
                else
                    macro._hasVotedStart = false
                end

                -- 2) เล่น Macro อัตโนมัติเมื่อ Wave >= 1
                if not macro.playing and not macro.recording and #macro.macro > 0 then
                    if curWave >= 1 and not macro._hasAutoStarted then
                        macro._hasAutoStarted = true
                        task.delay(1, function()
                            macro.Play()
                            Fluent:Notify({
                                Title   = "Auto Start",
                                Content = "เริ่มเล่น Macro อัตโนมัติในด่านใหม่แล้ว!",
                                Duration = 3,
                            })
                        end)
                    end
                end
            end
        end)
        task.wait(0.4)
    end
end)

-- ── VoteStart Event Listener ────────────────────────────────
task.spawn(function()
    local function hookVoteStart(vs)
        if not vs or not vs:IsA("ScreenGui") then return end
        vs:GetPropertyChangedSignal("Enabled"):Connect(function()
            if vs.Enabled and macro.autoStartOnMatch and not macro._hasVotedStart then
                macro._hasVotedStart = true
                task.delay(0.1, function()
                    macro.VoteGameStart()
                    Fluent:Notify({
                        Title    = "Auto Start",
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
            if child:IsA("ScreenGui") and child.Enabled and macro.autoStartOnMatch and not macro._hasVotedStart then
                macro._hasVotedStart = true
                task.delay(0.1, function()
                    macro.VoteGameStart()
                    Fluent:Notify({
                        Title    = "Auto Start",
                        Content  = "⚡ โหวตเริ่มเกม (VoteStart Yes) ทันที!",
                        Duration = 3,
                    })
                end)
            end
        end
    end)
end)

-- ── Finished ────────────────────────────────────────────────
Window:SelectTab(1)
Fluent:Notify({
    Title    = "AA Macro Studio Ready!",
    Content  = string.format("Profile: %s | Mode: %s | RightCtrl = ซ่อน UI", macro.currentProfileName, macro.playMode),
    Duration = 4,
})
