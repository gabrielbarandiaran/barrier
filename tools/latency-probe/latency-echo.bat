@echo off
REM Throwaway latency test helper. Double-click this, then tell the Mac to probe.
REM It listens for tiny UDP packets and bounces them straight back, so the Mac
REM can measure the real round trip for input-sized traffic.
REM
REM Allow the Windows Firewall prompt when it appears, then leave this open.
REM Close the window when the test is done.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0echo-responder.ps1"
