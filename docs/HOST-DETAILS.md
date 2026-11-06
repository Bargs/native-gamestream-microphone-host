# Native NVIDIA GameStream microphone host support

This supplies the Windows side of forwarding a Mac microphone through NVIDIA's existing native GameStream receiver. It accompanies [Moonlight macOS client PR2095](https://github.com/moonlight-stream/moonlight-qt/pull/2095) and [common-c PR173](https://github.com/moonlight-stream/moonlight-common-c/pull/173). It adds no separate audio receiver or driver.

## What has worked

With the original working helper, live speech from the Mac reached a Windows ChatGPT voice conversation and produced a response, confirmed by the user. Synthetic audio also reached the Windows WASAPI recording endpoint, including after a service restart and after disconnect/resume with the same Desktop/streamer process.

That evidence applies to **GameStream 7.1.437.0, GeForce Experience 3.25.1.27 and native audio 4.37.0.0** on the tested host. The [manual and evidence guide](../MANUAL-EQUIVALENCE.md) separates those historical results from the distributed build.

The **distributed review3 build** has source review and a [successful public Windows build](https://github.com/Bargs/native-gamestream-microphone-host/actions/runs/42303201066), with 93 isolated checks passing in each of Windows PowerShell and PowerShell. Its complete source/build artifact is available from that run. This rebuilt package has **not yet been installed or tested for live audio delivery**. Real task/ACL installation, interrupted-install recovery, reconnect stress, reboot and full uninstall/reinstall remain acceptance work.

## Why the Windows host needs assistance

On the tested NVIDIA build, a client microphone sender alone was insufficient. NVIDIA's native microphone path needed enabling and registration, and its receiver needed a valid native control handle shared from another NVIDIA process. This companion enables that existing path; the two registry flags alone do not perform the runtime registration and handle sharing.

The changes are specific to exact NVIDIA file versions. [PATCHES.md](../PATCHES.md) and the [manual](../MANUAL-EQUIVALENCE.md) disclose the instructions, offsets and required hashes. Other versions are refused rather than patched by guesswork. No NVIDIA executable, DLL or driver is redistributed.

## What installation changes

With administrator approval and an idle GameStream application, the installer:

1. Preserves the original executable and the exact presence, type and literal value of both registry settings in a protected installation directory.
2. Generates a patched copy of the matching local `nvstreamer.exe`, changing four bytes, and verifies its complete hash. It stops `NvContainerLocalSystem` to install that copy.
3. Sets `EnableGFNMicStreamerSupport` and `EnableGFNMicSupport` to DWORD 1 under the 64-bit NVIDIA registry key.
4. Copies the reviewed source and built helper to `%ProgramFiles%\BargarArtNativeGameStreamMic`, protects them against ordinary-user writes, and records the selected streaming account.
5. Creates and starts the scheduled task described below, restarts the NVIDIA service, and waits for fresh registration status from the current helper. Registration status is not proof of audible delivery.

The optional `NativeMicSetup.exe` only launches the disclosed adjacent scripts. Users can inspect and build the source, then invoke those scripts directly. Keep the whole source package together; the EXE is not a standalone installer.

## Exactly when the SYSTEM task runs

The task is named **`BargarArt.NativeGameStreamMic`**, in Task Scheduler's root folder. The installer starts it immediately. Its two automatic triggers are **Windows startup** and **logon of the selected streaming user**.

It runs `watch.ps1` through Windows PowerShell as **SYSTEM**, with the highest run level and a hidden window. SYSTEM is the chosen implementation because registration and handle sharing operate across NVIDIA processes, including privileged processes; a reduced-privilege design has not been validated.

Once started, the watcher continues in the background, including while no Moonlight session is connected. It has no execution time limit, may run on battery, and ignores an additional launch while an instance is already running. It checks NVIDIA processes roughly every 200 ms, rechecks file/package hashes, registers new matching processes, and refreshes the shared handle when the native session-log marker changes. Process-memory changes need reapplying when NVIDIA processes are replaced, which is why a one-time file/registry edit does not replace this watcher.

The helper reads native session-log markers locally and writes bounded, rotated status/error logs. It does not record microphone audio or send a separate audio stream. Its persistent background execution and SYSTEM privilege are part of the proposal for maintainers to evaluate.

## How to remove it

From the complete reviewed package, use an administrator PowerShell with the GameStream application idle:

```powershell
.\uninstall.ps1 -DryRun
.\uninstall.ps1
```

Uninstall disables and stops the owned task, stops the NVIDIA service, restores the known managed executable and registry values, removes the owned task, and independently attempts service restart/readiness. It preserves a foreign replacement task, a different vendor executable and later registry edits for inspection. Backups, source, configuration and recovery evidence remain on disk. Recovery faults are collected and recorded rather than reported as successful cleanup.

Stopping or deleting the task alone does not restore the disk patch or registry flags. The [full manual](../MANUAL-EQUIVALENCE.md) explains recovery, retained files and the equivalent effects of each step.

## Source build and audit

Download the [complete source package](https://github.com/Bargs/native-gamestream-microphone-host/archive/refs/heads/main.zip), inspect it, and build with 64-bit Windows PowerShell:

```powershell
powershell.exe -NoProfile -File .\build.ps1
powershell.exe -NoProfile -File .\tests.ps1
```

- [Manual/source-build equivalence](../MANUAL-EQUIVALENCE.md): exact versions and hashes, compiler commands, optional launcher modes, task definition, runtime changes, persistence and rollback.
- [Patch details](../PATCHES.md): local vendor instruction changes and runtime hook.
- [Build provenance](../build-provenance.json) and [package manifest](../package.json): reviewed source/compiler/output hashes. Binaries are unsigned and the .NET Framework build is nondeterministic; rebuilding regenerates the manifest. Hashes establish consistency, not publisher trust.
- [Public build workflow](../.github/workflows/build.yml): compiles the helper/launcher and runs isolated fixtures in both PowerShell runtimes. It never invokes installation or patches a live NVIDIA process.
- [Historical source/protocol review](../historical-review-evidence.md): earlier recovery findings and the limits of the saved RTSP evidence.

## Technical limits for review

Runtime instruction replacement is **not atomic**; readback, cache-flush and protection checks do not make concurrent execution safe. Successful handle-refresh ownership/lifetime remains unresolved for long sessions and repeated reconnects. Process/task identity checks also retain non-atomic check/mutate races. These are specific runtime review issues in addition to the live acceptance work above.

The paired client uses NVIDIA's legacy AES-CBC audio mode without packet authentication. IVs repeat and overlap the playback domain. It requires encrypted mode and private IPv4, intended for a trusted network or separately secured tunnel; a private address does not authenticate traffic. This is native NVIDIA GameStream support, separate from a proposed Sunshine microphone protocol.

Would Moonlight maintainers prefer the optional source-built launcher alongside these manual instructions, manual/source-build instructions only, or another host integration and distribution approach?


