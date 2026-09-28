--[[
    ═══════════════════════════════════════════════════════════
    ⚡ AA MACRO STUDIO v2.0 — UNIVERSAL CLOUD LOADER
    ═══════════════════════════════════════════════════════════
    • ใช้คำสั่งนี้รันได้ทุกเครื่อง
    • ทุกครั้งที่เปิด จะดึงโค้ดเวอร์ชันล่าสุดจาก GitHub อัตโนมัติ
    • บันทึกลงเครื่องให้อัตโนมัติ รองรับ Auto Replay ข้ามห้อง
--]]
task.wait(5)
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
