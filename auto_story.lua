-- ==============================================================================
-- ⚔️ ANIME ADVENTURES AUTO STORY PROGRESSION & PARTY ENGINE (v2.0 OVERHAUL)
-- Developed by: cook45 & clack
-- File: AA_Macro/auto_story.lua
-- Features:
--   • Cached Memory & Profile Data Story Progression Scanner (Zero GC Lag)
--   • Dual-Engine Level Lock & Start (UI + Direct Remote Invoke Failsafe)
--   • Single-Signal Precision GUI Clicker (No Double-Click / No UI Desync)
--   • Party Mode Support (Host / Leader, Member / Follower, & Solo)
--   • Accurate ACT 6 & All-Story Discord Webhook Notifications
-- ==============================================================================

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local GuiService        = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local LOBBY_PLACE_ID = 8304191830

-- ── Lobby Guard Check ─────────────────────────────────────────────────────────
local function isLobby()
    if game.PlaceId == LOBBY_PLACE_ID then return true end
    if Workspace:FindFirstChild("_LOBBIES") and Workspace._LOBBIES:FindFirstChild("Story") then
        return true
    end
    return false
end

if not isLobby() then
    print("[AA Auto Story] 🛑 Not in Lobby (PlaceId: " .. tostring(game.PlaceId) .. "). Script runs in Lobby only.")
    return
end

local gethui = gethui or function() return game:GetService("CoreGui") end
if _G.AA_AutoStoryUI and typeof(_G.AA_AutoStoryUI.Destroy) == "function" then
    pcall(function() _G.AA_AutoStoryUI:Destroy() end)
    _G.AA_AutoStoryUI = nil
end

pcall(function()
    for _, ch in ipairs(gethui():GetChildren()) do
        if ch:IsA("ScreenGui") and (ch.Name == "AA_AutoStory_HUD" or ch.Name:find("Fluent")) then
            pcall(function() ch:Destroy() end)
        end
    end
end)

-- ── 1. Load Fluent UI Library ─────────────────────────────────────────────────
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local function trim(s)
    return tostring(s or ""):match("^%s*(.-)%s*$") or tostring(s or "")
end

-- ── 2. Config & State Management ──────────────────────────────────────────────
local CONFIG_FILE     = "auto_story_config.json"
local LAST_MATCH_FILE = "last_story_match.json"

local Config = {
    Enabled            = false,
    Mode               = "Solo",        -- "Solo", "Party Leader (Host)", "Party Member (Follower)"
    PartySize          = 2,             -- Target party member count
    LeaderUsername     = "",            -- For Party Member to track & follow
    FriendsOnly        = false,         -- Door locks only for friends
    Difficulty         = "Normal",      -- "Normal" or "Hard"
    SelectDelay        = 3.5,           -- Delay before clicking Select button
    WebhookUrl         = "https://discord.com/api/webhooks/1564605032517869601/JFLes7jR2Z44H3vDdnZ10GmBKn-qTd0JOibxDNGuRh3L9U74c3a4SLiAATfvZYV893CQ",
    NotifyAct6         = true,
    NotifyAllCompleted = true,
    CheckInterval      = 2.5,
    DoorWaitTimeout    = 60,
}

local State = {
    CurrentStatus      = "STANDBY",
    TargetMapId        = "-",
    TargetMapName      = "-",
    TargetAct          = 0,
    TargetLevelId      = "-",
    IsAct6             = false,
    AllCompleted       = false,
    CurrentDoorName    = "-",
    PartyCount         = 0,
    TotalRuns          = 0,
    Act6ClearedCount   = 0,
}

-- Forward declarations (ป้องกันบั๊กเรียกฟังก์ชันก่อนประกาศ 100%)
local updateUIStatus
local updateUITarget

-- Load saved config
pcall(function()
    if isfile and isfile(CONFIG_FILE) then
        local raw = readfile(CONFIG_FILE)
        local data = HttpService:JSONDecode(raw)
        for k, v in pairs(data) do
            if Config[k] ~= nil then Config[k] = v end
        end
    end
end)

local function saveConfig()
    pcall(function()
        if writefile then
            writefile(CONFIG_FILE, HttpService:JSONEncode(Config))
        end
    end)
end

-- ── 3. Discord Webhook Engine ─────────────────────────────────────────────────
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request

local function sendWebhook(title, description, color, fields)
    if not Config.WebhookUrl or Config.WebhookUrl == "" or not httpRequest then return end
    task.spawn(function()
        pcall(function()
            local payload = {
                username = "Anime Adventures Story Bot",
                avatar_url = "https://raw.githubusercontent.com/PeeKillxa/AA_Macro/main/logo.png",
                embeds = {
                    {
                        title = title,
                        description = description,
                        color = color or 0x00FF88,
                        fields = fields or {},
                        footer = {
                            text = "AA Auto Story Studio v2.0 • Developed by cook45 & clack",
                            icon_url = "https://raw.githubusercontent.com/PeeKillxa/AA_Macro/main/logo.png"
                        },
                        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                    }
                }
            }
            httpRequest({
                Url = Config.WebhookUrl,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode(payload)
            })
        end)
    end)
end

-- ── 4. Character & Spatial Helpers ────────────────────────────────────────────
local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getRoot()
    local char = getCharacter()
    return char and (char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5))
end

local function getEndpoints()
    local ep = ReplicatedStorage:FindFirstChild("endpoints")
    return ep and ep:FindFirstChild("client_to_server")
end

-- ── 5. Cached Memory & UI Story Progress Scanner ──────────────────────────────
local cachedProfileData = nil
local cachedLoaderModules = nil

local function getProfileLevelData()
    if cachedProfileData and type(cachedProfileData) == "table" and rawget(cachedProfileData, "level_data") then
        return cachedProfileData.level_data
    end
    if not getgc then return nil end

    for _, obj in ipairs(getgc(true)) do
        if type(obj) == "table" then
            local ld = rawget(obj, "level_data")
            if type(ld) == "table" and rawget(ld, "completed_story_levels") then
                cachedProfileData = obj
                return ld
            end
        end
    end
    return nil
end

local function getGameStoryModules()
    if cachedLoaderModules then return cachedLoaderModules end
    local ok, mods = pcall(function()
        local src = ReplicatedStorage:FindFirstChild("src")
        local loaderModule = src and src:FindFirstChild("Loader")
        if not loaderModule then return nil end
        local Loader = require(loaderModule)
        return {
            ProgressionServiceCore = Loader.load_core_service(nil, "ProgressionServiceCore"),
            Worlds                 = Loader.load_data(nil, "Worlds"),
            WorldLevelOrder        = Loader.load_data(nil, "WorldLevelOrder"),
        }
    end)
    if ok and mods and mods.Worlds and mods.WorldLevelOrder then
        cachedLoaderModules = mods
        return mods
    end
    return nil
