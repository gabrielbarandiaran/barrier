# Barrier client launcher.
#
# Run barrier-client.bat instead of calling this directly.
#
# Asks for the server address once, remembers it, then runs the client and
# stays out of the way. If the server is not trusted yet it shows the
# fingerprint and offers to trust it, which is the only manual step in the
# whole setup and happens exactly once per machine.

$ErrorActionPreference = 'Stop'

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe        = Join-Path $here 'barrierc.exe'
$profileDir = Join-Path $env:LOCALAPPDATA 'Barrier'
$serverFile = Join-Path $profileDir 'server.txt'
$trustFile  = Join-Path $profileDir 'SSL\Fingerprints\TrustedServers.txt'
$screenName = 'windows'

function Info($m)  { Write-Host $m -ForegroundColor Cyan }
function Good($m)  { Write-Host $m -ForegroundColor Green }
function Warn($m)  { Write-Host $m -ForegroundColor Yellow }
function Fail($m)  { Write-Host $m -ForegroundColor Red }

if (-not (Test-Path $exe)) {
    Fail "barrierc.exe not found next to this script."
    Fail "Expected: $exe"
    Read-Host "`nPress Enter to close"
    exit 1
}

# --- server address ----------------------------------------------------------
$server = $null
if ($args.Count -ge 1 -and $args[0]) {
    $server = $args[0]
} elseif (Test-Path $serverFile) {
    $server = (Get-Content $serverFile -Raw).Trim()
}

if (-not $server) {
    Write-Host ''
    Info 'Barrier client - first run'
    Write-Host ''
    Write-Host "What is the MacBook's address on your network?"
    Write-Host "On the Mac you can find it with:  ipconfig getifaddr en0"
    Write-Host ''
    $server = (Read-Host 'Server address').Trim()
    if (-not $server) { Fail 'No address given.'; Read-Host 'Press Enter to close'; exit 1 }
}

New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
Set-Content -Path $serverFile -Value $server -Encoding ASCII

Write-Host ''
Info "Connecting to $server as screen '$screenName'"
Info 'Leave this window open. Close it to disconnect.'
Write-Host ''

# --- trust helper ------------------------------------------------------------
# The client re-reads TrustedServers.txt on every connection attempt and retries
# about once a second, so writing the entry here is enough; it connects on the
# next attempt without needing a restart.
function Trust-Fingerprint($sha256WithColons) {
    $hex = $sha256WithColons -replace ':',''
    $hex = $hex.ToLower()
    $line = "v2:sha256:$hex"

    $dir = Split-Path -Parent $trustFile
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $existing = @()
    if (Test-Path $trustFile) { $existing = Get-Content $trustFile }
    if ($existing -contains $line) { return }

    Add-Content -Path $trustFile -Value $line -Encoding ASCII
    Good "Trusted. TrustedServers.txt updated."
}

# --- run ---------------------------------------------------------------------
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = $exe
$psi.Arguments              = "--name $screenName --no-tray $server"
$psi.UseShellExecute         = $false
$psi.RedirectStandardOutput  = $true
$psi.RedirectStandardError   = $true
$psi.CreateNoWindow          = $true

$proc = [System.Diagnostics.Process]::Start($psi)

$pendingSha256 = $null
$asked         = $false
$connected     = $false

# stderr is where the log goes; drain stdout too so the pipe cannot fill.
$stdoutTask = $proc.StandardOutput.ReadToEndAsync()

while (-not $proc.HasExited) {
    $line = $proc.StandardError.ReadLine()
    if ($null -eq $line) { break }

    Write-Host $line

    if ($line -match 'peer fingerprint \(SHA1\): ([A-F0-9:]+) \(SHA256\): ([A-F0-9:]+)') {
        $pendingSha256 = $Matches[2]
    }

    if ($line -match 'connected to server' -and -not $connected) {
        $connected = $true
        Write-Host ''
        Good 'Connected. Move the mouse off the right edge of the Mac screen.'
        Write-Host ''
    }

    if ($line -match 'failed to verify server certificate fingerprint' -and -not $asked) {
        $asked = $true
        Write-Host ''
        Warn '----------------------------------------------------------'
        Warn ' This server is not trusted yet.'
        Warn '----------------------------------------------------------'
        Write-Host ''
        Write-Host ' Its fingerprint is:'
        Write-Host ''
        Write-Host "   $pendingSha256" -ForegroundColor White
        Write-Host ''
        Write-Host ' Check this matches the fingerprint shown on the Mac'
        Write-Host ' (Barrier shows it at startup and in its log). If it'
        Write-Host ' does not match, someone else may be answering.'
        Write-Host ''

        if ($pendingSha256) {
            $answer = Read-Host ' Trust this server? [y/N]'
            if ($answer -match '^[Yy]') {
                Trust-Fingerprint $pendingSha256
                Info 'Reconnecting...'
                $asked = $false
            } else {
                Warn ' Not trusted. Stopping.'
                try { $proc.Kill() } catch { }
                break
            }
        } else {
            Fail ' Could not read the fingerprint from the log.'
        }
    }
}

try { $proc.WaitForExit() } catch { }

Write-Host ''
if ($connected) {
    Info 'Disconnected.'
} else {
    Fail 'The client stopped without connecting. The log above says why.'
}
Read-Host 'Press Enter to close'
