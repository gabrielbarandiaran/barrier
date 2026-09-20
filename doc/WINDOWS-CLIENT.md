# Building and running the Windows client

Copy-paste reference for the Windows PC. The PC is the **client**: it receives
keyboard and mouse from the MacBook and never listens on the network itself.

You only build `barrierc.exe`. No Qt, no GUI, no Bonjour SDK, and no background
service — that service used to run as LocalSystem and take commands over an
unauthenticated local socket, and it is gone.

The MacBook side is covered in [SETUP-mac-to-windows.md](SETUP-mac-to-windows.md).

---

## 1. Install the prerequisites

- **Git** — https://git-scm.com/download/win
- **CMake** — https://cmake.org/download/ (tick "Add CMake to the system PATH")
- **Visual Studio 2017 or newer** with the **"Desktop development with C++"**
  workload. The free Community edition is fine.

## 2. Get the code

`--recursive` matters: the build needs the `gulrak-filesystem` submodule.

```bat
git clone --recursive -b security-hardening https://github.com/gabrielbarandiaran/barrier
cd barrier
```

Already cloned? Update instead:

```bat
git fetch origin
git checkout security-hardening
git pull
git submodule update --init --recursive
```

## 3. Install OpenSSL via vcpkg

One time. The last command compiles OpenSSL and takes a while.

```bat
git clone https://github.com/microsoft/vcpkg C:\vcpkg
C:\vcpkg\bootstrap-vcpkg.bat
C:\vcpkg\vcpkg install openssl:x64-windows
```

> This repo used to carry prebuilt OpenSSL 1.0.2l binaries, a 2017 release that
> went end-of-life in 2019. They were deleted; the build now finds a current
> OpenSSL the normal way.

## 4. Build

Open **"x64 Native Tools Command Prompt for VS"** from the Start menu — not a
plain `cmd` window, or the compiler will not be on your PATH. Then, from the
repository root:

```bat
build-windows-client.bat
```

That script configures and builds, checks the obvious failure modes, copies the
OpenSSL DLLs next to the executable, and prints the run command.

<details>
<summary>Doing it by hand instead</summary>

```bat
cmake -S . -B build -A x64 ^
  -DCMAKE_TOOLCHAIN_FILE=C:\vcpkg\scripts\buildsystems\vcpkg.cmake ^
  -DBARRIER_BUILD_GUI=OFF -DBARRIER_BUILD_INSTALLER=OFF -DBARRIER_BUILD_TESTS=OFF ^
  -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```
</details>

The result is **`build\bin\Release\barrierc.exe`**.

## 5. First run — expect it to fail

Replace the address with your MacBook's:

```bat
build\bin\Release\barrierc.exe --name windows 192.168.3.79
```

It will refuse the server and exit with `failed to verify server certificate
fingerprint`. **That is correct.** Neither machine trusts the other yet, and a
client that connected anyway would be a client an attacker could impersonate.

This run generated the client's own certificate, which is what you need next.

## 6. Trust each other, once

Each machine wrote its own fingerprints to `Local.txt` and logged the SHA256 at
startup:

| | fingerprint directory |
|---|---|
| Windows | `%LOCALAPPDATA%\Barrier\SSL\Fingerprints\` |
| macOS | `~/Library/Application Support/barrier/SSL/Fingerprints/` |

Open the Windows one:

```bat
explorer %LOCALAPPDATA%\Barrier\SSL\Fingerprints
```

Copy the whole `v2:sha256:...` line each way:

- **Windows `Local.txt`** → append to the Mac's `TrustedClients.txt`
- **Mac `Local.txt`** → append to Windows' `TrustedServers.txt`

One fingerprint per line, no trailing spaces. On the Mac, the GUI offers a
dialog for the client half when it connects, which does the same thing.

## 7. Run it for real

Start the server on the MacBook, then:

```bat
build\bin\Release\barrierc.exe --name windows 192.168.3.79
```

Push the mouse off the right edge of the MacBook screen. Keyboard follows the
pointer. `Cmd` acts as `Ctrl` on the PC, so Cmd+C and Cmd+V work as you expect.

Leave the window open — closing it disconnects the client. To keep it running
without a console window, make a shortcut to `barrierc.exe` with the arguments
in the Target field and set it to run minimised.

---

## Troubleshooting

**`cl.exe not found`** — you are in a plain `cmd` window. Use "x64 Native Tools
Command Prompt for VS".

**CMake cannot find OpenSSL** — step 3 was skipped, or vcpkg lives somewhere
other than `C:\vcpkg`. Point the script at it:
```bat
set VCPKG_ROOT=D:\path\to\vcpkg
build-windows-client.bat
```

**`Compatibility with CMake < 3.5 has been removed`** — you are on an old
checkout. Pull the `security-hardening` branch; the version floors were raised.

**`libcrypto-3-x64.dll` missing on launch** — copy it and `libssl-3-x64.dll`
from `C:\vcpkg\installed\x64-windows\bin\` into `build\bin\Release\`.

**`failed to verify server certificate fingerprint`** — step 6 was missed, or a
line was pasted incompletely. The entire `v2:sha256:...` line must be copied.

**`unrecognised client name`** — the server's config has no screen matching your
`--name`. It must be exactly `windows` to match `doc/mac-to-windows.conf`.

**Connects, but no keystrokes arrive** — check for an old `barrierd` service
left by a previous install, and remove it from an administrator prompt:
```bat
sc stop Barrier
sc delete Barrier
```

**Cannot reach the Mac at all** — check the MacBook's firewall allows incoming
TCP 24800. Nothing needs opening on the Windows side; the client dials out.