end

local function getLevelSelectContainer()
    local pGui = LocalPlayer:WaitForChild("PlayerGui", 5)
    if not pGui then return nil end
    local lvlGui = pGui:FindFirstChild("LevelSelectGui")
    if not lvlGui then return nil end
    local mapSelect = lvlGui:FindFirstChild("MapSelect")
    local main = mapSelect and mapSelect:FindFirstChild("Main")
    local wrapper = main and main:FindFirstChild("Wrapper")
    return wrapper and wrapper:FindFirstChild("Container")
end

local function scanStoryProgress()
    -- 1. ระบบหลัก: ดึงจาก Cached Profile Data ใน Memory (ไม่กระตุก ไม่ต้องเปิดประตู)
    local ok, memTarget = pcall(function()
        local lvlData = getProfileLevelData()
        local mods = getGameStoryModules()
        if not lvlData or not mods then return nil end

        local completedLevels = lvlData.completed_story_levels or {}
        local storyOrder = mods.WorldLevelOrder.WORLD_ORDER or {}
        local allMaps = {}
        local firstNextTarget = nil

        for idx, worldId in ipairs(storyOrder) do
            local wInfo = mods.Worlds[worldId]
            if wInfo and not wInfo.legend_stage and not wInfo.raid_world then
                local unlocked = mods.ProgressionServiceCore.check_if_unlocked_world(lvlData, worldId)
                local totalActs = 0
                local clearedActs = 0
                local levels = {}

                for k, lvl in pairs(wInfo.levels or {}) do
                    if not lvl.is_infinite and not lvl.is_raid then
                        totalActs = totalActs + 1
                        local actNum = tonumber(k) or tonumber( tostring(lvl.id):match("_(%d+)$") ) or tonumber( tostring(lvl.id):match("(%d+)$") ) or totalActs
                        local c = completedLevels[lvl.id]
                        local isCleared = (c and c.times_completed and c.times_completed > 0) and true or false
                        if isCleared then
                            clearedActs = clearedActs + 1
                        end
                        table.insert(levels, {
                            act     = actNum,
                            id      = lvl.id,
                            cleared = isCleared
                        })
                    end
                end

                table.sort(levels, function(a, b) return a.act < b.act end)

                table.insert(allMaps, {
                    id       = worldId,
                    name     = wInfo.name or worldId,
                    isLocked = not unlocked,
                    cleared  = clearedActs,
                    total    = totalActs > 0 and totalActs or 6,
                    order    = idx
                })

                if unlocked and not firstNextTarget and clearedActs < totalActs then
                    local nextActInfo = nil
                    for _, l in ipairs(levels) do
                        if not l.cleared then
                            nextActInfo = l
                            break
                        end
                    end
                    local actNum = nextActInfo and nextActInfo.act or (clearedActs + 1)
                    local lvlId = nextActInfo and nextActInfo.id or string.format("%s_level_%d", worldId, actNum)
                    firstNextTarget = {
                        completed = false,
                        mapId     = worldId,
                        mapName   = wInfo.name or worldId,
                        act       = actNum,
                        totalActs = totalActs,
                        cleared   = clearedActs,
                        levelId   = lvlId,
                        isAct6    = (actNum == totalActs),
                    }
                end
            end
        end

        if firstNextTarget then
            firstNextTarget.allMaps = allMaps
            return firstNextTarget
        end

        if #allMaps > 0 then
            return {
                completed = true,
                allMaps   = allMaps
            }
        end
        return nil
    end)

    if ok and memTarget then
        return memTarget, "Profile Memory Scan"
    end

    -- 2. ระบบสำรอง: สแกนจาก DOM LevelSelectGui
    local container = getLevelSelectContainer()
    if not container then
        return nil, "Waiting for LevelSelectGui / Memory Profile..."
    end

    local maps = {}
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("GuiObject") and child:FindFirstChild("Main") then
            local mapId = child.Name
            if not mapId:lower():find("comingsoon") and not mapId:lower():find("placeholder") then
                local main = child.Main
                local mapContainer = main:FindFirstChild("Container")
                local mapNameLabel = mapContainer and mapContainer:FindFirstChild("MapName")
                local mapName = mapNameLabel and (mapNameLabel:IsA("TextLabel") and mapNameLabel.Text or mapNameLabel.Value) or mapId

                local lockedFrame = main:FindFirstChild("Locked")
                local isLocked = false
                if lockedFrame then
                    local innerLocked = lockedFrame:FindFirstChild("locked")
                    if innerLocked and innerLocked:IsA("GuiObject") then
                        isLocked = innerLocked.Visible and lockedFrame.Visible
                    else
                        isLocked = lockedFrame.Visible
                    end
                end

                local levelsObj = mapContainer and mapContainer:FindFirstChild("LevelsCleared") and mapContainer.LevelsCleared:FindFirstChild("V")
                local clearedStr = levelsObj and (levelsObj:IsA("TextLabel") and levelsObj.Text or tostring(levelsObj.Value)) or "0/6"
                local cleared, total = clearedStr:match("(%d+)/(%d+)")
                cleared = tonumber(cleared) or 0
                total = tonumber(total) or 6

                local order = child.LayoutOrder or 0
                if order == 0 and child.AbsolutePosition then
                    order = math.floor(child.AbsolutePosition.X + child.AbsolutePosition.Y * 1000)
                end

                table.insert(maps, {
                    id       = mapId,
                    name     = mapName,
                    isLocked = isLocked,
                    cleared  = cleared,
                    total    = total,
                    order    = order
                })
            end
        end
    end

    table.sort(maps, function(a, b) return a.order < b.order end)

    if #maps == 0 then
        return nil, "Container has no map objects"
    end

    for _, m in ipairs(maps) do
        if not m.isLocked and m.cleared < m.total then
            local nextAct = m.cleared + 1
            local levelId = string.format("%s_level_%d", m.id, nextAct)
            return {
                completed = false,
                mapId     = m.id,
                mapName   = m.name,
                act       = nextAct,
                totalActs = m.total,
                cleared   = m.cleared,
                levelId   = levelId,
                isAct6    = (nextAct == m.total),
                allMaps   = maps
            }, "Found Next Story Level via UI"
        end
    end

    return {
        completed = true,
        allMaps   = maps
    }, "All Available Stories Completed!"
end

