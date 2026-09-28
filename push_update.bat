@echo off
chcp 65001 >nul
echo ═══════════════════════════════════════════════════════════
echo ⚡ AA MACRO STUDIO — PUSH UPDATE TO GITHUB
echo ═══════════════════════════════════════════════════════════
echo.

cd /d "%~dp0"

echo [1/3] ตรวจสอบความเปลี่ยนแปลง...
git add main_v2.lua main.lua loader.lua .gitignore README.md

set TIMESTAMP=%date% %time%
echo [2/3] สร้าง Commit: %TIMESTAMP%
git commit -m "Auto Update: %TIMESTAMP%"

echo [3/3] กำลังอัปโหลดขึ้น GitHub...
git push origin main

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ✅ อัปเดตขึ้น GitHub สำเร็จแล้ว!
    echo เครื่องอื่น ๆ สามารถรันคำสั่ง Loader เพื่อรับโค้ดใหม่ได้ทันที
) else (
    echo.
    echo ⚠️ เกิดข้อผิดพลาดในการ Push ตรวจสอบว่าได้สร้าง Repo และตั้งค่า Remote หรือยัง
)

echo.
pause
