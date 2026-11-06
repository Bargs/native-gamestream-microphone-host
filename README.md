# Use your Mac microphone in a Windows game or voice chat

This is the Windows companion for sending your Mac microphone through Moonlight to NVIDIA's existing native GameStream microphone receiver.

**Available today:** the compatible Mac client is [source you must build](https://github.com/Bargs/moonlight-qt/tree/native-microphone-forwarding#building); this change has no published Mac installer here yet. The [Windows ZIP](https://github.com/Bargs/native-gamestream-microphone-host/archive/refs/heads/main.zip) includes source, helper and an optional setup launcher. The distributed Windows build has source review and public build checks; its installation and live microphone delivery still need testing.

## What worked, and which setups qualify

With the **original working helper**, live speech from the Mac reached a Windows ChatGPT voice conversation and produced a user-confirmed response. Synthetic audio reached the Windows recording endpoint after a service restart and after disconnect/resume. This establishes the native route on the tested setup, rather than acceptance of the rebuilt download or a test in every game.

The tested host was **64-bit Windows with NVIDIA GameStream 7.1.437.0, GeForce Experience 3.25.1.27 and native audio 4.37.0.0**. Installation requires exact [NVIDIA file hashes](MANUAL-EQUIVALENCE.md#exact-compatibility-and-effects); other versions await verification. This is for NVIDIA GameStream, not Sunshine.

The integrated Mac client was built and tested on **macOS 15.6.1, Apple Silicon**. Use a trusted private IPv4 network or a separately secured tunnel. Protocol limits are below.

## What will run on your PC

On the tested NVIDIA version, a client microphone sender alone was insufficient. The host needed its existing microphone path enabled, registered and connected to a native control handle.

Installation backs up the original executable and registry state, changes four bytes in your matching local NVIDIA executable, sets two NVIDIA registry flags, and adds a background helper. It installs no separate audio receiver or driver and includes no NVIDIA executable or DLL.

The helper is a scheduled task named **BargarArt.NativeGameStreamMic**. The installer starts it immediately; it also starts at **Windows startup** and **logon of the selected streaming user**. It runs as **SYSTEM**, a powerful Windows account, to work across NVIDIA processes.

While running, it checks roughly every 0.2 seconds and reapplies runtime changes when matching NVIDIA processes or session markers change. It continues when Moonlight is disconnected, has no time limit, and can run on battery. Fatal verification/runtime errors stop it. It reads local NVIDIA session markers and keeps status/error logs; it does not record microphone audio. [Exact task behavior, privileges and installer effects](docs/HOST-DETAILS.md) are disclosed before installation.

## Setup walkthrough

These are the disclosed source/launcher steps. **The distributed build's full installation, live audio, reboot and uninstall walkthrough has not yet been validated.** The [manual](MANUAL-EQUIVALENCE.md) separates the original helper's live results from this rebuilt package.

### Mac: get the compatible client first

1. Get the [microphone-enabled Moonlight source](https://github.com/Bargs/moonlight-qt/tree/native-microphone-forwarding) and follow its [Mac build instructions](https://github.com/Bargs/moonlight-qt/tree/native-microphone-forwarding#building). **There is no normal Mac app download for this change here yet.** If you need a ready-to-install app, this is the step to wait at.
2. Confirm your build contains **Settings → Audio Settings → “Forward microphone to NVIDIA GameStream for this run.”** Leave it off until the Windows host is ready. Keep your current working Moonlight app available.

### Windows PC: review and set up the host

3. Download and extract the [complete Windows ZIP](https://github.com/Bargs/native-gamestream-microphone-host/archive/refs/heads/main.zip). Keep its files together. Read the [manual changes and rollback](MANUAL-EQUIVALENCE.md). You can [build from source](docs/HOST-DETAILS.md#source-build-and-audit) instead of trusting the unsigned supplied launcher.
4. In PowerShell opened in the extracted folder, run `.\NativeMicSetup.exe --dry-run`. It checks package and NVIDIA hashes without administrator approval or writes. Passing this check does not validate a real installation.
5. If you choose to test installation, save your work and end the GameStream application/session so the host is idle. Disconnecting Moonlight alone can leave a streamed Desktop session running. Run `.\NativeMicSetup.exe --install-experimental`. Windows asks for administrator approval and opens a visible installation console. This briefly restarts NVIDIA's service and installs the changes/background task above. The script route supports [explicit streaming-account selection](MANUAL-EQUIVALENCE.md).

### Mac and Windows: enable and verify the microphone

6. On the Mac, turn on **Forward microphone to NVIDIA GameStream for this run** and connect. At the first microphone permission request, grant access and reconnect. The preference starts off and is not saved for the next app run.
7. Confirm Moonlight shows **Microphone forwarding ON**. On Windows, check for the NVIDIA recording/input device in sound settings, speak, and check its input level. Then select that input in your game or voice app and use its microphone check. The exact device label varies and was not retained in the successful probe records. **This Windows settings/game walkthrough and live delivery with the distributed build still need confirmation.** A helper status such as **SourceReady** is not an audio test.
8. Press **Control + Option + Shift + N** on the Mac to stop forwarding immediately. Reconnect to enable it again. This stops Mac capture; the Windows host setup stays installed.

## Undo the Windows changes

With the GameStream application idle, run `.\NativeMicSetup.exe --uninstall` from the same complete extracted package and approve the Windows administrator prompt. The source-only alternative is `.\uninstall.ps1` in an administrator PowerShell.

Uninstall stops/disables the owned task, restores the known managed NVIDIA executable and registry state, removes the owned task, and attempts to restart NVIDIA's service. It preserves later edits, a different vendor version and unrelated replacement tasks for inspection. Backups, source and recovery records stay on disk. **The distributed build's real uninstall/recovery acceptance remains unrun.**

Stopping or deleting only the task does not undo the executable and registry changes. The [full manual](MANUAL-EQUIVALENCE.md) explains complete reversal and recorded recovery errors.

## Source, evidence and remaining limits

The [public Windows build](https://github.com/Bargs/native-gamestream-microphone-host/actions/runs/42303201066) compiled the helper/launcher, passed **93 isolated checks in each of two PowerShell runtimes**, and published a source/build artifact. It did not install the package or exercise a live NVIDIA process. Binaries are unsigned and builds are nondeterministic; hashes identify a package rather than a trusted publisher.

Native transport is legacy AES-CBC without packet authentication, with repeated IVs and overlapping playback/microphone domains. A private address does not authenticate traffic. Runtime instruction replacement is not atomic; process/task identity checks retain races, and successful handle-refresh lifetime remains unresolved for long sessions/repeated reconnects. Actual installation, interrupted recovery, reconnect stress, reboot and full uninstall/reinstall still need acceptance testing.

- [Host details](docs/HOST-DETAILS.md): installer effects, SYSTEM task lifecycle, source build/audit and technical cautions.
- [Complete manual/source equivalent](MANUAL-EQUIVALENCE.md): versions/hashes, commands, persistence and rollback.
- [Patch details](PATCHES.md), [build provenance](build-provenance.json), [package hashes](package.json), and [historical protocol/source review](historical-review-evidence.md).
- Moonlight contributions: [Mac client PR2095](https://github.com/moonlight-stream/moonlight-qt/pull/2095) and [common-c PR173](https://github.com/moonlight-stream/moonlight-common-c/pull/173).

For maintainers: would you prefer the optional source-built launcher plus full manual instructions, manual/source-build instructions alone, or another integration and distribution approach?

