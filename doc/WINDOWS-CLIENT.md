# Barrier client on Windows

The PC receives keyboard and mouse from the MacBook. You do not need Visual
Studio, CMake, vcpkg, or any build tools — GitHub builds the client on every
push and you download the result.

The MacBook side is in [SETUP-mac-to-windows.md](SETUP-mac-to-windows.md).

---

## 1. Download it

On the Windows PC, paste this into any browser:

```
https://github.com/gabrielbarandiaran/barrier/releases/latest/download/barrier-client-windows.zip
```

It downloads straight away — no GitHub account, no sign-in, no navigating the
Actions tab. The link always serves the newest build; CI refreshes it on every
push.

Unzip it anywhere. The Desktop is fine.

You get:

| file | |
|---|---|
| `barrier-client.bat` | **double-click this** |
| `barrierc.exe` | the client |
| `libssl-*.dll`, `libcrypto-*.dll` | OpenSSL, so it runs on a clean machine |
| `install-windows-autostart.bat` | start at login |
| `remove-windows-autostart.bat` | undo that |

## 2. Double-click `barrier-client.bat`

It asks for the MacBook's address the first time and remembers it:

```
What is the MacBook's address on your network?
Server address: 192.168.3.79
```

Then it connects and shows what it is doing.

**The first time it will say the server is not trusted** and show a fingerprint:

```
 This server is not trusted yet.

 Its fingerprint is:

   39:E8:22:F4:FE:63:E0:F6:...

 Trust this server? [y/N]
```

Compare it with the fingerprint the Mac shows, then press `y`. It connects
straight away — no restart, no editing files, nothing copied between machines.

That question appears **once per machine**. It is the only manual step, and it
exists because without it any machine on your network could pretend to be your
Mac and collect everything you type.

Once it says **Connected**, push the mouse off the right edge of the MacBook
screen. `Cmd` acts as `Ctrl` on the PC, so Cmd+C and Cmd+V work as expected.

## 3. Make it automatic

```bat
install-windows-autostart.bat 192.168.3.79
```

Now it starts at every login with no window and no clicks. It retries about once
a second forever, so it reconnects by itself whenever the Mac appears — after a
reboot, waking from sleep, or changing networks.

Undo with `remove-windows-autostart.bat`.

**One limitation:** this runs in your user session, so the MacBook keyboard works
once you are logged in, but not on the lock screen or sign-in screen. Use Windows
Hello or the PC's own keyboard to log in; Barrier takes over immediately after.
The old background service covered the sign-in screen, but it did so by running
as LocalSystem while accepting commands over an unauthenticated local socket,
which let any local user get SYSTEM. It has been removed.

## 4. Updating

Download the same link again and replace the files. If you set up autostart, run
`install-windows-autostart.bat` again afterwards so the new client is copied into
place.

Your certificate and trusted fingerprints live in `%LOCALAPPDATA%\Barrier\SSL`
and are never touched, so updating never means trusting the server again.

---

## Troubleshooting

**Nothing happens when I double-click** — Windows may have blocked the
downloaded zip. Right-click the zip, Properties, tick **Unblock**, unzip again.

**"failed to verify server certificate fingerprint" and no prompt** — you are
running `barrierc.exe` directly instead of `barrier-client.bat`. The prompt lives
in the launcher.

**It was working, now it silently does nothing** — autostart hides the window on
purpose. Run `barrier-client.bat` by hand to see the log.

**`unrecognised client name`** — the Mac's config has no screen called `windows`.
The name must match `doc/mac-to-windows.conf`.

**Cannot reach the Mac** — check the Mac's firewall allows incoming TCP 24800.
Nothing needs opening on Windows; the client dials out.

**The server address changed** — re-run `barrier-client.bat <new-ip>`, or give
the MacBook a DHCP reservation so it stops moving.

**An old service is still installed** — from an administrator prompt:
```bat
sc stop Barrier
sc delete Barrier
```

---

## Building it yourself (optional)

Only needed if you want to change the code. CI does this on every push.

Prerequisites: Git, CMake, Visual Studio 2017+ with "Desktop development with
C++", and OpenSSL via vcpkg:

```bat
git clone --recursive -b security-hardening https://github.com/gabrielbarandiaran/barrier
cd barrier

git clone https://github.com/microsoft/vcpkg C:\vcpkg
C:\vcpkg\bootstrap-vcpkg.bat
C:\vcpkg\vcpkg install openssl:x64-windows
```

Then from an **x64 Native Tools Command Prompt for VS**:

```bat
build-windows-client.bat
```

The result is `build\bin\Release\barrierc.exe`. `update-windows.bat` pulls,
rebuilds, reinstalls and restarts in one go.

If CMake cannot find vcpkg, point it there: `set VCPKG_ROOT=D:\path\to\vcpkg`.