-- ── 6. Precision GUI Clicker & Remote Controllers ─────────────────────────────
-- ยิงคลิกครั้งเดียวตามลำดับความแม่นยำ (ไม่ยิงซ้ำ 4 ระบบซ้อนกันจนปุ่มรวน)
local function clickGuiElement(btn)
    if not btn then return false end

    -- 1. ลองใช้ firesignal ก่อน (เสถียรและไม่โดนหน้าต่างอื่นบัง)
    if typeof(firesignal) == "function" then
        local fired = false
        pcall(function()
            if btn:IsA("GuiButton") then
                firesignal(btn.Activated)
                firesignal(btn.MouseButton1Click)
                fired = true
            end
        end)
        if fired then return true end
    end

    -- 2. ลองใช้ getconnections หาก Executor ไม่มี firesignal
    if typeof(getconnections) == "function" then
        local fired = false
        pcall(function()
            if btn:IsA("GuiButton") then
                for _, conn in ipairs(getconnections(btn.Activated)) do
                    if conn.Function then
                        task.spawn(conn.Function)
                        fired = true
                    elseif conn.Fire then
                        conn:Fire()
                        fired = true
                    end
                end
                if not fired then
                    for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do
                        if conn.Function then
                            task.spawn(conn.Function)
                            fired = true
                        elseif conn.Fire then
                            conn:Fire()
                            fired = true
                        end
                    end
                end
            end
        end)
        if fired then return true end
    end

    -- 3. Fallback สุดท้าย: VirtualInputManager (ชดเชย GuiInset 36px ให้ตรงตำแหน่งจริง)
    local vimSuccess = false
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local inset = GuiService:GetGuiInset()
        local absPos = btn.AbsolutePosition
        local absSize = btn.AbsoluteSize
        if absSize.X > 0 and absSize.Y > 0 then
            local x = absPos.X + (absSize.X / 2)
            local y = absPos.Y + (absSize.Y / 2) + inset.Y
            vim:SendMouseButtonEvent(x, y, 0, true, game, 1)
            task.wait(0.05)
            vim:SendMouseButtonEvent(x, y, 0, false, game, 1)
            vimSuccess = true
        end
    end)

    return vimSuccess
end

-- ยิง Remote ล็อคด่านตรงเข้าเซิร์ฟเวอร์
local function invokeLockDoorRemote(doorModelName, levelId, friendsOnly, difficulty)
    local ep = getEndpoints()
    local remote = ep and ep:FindFirstChild("request_lock_level")
    if remote then
        local ok, err = pcall(function()
            remote:InvokeServer(
                doorModelName,
                levelId,
                friendsOnly == true,
                difficulty or "Normal"
            )
        end)
        return ok, err
    end
    return false, "request_lock_level remote not found"
end

-- ยิง Remote เริ่มเกมตรงเข้าเซิร์ฟเวอร์ (ถ้ามี)
local function invokeStartMatchRemote(doorModelName)
    local ep = getEndpoints()
    if not ep then return false end
    local startRemote = ep:FindFirstChild("request_start_game") or ep:FindFirstChild("start_lobby")
    if startRemote then
        local ok = pcall(function()
            startRemote:InvokeServer(doorModelName)
        end)
        return ok
    end
    return false
end

-- เลือกด่านใน UI + รอดีเลย์ + กดปุ่ม Select + ยิง Remote กำกับความชัวร์ 100%
local function lockStoryLevelInUI(target, doorModelName)
    if not target or not target.mapId then
        return false, "Invalid target table"
    end

    -- 1. ยิง Remote request_lock_level นำร่องก่อนเลย (เผื่อ UI โหลดช้า)
    if doorModelName and target.levelId then
        invokeLockDoorRemote(doorModelName, target.levelId, Config.FriendsOnly, Config.Difficulty)
    end

    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not pGui then return false, "PlayerGui not found" end

    local lvlGui = pGui:FindFirstChild("LevelSelectGui")
    local t0 = tick()
    while not lvlGui and (tick() - t0 < 4) do
        task.wait(0.2)
        lvlGui = pGui:FindFirstChild("LevelSelectGui")
    end

    if not lvlGui then
        return true, "Locked via Remote (LevelSelectGui not open)"
    end

    local selectClicked = false

    pcall(function()
        -- ขั้นตอน A: กดเลือกการ์ดแมพใน MapSelect.Main.Wrapper.Container
        local container = getLevelSelectContainer()
        if container then
            local mapCard = container:FindFirstChild(target.mapId)
            if mapCard then
                local btn = mapCard:IsA("GuiButton") and mapCard or mapCard:FindFirstChildWhichIsA("GuiButton", true)
                if btn then
                    clickGuiElement(btn)
                    task.wait(0.6)
                end
            end
        end

        -- ขั้นตอน B: กดเลือกปุ่ม Act ใน LevelSelect.InfoFrame.LevelButtons
        local levelSelect = lvlGui:FindFirstChild("LevelSelect")
        local infoFrame = levelSelect and levelSelect:FindFirstChild("InfoFrame")
        local lvlButtons = infoFrame and infoFrame:FindFirstChild("LevelButtons")
        if lvlButtons then
            local actButtons = {}
            for _, b in ipairs(lvlButtons:GetChildren()) do
                if b:IsA("GuiButton") and b.Visible then
                    table.insert(actButtons, b)
                end
            end
            table.sort(actButtons, function(a, b)
                return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
            end)
            if target.act and actButtons[target.act] then
                clickGuiElement(actButtons[target.act])
                task.wait(0.5)
            end
        end

        -- ขั้นตอน C: รอจังหวะให้ UI โหลดข้อมูลด่านครบตาม Config.SelectDelay (3.5s)
        local delaySec = tonumber(Config.SelectDelay) or 3.5
        if updateUIStatus then
            updateUIStatus("WAITING SELECT", string.format("เลือก %s Act %d แล้ว... รอ %.1f วินาทีก่อนกด Select", tostring(target.mapName), tonumber(target.act) or 1, delaySec))
        end
        task.wait(delaySec)

        -- ขั้นตอน D: กดปุ่ม Select ใน LevelSelect.Buttons.Select
        local selectBtn = levelSelect and levelSelect:FindFirstChild("Buttons") and levelSelect.Buttons:FindFirstChild("Select")
        if selectBtn and selectBtn.Visible then
            local innerBtn = selectBtn:IsA("GuiButton") and selectBtn or selectBtn:FindFirstChildWhichIsA("GuiButton", true)
            if innerBtn then
                selectClicked = clickGuiElement(innerBtn)
            end
            task.wait(0.4)
        end

        -- ขั้นตอน E: ยิง Remote request_lock_level ซ้ำอีกครั้งเพื่อรับประกันว่าล็อคระดับด่านชัวร์ 100%
        if doorModelName and target.levelId then
            invokeLockDoorRemote(doorModelName, target.levelId, Config.FriendsOnly, Config.Difficulty)
        end
    end)

    return selectClicked, selectClicked and "Clicked Select & Invoked Remote" or "Invoked Remote Lock"
