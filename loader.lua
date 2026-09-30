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

-- ตรวจจับ VoteStart: ถ้ายังไม่ขึ้น ให้รอจนกว่าจะขึ้น (รอสูงสุด 120 วินาที)
local voteStart = playerGui:FindFirstChild("VoteStart") or playerGui:WaitForChild("VoteStart", 120)

if not voteStart then
    warn("[AA Macro] ⚠️ ไม่พบ VoteStart ในแมพต่อสู้ (หมดเวลา 120s) ยกเลิกการรันสคริปต์เพื่อความปลอดภัย")
    return
end

print("[AA Macro] ⚡ ตรวจพบ VoteStart แล้ว! กำลังเริ่มต้นโหลดสคริปต์...")
task.wait(1.5) -- หน่วงเวลาเล็กน้อยเพื่อให้ Remote และ GUI ในเกมพร้อมทำงาน 100%

-- ── 4. ดาวน์โหลดและรันเวอร์ชันล่าสุดจาก GitHub ────────────
local GITHUB_USER   = "PeeKillxa"
local GITHUB_REPO   = "AA_Macro"
local GITHUB_BRANCH = "main"
local REMOTE_URL    = string.format("https://raw.githubusercontent.com/%s/%s/%s/main_v2.lua?t=%d", GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH, tick())
local LOCAL_PATH    = "AA_Macro/main_v2.lua"

local function loadScript()
    -- 1. พยายามดาวน์โหลดเวอร์ชันล่าสุดจาก GitHub
    local ok, content = pcall(function()
        return game:HttpGet(REMOTE_URL)
    end)

    if ok and content and #content > 1000 and not content:find("404: Not Found") then
        -- บันทึกไฟล์อัปเดตลงเครื่อง
        pcall(function()
            if not isfolder("AA_Macro") then makefolder("AA_Macro") end
            writefile(LOCAL_PATH, content)
        end)

        local fn, err = loadstring(content)
        if fn then
            print("[AA Macro] ✅ โหลดเวอร์ชันล่าสุดจาก Cloud สำเร็จ!")
            return fn()
        else
            warn("[AA Macro] ⚠️ เกิดข้อผิดพลาดในการรันโค้ดจาก Cloud: " .. tostring(err))
        end
    end

    -- 2. Fallback: ถ้าเน็ตติดขัด หรือ GitHub ยังไม่เปิด ให้รันจากไฟล์ในเครื่อง
    if isfile and isfile(LOCAL_PATH) then
        print("[AA Macro] 📁 รันสคริปต์จากไฟล์ในเครื่อง (Offline Mode)")
        return loadstring(readfile(LOCAL_PATH))()
    else
        warn("[AA Macro] ❌ ไม่สามารถโหลดสคริปต์ได้ ตรวจสอบอินเทอร์เน็ตหรือ URL ของ GitHub")
    end
end

loadScript()
