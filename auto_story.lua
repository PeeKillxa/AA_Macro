-- ==============================================================================
-- ⚔️ ANIME ADVENTURES AUTO STORY PROGRESSION & PARTY ENGINE (v1.0)
-- Developed by: cook45 & clack
-- File: AA_Macro/auto_story.lua
-- Features:
--   • Auto latest story level detection (Maps & Act 1 to 6)
--   • Party Mode Support (Host / Leader & Member / Follower & Solo)
--   • Discord Webhook Notifications (Act 6 Completed & All Stories Finished)
--   • Modern Fluent UI with Live Dashboard & Persistent JSON Config
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
-- ตรวจสอบว่าอยู่ใน Lobby หรือไม่ (PlaceId: 8304191830 หรือมีโฟลเดอร์ _LOBBIES.Story)
-- ถ้าอยู่ในด่านเล่นเกม (Match / Game) สคริปต์จะหยุดการทำงานทันที (ไม่เปิด UI, ไม่รันในแมพ)
local function isLobby()
    if game.PlaceId == LOBBY_PLACE_ID then return true end
    if Workspace:FindFirstChild("_LOBBIES") and Workspace._LOBBIES:FindFirstChild("Story") then
        return true
    end
    return false
end

if not isLobby() then
    print("[AA Auto Story] 🛑 Not in Lobby (PlaceId: " .. tostring(game.PlaceId) .. "). Script will ONLY run in Lobby!")
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

-- ── 2. Config & State Management ──────────────────────────────────────────────
local CONFIG_FILE = "auto_story_config.json"
local LAST_MATCH_FILE = "last_story_match.json"

local Config = {
    Enabled            = false,
    Mode               = "Solo",        -- "Solo", "Party Leader (Host)", "Party Member (Follower)"
    PartySize          = 2,             -- Target party member count
    LeaderUsername     = "",            -- For Party Member to track & follow
    FriendsOnly        = false,         -- Door locks only for friends
    Difficulty         = "Normal",      -- "Normal" for Story progression
    WebhookUrl         = "https://discord.com/api/webhooks/1564605032517869601/JFLes7jR2Z44H3vDdnZ10GmBKn-qTd0JOibxDNGuRh3L9U74c3a4SLiAATfvZYV893CQ",
    NotifyAct6         = true,
    NotifyAllCompleted = true,
    AutoReplayOrNext   = true,
    CheckInterval      = 3.0,
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
    InGame             = (game.PlaceId ~= LOBBY_PLACE_ID),
}

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
                            text = "AA Auto Story Studio • Developed by cook45 & clack",
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

-- ── 4. Character & Spatial Helpers ───────────────────────────────────────────
local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getRoot()
    local char = getCharacter()
    return char and (char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5))
end

local function teleportTo(cf)
    local root = getRoot()
    if root then
        root.CFrame = cf
        task.wait(0.1)
    end
end

-- ── 5. Story Progress Scanner (DOM UI Inspector) ──────────────────────────────
local function getLevelSelectContainer()
    local pGui = LocalPlayer:WaitForChild("PlayerGui", 10)
    if not pGui then return nil end
    local lvlGui = pGui:FindFirstChild("LevelSelectGui")
    if not lvlGui then return nil end
    local mapSelect = lvlGui:FindFirstChild("MapSelect")
    local main = mapSelect and mapSelect:FindFirstChild("Main")
    local wrapper = main and main:FindFirstChild("Wrapper")
    return wrapper and wrapper:FindFirstChild("Container")
end

local function scanStoryProgress()
    local container = getLevelSelectContainer()
    if not container then
        return nil, "Waiting for LevelSelectGui.MapSelect.Main.Wrapper.Container..."
    end

    local maps = {}
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("GuiObject") and child:FindFirstChild("Main") then
            local mapId = child.Name
            local main = child.Main
            local mapContainer = main:FindFirstChild("Container")
            local mapNameLabel = mapContainer and mapContainer:FindFirstChild("MapName")
            local mapName = mapNameLabel and (mapNameLabel:IsA("TextLabel") and mapNameLabel.Text or mapNameLabel.Value) or mapId

            local lockedObj = main:FindFirstChild("Locked") and main.Locked:FindFirstChild("locked")
            local isLocked = lockedObj and lockedObj.Visible or false

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

    table.sort(maps, function(a, b) return a.order < b.order end)

    if #maps == 0 then
        return nil, "Container has no map objects"
    end

    -- Find first unlocked map that is not fully cleared
    for _, m in ipairs(maps) do
        if not m.isLocked then
            if m.cleared < m.total then
                local nextAct = m.cleared + 1
                local levelId = string.format("%s_level_%d", m.id, nextAct)
                return {
                    completed      = false,
                    mapId          = m.id,
                    mapName        = m.name,
                    act            = nextAct,
                    totalActs      = m.total,
                    cleared        = m.cleared,
                    levelId        = levelId,
                    isAct6         = (nextAct == m.total),
                    allMaps        = maps
                }, "Found Next Story Level"
            end
        end
    end

    -- All unlocked maps are cleared!
    return {
        completed = true,
        allMaps   = maps
    }, "All Available Stories Completed!"
