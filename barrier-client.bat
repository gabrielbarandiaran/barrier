@echo off
REM ---------------------------------------------------------------------------
REM Barrier client - double-click this.
REM
REM Asks for the MacBook's address the first time, remembers it after that,
REM and offers to trust the server's fingerprint if it has not been trusted
REM yet. No build tools, no editing files by hand.
REM
REM     barrier-client.bat                 use the saved address
REM     barrier-client.bat 192.168.3.79    use (and save) this address
REM ---------------------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0barrier-client.ps1" %*
