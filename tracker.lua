-- ============================================================
-- 🤖 ROBLOX MULTI-ACCOUNT FARM TELEMETRY SENDER (v2.1)
-- Optimized for: Anime Adventures (Lobby + Story/Match) & All Games
-- Author: cook45 for clack (Tuned for nexuse-website.vercel.app)
-- วางสคริปต์นี้ใน Auto-Execute ของ Executor ทุกจอ
-- ============================================================

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Stats = game:GetService("Stats")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local GuiService = game:GetService("GuiService")

local API_URL = "https://nexuse-website.vercel.app/api/telemetry"
local SEND_INTERVAL = 15 -- ส่งข้อมูลทุกๆ 15 วินาที

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
if not httpRequest then
    warn("[FarmDashboard] ❌ Executor ของคุณไม่รองรับคำสั่ง http_request / request")
    return
end

local player = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ============================================================
-- 🛡️ BULLETPROOF ANTI-AFK ENGINE (ป้องกันการโดนเตะ AFK 20 นาที 100%)
-- ============================================================
pcall(function()
    player.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end)
end)

-- ส่งคลิกเสมือนทุกๆ 3 นาทีเพื่อรีเซ็ต Idle Timer ต่อเนื่อง
task.spawn(function()
    while task.wait(180) do
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end
end)

-- ============================================================
-- ⏱️ PERSISTENT BOT SESSION & WATCHDOG HEARTBEAT ENGINE
-- ============================================================
local sessionFile = string.format("bot_session_%s.json", tostring(player.UserId))
local heartbeatFile = "watchdog_heartbeat.txt"
local isKickedOrDisconnected = false
local disconnectReason = ""

-- อ่านข้อมูล Session เดิมจากเครื่อง (ถ้ามี)
-- หากสคริปต์เพิ่งถูกรันใหม่จากการ Replay, ย้ายแมพ, หรือเซิร์ฟรี ภายใน 10 นาที (600 วิ)
-- จะนับเวลา Uptime ต่อเนื่องจาก Session เดิมทันที ไม่รีเซ็ตเป็น 0!
local sessionStartTime = os.time()
local isFileSystemSupported = (writefile and readfile and isfile) and true or false

if isFileSystemSupported then
    pcall(function()
        if isfile(sessionFile) then
            local content = readfile(sessionFile)
            local data = HttpService:JSONDecode(content)
            if data and data.session_start and data.last_seen then
                local timeSinceLast = os.time() - data.last_seen
                -- ถ้าห่างจากรอบล่าสุดไม่เกิน 600 วินาที (10 นาที) ให้นับ Uptime ต่อเนื่อง
                if timeSinceLast >= 0 and timeSinceLast < 600 then
                    sessionStartTime = data.session_start
                end
            end
        end
    end)
end

-- ฟังก์ชันแจ้งเตือน Disconnect ให้ Watchdog ฝั่ง Python รู้ทันที
local function onDisconnectDetected(reason)
    if isKickedOrDisconnected then return end
    isKickedOrDisconnected = true
    disconnectReason = reason or "Roblox Disconnected / Kicked"
    warn("[AntiAFK/Watchdog] 🚨 DISCONNECT DETECTED: " .. tostring(disconnectReason))

    pcall(function()
        -- 1. ลบ Heartbeat file ทิ้งทันที! เพื่อให้ Watchdog รู้ว่าสคริปต์หยุด
        if delfile and isfile and isfile(heartbeatFile) then
            delfile(heartbeatFile)
        end
        -- 2. เขียนไฟล์แจ้งเตือน Disconnect ให้ Watchdog ฝั่ง Python อ่านและสั่งรีจอทันที
        if writefile then
            writefile("watchdog_disconnected.txt", tostring(disconnectReason))
        end
    end)
end

-- ดักจับเมื่อมี Error / Kick modal จาก GuiService
pcall(function()
    GuiService.ErrorMessageChanged:Connect(function(msg)
        if msg and #msg > 0 then
            onDisconnectDetected("GuiService: " .. msg)
        end
    end)
end)

