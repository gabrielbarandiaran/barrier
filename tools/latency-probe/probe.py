#!/usr/bin/env python3
"""Throwaway latency probe. Measures UDP round-trip for input-sized packets.

Answers one question: can this network carry mouse/keyboard events smoothly?
ICMP ping is deprioritised by APs and routers, so it can mislead in either
direction. This sends the packet shape a real input tool would send, at the
rate a trackpad generates motion.

    python3 probe.py <windows-ip>
"""
import socket, struct, sys, time, statistics

HOST = sys.argv[1] if len(sys.argv) > 1 else "192.168.3.15"
PORT = 24801
COUNT = 500          # ~5 seconds of continuous motion
INTERVAL = 0.010     # 100 events/sec, the rate a trackpad produces
PAYLOAD = 24         # bytes: about one mouse-move message

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, 0x10)   # low delay
s.settimeout(0.5)

print(f"probing {HOST}:{PORT}  {COUNT} packets, {PAYLOAD}B, {1/INTERVAL:.0f}/sec\n")

rtts, lost = [], 0
pad = b"x" * (PAYLOAD - 12)

for seq in range(COUNT):
    sent = time.perf_counter()
    try:
        s.sendto(struct.pack("!Id", seq, sent) + pad, (HOST, PORT))
        while True:
            data, _ = s.recvfrom(64)
            rseq, rsent = struct.unpack("!Id", data[:12])
            if rseq == seq:                       # ignore stragglers
                rtts.append((time.perf_counter() - rsent) * 1000)
                break
    except socket.timeout:
        lost += 1
    time.sleep(INTERVAL)

if not rtts:
    print("No replies. Is the responder running, and did you allow the firewall prompt?")
    sys.exit(1)

rtts.sort()
def pct(p): return rtts[min(int(len(rtts) * p / 100), len(rtts) - 1)]

print(f"  replies   {len(rtts)}/{COUNT}   lost {lost} ({100*lost/COUNT:.1f}%)")
print(f"  min       {rtts[0]:6.2f} ms")
print(f"  median    {pct(50):6.2f} ms")
print(f"  mean      {statistics.mean(rtts):6.2f} ms")
print(f"  p95       {pct(95):6.2f} ms")
print(f"  p99       {pct(99):6.2f} ms")
print(f"  max       {rtts[-1]:6.2f} ms")
print(f"  jitter    {statistics.pstdev(rtts):6.2f} ms  (std dev - this is what feels glitchy)")

print()
m, j = statistics.mean(rtts), statistics.pstdev(rtts)
if m < 5 and j < 3:
    print("  VERDICT: network is fine. Barrier's design is the problem; a rewrite will help.")
elif m < 12 and j < 8:
    print("  VERDICT: usable. A UDP + relative-delta design should feel clearly better.")
else:
    print("  VERDICT: the network itself is the limit. No software design fixes this,")
    print("           and a rewrite would feel the same. Worth knowing before building.")
