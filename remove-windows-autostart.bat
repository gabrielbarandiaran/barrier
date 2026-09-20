@echo off
REM ---------------------------------------------------------------------------
REM Undo install-windows-autostart.bat: stop the Barrier client and stop it
REM starting at login. Leaves your certificate and trusted fingerprints alone,
REM so reinstalling does not mean exchanging fingerprints again.
REM ---------------------------------------------------------------------------

setlocal

set "DEST=%LOCALAPPDATA%\Barrier\bin"
set "VBS=%LOCALAPPDATA%\Barrier\start-barrier-client.vbs"
set "LINK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Barrier Client.vbs"

echo Removing Barrier client autostart
echo.

REM Stop the launcher loop first, or it will just restart the client.
if exist "%LINK%" (
    del /F /Q "%LINK%" >NUL 2>&1
    echo Removed from Startup
) else (
    echo Not present in Startup
)

REM End only the wscript.exe running our launcher, not every script on the
REM machine. No pipes and no double quotes inside the command, so batch does not
REM mangle it, and no wmic, which recent Windows releases no longer ship.
powershell -NoProfile -Command "foreach($p in (Get-CimInstance Win32_Process)){ if($p.Name -eq 'wscript.exe' -and $p.CommandLine -like '*start-barrier-client.vbs*'){ Stop-Process -Id $p.ProcessId -Force } }" >NUL 2>&1

taskkill /f /im barrierc.exe >NUL 2>&1
echo Stopped the client

if exist "%VBS%" (
    del /F /Q "%VBS%" >NUL 2>&1
    echo Removed launcher
)

echo.
echo ============================================================
echo  Autostart removed. The client is stopped and will not
echo  start at login.
echo.
echo  Left in place on purpose:
echo    %DEST%
echo    %LOCALAPPDATA%\Barrier\SSL
echo.
echo  The SSL folder holds this machine's certificate and the
echo  fingerprints it trusts. Delete it only if you want to redo
echo  the fingerprint exchange from scratch.
echo ============================================================
echo.

endlocal
