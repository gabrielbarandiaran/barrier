# Throwaway UDP echo responder for a latency measurement. Not part of Barrier.
# Run on the Windows PC:   powershell -ExecutionPolicy Bypass -File echo-responder.ps1
# Allow the firewall prompt when it appears. Ctrl+C to stop.
$port = 24801
$u  = New-Object System.Net.Sockets.UdpClient $port
$ep = New-Object System.Net.IPEndPoint ([Net.IPAddress]::Any), 0
Write-Host "UDP echo listening on $port. Ctrl+C to stop." -ForegroundColor Cyan
while ($true) {
    $d = $u.Receive([ref]$ep)
    [void]$u.Send($d, $d.Length, $ep)
}
