# Barrier client launcher.
#
# Run barrier-client.bat instead of calling this directly.
#
# Asks for the server address once, remembers it, pairs with the server the
# first time, then runs the client.

$ErrorActionPreference = 'Stop'

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe        = Join-Path $here 'barrierc.exe'
$profileDir = Join-Path $env:LOCALAPPDATA 'Barrier'
$serverFile = Join-Path $profileDir 'server.txt'
$trustFile  = Join-Path $profileDir 'SSL\Fingerprints\TrustedServers.txt'
$screenName = 'windows'

function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Good($m) { Write-Host $m -ForegroundColor Green }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Fail($m) { Write-Host $m -ForegroundColor Red }

if (-not (Test-Path $exe)) {
    Fail "barrierc.exe not found next to this script."
    Fail "Expected: $exe"
    Read-Host "`nPress Enter to close"
    exit 1
}

# --- server address ----------------------------------------------------------
$server = $null
if ($args.Count -ge 1 -and $args[0]) {
    $server = [string]$args[0]
} elseif (Test-Path $serverFile) {
    $server = (Get-Content $serverFile -Raw).Trim()
}

if (-not $server) {
    Write-Host ''
    Info 'Barrier client - first run'
    Write-Host ''
    Write-Host "What is the MacBook's address on your network?"
    Write-Host "On the Mac, find it with:  ipconfig getifaddr en0"
    Write-Host ''
    $server = (Read-Host 'Server address').Trim()
    if (-not $server) {
        Fail 'No address given.'
        Read-Host 'Press Enter to close'
        exit 1
    }
}

New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
Set-Content -Path $serverFile -Value $server -Encoding ASCII

function Trust-Fingerprint([string]$withColons) {
    $line = 'v2:sha256:' + ($withColons -replace ':','').ToLower()
    $dir  = Split-Path -Parent $trustFile
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $existing = @()
    if (Test-Path $trustFile) { $existing = @(Get-Content $trustFile) }
    if ($existing -notcontains $line) {
        Add-Content -Path $trustFile -Value $line -Encoding ASCII
    }
    Good ' Trusted.'
}

# Barrier splits its log across two streams: FATAL/ERROR/WARNING go to stderr,
# everything else (including the peer fingerprint, which is a NOTE, and
# "connected to server", which is a PRINT) goes to stdout. Run through cmd with
# 2>&1 so both arrive on one pipe; reading only one stream misses half the
# conversation.
function Start-Merged([string]$extraArgs) {
    $inner = '"' + $exe + '" --name ' + $screenName + ' --no-tray ' + $extraArgs + ' ' + $server + ' 2>&1'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $env:ComSpec
    $psi.Arguments              = '/s /c "' + $inner + '"'
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow         = $true
    return [System.Diagnostics.Process]::Start($psi)
}

function Stop-Tree($proc) {
    if ($null -eq $proc) { return }
    try { if (-not $proc.HasExited) { & taskkill /T /F /PID $proc.Id 2>&1 | Out-Null } } catch { }
}

# --- pairing -----------------------------------------------------------------
# --no-restart so the probe exits on failure instead of retrying forever.
Write-Host ''
Info "Checking the connection to $server ..."

$probe     = Start-Merged '--no-restart'
$sha256    = $null
$connected = $false
$untrusted = $false
$refused   = $null
$clock     = [Diagnostics.Stopwatch]::StartNew()

while ($clock.Elapsed.TotalSeconds -lt 30) {
    $line = $probe.StandardOutput.ReadLine()
    if ($null -eq $line) { break }

    if ($line -match 'peer fingerprint \(SHA1\): ([0-9A-Fa-f:]+) \(SHA256\): ([0-9A-Fa-f:]+)') {
        $sha256 = $Matches[2]
    }
    elseif ($line -match 'failed to verify server certificate fingerprint') {
        $untrusted = $true
        break
    }
    elseif ($line -match 'connected to server') {
        $connected = $true
        break
    }
    elseif ($line -match 'failed to connect to server: (.+)') {
        $refused = $Matches[1]
        break
    }
}

Stop-Tree $probe

if ($untrusted -and $sha256) {
    Write-Host ''
    Warn '-----------------------------------------------------------'
    Warn ' This server is not trusted yet.'
    Warn '-----------------------------------------------------------'
    Write-Host ''
    Write-Host ' Its fingerprint is:'
    Write-Host ''
    Write-Host "   $sha256" -ForegroundColor White
    Write-Host ''
    Write-Host ' Check it matches the fingerprint shown on the Mac. If it'
    Write-Host ' does not, another machine may be answering instead.'
    Write-Host ''
    $answer = Read-Host ' Trust this server? [y/N]'
    if ($answer -match '^[Yy]') {
        Trust-Fingerprint $sha256
    } else {
        Warn ' Not trusted. Nothing was changed.'
        Read-Host 'Press Enter to close'
        exit 1
    }
}
elseif ($untrusted) {
    Fail ' The server rejected us and no fingerprint was reported.'
    Fail ' Run barrierc.exe by hand to see the full log.'
    Read-Host 'Press Enter to close'
    exit 1
}
elseif ($refused) {
    Warn " Could not reach the server: $refused"
    Warn ' Starting anyway - it retries once a second and will connect'
    Warn ' as soon as the Mac is up.'
}
elseif ($connected) {
    Good ' Server already trusted.'
}

# --- run ---------------------------------------------------------------------
Write-Host ''
Info "Connecting to $server as screen '$screenName'"
Info 'Leave this window open. Close it to disconnect.'
Write-Host ''

# No redirection here: the client writes straight to this console, so you see
# everything it says.
$runPsi = New-Object System.Diagnostics.ProcessStartInfo
$runPsi.FileName        = $exe
$runPsi.Arguments       = "--name $screenName --no-tray $server"
$runPsi.UseShellExecute = $false
$run = [System.Diagnostics.Process]::Start($runPsi)
$run.WaitForExit()

Write-Host ''
Fail 'The client stopped. The log above says why.'
Read-Host 'Press Enter to close'