-- ดักจับหน้าต่าง Popup เตือนหลุดทุกประเภทใน CoreGui (รวมถึง AFK 20 นาที)
pcall(function()
    local CoreGui = game:GetService("CoreGui")
    local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
    if promptGui then
        local overlay = promptGui:FindFirstChild("promptOverlay")
        if overlay then
            overlay.DescendantAdded:Connect(function(desc)
                if desc:IsA("TextLabel") or desc:IsA("TextBox") then
                    task.wait(0.2)
                    local txt = desc.Text:lower()
                    if txt:find("idle") or txt:find("kick") or txt:find("disconnect") or txt:find("error") or txt:find("lost connection") then
                        onDisconnectDetected("PromptModal: " .. desc.Text)
                    end
                end
            end)
        end
    end
end)

-- ฟังก์ชันอัปเดต Heartbeat สื่อสารกับ Watchdog CMD และบันทึก Session
local function pulseHeartbeat()
    if not isFileSystemSupported or isKickedOrDisconnected then return end
    pcall(function()
        -- 1. Heartbeat สำหรับ Watchdog เช็คสถานะตัวรันใน Android
        writefile(heartbeatFile, tostring(os.time()))
        -- 2. บันทึก Session Uptime สะสม ไม่ให้เวลารีตอน Replay / Server Hop
        writefile(sessionFile, HttpService:JSONEncode({
            user_id = player.UserId,
            session_start = sessionStartTime,
            last_seen = os.time()
        }))
    end)
end

-- ส่ง Heartbeat ครั้งแรกทันทีที่โหลดสคริปต์ติด
pulseHeartbeat()

-- ส่ง Heartbeat สม่ำเสมอทุกๆ 5 วินาทีใน background thread
task.spawn(function()
    while task.wait(5) do
        if not isKickedOrDisconnected then
            pulseHeartbeat()
        end
    end
end)

-- ตัวแปรเก็บค่าล่าสุด (ป้องกันค่าเพชร/เวลกลายเป็น 0 หรือ 1 ตอนกำลังโหลดห้อง Replay)
local cached_level = 1
local cached_gems = 0
local cached_gold = 0
local cached_rerolls = 0

-- ดึงชื่อแมพเกมอัตโนมัติ
local gameName = "Roblox Game"
pcall(function()
    local info = MarketplaceService:GetProductInfo(game.PlaceId)
    if info and info.Name then gameName = info.Name end
end)

-- ฟังก์ชันคำนวณ FPS ปัจจุบัน
local currentFps = 60
RunService.RenderStepped:Connect(function(dt)
    if dt > 0 then
        currentFps = math.clamp(math.floor(1 / dt), 1, 240)
    end
end)

-- Helper: แปลงข้อความตัวเลขที่มี comma เช่น "85,400" หรือ "12.5K" เป็น number แท้
local function parseNumber(val)
    if typeof(val) == "number" then return val end
    if typeof(val) ~= "string" then return 0 end
    
    local clean = val:gsub(",", ""):gsub("%s+", ""):upper()
    local multiplier = 1
    if clean:find("K") then
        multiplier = 1000
        clean = clean:gsub("K", "")
    elseif clean:find("M") then
        multiplier = 1000000
        clean = clean:gsub("M", "")
    elseif clean:find("B") then
        multiplier = 1000000000
        clean = clean:gsub("B", "")
    end
    
    local num = tonumber(clean:match("%d+%.?%d*"))
    return num and (num * multiplier) or 0
end

-- Helper: สกัดตัวเลขเลเวลโดยเฉพาะ เช่น "Level 7 [18/142]" -> 7
local function parseLevel(val)
    if typeof(val) == "number" then return val end
    if typeof(val) ~= "string" then return nil end
    local clean = val:gsub("%s+", " ")
    -- หาตัวเลขหลังคำว่า Level / Lvl / Lv ก่อนอันดับแรก (เช่น "Level 7 [18/142]")
    local num = clean:match("[Ll]ev?e?l?%s*[:.]?%s*(%d+)") or clean:match("(%d+)")
    return num and tonumber(num) or nil
end

