--[[
    ═══════════════════════════════════════════════════════════
    ⚡ AA MACRO STUDIO v2.0 — UNIVERSAL CLOUD LOADER
    ═══════════════════════════════════════════════════════════
    • ตรวจสอบ PlaceId: หากอยู่ใน Lobby (8304191830) จะไม่รันสคริปต์ต่อสู้ เพื่อความปลอดภัย
    • ตรวจจับ VoteStart: ในแมพต่อสู้ จะรอจนกว่า VoteStart จะขึ้น หากไม่ขึ้นจะไม่รัน
    • ทุกครั้งที่เปิด จะดึงโค้ดเวอร์ชันล่าสุดจาก GitHub อัตโนมัติ
    • บันทึกลงเครื่องให้อัตโนมัติ รองรับ Auto Execute ข้ามห้อง
--]]

-- ── 1. รอให้ตัวเกมโหลดเสร็จสมบูรณ์ ─────────────────────────
if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- ── 2. ตรวจสอบสถานที่ (Lobby vs Combat Map) ────────────────
local LOBBY_PLACE_ID = 8304191830
local currentPlaceId = game.PlaceId

if currentPlaceId == LOBBY_PLACE_ID then
    print("[AA Macro] 🏠 ตรวจพบว่าอยู่ใน Lobby (PlaceId: " .. tostring(currentPlaceId) .. ")")
    print("[AA Macro] 🛡️ ข้ามการรันสคริปต์มาโครต่อสู้เพื่อความปลอดภัย ป้องกันการตรวจจับ/แบน")
    return
end

-- ── 3. ตรวจสอบแมพต่อสู้ & รอตรวจจับ VoteStart ──────────────
print("[AA Macro] ⚔️ เข้าสู่แมพต่อสู้ (PlaceId: " .. tostring(currentPlaceId) .. ")")
print("[AA Macro] ⏳ กำลังรอระบบเกมและตรวจจับ VoteStart...")

local Players = game:GetService("Players")
local plr = Players.LocalPlayer or Players.PlayerAdded:Wait()
local playerGui = plr:WaitForChild("PlayerGui", 60)

if not playerGui then
    warn("[AA Macro] ❌ ไม่พบ PlayerGui ภายในเวลาที่กำหนด ยกเลิกการรัน")
    return
end

-- ตรวจจับ VoteStart หรือห้องต่อสู้ที่เริ่มไปแล้ว
local voteStart = playerGui:FindFirstChild("VoteStart")
if not voteStart and not workspace:FindFirstChild("_UNITS") then
    voteStart = playerGui:WaitForChild("VoteStart", 60)
end

print("[AA Macro] ⚡ ตรวจพบห้องต่อสู้พร้อมทำงาน กำลังโหลดสคริปต์...")
task.wait(1)

-- ── 4. ดาวน์โหลดและรันเวอร์ชันล่าสุดจาก GitHub ────────────
local GITHUB_USER   = "PeeKillxa"
local GITHUB_REPO   = "AA_Macro"
local GITHUB_BRANCH = "main"
local LOCAL_PATH    = "AA_Macro/main_v2.lua"

local function fetchLatestScript()
    -- 1. พยายามดึง Commit SHA ล่าสุดจาก GitHub API เพื่อ bypass CDN Cache 100%
    local apiUrl = string.format("https://api.github.com/repos/%s/%s/commits/%s", GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH)
    local apiOk, apiRes = pcall(function()
        return game:HttpGet(apiUrl)
    end)

    if apiOk and apiRes then
        local sha = apiRes:match('"sha"%s*:%s*"([a-f0-9]+)"')
        if sha and #sha >= 7 then
            local shaUrl = string.format("https://raw.githubusercontent.com/%s/%s/%s/main_v2.lua", GITHUB_USER, GITHUB_REPO, sha)
            local okSha, contentSha = pcall(function() return game:HttpGet(shaUrl) end)
            if okSha and contentSha and #contentSha > 1000 and not contentSha:find("404: Not Found") then
                return contentSha
            end
        end
    end

    -- 2. Fallback: ดึงจาก Branch URL ตรงๆ
    local branchUrl = string.format("https://raw.githubusercontent.com/%s/%s/%s/main_v2.lua?t=%d", GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH, tick())
    local okBranch, contentBranch = pcall(function() return game:HttpGet(branchUrl) end)
    if okBranch and contentBranch and #contentBranch > 1000 and not contentBranch:find("404: Not Found") then
        return contentBranch
    end

    return nil
end

local function loadScript()
    -- 1. พยายามดาวน์โหลดเวอร์ชันล่าสุดจาก GitHub
    local content = fetchLatestScript()
    if content then
        local fn, err = loadstring(content)
        if fn then
            pcall(function()
                if not isfolder("AA_Macro") then makefolder("AA_Macro") end
                writefile(LOCAL_PATH, content)
            end)
            print("[AA Macro] ✅ โหลดเวอร์ชันล่าสุดจาก Cloud สำเร็จ!")
            return fn()
        else
            warn("[AA Macro] ⚠️ เกิดข้อผิดพลาดในการ Compile โค้ดจาก Cloud: " .. tostring(err))
        end
    end

    -- 2. Fallback: ถ้าเน็ตติดขัด หรือ Cloud ไม่พร้อม ให้รันจากไฟล์ในเครื่อง
    if isfile and isfile(LOCAL_PATH) then
        print("[AA Macro] 📁 รันสคริปต์จากไฟล์ในเครื่อง (Offline Mode)")
        local offlineContent = readfile(LOCAL_PATH)
        local fn, err = loadstring(offlineContent)
        if fn then
            return fn()
        else
            warn("[AA Macro] ❌ ไฟล์ในเครื่องเกิดข้อผิดพลาด: " .. tostring(err))
        end
    else
        warn("[AA Macro] ❌ ไม่สามารถโหลดสคริปต์ได้ ตรวจสอบอินเทอร์เน็ตหรือ URL ของ GitHub")
    end
end

loadScript()