end

-- กดปุ่ม START เริ่มเกม (ทั้ง UI + Remote)
local function pressStartMatchButton(doorModelName)
    local clicked = false

    -- 1. ยิง Remote เริ่มเกม (ถ้ามี)
    if doorModelName then
        if invokeStartMatchRemote(doorModelName) then
            clicked = true
        end
    end

    -- 2. กดปุ่ม LevelSelectGui.Buttons.Start บน UI
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    local lvlGui = pGui and pGui:FindFirstChild("LevelSelectGui")
    if lvlGui then
        local buttons = lvlGui:FindFirstChild("Buttons")
        local startObj = buttons and buttons:FindFirstChild("Start") or lvlGui:FindFirstChild("Start", true)
        if startObj then
            local targetBtn = startObj:IsA("GuiButton") and startObj or startObj:FindFirstChildWhichIsA("GuiButton", true)
            if targetBtn then
                clicked = clickGuiElement(targetBtn) or clicked
            end
        end
    end

    return clicked, clicked and "Triggered Start Match" or "Start button not found"
end

-- ── 7. Lobby Door Inspector & Movement Controller ─────────────────────────────
local function getStoryLobbies()
    local lobbies = Workspace:FindFirstChild("_LOBBIES")
    return lobbies and lobbies:FindFirstChild("Story")
end

local function getDoorInfo(doorModel)
    local door = doorModel and doorModel:FindFirstChild("Door")
    if not door then return nil end
    local surface = door:FindFirstChild("Surface")
    local status = surface and surface:FindFirstChild("Status") and surface.Status:FindFirstChild("State")
    local map = surface and surface:FindFirstChild("MapName")
    local lvl = surface and surface:FindFirstChild("LevelName")
    local diff = surface and surface:FindFirstChild("Difficulty")

    local statusText = status and (status:IsA("TextLabel") and status.Text or tostring(status.Value)) or "Unknown"
    local mapText    = map and (map:IsA("TextLabel") and map.Text or tostring(map.Value)) or ""
    local lvlText    = lvl and (lvl:IsA("TextLabel") and lvl.Text or tostring(lvl.Value)) or ""
    local diffText   = diff and (diff:IsA("TextLabel") and diff.Text or tostring(diff.Value)) or ""

    local lowerStatus = statusText:lower()
    return {
        model       = doorModel,
        door        = door,
        cframe      = door.CFrame,
        statusText  = statusText,
        mapText     = mapText,
        lvlText     = lvlText,
        diffText    = diffText,
        isEmpty     = (statusText == "Empty" or lowerStatus:find("empty") ~= nil),
        isWaiting   = (statusText == "Waiting for players..." or lowerStatus:find("waiting") ~= nil),
        isSelecting = (statusText == "Selecting..." or lowerStatus:find("selecting") ~= nil),
    }
end

local function findEmptyDoor()
    local story = getStoryLobbies()
    if not story then return nil end
    for _, doorModel in ipairs(story:GetChildren()) do
        local info = getDoorInfo(doorModel)
        if info and info.isEmpty then
            return info
        end
    end
    return nil
end

local function countPlayersInDoor(doorPart)
    if not doorPart then return 0 end
    local count = 0
    for _, p in ipairs(Players:GetPlayers()) do
        local char = p.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp and (hrp.Position - doorPart.Position).Magnitude <= 12 then
            count = count + 1
        end
    end
    return count
end

local function findLeaderPlayer(leaderInput)
    if not leaderInput or #leaderInput == 0 then return nil end
    local clean = trim(leaderInput):gsub("^@", ""):lower()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower() == clean or p.DisplayName:lower() == clean then
            return p
        end
    end
    return nil
end