-- Helper: สแกนหาตัวเลขใน PlayerGui
local function findGuiStat(pattern)
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil end
    for _, obj in ipairs(pg:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextBox")) and obj.Visible then
            local objName = obj.Name:lower()
            local parentName = obj.Parent and obj.Parent.Name:lower() or ""
            if objName:find(pattern) or parentName:find(pattern) then
                local val = parseNumber(obj.Text)
                if val > 0 then return val end
            end
        end
    end
    return nil
end

-- ฟังก์ชันดึงค่า Gems / Gold / Level แบบละเอียด (รองรับทั้ง Lobby และห้องเล่น Story/Match)
local function getGameStats()
    local stats = {
        gems = 0,
        gold = 0,
        level = 0,
        rerolls = 0
    }

    local pg = player:FindFirstChild("PlayerGui")
    if pg then
        -- 1. ตรวจสอบ Level จากหน้าต่างในห้องเล่น Story / Match:
        -- Path ตรง: PlayerGui.spawn_units.Lives.Main.Desc.Level (Text: "Level 7 [18/142]")
        pcall(function()
            local su = pg:FindFirstChild("spawn_units")
            if su then
                local lvlObj = su:FindFirstChild("Lives") 
                    and su.Lives:FindFirstChild("Main") 
                    and su.Lives.Main:FindFirstChild("Desc") 
                    and su.Lives.Main.Desc:FindFirstChild("Level")
                
                if lvlObj and (lvlObj:IsA("TextLabel") or lvlObj:IsA("TextBox")) then
                    local lvl = parseLevel(lvlObj.Text)
                    if lvl and lvl > 0 then
                        stats.level = lvl
                    end
                end
            end
        end)

        -- 2. ตรวจสอบ UI หน้ารวมตอนอยู่ใน Lobby (Spawn UI)
        pcall(function()
            local spawnGui = pg:FindFirstChild("Spawn") and pg.Spawn:FindFirstChild("Main")
            if spawnGui then
                local top = spawnGui:FindFirstChild("Main") and spawnGui.Main:FindFirstChild("Top")
                if top then
                    if top:FindFirstChild("Gems") and top.Gems:FindFirstChild("Amount") then
                        stats.gems = parseNumber(top.Gems.Amount.Text)
                    end
                    if top:FindFirstChild("Gold") and top.Gold:FindFirstChild("Amount") then
                        stats.gold = parseNumber(top.Gold.Amount.Text)
                    end
                    if stats.level == 0 and top:FindFirstChild("Level") and top.Level:FindFirstChild("Amount") then
                        local lvl = parseLevel(top.Level.Amount.Text)
                        if lvl and lvl > 0 then stats.level = lvl end
                    end
                end
            end
        end)

        -- 3. ตรวจ Collection UI (หน้าดูของ/เพชร)
        if stats.gems == 0 then
            pcall(function()
                local collection = pg:FindFirstChild("Collection") and pg.Collection:FindFirstChild("Main")
                if collection and collection:FindFirstChild("Currency") then
                    local curr = collection.Currency
                    if curr:FindFirstChild("Gems") and curr.Gems:FindFirstChild("Amount") then
                        stats.gems = parseNumber(curr.Gems.Amount.Text)
                    end
                    if curr:FindFirstChild("Gold") and curr.Gold:FindFirstChild("Amount") then
                        stats.gold = parseNumber(curr.Gold.Amount.Text)
                    end
                end
            end)
        end

        -- 4. ตรวจสอบลึกลงไปใน spawn_units กรณีโครงสร้างลูกเปลี่ยนตำแหน่ง
        if stats.level == 0 and pg:FindFirstChild("spawn_units") then
            pcall(function()
                for _, obj in ipairs(pg.spawn_units:GetDescendants()) do
                    if obj.Name == "Level" and (obj:IsA("TextLabel") or obj:IsA("TextBox")) and obj.Visible then
                        local lvl = parseLevel(obj.Text)
                        if lvl and lvl > 0 then
                            stats.level = lvl
                            break
                        end
                    end
                end
            end)
        end
    end

    -- 5. ตรวจสอบผ่าน leaderstats, Stats, Data, PlayerData (สำหรับเกมทั่วไป)
    for _, folderName in ipairs({"leaderstats", "Stats", "Data", "PlayerData", "_stats"}) do
        local folder = player:FindFirstChild(folderName)
        if folder then
            for _, item in ipairs(folder:GetChildren()) do
                local name = item.Name:lower()
                if stats.gems == 0 and (name:find("gem") or name:find("diamond") or name:find("jewel") or name:find("emerald")) then
                    stats.gems = parseNumber(item.Value)
                elseif stats.gold == 0 and (name:find("gold") or name:find("coin") or name:find("cash") or name:find("yen") or name:find("beli")) then
                    stats.gold = parseNumber(item.Value)
                elseif stats.level == 0 and (name:find("level") or name:find("lvl") or name:find("lv")) then
                    stats.level = parseLevel(item.Value) or 0
                elseif stats.rerolls == 0 and (name:find("reroll") or name:find("spin")) then
                    stats.rerolls = parseNumber(item.Value)
                end
            end
        end
    end

    -- 6. ตรวจสอบผ่าน Player Attributes
    if stats.gems == 0 then
        for _, attr in ipairs({"Gems", "Gem", "Diamonds"}) do
            local v = player:GetAttribute(attr)
            if v ~= nil then stats.gems = parseNumber(v) break end
        end
    end
    if stats.gold == 0 then
        for _, attr in ipairs({"Gold", "Coins", "Cash", "Yen"}) do
            local v = player:GetAttribute(attr)
            if v ~= nil then stats.gold = parseNumber(v) break end
        end
    end
    if stats.level == 0 then
        for _, attr in ipairs({"Level", "Lvl", "Lv"}) do
            local v = player:GetAttribute(attr)
            if v ~= nil then stats.level = parseLevel(v) or 0 break end
        end
    end

    -- 7. Smart UI Fallback Scanner
    if stats.gems == 0 then
        stats.gems = findGuiStat("gem") or 0
    end
    if stats.gold == 0 then
        stats.gold = findGuiStat("gold") or findGuiStat("coin") or 0
    end

    -- 8. Anti-Flicker Caching: ถ้ากำลังโหลดห้องแล้วหาค่าไม่เจอ ให้จำค่าล่าสุดไว้เสมอ
    if stats.level > 0 then
        cached_level = stats.level
    else
        stats.level = cached_level
    end

    if stats.gems > 0 then
        cached_gems = stats.gems
    else
        stats.gems = cached_gems
    end

    if stats.gold > 0 then
        cached_gold = stats.gold
    else
        stats.gold = cached_gold
    end

    if stats.rerolls > 0 then
        cached_rerolls = stats.rerolls
    else
        stats.rerolls = cached_rerolls
    end

    return stats
end

-- ฟังก์ชันส่ง Telemetry เข้าเว็บ Vercel
local function sendTelemetry(customStatus)
    local pingMs = 50
    pcall(function()
        local item = Stats.Network.ServerStatsItem["Data Ping"]
        if item then pingMs = math.floor(item:GetValue()) end
    end)

    local gameStats = getGameStats()

    local payload = {
        user_id = player.UserId,
        username = player.Name,
        display_name = player.DisplayName,
        avatar_url = string.format(
            "https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=150&height=150&format=png",
            player.UserId
        ),
        account_age = player.AccountAge,
        game_name = gameName,
        place_id = game.PlaceId,
        job_id = (game.JobId ~= "" and game.JobId) or "private-server",
        status = isKickedOrDisconnected and "OFFLINE" or (customStatus or "ONLINE"),
        level = gameStats.level,
        gems = gameStats.gems,
        gold = gameStats.gold,
        extra_stats = {
            rerolls = gameStats.rerolls
        },
        ping = pingMs,
        fps = currentFps,
        uptime_seconds = os.time() - sessionStartTime,
        updated_at = os.time()
    }

    pulseHeartbeat()

    pcall(function()
        httpRequest({
            Url = API_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["User-Agent"] = "RobloxTelemetry/2.2"
            },
            Body = HttpService:JSONEncode(payload)
        })
    end)
end

-- หมายเหตุ: ไม่ผูก PlayerRemoving ด้วย OFFLINE อีกต่อไป เพื่อไม่ให้หน้าเว็บเด้งเป็น Offline ตอนกด Replay หรือย้ายห้อง
-- ฝั่ง Vercel Server มีระบบ timeout 60 วินาทีอยู่แล้ว ถ้าเกมดับจริงเว็บจะขึ้น Offline ให้เองตามธรรมชาติ

-- ส่งครั้งแรกทันที
task.spawn(function()
    task.wait(2) -- รอ GUI สร้างตัว
    sendTelemetry()
    print("[FarmDashboard] ✅ Telemetry Connected -> " .. API_URL)

    -- วนลูปส่งต่อเนื่องทุก 15 วินาที
    while task.wait(SEND_INTERVAL) do
        sendTelemetry()
    end
end)
