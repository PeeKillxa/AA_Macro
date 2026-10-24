-- ============================================================
--  AA Event Studio | April Fool's Event Auto Play
--  Created by cook45 & clack
--  File: AA_Macro/lobby_event.lua
-- ============================================================

local Players     = game:GetService("Players")
local Workspace   = game:GetService("Workspace")
local RunService  = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local plr = Players.LocalPlayer
if not plr then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    plr = Players.LocalPlayer
end

-- ── 0. Cleanup Previous Window ──────────────────────────────
local gethui = gethui or function() return game:GetService("CoreGui") end

if _G.AAEventUI and typeof(_G.AAEventUI.Destroy) == "function" then
    pcall(function() _G.AAEventUI:Destroy() end)
    _G.AAEventUI = nil
end

pcall(function()
    for _, ch in ipairs(gethui():GetChildren()) do
        if ch:IsA("ScreenGui") and ch.Name == "AAEvent_HUD" then
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

-- ── 2. Script State ─────────────────────────────────────────
local State = {
    AutoPlayEvent = false,
    LoopInterval  = 3.0,
    StatusText    = "⏹️ STANDBY — รอคำสั่ง",
    TotalAttempts = 0,
    LastSolved    = "-",
}

-- ── 3. Fluent UI Window ─────────────────────────────────────
local Window = Fluent:CreateWindow({
    Title       = "AA Event Studio v1.0",
    SubTitle    = "April Fool's Edition | by cook45 & clack",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(580, 420),
    Acrylic     = true,
    Theme       = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl,
})
_G.AAEventUI = Window

local Tabs = {
    Event    = Window:AddTab({ Title = "April Fool's", Icon = "play" }),
    Settings = Window:AddTab({ Title = "Settings",     Icon = "settings" }),
}

-- ── Section: Status Dashboard ───────────────────────────────
Tabs.Event:AddSection("⚡ LIVE STATUS")

local StatusCard = Tabs.Event:AddParagraph({
    Title   = "สถานะการทำงาน",
    Content = State.StatusText,
})

local function updateStatus(txt)
    State.StatusText = txt
    if StatusCard then
        StatusCard:SetDesc(txt .. "\nรอบที่พยายาม: " .. tostring(State.TotalAttempts) .. " | Captcha ล่าสุด: " .. tostring(State.LastSolved))
    end
    print("[AA Event] " .. txt)
end

-- ── Section: Automation Controls ────────────────────────────
Tabs.Event:AddSection("🎮 AUTOMATION")

local EventToggle = Tabs.Event:AddToggle("AutoPlayEventToggle", {
    Title   = "Auto Play April Fool's Event",
    Default = false,
    Description = "กดปุ่ม EventTeleport -> เดินเข้าประตู Event3 -> กด Find Match -> ออโต้แก้ Captcha & Submit",
})

EventToggle:OnChanged(function()
    State.AutoPlayEvent = Fluent.Options.AutoPlayEventToggle.Value
    if State.AutoPlayEvent then
        updateStatus("🟢 เริ่มต้นทำงาน Auto Play April Fool's Event")
    else
        updateStatus("⏹️ หยุดการทำงาน Auto Play")
    end
end)

Tabs.Event:AddSlider("LoopIntervalSlider", {
    Title = "ระยะห่างการตรวจสอบ (วินาที)",
    Default = 3,
    Min = 1,
    Max = 10,
    Rounding = 1,
    Callback = function(val)
        State.LoopInterval = val
    end,
})

Tabs.Event:AddButton({
    Title = "⚡ ทดสอบยิงรอบเดียวทันที (Run Once)",
    Description = "รันขั้นตอนเทเลพอร์ต -> เข้าประตู -> Find Match -> Captcha หนึ่งรอบ",
    Callback = function()
        task.spawn(function()
            updateStatus("🚀 กำลังรันแบบ Manual ทันที...")
            runEventSequence()
        end)
    end,
})

-- ── 4. Core Workflow Function ───────────────────────────────
function runEventSequence()
    -- ตรวจสอบว่าอยู่ใน Lobby หรือไม่ (PlaceId: 8304191830)
    if game.PlaceId ~= 8304191830 then
        return false
    end

    State.TotalAttempts = State.TotalAttempts + 1

    local playerGui = plr:WaitForChild("PlayerGui", 10)
    if not playerGui then
        updateStatus("❌ ไม่พบ PlayerGui")
        return false
    end

    -- ขั้นตอนที่ 1: กดปุ่ม EventTeleport ใน LeftUI_test
    updateStatus("📍 [1/4] ตรวจสอบปุ่ม EventTeleport...")
    local leftUI = playerGui:FindFirstChild("LeftUI_test")
    local eventBtn = leftUI and leftUI:FindFirstChild("Buttons") and leftUI.Buttons:FindFirstChild("EventTeleport")

    if eventBtn then
        updateStatus("👉 [1/4] กดปุ่ม EventTeleport สำเร็จ")
        if firesignal then
            firesignal(eventBtn.Activated)
            pcall(function() firesignal(eventBtn.MouseButton1Click) end)
        end
        task.wait(1.5)
    else
        updateStatus("⚠️ [1/4] ไม่พบปุ่ม LeftUI_test.Buttons.EventTeleport (อาจอยู่ที่โซนแล้ว)")
    end

    -- ขั้นตอนที่ 2: เดินไปที่ประตู Event ด้วย WalkTo (ไม่ใช้วาร์ป CFrame เพื่อความปลอดภัย)
    updateStatus("🚶 [2/4] กำลังเดินไปยังประตู _lobbytemplate_event3.Door (WalkTo)...")
    local lobbies = Workspace:FindFirstChild("_EVENT_CHALLENGES") and Workspace._EVENT_CHALLENGES:FindFirstChild("Lobbies")
    local lobby3 = lobbies and lobbies:FindFirstChild("_lobbytemplate_event3")
    local door = lobby3 and lobby3:FindFirstChild("Door")

    local char = plr.Character or plr.CharacterAdded:Wait()
    local root = char and char:WaitForChild("HumanoidRootPart", 5)
    local hum  = char and (char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5))

    if not door or not root or not hum then
        updateStatus("❌ [2/4] ไม่พบประตู Event หรือ Humanoid")
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
            updateStatus("🎯 [2/4] ตรวจพบหน้าต่าง MatchmakingPrompt แล้ว! หยุดเดิน")
            break
        end

        -- ถ้าเดินมาชนหรือชิดประตูแล้ว (ระยะ <= 3.5 studs)
        if distXZ <= 3.5 then
            updateStatus("🚪 [2/4] เดินถึงประตูแล้ว สัมผัสประตู...")
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

    updateStatus("✨ [2/4] เข้าถึงประตูเรียบร้อย กำลังรอ MatchmakingPrompt...")
    task.wait(0.8)

    -- ขั้นตอนที่ 3: รอและกดปุ่ม Find Match
    local notif = playerGui:FindFirstChild("NotificationWindows")
    local popups = notif and notif:FindFirstChild("Popups")
    if not popups then
        updateStatus("❌ ไม่พบ NotificationWindows.Popups")
        return false
    end

    -- รอ MatchmakingPrompt สูงสุด 5 วินาที
    local prompt = popups:FindFirstChild("MatchmakingPrompt") or popups:WaitForChild("MatchmakingPrompt", 5)
    if prompt and prompt:FindFirstChild("Main") and prompt.Main:FindFirstChild("Buttons") then
        local matchBtn = prompt.Main.Buttons:FindFirstChild("Matchmaking")
        if matchBtn then
            updateStatus("🔍 [3/4] ตรวจพบปุ่ม 'Find Match' -> กำลังกดค้นหาห้อง...")
            task.wait(0.3)
            if firesignal then
                firesignal(matchBtn.Activated)
                pcall(function() firesignal(matchBtn.MouseButton1Click) end)
            end
        end
    else
        updateStatus("⚠️ [3/4] ไม่พบหน้าต่าง MatchmakingPrompt (อาจติดคิวอยู่แล้วหรือแก้ Captcha ไปแล้ว)")
    end

    task.wait(0.8)

    -- ขั้นตอนที่ 4: ตรวจสอบ Captcha และ Auto Fill + Submit
    local captchaWin = popups:FindFirstChild("CaptchaWindow") or popups:WaitForChild("CaptchaWindow", 3)
    if captchaWin then
        updateStatus("🧩 [4/4] ตรวจพบหน้าต่าง Captcha! กำลังดึงรหัส...")
        task.wait(0.2)

        local captchaLabel = captchaWin:FindFirstChild("Captcha")
        local typeBox = captchaWin:FindFirstChildWhichIsA("TextBox", true)
        local submitBtn = captchaWin:FindFirstChild("Yes", true) or (captchaWin:FindFirstChild("ButtonHolder") and captchaWin.ButtonHolder:FindFirstChild("Yes"))

        if captchaLabel and typeBox and submitBtn then
            local code = captchaLabel.Text
            State.LastSolved = tostring(code)
            updateStatus("🔢 [4/4] ถอดรหัส Captcha ได้: '" .. tostring(code) .. "' -> กำลังพิมพ์ลงกล่องข้อความ...")

            typeBox.Text = tostring(code)
            task.wait(0.25)

            updateStatus("📩 [4/4] กำลังกดปุ่ม Submit...")
            if firesignal then
                firesignal(submitBtn.Activated)
                pcall(function() firesignal(submitBtn.MouseButton1Click) end)
            end

            updateStatus("🎉 [4/4] กด Submit เรียบร้อย! รอเซิร์ฟเวอร์ดึงเข้าเกม...")
            return true
        else
            updateStatus("❌ [4/4] องค์ประกอบใน CaptchaWindow ไม่ครบ")
        end
    else
        updateStatus("⚡ [4/4] ข้าม Captcha (ระบบจดจำสถานะ Captcha เดิม หรือไม่ต้องกรอก)")
        return true
    end

    return false
end

-- ── 5. Background Automation Worker ─────────────────────────
task.spawn(function()
    while true do
        if (game.PlaceId == 8304191830) and State.AutoPlayEvent then
            pcall(function()
                runEventSequence()
            end)
            task.wait(State.LoopInterval)
        else
            task.wait(1.5)
        end
    end
end)

-- ── 6. Anti-AFK Worker ──────────────────────────────────────
local VirtualUser = game:GetService("VirtualUser")
plr.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
    task.wait(1)
    VirtualUser:Button2Up(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
    print("[AA Event Anti-AFK] Prevented idle disconnect in Lobby.")
end)

-- ── 7. Save & Settings Manager ──────────────────────────────
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("AA_Macro")
SaveManager:SetFolder("AA_Macro/event_settings")

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)

Fluent:Notify({
    Title    = "AA Event Studio",
    Content  = "โหลดระบบ April Fool's Event เรียบร้อยแล้ว (กด RightControl เพื่อพับจอ)",
    Duration = 5,
})

print("[Cook45 & Clack] AA Lobby Event Script Loaded Successfully.")
