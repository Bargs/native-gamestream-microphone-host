# Native NVIDIA GameStream microphone: manual/source-build and optional launcher

This document describes **candidate v1 review3**, ZIP SHA256 `5A61C00771FF2A3DAE7E571A9E89DAA0BC08D4ECA4D966E17CD834032B651CA9`. It replaces the earlier prototype-only comparison; that earlier document remains preserved separately. Review3 is an inspectable build candidate, not an installed or live-accepted release. Independent source review found the earlier preservation/readiness issues addressed. Actual activation remains a separate, explicitly authorized action with the runtime and acceptance limits below.

The optional executable and manual route disclose the same changes. A person can inspect the source, build the helper and launcher locally, and invoke the scripts directly. The launcher is a convenience path, not a prerequisite or an embedded NVIDIA installer.

## Exact compatibility and effects

Historical native acceptance used GameStream 7.1.437.0, GeForce Experience 3.25.1.27 and native audio 4.37.0.0. This candidate requires the following file hashes. Other builds are unverified and are refused rather than patched heuristically.

| File | Expected original SHA256 |
| --- | --- |
| nvstreamer.exe | 692BCEE24D826B639EFCA7C77D3E1131EF464924DE647233822C6E660C0333F3 |
| NvStreamUserAgentPlugin.dll | EDEB124040E78C11332D29C92256FBE377EB9C0284ECE29F4E6EB64BD99A264C |
| nvaudcap64v.dll | 6114183B57A9F485263B7891EB4D8F68CBCED50FFE65083BC21FE1DC5EB69839 |
| nvcontainer.exe | B023A93E13EE20A16791E98FBB6231FB83613E84255BBE8C8EA87930D4467E7A |

Host operations require a 64-bit Windows process, administrator approval and an idle native GameStream application (`currentgame=0` in local serverinfo). Closing Moonlight alone may leave a streamed Desktop application running. The installer asks for explicit acknowledgement of experimental runtime patching. It preserves an unknown install/task/version for inspection. Actual task/ACL/native-runtime/reboot/full-uninstall acceptance with this new build remains unrun.

| Host effect | Manual/source equivalent | Verification and reversal |
| --- | --- | --- |
| Review source/payload integrity | Inspect package.json's 12 operational/source/build/test/binary files; verify hashes with PowerShell before choosing elevation | Hashes prove consistency with the manifest, not publisher identity. Keep a trusted source copy |
| Choose streaming account | Supply `-TargetUserSid` to install.ps1 or let it translate the current console account | It does not assume the elevated administrator is the streaming user. SID remains in protected local runtime-config.json |
| Protect root/payloads | Inspect management.ps1 ACL functions; create the fixed Program Files root with inheritance disabled, administrator/SYSTEM ownership, SYSTEM/Administrators full control, Users read/execute; reject links and ordinary-user write grants | Verify the complete installed tree before privileged use. Do not reuse an unrelated directory |
| Preserve original baseline | Copy/hash original vendor executable; record exact presence/type/raw value of both registry flags in an installation journal before vendor mutation | Registry64 reads use DoNotExpandEnvironmentNames. Keep literal REG_EXPAND_SZ tokens and binary/multistring types intact |
| Generate disk patch locally | Patch a copy of the user's verified nvstreamer.exe at **file offset 1136171 / 0x11562B**, changing exactly `45 0F B6 00` to `41 B0 01 90` | All other bytes remain original. Verify resulting SHA256 below; keep original backup. Do not redistribute the NVIDIA executable |
| Stop vendor service and install local patch | With host idle, stop NvContainerLocalSystem, copy the generated verified patched file into its vendor location | Explicit recovery restores only known managed patched bytes from the verified original; unknown vendor versions remain untouched |
| Enable native registry flags | Under 64-bit `HKLM\SOFTWARE\NVIDIA Corporation\NvStreamSrv`, set `EnableGFNMicStreamerSupport` and `EnableGFNMicSupport` to DWORD 1 using Registry Editor or inspected source commands | Back up first. Restore original type/raw value or original absence only while the current value is still managed DWORD 1; preserve later edits |
| Build native runtime helper | Compile NativeMic.cs + Registration.cs + RuntimeSafety.cs with the disclosed 64-bit compiler command | Record exact source/compiler/output hashes. A source build still executes privileged native code |
| Enable registration branch in memory | Invoke the inspected registration helper on the validated native user-agent process/module | Three runtime bytes at module+0xD6D1C: `40 32 ED` → `40 B5 01`. Plugin file remains original on disk |
| Share native control handle | Invoke the inspected native helper to locate a unique validated source control session, duplicate its driver handle into nvstreamer and replace the receiver's open-control path in memory | All 17 observed baseline bytes are checked; readback/cache/protection results are checked. Runtime writes are not atomic and native ownership remains experimental |
| Persist helper | Create the exact SYSTEM/highest startup + selected-user-logon task below, pointing only at the protected watcher | The whole watcher runs as SYSTEM. Each recovery task mutation re-reads root task name/path, description marker, exact single action and SYSTEM/highest/service-account principal; foreign replacements are preserved and recorded |
| Verify new helper and microphone | Require fresh SourceReady, then synthetic input at the actual Windows recording endpoint | SourceReady/StreamReady alone is not audible input. A fresh run nonce, built-helper hash, timestamp and validated live source PID/start/path/session/owner bind readiness to the current attempt; prior status is preserved |
| Undo and preserve recovery evidence | Explicit idle-host recovery stops/disables the owned task, stops service, restores managed file/flags, removes owned task, then independently attempts service restart/readiness | Each cleanup fault is collected; failed service stop defers file/registry writes. RecoveryRequired remains when any step fails. Backups, source, config and logs remain |

