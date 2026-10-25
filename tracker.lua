-- ============================================================
-- 🤖 ROBLOX MULTI-ACCOUNT FARM TELEMETRY SENDER (v2.0)
-- Optimized for: Anime Adventures & All Roblox Games
-- Author: cook45 for clack (Tuned for nexuse-website.vercel.app)
-- วางสคริปต์นี้ใน Auto-Execute ของ Executor ทุกจอ
-- ============================================================

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Stats = game:GetService("Stats")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local API_URL = "https://nexuse-website.vercel.app/api/telemetry"
local SEND_INTERVAL = 15 -- ส่งข้อมูลทุกๆ 15 วินาที
local startTime = os.time()

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
if not httpRequest then
    warn("[FarmDashboard] ❌ Executor ของคุณไม่รองรับคำสั่ง http_request / request")
    return
end

local player = Players.LocalPlayer or Players.PlayerAdded:Wait()

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

-- Helper: สแกนหาตัวเลขใน PlayerGui (สำหรับ Anime Adventures และเกมที่ไม่มีใน leaderstats)
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

-- ฟังก์ชันดึงค่า Gems / Gold / Level แบบละเอียด (รองรับทั้ง UI Anime Adventures + leaderstats + Attributes)
local function getGameStats()
    local stats = {
        gems = 0,
        gold = 0,
        level = 1,
        rerolls = 0
    }

    -- 1. ตรวจสอบ UI เฉพาะของ Anime Adventures (แม่นยำ 100%)
    local pg = player:FindFirstChild("PlayerGui")
    if pg then
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
                    if top:FindFirstChild("Level") and top.Level:FindFirstChild("Amount") then
                        stats.level = parseNumber(top.Level.Amount.Text)
                    end
                end
            end
        end)

        -- ตรวจ Collection UI (หน้าดูของ/เพชร)
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
    end

    -- 2. ตรวจสอบผ่าน leaderstats, Stats, Data, PlayerData (สำหรับเกมทั่วไป)
    for _, folderName in ipairs({"leaderstats", "Stats", "Data", "PlayerData", "_stats"}) do
        local folder = player:FindFirstChild(folderName)
        if folder then
            for _, item in ipairs(folder:GetChildren()) do
                local name = item.Name:lower()
                if stats.gems == 0 and (name:find("gem") or name:find("diamond") or name:find("jewel") or name:find("emerald")) then
                    stats.gems = parseNumber(item.Value)
                elseif stats.gold == 0 and (name:find("gold") or name:find("coin") or name:find("cash") or name:find("yen") or name:find("beli")) then
                    stats.gold = parseNumber(item.Value)
                elseif stats.level <= 1 and (name:find("level") or name:find("lvl") or name:find("lv")) then
                    stats.level = parseNumber(item.Value)
                elseif stats.rerolls == 0 and (name:find("reroll") or name:find("spin")) then
                    stats.rerolls = parseNumber(item.Value)
                end
            end
        end
    end

    -- 3. ตรวจสอบผ่าน Player Attributes
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
    if stats.level <= 1 then
        for _, attr in ipairs({"Level", "Lvl", "Lv"}) do
            local v = player:GetAttribute(attr)
            if v ~= nil then stats.level = parseNumber(v) break end
        end
    end

    -- 4. Smart UI Fallback Scanner (กรณีเกมซ่อนค่าไว้ใน GUI ตัวอื่น)
    if stats.gems == 0 then
        stats.gems = findGuiStat("gem") or 0
    end
    if stats.gold == 0 then
        stats.gold = findGuiStat("gold") or findGuiStat("coin") or 0
    end
    if stats.level <= 1 then
        stats.level = findGuiStat("level") or findGuiStat("lvl") or 1
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
        status = customStatus or "ONLINE",
        level = gameStats.level,
        gems = gameStats.gems,
        gold = gameStats.gold,
        extra_stats = {
            rerolls = gameStats.rerolls
        },
        ping = pingMs,
        fps = currentFps,
        uptime_seconds = os.time() - startTime,
        updated_at = os.time()
    }

    local success, res = pcall(function()
        return httpRequest({
            Url = API_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["User-Agent"] = "RobloxTelemetry/2.0"
            },
            Body = HttpService:JSONEncode(payload)
        })
    end)

    if success and res then
        -- Optional: print debug log
        -- print(string.format("[FarmDashboard] Sent -> Gems: %d | Level: %d (Code: %s)", payload.gems, payload.level, tostring(res.StatusCode)))
    end
end

-- แจ้งสถานะ OFFLINE ทันทีเมื่อผู้เล่นออกจากเกม / หลุด
Players.PlayerRemoving:Connect(function(plr)
    if plr == player then
        pcall(function()
            sendTelemetry("OFFLINE")
        end)
    end
end)

-- ส่งครั้งแรกทันที
task.spawn(function()
    task.wait(3) -- รอ GUI และ Asset ในเกมโหลดครบ
    sendTelemetry()
    print("[FarmDashboard] ✅ Telemetry Connected -> " .. API_URL)

    -- วนลูปส่งต่อเนื่องทุก 15 วินาที
    while task.wait(SEND_INTERVAL) do
        sendTelemetry()
    end
end)
