@echo off
setlocal enabledelayedexpansion

echo Formatting all Lua files...
for /r "C:\Users\Terminatort8000\Desktop\Cheater_Detection-Beta-CDv2-Recode" %%f in (*.lua) do (
    echo Formatting: %%f
    stylua "%%f"
)

echo Done!
pause