Patched nvstreamer.exe SHA256: `37E62C2F107EB2EBE4F185C965AAAEDE5689818DD32BA5A0925E9F90C8E4E99F`. The instruction's image VA is `0x14011622B` and RVA is `0x11622B`; those are different from its disk file offset `0x11562B`. A hex editor must use the disk offset. Modifying the executable changes its vendor signature status. The vendor plugin/audio DLLs remain unmodified on disk.

## Source build and optional executable

From a separate writable, trusted source package, inspect then use 64-bit Windows PowerShell:

```powershell
powershell.exe -NoProfile -File .\build.ps1
powershell.exe -NoProfile -File .\tests.ps1
```

The actual compilation recipes are:

```powershell
& 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /nologo /target:library /platform:x64 /out:NativeInterop.dll NativeMic.cs Registration.cs RuntimeSafety.cs
& 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /nologo /target:exe /platform:x64 /out:NativeMicSetup.exe Launcher.cs
```

build.ps1 regenerates the package manifest and provenance after compilation. Review3 records compiler version `4.8.9221.0 built by: NET481REL1LAST_25H2`, compiler SHA256 `46809206887326D2D24DB1EFF1F3064DE972C3451ABE766B49111450A5E08E00`, five source/build input hashes, architecture x64 and these outputs:

| Artifact | Bytes | SHA256 |
| --- | --- | --- |
| NativeInterop.dll | 10240 | 0D57A6256C840F08E0D66FE8F0E5FC2D6D7DB291E6163FD6D95D8A51F5841085 |
| NativeMicSetup.exe | 5120 | C628709F03202674140E77AC8FA7A00C55926A841C083A9C0BA077BEB9FEEC24 |

Both are unsigned, nondeterministic .NET Framework builds. The package/source/output hashes are internally consistent; no bit-for-bit independent rebuild is claimed. A local rebuild may change binary hashes and must regenerate the manifest. The watcher reads the compiled helper's expected hash from that manifest rather than pinning an old private DLL.

NativeMicSetup.exe accepts only `--dry-run` (also the default), `--install-experimental`, `--recover`, or `--uninstall`. It invokes the fixed adjacent install/uninstall script through Windows PowerShell `-File`; it accepts no arbitrary script/command argument. Default dry run does not elevate. The other modes request normal Windows administrator approval and run a visible console. Keep the complete adjacent package together. Explicit user-account selection is available through install.ps1, not an arbitrary launcher argument.

The direct script route is the same source behavior, without the convenience launcher:

```powershell
.\install.ps1 -DryRun
.\install.ps1 -TargetUserSid '<chosen account SID>' -AcknowledgeExperimentalRuntime
.\install.ps1 -Recover -AcknowledgeExperimentalRuntime
.\uninstall.ps1
```

