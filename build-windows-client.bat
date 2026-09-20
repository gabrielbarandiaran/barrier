@echo off
REM ---------------------------------------------------------------------------
REM Build the Barrier client (barrierc.exe) on Windows.
REM
REM Run this from an "x64 Native Tools Command Prompt for VS", from the root of
REM the repository. It builds only the client: no Qt, no GUI, no Bonjour SDK,
REM and no background service.
REM
REM Requires OpenSSL. The easiest source is vcpkg:
REM     git clone https://github.com/microsoft/vcpkg C:\vcpkg
REM     C:\vcpkg\bootstrap-vcpkg.bat
REM     C:\vcpkg\vcpkg install openssl:x64-windows
REM ---------------------------------------------------------------------------

setlocal

REM --- locate the compiler -----------------------------------------------------
where cl.exe >NUL 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: cl.exe not found.
    echo.
    echo Run this from an "x64 Native Tools Command Prompt for VS", not a
    echo plain cmd window. Find it in the Start menu under Visual Studio.
    echo.
    exit /b 1
)

where cmake.exe >NUL 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: cmake.exe not found. Install CMake and make sure it is on PATH.
    echo.
    exit /b 1
)

REM --- locate vcpkg ------------------------------------------------------------
if not "%VCPKG_ROOT%"=="" goto have_vcpkg_var
if exist "C:\vcpkg\scripts\buildsystems\vcpkg.cmake" set "VCPKG_ROOT=C:\vcpkg"
:have_vcpkg_var

set "TOOLCHAIN="
if "%VCPKG_ROOT%"=="" goto no_vcpkg
REM Quote the path, not the whole argument, so a vcpkg root containing spaces
REM still works.
if exist "%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake" (
    set TOOLCHAIN=-DCMAKE_TOOLCHAIN_FILE="%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake"
    echo Using vcpkg at %VCPKG_ROOT%
    goto configure
)

:no_vcpkg
echo.
echo NOTE: vcpkg not found at C:\vcpkg and VCPKG_ROOT is not set.
echo Trying anyway -- this only works if CMake can already find OpenSSL 1.1.1
echo or newer by itself. If configuration fails on OpenSSL, install vcpkg:
echo.
echo     git clone https://github.com/microsoft/vcpkg C:\vcpkg
echo     C:\vcpkg\bootstrap-vcpkg.bat
echo     C:\vcpkg\vcpkg install openssl:x64-windows
echo.

:configure
echo.
echo === Configuring ===
cmake -S . -B build -A x64 %TOOLCHAIN% ^
  -DBARRIER_BUILD_GUI=OFF ^
  -DBARRIER_BUILD_INSTALLER=OFF ^
  -DBARRIER_BUILD_TESTS=OFF ^
  -DCMAKE_BUILD_TYPE=Release
if errorlevel 1 (
    echo.
    echo ERROR: CMake configuration failed. See the messages above.
    echo If it could not find OpenSSL, see the vcpkg instructions at the top
    echo of this script.
    echo.
    exit /b 1
)

echo.
echo === Building ===
cmake --build build --config Release
if errorlevel 1 (
    echo.
    echo ERROR: Build failed. See the messages above.
    echo.
    exit /b 1
)

if not exist "build\bin\Release\barrierc.exe" (
    echo.
    echo ERROR: The build reported success but barrierc.exe is missing.
    echo.
    exit /b 1
)

REM --- make sure the OpenSSL DLLs sit next to the exe --------------------------
REM The vcpkg toolchain usually does this itself; copy them if it did not.
if not "%VCPKG_ROOT%"=="" (
    if exist "%VCPKG_ROOT%\installed\x64-windows\bin\libssl-3-x64.dll" (
        copy /Y "%VCPKG_ROOT%\installed\x64-windows\bin\libssl-3-x64.dll" "build\bin\Release\" >NUL 2>&1
        copy /Y "%VCPKG_ROOT%\installed\x64-windows\bin\libcrypto-3-x64.dll" "build\bin\Release\" >NUL 2>&1
    )
)

echo.
echo ============================================================
echo  Built: build\bin\Release\barrierc.exe
echo.
echo  Connect to the MacBook with:
echo.
echo      build\bin\Release\barrierc.exe --name windows ^<mac-ip^>
echo.
echo  The FIRST run is expected to fail with a fingerprint error.
echo  That is the certificate exchange, not a bug -- see
echo  doc\WINDOWS-CLIENT.md step 4.
echo ============================================================
echo.

endlocal