end

-- ── 6. Lobby Door Inspector & Controller ──────────────────────────────────────
local function getStoryLobbies()
    local lobbies = Workspace:FindFirstChild("_LOBBIES")
    return lobbies and lobbies:FindFirstChild("Story")
end

local function getDoorInfo(doorModel)
    local door = doorModel:FindFirstChild("Door")
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

    return {
        model      = doorModel,
        door       = door,
        cframe     = door.CFrame,
        statusText = statusText,
        mapText    = mapText,
        lvlText    = lvlText,
        diffText   = diffText,
        isEmpty    = (statusText == "Empty" or statusText:lower():find("empty") ~= nil),
        isWaiting  = (statusText == "Waiting for players..." or statusText:lower():find("waiting") ~= nil),
        isSelecting= (statusText == "Selecting..." or statusText:lower():find("selecting") ~= nil),
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

local function findLeaderDoor(leaderName, targetMapName, targetAct)
    local story = getStoryLobbies()
    if not story then return nil end

    -- 1. Scan by Leader Position if leader is in server
    local leaderPlayer = leaderName and #leaderName > 0 and Players:FindFirstChild(leaderName)
    local leaderHrp = leaderPlayer and leaderPlayer.Character and leaderPlayer.Character:FindFirstChild("HumanoidRootPart")

    if leaderHrp then
        for _, doorModel in ipairs(story:GetChildren()) do
            local info = getDoorInfo(doorModel)
            if info and (info.door.Position - leaderHrp.Position).Magnitude <= 14 then
                return info
            end
        end
    end

    -- 2. Fallback scan by Door Surface GUI (MapName and Act)
    local actPattern = "act " .. tostring(targetAct)
    for _, doorModel in ipairs(story:GetChildren()) do
        local info = getDoorInfo(doorModel)
        if info and info.isWaiting then
            local mapMatch = (targetMapName and info.mapText:lower():find(targetMapName:lower()) ~= nil)
            local actMatch = (info.lvlText:lower():find(actPattern) ~= nil)
            if mapMatch and actMatch then
                return info
            end
        end
    end

    return nil
end

local function lockDoorLevel(doorModelName, levelId, friendsOnly, difficulty)
    local remote = ReplicatedStorage:FindFirstChild("endpoints")
        and ReplicatedStorage.endpoints:FindFirstChild("client_to_server")
        and ReplicatedStorage.endpoints.client_to_server:FindFirstChild("request_lock_level")

    if remote then
        local success, err = pcall(function()
            remote:InvokeServer(doorModelName, levelId, friendsOnly, difficulty or "Normal")
        end)
        return success, err
    end
    return false, "Remote endpoints.client_to_server.request_lock_level not found"
end

-- ── 7. Fluent UI Creation ─────────────────────────────────────────────────────
local Window = Fluent:CreateWindow({
    Title       = "AA Auto Story Studio",
    SubTitle    = "by cook45 & clack | Party & Solo Edition",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(590, 440),
    Acrylic     = true,
    Theme       = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})
_G.AA_AutoStoryUI = Window

local Tabs = {
    Dashboard = Window:AddTab({ Title = "Dashboard", Icon = "home" }),
    Party     = Window:AddTab({ Title = "Party Mode", Icon = "users" }),
    Webhook   = Window:AddTab({ Title = "Webhook",    Icon = "bell" }),
    Settings  = Window:AddTab({ Title = "Settings",   Icon = "settings" })
}

-- ── Dashboard Tab ─────────────────────────────────────────────────────────────
Tabs.Dashboard:AddSection("⚡ LIVE PROGRESSION STATUS")

local StatusParagraph = Tabs.Dashboard:AddParagraph({
    Title   = "Current Status",
    Content = "STANDBY"
})

local TargetCard = Tabs.Dashboard:AddParagraph({
    Title   = "🎯 Target Story Level",
    Content = "Scanning progression..."
})

local function updateUIStatus(status, details)
    State.CurrentStatus = status
    local text = string.format("สถานะ: %s\nโหมด: %s | ประตู: %s\nผู้เล่นในตี้: %d/%d\nจบไปแล้ว: %d ด่าน (ACT 6: %d)",
        status, Config.Mode, State.CurrentDoorName, State.PartyCount, Config.PartySize, State.TotalRuns, State.Act6ClearedCount)
    if details then text = text .. "\n" .. details end
    if StatusParagraph then StatusParagraph:SetDesc(text) end
end

local function updateUITarget(target)
    if not target then
        if TargetCard then TargetCard:SetDesc("✅ เคลียร์สตอรี่ครบทุกด่านแล้ว! (All Stories Cleared)") end
        return
    end
    if target.completed then
        if TargetCard then TargetCard:SetDesc("🏆 สตอรี่ทุกแมพเคลียร์ครบ 6/6 แล้วทั้งหมด!") end
        return
    end
    local text = string.format("🗺️ แมพเป้าหมาย: %s (`%s`)\n⭐ ระดับ: Act %d / %d (%s)\n🔑 Level ID: `%s`",
        target.mapName, target.mapId, target.act, target.totalActs, target.isAct6 and "🔥 บอสด่านสุดท้าย ACT 6" or "Normal", target.levelId)
    if TargetCard then TargetCard:SetDesc(text) end
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
    Placeholder = "พิมพ์ Username ของหัวตี้...",
    Finished    = true,
    Callback    = function(val)
        Config.LeaderUsername = val:strip()
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
        Config.WebhookUrl = val:strip()
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
            "ระบบแจ้งเตือนของสคริปต์ **AA Auto Story Studio** พร้อมใช้งานแล้ว!",
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

local IntervalSlider = Tabs.Settings:AddSlider("IntervalSlider", {
    Title    = "ระยะห่างการตรวจสอบ (วินาที)",
    Default  = Config.CheckInterval,
    Min      = 1,
    Max      = 10,
    Rounding = 1
})
IntervalSlider:OnChanged(function(val)
    Config.CheckInterval = val
    saveConfig()
end)

-- ── 8. Core Workflow Automation Engine ────────────────────────────────────────

local isProcessing = false

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

    -- Save state for match reporting
    pcall(function()
        if writefile then
            writefile(LAST_MATCH_FILE, HttpService:JSONEncode({
                mapId     = target.mapId,
                mapName   = target.mapName,
                act       = target.act,
                isAct6    = target.isAct6,
                timestamp = os.time()
            }))
        end
    end)

    -- Case 2: Solo / Host Mode
    if Config.Mode == "Solo" or Config.Mode == "Party Leader (Host)" then
        isProcessing = true
        updateUIStatus("SEARCHING DOOR", "กำลังหาประตูที่ว่าง (Empty)...")

        local doorInfo = findEmptyDoor()
        if not doorInfo then
            updateUIStatus("WAITING DOOR", "ประตูเต็ม กำลังรอห้องว่าง...")
            isProcessing = false
            return
        end

        State.CurrentDoorName = doorInfo.model.Name
        updateUIStatus("ENTERING DOOR", "เดินเข้าประตู " .. doorInfo.model.Name)

        -- Teleport inside door
        teleportTo(doorInfo.cframe * CFrame.new(0, 0, -2))
        if firetouchinterest then
            firetouchinterest(getRoot(), doorInfo.door, 0)
            task.wait(0.05)
            firetouchinterest(getRoot(), doorInfo.door, 1)
        end
        task.wait(1.5)

        -- Lock the target story level
        updateUIStatus("LOCKING LEVEL", string.format("ล็อค %s Act %d", target.mapName, target.act))
        local locked, err = lockDoorLevel(doorInfo.model.Name, target.levelId, Config.FriendsOnly, Config.Difficulty)

        if not locked then
            warn("[AutoStory] Lock failed: " .. tostring(err))
        end

        -- If Solo Mode, let timer count down and start
        if Config.Mode == "Solo" then
            updateUIStatus("READY", "ล็อคด่านเรียบร้อย กำลังรอเทเลพอร์ตเข้าแมพ...")
            task.wait(5)
            isProcessing = false
            return
        end

        -- If Party Leader Mode: wait for party members
        local waitStart = tick()
        while tick() - waitStart < Config.DoorWaitTimeout do
            local currentPlayers = countPlayersInDoor(doorInfo.door)
            State.PartyCount = currentPlayers
            updateUIStatus("WAITING PARTY", string.format("รอเพื่อนร่วมตี้ (%d/%d คน)", currentPlayers, Config.PartySize))

            if currentPlayers >= Config.PartySize then
                updateUIStatus("PARTY FULL", "สมาชิกครบแล้ว! รอตัวเกมเริ่มต้น...")
                task.wait(3)
                break
            end
            task.wait(1.5)
        end

        isProcessing = false

    -- Case 3: Party Member (Follower) Mode
    elseif Config.Mode == "Party Member (Follower)" then
        isProcessing = true
        updateUIStatus("SEARCHING LEADER", "กำลังหาประตูของหัวตี้ (" .. tostring(Config.LeaderUsername) .. ")...")

        local doorInfo = findLeaderDoor(Config.LeaderUsername, target.mapName, target.act)
        if not doorInfo then
            updateUIStatus("WAITING LEADER", "ยังไม่พบประตูหัวตี้ รอหัวตี้เลือกห้อง...")
            isProcessing = false
            return
        end

        State.CurrentDoorName = doorInfo.model.Name
        updateUIStatus("JOINING LEADER", "พบประตูแล้ว กำลังเดินเข้า " .. doorInfo.model.Name)

        -- Teleport inside the door with the party
        teleportTo(doorInfo.cframe * CFrame.new(0, 0, -2))
        if firetouchinterest then
            firetouchinterest(getRoot(), doorInfo.door, 0)
            task.wait(0.05)
            firetouchinterest(getRoot(), doorInfo.door, 1)
        end

        updateUIStatus("IN LOBBY DOOR", "อยู่ในประตูเรียบร้อย รอด่านเริ่มพร้อมตี้...")
        task.wait(4)
        isProcessing = false
    end
end

-- ── 9. Lobby Return & ACT 6 Victory Verification ─────────────────────────────
local function checkLastMatchOutcome()
    if not isfile or not isfile(LAST_MATCH_FILE) then return end
    local lastMatch = nil
    pcall(function()
        lastMatch = HttpService:JSONDecode(readfile(LAST_MATCH_FILE))
    end)
    if not lastMatch then return end

    -- ตรวจสอบว่าด่านที่เพิ่งเล่นไปคือ ACT 6 หรือไม่
    if lastMatch.isAct6 and Config.NotifyAct6 then
        local target, _ = scanStoryProgress()
        if target and target.allMaps then
            for _, m in ipairs(target.allMaps) do
                -- ถ้าแมพเป้าหมายเดิมตอนนี้ขึ้นเคลียร์ครบ 6/6 แล้ว แสดงว่าเพิ่งชนะ ACT 6 สดๆ ร้อนๆ!
                if m.id == lastMatch.mapId and m.cleared >= 6 then
                    State.Act6ClearedCount = State.Act6ClearedCount + 1
                    sendWebhook(
                        "🏆 [Anime Adventures] ผ่านด่าน ACT 6 สำเร็จ!",
                        string.format("🎉 **เคลียร์ด่านสุดท้ายของแมพสำเร็จแล้ว!**\n\n🗺️ **แมพ:** `%s` (`%s`)\n⭐ **ระดับ:** `Act 6 (Completed)`\n👤 **ผู้เล่น:** `%s`\n🎮 **โหมด:** `%s`",
                            lastMatch.mapName, lastMatch.mapId, LocalPlayer.Name, Config.Mode),
                        0x00FF88,
                        {
                            { name = "🗺️ โลก", value = lastMatch.mapName, inline = true },
                            { name = "⭐ ระดับ", value = "Act 6 (Cleared)", inline = true },
                            { name = "⏱️ เวลา", value = os.date("%H:%M:%S"), inline = true }
                        }
                    )
                    break
                end
            end
        end
    end
    -- ลบไฟล์บันทึกสถานะรอบก่อน เพื่อไม่ให้แจ้งเตือนซ้ำ
    pcall(function() if delfile then delfile(LAST_MATCH_FILE) end end)
end

-- ── 10. Main Lobby Loop Thread ────────────────────────────────────────────────
task.spawn(function()
    -- รอให้ UI ในล็อบบี้โหลดสมบูรณ์
    task.wait(2)
    checkLastMatchOutcome()

    while true do
        pcall(function()
            handleLobbyProgression()
        end)
        task.wait(Config.CheckInterval or 3.0)
    end
end)

print("[AA Auto Story] 🚀 Lobby Story Engine loaded successfully!")