These are documented entry points for a future authorized activation, not instructions to run the current review snapshot now. Installation/retry from the retained install root is explicitly rejected before staging/copying; use a separate intact reviewed package. The retained root still supports inspection and recovery.

## Native runtime details

Registration changes the validated user-agent plugin's branch in process memory. NativeMic scans committed private RW/WriteCopy memory for the native `0x010801A8` wrapper/API marker, expected function pointers at audio base+0x11260 and +0x115B0, registered session state and bounded control-handle form. Exactly one distinct session is required. DuplicateHandle transfers a native control handle into the streamer with SAME_ACCESS. A 17-byte replacement at target audio base+0xB7E0 stores that handle in the receiver instance and returns success. Full source describes both expected and replacement bytes.

RuntimeSafety rechecks expected instructions immediately before writing, restores memory protection, flushes instruction cache and verifies readback. A duplicate created before a pre-write failure is closed explicitly. After a write attempt, it can be referenced by the receiver and is retained until target teardown. Restart-required failures stop the watcher. These checks do not suspend target threads or make instruction replacement atomic. Prior successful refresh duplicates can remain until receiver exit; no claim of bounded handles through unlimited reconnects is made.

Registry and disk edits alone cannot implement this driver-handle handoff. “Manual” means a person can inspect, compile and invoke the disclosed source with appropriate Windows tools/admin rights. It does not mean the native operations can all be performed through Registry Editor or Task Scheduler alone. No separate receiver or new driver is provided by this package; the existing native NVIDIA path supplies those functions.

## Persistence, local records and reversal

- Task name `BargarArt.NativeGameStreamMic`; principal SYSTEM/service account/highest.
- Startup and selected-user-logon triggers; IgnoreNew instances; no execution limit; hidden task; permits/continues battery operation.
- Fixed Windows PowerShell path; arguments `-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File` pointing at protected watch.ps1.
- Task DACL `D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GR;;;BU)`.
- Watcher checks package/vendor pins, selected SID/session/process start/module identity, polls roughly every 200ms and hashes the latest native session-log line as a reconnect heuristic.
- Local records include selected SID in runtime-config, original registry baseline, source/streamer PIDs, timestamps/status/errors and rotated runtime logs. Audio/key/credential logging is absent from inspected helper code. The public package contains no personal SID, network identity, raw private log or voice recording.

Staging/Installing/RecoveryRequired states require explicit recovery. Unknown owner/ACL/build/task/version, incomplete baseline, mismatched backup or interrupted `.new` state write require inspection. Installed state checks package/build, patched file and task action/principal before reporting unchanged. RolledBack permits a retry from an external reviewed package; same-root self-copy is guarded. Each recovery task operation validates the current task and passes its validated object to the OS command. An administrator can still replace it in the non-atomic interval between validation and mutation; no atomic ownership guarantee is claimed. Recovery preserves later registry edits and unrelated vendor versions. Restarting the relevant vendor processes resets in-memory patches; verify process restart rather than assuming every user-session process ends with one service stop.

## Evidence boundaries and maintainer choice

Review3's 93 checks pass under Windows PowerShell 5.1 x64 and PowerShell 7 x64. They exercise parsing, manifest consistency, synthetic byte arrays, in-memory registry-shaped fixtures, state policy and recording cleanup/activation mocks, production recovery with foreign/replaced tasks, external-root retry policy and stale/malformed readiness rejection. They do not install a task, set real NVIDIA registry values, patch live memory or prove input for the rebuilt DLL. Earlier real scratch-key tests established the original registry defects and a reference correction; generalized production-source real-registry acceptance is separate.

Historical original-helper evidence includes encrypted Mac synthetic tone reaching Windows WASAPI, a user-confirmed live speech response, service restart and same-process disconnect/resume. It does not establish this rebuilt helper's native input, reconnect stress, reboot or full uninstall/reinstall behavior. Historical `mic:0` before successful SETUP port48002 comes from an unframed socket.Available collector, not a complete Content-Length-bounded SDP capture. Keep that qualification.

Ask maintainers which distribution they prefer: the source-traceable optional launcher, manual/source-build instructions only, or another approach. A regular PR may propose this experimental complete path while plainly identifying compatibility, privileges and acceptance boundaries. It does not imply maintainer endorsement or production-readiness of the convenience package.
