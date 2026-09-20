# MacBook keyboard and trackpad → Windows PC

The MacBook is the **server** (it has the keyboard). The Windows PC is the
**client** (it receives input). Everything you type crosses the network, so the
link is TLS-encrypted and both ends check each other's certificate fingerprint.

Two setup steps are unavoidable and worth understanding, because they are the
ones that actually stop a stranger on your network from receiving your
keystrokes:

1. macOS must grant Barrier the Accessibility permission, or the server cannot
   read the keyboard at all.
2. Each machine must be told to trust the other's fingerprint, once.

---

## 1. Build on the MacBook (server)

```sh
brew install cmake qt@5 openssl@3
git submodule update --init --recursive

cmake -S . -B build \
  -DCMAKE_PREFIX_PATH="$(brew --prefix qt@5);$(brew --prefix openssl@3)" \
  -DBARRIER_BUILD_INSTALLER=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build -j8
```

`-DBARRIER_BUILD_INSTALLER=ON` is what produces `build/bundle/Barrier.app`.
**Build the bundle, do not run the bare binaries.** macOS attributes privacy
permissions to the application that owns a process, and a loose executable in
`build/bin/` has no application identity — it inherits your terminal's. The
Accessibility grant then either lands on Terminal or cannot be made at all.

`qt@5` is deprecated in Homebrew and disappears in May 2027. Only the GUI needs
it — add `-DBARRIER_BUILD_GUI=OFF` to build just the command-line tools.

## 2. Build on the Windows PC (client)

You need Visual Studio (2017 or newer) and CMake. You do **not** need Qt: the
Windows side only runs the client, which takes one command line, so skip the
GUI and skip the single most painful Windows dependency.

Get an OpenSSL 3.x for MSVC. The least painful route is vcpkg:

```bat
vcpkg install openssl:x64-windows
```

Then, from a Visual Studio developer prompt in the repo:

```bat
cmake -S . -B build -A x64 ^
  -DCMAKE_TOOLCHAIN_FILE=C:\path\to\vcpkg\scripts\buildsystems\vcpkg.cmake ^
  -DBARRIER_BUILD_GUI=OFF -DBARRIER_BUILD_INSTALLER=OFF ^
  -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

`build\bin\Release\barrierc.exe` is what you want. Copy the OpenSSL DLLs from
vcpkg next to it if it will not start.

> The old build linked prebuilt OpenSSL 1.0.2l binaries that were committed to
> this repo in 2017 and went end-of-life in 2019. They are gone; the build now
> finds a current OpenSSL the normal way.

## 3. Install the app and grant Accessibility

```sh
cp -R build/bundle/Barrier.app /Applications/
open /Applications/Barrier.app
```

Copy it to `/Applications` first. The permission is pinned to the app, and
moving or replacing the app afterwards invalidates it.

On first launch Barrier asks for Accessibility itself and macOS offers to open
the right settings pane. If you dismissed that prompt, go to System Settings →
Privacy & Security → Accessibility and enable **Barrier** — it will already be
listed, because launching the app is what puts it there. You cannot usefully add
it with the "+" button before it has asked.

macOS may also ask for **Input Monitoring**. Grant that too; the server reads
the keyboard through an event tap.

Without Accessibility the server exits immediately with:

```
FATAL: assistive devices does not trust this process, allow it in system settings.
```

That message means the permission is missing, nothing else.

**After you rebuild.** The app is ad-hoc signed, which is all a locally built
app can be without an Apple Developer certificate. Its identity changes every
time you rebuild, so macOS may stop honouring the grant. If the server starts
refusing after a rebuild, remove Barrier from the Accessibility list with the
"−" button, re-copy the app to `/Applications`, and launch it again.

## 4. Exchange fingerprints (once)

Run each program once so it generates its certificate. Both now do this by
themselves on first start — previously only the GUI did, so a command-line-only
install had no certificate and could not use TLS at all.

Each machine writes its own fingerprints to `Local.txt` and logs the SHA256 at
startup:

| | profile directory |
|---|---|
| macOS | `~/Library/Application Support/barrier/` |
| Windows | `%LOCALAPPDATA%\Barrier\` |

Fingerprint files live under `SSL/Fingerprints/` in there.

Now copy one line each way — the `v2:sha256:...` line from each machine's
`Local.txt`:

- Windows `Local.txt` → append to the MacBook's `SSL/Fingerprints/TrustedClients.txt`
- MacBook `Local.txt` → append to Windows's `SSL/Fingerprints/TrustedServers.txt`

If you run the GUI on the Mac, it offers a dialog for the client half instead,
and it now warns loudly if a fingerprint you already trusted has *changed*
rather than showing the same routine prompt it shows for a first connection.

## 5. Run it

On the MacBook, either use the GUI you already launched (set **Screen name** to
`mac`, choose **"Use existing configuration:"** and point it at
`doc/mac-to-windows.conf`, then press **Start**), or run the server
inside the bundle directly:

```sh
/Applications/Barrier.app/Contents/MacOS/barriers \
    --name mac -c doc/mac-to-windows.conf -f
```

On the Windows PC (replace with the MacBook's IP):

```bat
build\bin\Release\barrierc.exe --name windows 192.168.1.50
```

`--name` must match the screen names in the config file. `-f` keeps the server
in the foreground so you can see the log; drop it once it works.

Push the pointer off the right-hand edge of the MacBook screen and it appears on
the PC, with the keyboard following it. `doc/mac-to-windows.conf` assumes
the PC sits to the right — swap `right`/`left` in the `links` section if not.

---

## The keyboard specifically

**Command behaves like Control on the PC.** The config maps macOS's Command key
(which Barrier reports as `super`) to Control, and Control to the Windows key, so
Cmd+C, Cmd+V and Cmd+Tab do what your fingers expect. Delete those two lines in
the `windows:` section if you would rather they pass through unchanged.

**Media and brightness keys work.** macOS reports them as system-defined events
and Barrier forwards them.

**The `fn` key does not cross.** It is handled in hardware on the Mac and never
becomes an event Barrier can see. This is a Mac hardware limitation, not
something configuration fixes.

**F1–F12:** if your MacBook sends brightness/volume instead of function keys,
either hold `fn`, or turn on "Use F1, F2, etc. keys as standard function keys" in
macOS keyboard settings.

## If something goes wrong

**Server exits with "assistive devices does not trust this process"** — step 3.

**Client connects then immediately drops, log says `failed to verify server
certificate fingerprint`** — step 4 was missed or the line was pasted wrong. The
whole `v2:sha256:...` line must be copied, one per line.

**Server logs `unrecognised client name "..."`** — the client's `--name` does not
match a screen in the config. They must match exactly.

**Nothing connects at all** — check the Mac's firewall allows incoming TCP 24800.
The installer no longer opens this port for you; on the Windows side nothing
needs opening, because the client dials out.

**Connection works but no keys arrive** — make sure you are not running an old
`barrierd` service on Windows. It is no longer installed or built; if a previous
install left one behind, remove it with `sc delete Barrier` from an
administrator prompt.
