@echo off
REM ---------------------------------------------------------------------------
REM Update the Barrier client on Windows: pull, rebuild, reinstall, restart.
REM
REM     update-windows.bat
REM     update-windows.bat --no-pull     rebuild what is already checked out
REM
REM Run this from an "x64 Native Tools Command Prompt for VS", from the root of
REM the repository.
REM
REM Your certificate and trusted fingerprints live in
REM %LOCALAPPDATA%\Barrier\SSL and are left alone, so updating never means
REM redoing the fingerprint exchange.
REM ---------------------------------------------------------------------------

setlocal

set "BRANCH=security-hardening"
set "DEST=%LOCALAPPDATA%\Barrier\bin"
set "VBS=%LOCALAPPDATA%\Barrier\start-barrier-client.vbs"
set "SRC=%~dp0build\bin\Release"
set "PULL=1"

if /i "%~1"=="--no-pull" set "PULL=0"

where cl.exe >NUL 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: cl.exe not found. Run this from an
    echo "x64 Native Tools Command Prompt for VS".
    echo.
    exit /b 1
)

REM --- 1. pull -----------------------------------------------------------------
if "%PULL%"=="0" goto skip_pull

echo.
echo === Pulling %BRANCH% ===

for /f %%i in ('git status --porcelain 2^>NUL') do goto dirty
goto do_pull

:dirty
echo.
echo ERROR: you have local changes in this repository.
git status --short
echo.
echo Commit or stash them, or run: update-windows.bat --no-pull
echo.
exit /b 1

:do_pull
git checkout %BRANCH% || exit /b 1
git pull --ff-only || exit /b 1
git submodule update --init --recursive || exit /b 1

:skip_pull

REM --- 2. stop the running client ----------------------------------------------
REM Windows will not let us overwrite a running exe, and the autostart launcher
REM relaunches the client a few seconds after it exits -- so stop the launcher
REM first, then the client.
echo.
echo === Stopping the client ===
powershell -NoProfile -Command "foreach($p in (Get-CimInstance Win32_Process)){ if($p.Name -eq 'wscript.exe' -and $p.CommandLine -like '*start-barrier-client.vbs*'){ Stop-Process -Id $p.ProcessId -Force } }" >NUL 2>&1
taskkill /f /im barrierc.exe >NUL 2>&1

REM --- 3. build ------------------------------------------------------------------
echo.
echo === Building ===
call "%~dp0build-windows-client.bat"
if errorlevel 1 (
    echo.
    echo ERROR: build failed. The old client is still installed at:
    echo   %DEST%
    echo Start it again with: wscript.exe "%VBS%"
    echo.
    exit /b 1
)

REM --- 4. install ------------------------------------------------------------------
echo.
echo === Installing ===
if not exist "%DEST%" mkdir "%DEST%" >NUL 2>&1
copy /Y "%SRC%\barrierc.exe" "%DEST%\" >NUL
if errorlevel 1 (
    echo ERROR: could not copy barrierc.exe into %DEST%
    echo Something may still be holding it open. Check with:
    echo   tasklist ^| findstr barrierc
    exit /b 1
)
copy /Y "%SRC%\*.dll" "%DEST%\" >NUL 2>&1
echo Updated %DEST%

REM --- 5. restart ------------------------------------------------------------------
if not exist "%VBS%" (
    echo.
    echo NOTE: autostart is not set up, so nothing was restarted.
    echo Set it up with: install-windows-autostart.bat ^<mac-ip^>
    echo.
    goto done
)

echo.
echo === Restarting ===
start "" wscript.exe "%VBS%"
echo Client restarted

:done
echo.
echo ============================================================
echo  Update complete.
echo.
echo  Your certificate and trusted fingerprints were not
echo  touched, so no fingerprint exchange is needed.
echo.
echo  Check it is running:  tasklist ^| findstr barrierc
echo ============================================================
echo.

endlocal