local function findLeaderDoor(leaderName, targetMapName, targetAct)
    local story = getStoryLobbies()
    if not story then return nil, "NO_LOBBIES" end

    local leaderPlayer = findLeaderPlayer(leaderName)
    local leaderHrp = leaderPlayer and leaderPlayer.Character and leaderPlayer.Character:FindFirstChild("HumanoidRootPart")

    -- 1. ตรวจสอบจากตำแหน่งตัวละครของหัวห้อง (หากอยู่ในเซิร์ฟเวอร์เดียวกัน)
    if leaderHrp then
        for _, doorModel in ipairs(story:GetChildren()) do
            local info = getDoorInfo(doorModel)
            if info and (info.door.Position - leaderHrp.Position).Magnitude <= 14 then
                if info.isSelecting then
                    return info, "SELECTING"
                end
                if info.isEmpty then
                    return info, "EMPTY"
                end
                if info.isWaiting or (#info.mapText > 0 and #info.lvlText > 0) then
                    return info, "READY"
                end
                return info, "SELECTING"
            end
        end
    end

    -- 2. ตรวจสอบจากป้ายหน้าประตูที่มีสถานะ Waiting for players... และแมพ/Act ตรงกัน
    local actPattern = "act " .. tostring(targetAct)
    for _, doorModel in ipairs(story:GetChildren()) do
        local info = getDoorInfo(doorModel)
        if info and info.isWaiting and not info.isSelecting and not info.isEmpty then
            local mapMatch = (targetMapName and info.mapText:lower():find(targetMapName:lower(), 1, true) ~= nil)
            local actMatch = (info.lvlText:lower():find(actPattern, 1, true) ~= nil)
            if mapMatch and actMatch then
                return info, "READY"
            end
        end
    end

    return nil, "NOT_IN_DOOR"
end

local function isNearStoryDoors()
    local root = getRoot()
    local story = getStoryLobbies()
    if not root or not story then return false end
    for _, doorModel in ipairs(story:GetChildren()) do
        local door = doorModel:FindFirstChild("Door")
        if door and (door.Position - root.Position).Magnitude <= 35 then
            return true
        end
    end
    return false
end

local function fastTravelToPlayZone()
    if isNearStoryDoors() then
        return true
    end

    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    local leftUI = pGui and pGui:FindFirstChild("LeftUI_test")
    local eventBtn = leftUI and leftUI:FindFirstChild("Buttons") and leftUI.Buttons:FindFirstChild("EventTeleport")

    if eventBtn then
        clickGuiElement(eventBtn)
        task.wait(1.2)
        return true
    end
    return false
end

-- เดินเข้าประตูและแตะ TouchInterest ครั้งเดียวอย่างแม่นยำ
local function enterDoor(doorPart, doorModelName)
    if not doorPart then return end
    local char = getCharacter()
    local root = getRoot()
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end

    local distXZ = Vector2.new(root.Position.X - doorPart.Position.X, root.Position.Z - doorPart.Position.Z).Magnitude

    -- ถ้าอยู่ไกลเกิน 35 studs ให้วาร์ปมาหน้าประตูก่อนที่ระยะ 7 studs
    if distXZ > 35 then
        root.CFrame = doorPart.CFrame * CFrame.new(0, 0, 7)
        task.wait(0.15)
    end

    -- เดินเข้าหาจุดศูนย์กลางประตู
    local targetPos = Vector3.new(doorPart.Position.X, root.Position.Y, doorPart.Position.Z)
    local walkStart = tick()
    while (tick() - walkStart) < 4.5 do
        if not root or not hum or not doorPart then break end
        local curDist = Vector2.new(root.Position.X - doorPart.Position.X, root.Position.Z - doorPart.Position.Z).Magnitude
        if curDist <= 2.8 then
            break
        end
        hum:MoveTo(targetPos)
        task.wait(0.1)
    end

    -- ยืนตรงกลางประตูพอดี
    root.CFrame = doorPart.CFrame
    task.wait(0.1)

    -- แตะ TouchInterest
    if firetouchinterest then
        pcall(function()
            firetouchinterest(root, doorPart, 0)
            task.wait(0.05)
            firetouchinterest(root, doorPart, 1)
        end)
    end

    -- หากมี Remote request_join_lobby ให้ยิงเสริมด้วย
    if doorModelName then
        pcall(function()
            local ep = getEndpoints()
            local joinRemote = ep and ep:FindFirstChild("request_join_lobby")
            if joinRemote then
                joinRemote:InvokeServer(doorModelName)
            end
        end)
    end
end

-- รักษาตำแหน่งในประตูเฉพาะตอนที่ตัวละครไหลออกห่างเกิน 3.5 studs (ไม่ยิง TouchEnded รัวๆ จนหลุดห้อง)
local function keepStandingInDoor(doorPart)
    if not doorPart then return end
    local char = getCharacter()
    local root = getRoot()
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end

    local distXZ = Vector2.new(root.Position.X - doorPart.Position.X, root.Position.Z - doorPart.Position.Z).Magnitude
    if distXZ > 3.5 then
        local targetPos = Vector3.new(doorPart.Position.X, root.Position.Y, doorPart.Position.Z)
        hum:MoveTo(targetPos)
        if distXZ > 7 then
            root.CFrame = doorPart.CFrame
        end
    end
end

local function rejoinServer()
    local TeleportService = game:GetService("TeleportService")

    pcall(function()
        local scriptCode = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/PeeKillxa/AA_Macro/main/auto_story.lua"))()'
        if typeof(queue_on_teleport) == "function" then
            queue_on_teleport(scriptCode)
        elseif typeof(syn) == "table" and typeof(syn.queue_on_teleport) == "function" then
            syn.queue_on_teleport(scriptCode)
        end
    end)

    pcall(function()
        if #Players:GetPlayers() <= 1 then
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end
    end)
end

-- ── 8. Fluent UI Creation ─────────────────────────────────────────────────────
local Window = Fluent:CreateWindow({
    Title       = "AA Auto Story Studio v2.0",
    SubTitle    = "by cook45 & clack | Overhauled Party & Solo Engine",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(590, 450),
    Acrylic     = true,
    Theme       = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})
_G.AA_AutoStoryUI = Window

local Tabs = {
    Dashboard = Window:AddTab({ Title = "Dashboard",  Icon = "home" }),
    Party     = Window:AddTab({ Title = "Party Mode", Icon = "users" }),
    Webhook   = Window:AddTab({ Title = "Webhook",    Icon = "bell" }),
    Settings  = Window:AddTab({ Title = "Settings",   Icon = "settings" })
}

Tabs.Dashboard:AddSection("⚡ LIVE PROGRESSION STATUS")

local StatusParagraph = Tabs.Dashboard:AddParagraph({
    Title   = "Current Status",
    Content = "STANDBY"
})

local TargetCard = Tabs.Dashboard:AddParagraph({
    Title   = "🎯 Target Story Level",
    Content = "Scanning progression..."
})

updateUIStatus = function(status, details)
    State.CurrentStatus = status
    local text = string.format(
        "สถานะ: %s\nโหมด: %s | ประตู: %s\nผู้เล่นในตี้: %d/%d\nจบไปแล้ว: %d ด่าน (ACT 6: %d)",
        tostring(status),
        tostring(Config.Mode),
        tostring(State.CurrentDoorName),
        tonumber(State.PartyCount) or 0,
        tonumber(Config.PartySize) or 1,
        tonumber(State.TotalRuns) or 0,
        tonumber(State.Act6ClearedCount) or 0
    )
    if details then text = text .. "\n" .. tostring(details) end
    if StatusParagraph then
        pcall(function() StatusParagraph:SetDesc(text) end)
    end
end

updateUITarget = function(target)
    if not target then
        if TargetCard then
            pcall(function() TargetCard:SetDesc("⏳ กำลังสแกนหาข้อมูลด่าน...") end)
        end
        return
    end
    if target.completed then
        if TargetCard then
            pcall(function() TargetCard:SetDesc("🏆 สตอรี่ทุกแมพเคลียร์ครบ 6/6 แล้วทั้งหมด!") end)
        end
        return
    end
    local text = string.format(
        "🗺️ แมพเป้าหมาย: %s (`%s`)\n⭐ ระดับ: Act %d / %d (%s)\n🔑 Level ID: `%s`",
        tostring(target.mapName),
        tostring(target.mapId),
        tonumber(target.act) or 1,
        tonumber(target.totalActs) or 6,
        target.isAct6 and "🔥 บอสด่านสุดท้าย ACT 6" or "Normal",
        tostring(target.levelId)
    )
    if TargetCard then
        pcall(function() TargetCard:SetDesc(text) end)
    end
end

Tabs.Dashboard:AddSection("🎮 AUTOMATION CONTROLS")

local ToggleMaster = Tabs.Dashboard:AddToggle("MasterToggle", {
    Title       = "Auto Story Progression (เปิดใช้งาน)",
    Default     = Config.Enabled,
    Description = "ค้นหาด่านล่าสุด -> เข้าประตู -> ล็อคระดับ -> ลงจนถึงด่านสุดท้ายอัตโนมัติ"
})

ToggleMaster:OnChanged(function()
    Config.Enabled = Fluent.Options.MasterToggle.Value
    saveConfig()
    updateUIStatus(Config.Enabled and "RUNNING" or "STANDBY")
end)

local ModeDropdown = Tabs.Dashboard:AddDropdown("ModeDropdown", {
    Title       = "เลือกโหมดการเล่น (Play Mode)",
    Values      = { "Solo", "Party Leader (Host)", "Party Member (Follower)" },
    Default     = Config.Mode,
    Multi       = false
})

ModeDropdown:OnChanged(function(val)
    Config.Mode = val
    saveConfig()
    updateUIStatus(State.CurrentStatus)
end)

Tabs.Dashboard:AddButton({
    Title       = "🔒 บังคับกดปุ่ม SELECT ล็อคด่าน (Force Lock Level)",
    Description = "ล็อคด่านเป้าหมายปัจจุบันผ่าน UI + Remote ทันที",
    Callback    = function()
        local target = State.TargetMapId and State.TargetMapId ~= "-" and {
            mapId   = State.TargetMapId,
            mapName = State.TargetMapName,
            act     = State.TargetAct or 1,
            levelId = State.TargetLevelId
        } or nil
        local ok, msg = lockStoryLevelInUI(target, State.CurrentDoorName ~= "-" and State.CurrentDoorName or nil)
        Fluent:Notify({
            Title    = "Force Lock Level",
            Content  = ok and ("สำเร็จ: " .. tostring(msg)) or ("ผลลัพธ์: " .. tostring(msg)),
            Duration = 3
        })
    end
})

Tabs.Dashboard:AddButton({
    Title       = "▶️ บังคับกดปุ่ม START ทันที (Force Start Match)",
    Description = "คลิกปุ่ม LevelSelectGui.Buttons.Start + ยิง Remote เริ่มแมตช์",
    Callback    = function()
        local ok, msg = pressStartMatchButton(State.CurrentDoorName ~= "-" and State.CurrentDoorName or nil)
        Fluent:Notify({
            Title    = "Force Click Start",
            Content  = ok and "กดปุ่ม START สำเร็จ!" or ("ไม่พบปุ่ม: " .. tostring(msg)),
            Duration = 3
        })
    end
})

Tabs.Dashboard:AddButton({
    Title       = "🚀 วาร์ปไปโซนเล่น (PLAY Fast Travel)",
    Description = "คลิกปุ่ม LeftUI_test.Buttons.EventTeleport เพื่อวาร์ปไปหน้าห้องสตอรี่",
    Callback    = function()
        local ok = fastTravelToPlayZone()
        Fluent:Notify({
            Title    = "PLAY Fast Travel",
            Content  = ok and "วาร์ปไปโซนประตูสตอรี่สำเร็จ!" or "ไม่พบปุ่ม LeftUI_test.Buttons.EventTeleport",
            Duration = 3
        })
    end
})

-- ── Party Mode Tab ────────────────────────────────────────────────────────────
Tabs.Party:AddSection("👥 PARTY MODE SETTINGS")

local PartySlider = Tabs.Party:AddSlider("PartySizeSlider", {
    Title    = "จำนวนผู้เล่นในปาร์ตี้ (Party Size)",
    Default  = Config.PartySize,
    Min      = 1,
    Max      = 4,
    Rounding = 0
})

PartySlider:OnChanged(function(val)
    Config.PartySize = val
    saveConfig()
end)

local LeaderInput = Tabs.Party:AddInput("LeaderInput", {
    Title       = "ชื่อ Party Leader (สำหรับลูกตี้ Follower)",
    Default     = Config.LeaderUsername,
    Placeholder = "พิมพ์ Username หรือ DisplayName ของหัวตี้...",
    Finished    = true,
    Callback    = function(val)
        Config.LeaderUsername = trim(val)
        saveConfig()
    end
})

local FriendsOnlyToggle = Tabs.Party:AddToggle("FriendsOnlyToggle", {
    Title       = "Friends Only Door (เฉพาะเพื่อนเท่านั้น)",
    Default     = Config.FriendsOnly,
    Description = "ส่งคำสั่งล็อคประตูแบบอนุญาตเฉพาะเพื่อนในเซิร์ฟเวอร์"
})

FriendsOnlyToggle:OnChanged(function()
    Config.FriendsOnly = Fluent.Options.FriendsOnlyToggle.Value
    saveConfig()
end)

-- ── Webhook Tab ───────────────────────────────────────────────────────────────
Tabs.Webhook:AddSection("🔔 DISCORD WEBHOOK")

local WebhookInput = Tabs.Webhook:AddInput("WebhookInput", {
    Title       = "Discord Webhook URL",
    Default     = Config.WebhookUrl,
    Placeholder = "https://discord.com/api/webhooks/...",
    Finished    = true,
    Callback    = function(val)
        Config.WebhookUrl = trim(val)
        saveConfig()
    end
})

local NotifyAct6Toggle = Tabs.Webhook:AddToggle("NotifyAct6Toggle", {
    Title   = "แจ้งเตือนเมื่อเคลียร์ ACT 6 สำเร็จ",
    Default = Config.NotifyAct6
})
NotifyAct6Toggle:OnChanged(function()
    Config.NotifyAct6 = Fluent.Options.NotifyAct6Toggle.Value
    saveConfig()
end)

local NotifyAllToggle = Tabs.Webhook:AddToggle("NotifyAllToggle", {
    Title   = "แจ้งเตือนเมื่อจบสตอรี่ทุกด่าน",
    Default = Config.NotifyAllCompleted
})
NotifyAllToggle:OnChanged(function()
    Config.NotifyAllCompleted = Fluent.Options.NotifyAllToggle.Value
    saveConfig()
end)

Tabs.Webhook:AddButton({
    Title       = "🧪 ทดสอบส่ง Webhook (Test Notification)",
    Description = "ส่งการ์ดทดสอบไปยัง Discord ทันที",
    Callback    = function()
        sendWebhook(
            "🧪 [Anime Adventures] Webhook Test Successful!",
            "ระบบแจ้งเตือนของสคริปต์ **AA Auto Story Studio v2.0** พร้อมใช้งานแล้ว!",
            0x00FF88,
            {
                { name = "👤 ผู้เล่น", value = "`" .. LocalPlayer.Name .. "`", inline = true },
                { name = "🎮 โหมด", value = "`" .. Config.Mode .. "`", inline = true },
                { name = "👥 ขนาดตี้", value = tostring(Config.PartySize) .. " คน", inline = true }
            }
        )
    end
})

-- ── Settings Tab ──────────────────────────────────────────────────────────────
Tabs.Settings:AddSection("⚙️ ADVANCED SETTINGS")

local SelectDelaySlider = Tabs.Settings:AddSlider("SelectDelaySlider", {
    Title    = "หน่วงเวลาก่อนกดปุ่ม Select (วินาที)",
    Default  = Config.SelectDelay or 3.5,
    Min      = 1.0,
    Max      = 6.0,
    Rounding = 1
})
SelectDelaySlider:OnChanged(function(val)
    Config.SelectDelay = val
    saveConfig()
end)

local IntervalSlider = Tabs.Settings:AddSlider("IntervalSlider", {
    Title    = "ระยะห่างการตรวจสอบลูปหลัก (วินาที)",
    Default  = Config.CheckInterval,
    Min      = 1,
    Max      = 10,
    Rounding = 1
})
IntervalSlider:OnChanged(function(val)
    Config.CheckInterval = val
    saveConfig()
end)

-- ── 9. Core Workflow Automation Engine ────────────────────────────────────────
local isProcessing = false
local doorLockFailCount = 0

local function handleLobbyProgression()
    if not Config.Enabled or isProcessing then return end

    local target, scanMsg = scanStoryProgress()
    if not target then
        updateUIStatus("SCANNING...", scanMsg)
        return
    end

    -- Case 1: All Stories Are Cleared!
    if target.completed then
        if not State.AllCompleted then
            State.AllCompleted = true
            updateUIStatus("FINISHED", "🎉 ยินดีด้วย! สตอรี่ทุกแมพเคลียร์ครบหมดแล้ว")
            updateUITarget(target)
            if Config.NotifyAllCompleted then
                sendWebhook(
                    "🎉 [Anime Adventures] เคลียร์สตอรี่ครบทุกด่านแล้ว! (All Stories Cleared)",
                    "บอททำภารกิจลงสตอรี่จนถึงด่านสุดท้ายครบทั้งหมดแล้ว และหยุดการทำงานอัตโนมัติเรียบร้อย!",
                    0xFFD700,
                    {
                        { name = "👤 ผู้เล่น", value = "`" .. LocalPlayer.Name .. "`", inline = true },
                        { name = "📊 จำนวนรอบทั้งหมด", value = tostring(State.TotalRuns) .. " รอบ", inline = true },
                        { name = "🏆 เคลียร์ ACT 6 ทั้งหมด", value = tostring(State.Act6ClearedCount) .. " แมพ", inline = true }
                    }
                )
            end
        end
        return
    end

    State.TargetMapId   = target.mapId
    State.TargetMapName = target.mapName
    State.TargetAct     = target.act
    State.TargetLevelId = target.levelId
    State.IsAct6        = target.isAct6
    updateUITarget(target)

    -- บันทึกข้อมูลด่านปัจจุบันไว้เช็คตอนกลับออกมาหน้า Lobby ว่าผ่าน ACT 6 หรือไม่
    pcall(function()
        if writefile then
            writefile(LAST_MATCH_FILE, HttpService:JSONEncode({
                mapId     = target.mapId,
                mapName   = target.mapName,
                act       = target.act,
                levelId   = target.levelId,
                isAct6    = target.isAct6,
                timestamp = os.time()
            }))
        end
    end)

    -- Case 2: Solo / Party Leader (Host) Mode
    if Config.Mode == "Solo" or Config.Mode == "Party Leader (Host)" then
        isProcessing = true

        -- 1. วาร์ปไปโซนประตูสตอรี่ถ้าอยู่ไกล
        updateUIStatus("FAST TRAVEL", "กำลังไปโซนประตูสตอรี่...")
        fastTravelToPlayZone()

        -- 2. ค้นหาประตูที่ว่าง
        updateUIStatus("SEARCHING DOOR", "กำลังหาประตูที่ว่าง (Empty)...")
        local doorInfo = findEmptyDoor()
        if not doorInfo then
            updateUIStatus("WAITING DOOR", "ประตูเต็มทุกห้อง กำลังรอห้องว่าง...")
            isProcessing = false
            return
        end

        State.CurrentDoorName = doorInfo.model.Name
        updateUIStatus("ENTERING DOOR", "กำลังเดินเข้าประตู " .. doorInfo.model.Name .. "...")

        -- 3. เดินเข้าประตู
        enterDoor(doorInfo.door, doorInfo.model.Name)
        task.wait(0.8)

        -- 4. ล็อคระดับด่าน (ผ่านทั้ง UI และ Remote request_lock_level)
        updateUIStatus("LOCKING LEVEL", string.format("กำลังล็อคด่าน %s Act %d...", target.mapName, target.act))
        for attempt = 1, 2 do
            lockStoryLevelInUI(target, doorInfo.model.Name)
            local curInfo = getDoorInfo(doorInfo.model)
            if curInfo and (curInfo.isWaiting or (#curInfo.mapText > 0 and #curInfo.lvlText > 0 and not curInfo.isSelecting)) then
                break
            end
            task.wait(0.6)
        end

        -- 5. ตรวจสอบว่าสถานะหน้าประตูเปลี่ยนเป็น "Waiting for players..." แล้วหรือยัง
        updateUIStatus("VERIFYING DOOR", "ตรวจสอบสถานะประตู (Waiting for players...)...")
        local verifiedWaiting = false
        local checkStart = tick()
        while tick() - checkStart < 6 do
            local curInfo = getDoorInfo(doorInfo.model)
            if curInfo and (curInfo.isWaiting or (#curInfo.mapText > 0 and #curInfo.lvlText > 0 and not curInfo.isSelecting and not curInfo.isEmpty)) then
                verifiedWaiting = true
                break
            end
            invokeLockDoorRemote(doorInfo.model.Name, target.levelId, Config.FriendsOnly, Config.Difficulty)
            task.wait(0.6)
        end

        if not verifiedWaiting then
            doorLockFailCount = doorLockFailCount + 1
            warn(string.format("[AutoStory] ⚠️ Door status is NOT waiting for players! Attempt %d/3", doorLockFailCount))

            if doorLockFailCount >= 3 then
                updateUIStatus("REJOINING", "ล็อคห้องไม่ผ่านครบ 3 รอบ! กำลัง Rejoin เซิร์ฟเวอร์ใหม่...")
                task.wait(1.5)
                rejoinServer()
                isProcessing = false
                return
            end

            updateUIStatus("RETRYING", string.format("ล็อคห้องไม่ติด (รอบ %d/3) ถอยออกมาตั้งหลักใหม่...", doorLockFailCount))
            local root = getRoot()
            if root and doorInfo and doorInfo.door then
                root.CFrame = doorInfo.door.CFrame * CFrame.new(0, 0, 15)
            end
            task.wait(1.8)
            isProcessing = false
            return
        end

        doorLockFailCount = 0

        -- โหมด Solo: กด START ทันที
        if Config.Mode == "Solo" then
            updateUIStatus("STARTING SOLO", "ล็อคด่านสำเร็จ! กำลังกดปุ่ม START...")
            task.wait(0.4)
            for attempt = 1, 3 do
                local ok = pressStartMatchButton(doorInfo.model.Name)
                if ok then break end
                task.wait(0.5)
            end
            updateUIStatus("TELEPORTING", "กด START เรียบร้อย กำลังรอวาร์ปเข้าด่าน...")
            task.wait(5)
            isProcessing = false
            return
        end

        -- โหมด Party Leader (Host): ยืนนิ่งๆ ในประตูรอเพื่อนครบตามจำนวน PartySize แล้วค่อยกด START
        updateUIStatus("WAITING PARTY", string.format("ล็อคด่านแล้ว รอเพื่อนเข้าประตู (1/%d คน)...", Config.PartySize))

        local waitStart = tick()
        while tick() - waitStart < Config.DoorWaitTimeout do
            if not Config.Enabled then break end
            keepStandingInDoor(doorInfo.door)

            local currentPlayers = countPlayersInDoor(doorInfo.door)
            State.PartyCount = currentPlayers
            updateUIStatus("WAITING PARTY", string.format("ล็อคด่านแล้ว รอเพื่อนร่วมตี้ (%d/%d คน)", currentPlayers, Config.PartySize))

            if currentPlayers >= Config.PartySize then
                updateUIStatus("PARTY FULL", "สมาชิกครบแล้ว! กำลังกดปุ่ม START...")
                task.wait(0.6)
                for attempt = 1, 4 do
                    keepStandingInDoor(doorInfo.door)
                    local ok = pressStartMatchButton(doorInfo.model.Name)
                    if ok then
                        print(string.format("[AutoStory] 🟢 Party full -> Triggered START (attempt #%d)", attempt))
                        break
                    end
                    task.wait(0.5)
                end
                task.wait(4)
                break
            end
            task.wait(0.6)
        end

        isProcessing = false

    -- Case 3: Party Member (Follower) Mode
    elseif Config.Mode == "Party Member (Follower)" then
        isProcessing = true

        fastTravelToPlayZone()

        updateUIStatus("CHECKING LEADER", "กำลังเช็คประตูของหัวตี้ (" .. tostring(Config.LeaderUsername) .. ")...")
        local doorInfo, statusReason = findLeaderDoor(Config.LeaderUsername, target.mapName, target.act)

        if doorInfo and doorInfo.door then
            local root = getRoot()
            if root and (root.Position - doorInfo.door.Position).Magnitude <= 10 then
                State.CurrentDoorName = doorInfo.model.Name
                updateUIStatus("IN LOBBY DOOR", "อยู่ในประตูกับหัวตี้แล้ว รอหัวตี้กดเริ่มเกม...")
                keepStandingInDoor(doorInfo.door)
                task.wait(0.8)
                isProcessing = false
                return
            end
        end

        if not doorInfo or statusReason ~= "READY" then
            if statusReason == "SELECTING" then
                updateUIStatus("LEADER SELECTING", string.format("หัวตี้อยู่ในประตู %s กำลังเลือกด่าน... ยืนรอนอกห้อง", doorInfo and doorInfo.model.Name or ""))
            elseif statusReason == "EMPTY" then
                updateUIStatus("WAITING DOOR SYNC", "หัวตี้เพิ่งเข้าประตู รอสถานะประตูอัปเดต...")
            else
                updateUIStatus("WAITING LEADER", "กำลังรอหัวตี้เดินเข้าประตูและล็อคด่าน...")
            end
            isProcessing = false
            return
        end

        State.CurrentDoorName = doorInfo.model.Name
        updateUIStatus("JOINING LEADER", "หัวตี้ล็อคด่านเสร็จแล้ว! กำลังเดินเข้า " .. doorInfo.model.Name)

        enterDoor(doorInfo.door, doorInfo.model.Name)
        keepStandingInDoor(doorInfo.door)

        updateUIStatus("IN LOBBY DOOR", "เข้าประตูหัวตี้เรียบร้อย รอหัวตี้กดเริ่มเกม...")
        task.wait(1.5)
        isProcessing = false
    end
end

-- ── 10. Lobby Return & ACT 6 Victory Verification ────────────────────────────
local function checkLastMatchOutcome()
    if not isfile or not isfile(LAST_MATCH_FILE) then return end
    local lastMatch = nil
    pcall(function()
        lastMatch = HttpService:JSONDecode(readfile(LAST_MATCH_FILE))
    end)
    if not lastMatch then return end

    if lastMatch.isAct6 and Config.NotifyAct6 then
        local isAct6NowCleared = false

        -- 1. เช็คตรงจาก Profile Memory ก่อน
        pcall(function()
            local lvlData = getProfileLevelData()
            if lvlData and lvlData.completed_story_levels and lastMatch.levelId then
                local entry = lvlData.completed_story_levels[lastMatch.levelId]
                if entry and entry.times_completed and entry.times_completed > 0 then
                    isAct6NowCleared = true
                end
            end
        end)

        -- 2. เช็คจาก allMaps ใน scanStoryProgress()
        if not isAct6NowCleared then
            local target, _ = scanStoryProgress()
            if target and target.allMaps then
                for _, m in ipairs(target.allMaps) do
                    if m.id == lastMatch.mapId and m.cleared >= (m.total or 6) then
                        isAct6NowCleared = true
                        break
                    end
                end
            end
        end

        if isAct6NowCleared then
            State.Act6ClearedCount = State.Act6ClearedCount + 1
            sendWebhook(
                "🏆 [Anime Adventures] ผ่านด่าน ACT 6 สำเร็จ!",
                string.format(
                    "🎉 **เคลียร์ด่านสุดท้ายของแมพสำเร็จแล้ว!**\n\n🗺️ **แมพ:** `%s` (`%s`)\n⭐ **ระดับ:** `Act 6 (Completed)`\n👤 **ผู้เล่น:** `%s`\n🎮 **โหมด:** `%s`",
                    tostring(lastMatch.mapName),
                    tostring(lastMatch.mapId),
                    LocalPlayer.Name,
                    Config.Mode
                ),
                0x00FF88,
                {
                    { name = "🗺️ โลก", value = tostring(lastMatch.mapName), inline = true },
                    { name = "⭐ ระดับ", value = "Act 6 (Cleared)", inline = true },
                    { name = "⏱️ เวลา", value = os.date("%H:%M:%S"), inline = true }
                }
            )
        end
    end

    pcall(function()
        if delfile then delfile(LAST_MATCH_FILE) end
    end)
end

-- ── 11. Anti-AFK & Main Lobby Loop Thread ────────────────────────────────────
pcall(function()
    local VirtualUser = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end)
end)

task.spawn(function()
    task.wait(2)
    checkLastMatchOutcome()

    while true do
        pcall(function()
            handleLobbyProgression()
        end)
        task.wait(Config.CheckInterval or 2.5)
    end
end)

print("[AA Auto Story v2.0] 🚀 Overhauled Lobby Story Engine loaded successfully!")
