# Experimental native NVIDIA GameStream microphone host candidate

Inspection/build candidate, version 1. This package has **not been installed or exercised against the live host**. The existing working prototype is preserved. No vendor executable or driver is distributed. This package uses the existing NVIDIA receiver, changes four bytes in the matching local vendor executable, sets two registry flags and creates a privileged runtime helper task. Review these changes before choosing to run it.

## Build and optional executable

Use 64-bit Windows PowerShell on Windows with the .NET Framework compiler:

```powershell
powershell.exe -NoProfile -File .\build.ps1
powershell.exe -NoProfile -File .\tests.ps1
```

build.ps1 invokes `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` with `/target:library /platform:x64 /out:NativeInterop.dll NativeMic.cs Registration.cs RuntimeSafety.cs`, then `/target:exe /platform:x64 /out:NativeMicSetup.exe Launcher.cs`. The manifest is regenerated after both compilations and covers all operational/source/build/test files and both compiled artifacts. build-provenance.json identifies source input, compiler and binary hashes. This .NET Framework build is not deterministic or signed. A rebuild can produce different binary hashes. The manifest detects mismatched package files; it is not a vendor signature or independent trust anchor. Obtain/review the source through a trusted path before elevating anything.

NativeMicSetup.exe is optional: a small source-built launcher, not a self-contained installer. Keep the whole verified package together. With no argument or `--dry-run`, it checks without elevation. Other accepted arguments are `--install-experimental`, `--recover`, `--uninstall`; these request elevation and invoke the corresponding disclosed script. It accepts no arbitrary script or command argument. It opens the normal visible installation console so the user can inspect the outcome. Running it was deliberately excluded from this review build.

## Manual equivalent

Read all scripts and PATCHES.md before executing. Every step below corresponds to disclosed script/C# source; no hidden native payload is embedded.

1. Verify package hashes and exact vendor dependency hashes. Back up nvstreamer.exe and preserve the presence/type/literal value of both registry flags. Use explicit 64-bit registry access and `DoNotExpandEnvironmentNames`; existing REG_EXPAND_SZ text must stay literal. Save JSON baseline before any vendor mutation.
2. Choose the intended streaming Windows user's account SID with `-TargetUserSid`. If omitted, the installer translates the current console account to a SID. It does not assume that an elevated installer account is the streaming account. No hardcoded machine SID or old experiment PID appears in this candidate.
3. Quit the streamed application so native currentgame is zero; Windows applications/work can remain open. The installer requires administrator approval and an explicit experimental-runtime acknowledgement. It preserves a different existing installation/task rather than migrating it implicitly.
4. Protect the fixed Program Files installation directory and each payload, baseline and configuration file: SYSTEM/Administrators full control, ordinary Users read/execute, Administrators owner. Links are refused. Copy the verified source and built payloads. The intended SID is written only to protected runtime-config.json.
5. Generate the patched executable locally from the exact original SHA256 and expected four bytes at offset 1136171. Verify the complete result hash. Stop NvContainerLocalSystem, replace those vendor bytes through the generated local candidate, set `EnableGFNMicStreamerSupport` and `EnableGFNMicSupport` as DWORD 1 under the disclosed 64-bit NVIDIA key.
6. Create the fixed SYSTEM/highest task at startup and intended-user logon. Exact action, arguments, principal, triggers, settings and task DACL are inspectable in install.ps1. Start the helper before restarting the service. The persistent watcher verifies source-built runtime and vendor pins; it registers the native mic and shares the native control handle using the disclosed C# implementations. Registry/file edits alone do not perform this process-memory work.
7. Confirm SourceReady, connect the client and verify actual recording input. A status file is not proof of audible delivery. No broad compatibility claim follows from the historical prototype tests.

Equivalent script entry points, for a **future explicitly authorized installation**:

```powershell
.\install.ps1 -DryRun
.\install.ps1 -TargetUserSid '<chosen account SID>' -AcknowledgeExperimentalRuntime
.\install.ps1 -Recover -AcknowledgeExperimentalRuntime
.\uninstall.ps1
```

Elevated recovery/uninstall require an idle host. They retain backups, source and evidence. The original executable is restored only when the current file matches this managed patch; a different vendor version is preserved for inspection. Registry restoration touches only current managed DWORD1 entries, preserving later edits. Cleanup actions collect errors independently; service restart and host-readiness checks are attempted even when task/file/registry recovery fails. A failed service stop defers vendor file/registry restoration. RecoveryRequired remains recorded when any recovery step fails.

Staging/Installing/RecoveryRequired states require explicit recovery; they never silently resume mutation. A confirmed Installed state checks package/build, patched file and task identity/action/principal before returning unchanged. Each recovery task mutation re-reads and validates the root task path/name, candidate description marker, single expected executable/script action, SYSTEM service-account principal and highest run level. A foreign replacement is preserved and recorded as RecoveryRequired while other guarded recovery work continues. Task replacement between validation and the OS mutation remains a non-atomic administrative race; validation is repeated for each operation and the validated task object is passed to the cmdlet.

RolledBack can be retried from an external reviewed package folder. Retained installed sources support inspection/recovery, but same-root reinstall is explicitly refused to avoid self-copying payloads. A fresh installation run token and built-helper hash bind readiness to that attempt; old status is preserved under a uniquely named status.previous file. Installer acceptance additionally requires a current timestamp and matching source process path, start time, interactive session and allowed owner. SourceReady still describes helper registration rather than audio acceptance. Interrupted `.new` state files, unknown state/owner/ACL, a backup mismatch or foreign task/build require inspection. The fixture suite covers state policy and production recovery/activation control flow with mocks, not end-to-end interrupted installation recovery on Windows.

## Runtime safety changes and open boundaries

- All 17 original hook bytes are now checked. Patches recheck the observed bytes immediately before writing, verify cache flush, read back written bytes, and check memory-protection restoration. Errors after a write attempt stop the watcher and request a vendor-process restart; no attempt is made to roll back a partially executing patch in place.
- A remote duplicate created before a failed pre-write operation is explicitly closed using DuplicateHandle CLOSE_SOURCE/SAME_ACCESS. Once a write is attempted the target may reference it, so it is retained until target teardown. Refresh always supplies a current control handle instead of blindly adopting a hook after a watcher restart.
- **Target threads are not suspended and instruction replacement is not atomic.** Readback/protection checks do not make concurrent execution safe. Live patch races and partial-write behavior remain unresolved release-review issues.
- **Refresh handle lifetime remains experimental.** Earlier successful duplicates may remain until target process exit; closing an older value without knowing native ownership could invalidate a live session. No claim of leak-free long sessions/repeated reconnects is made.
- Source/target path, hash, SID/session and process start checks are retained, but are not an atomic identity guarantee across every native operation. Cached process maps/session-log heuristics remain prototype mechanisms.
- The installed watcher uses SYSTEM privileges and reads native log lines locally to recognize reconnects. Runtime output is bounded/rotated; package exports contain no raw logs, voice, key or network identity.
- Task/ACL installation, recovery after a real partial install, administrator-account selection, native audio delivery with this rebuilt helper, reconnect stress, reboot and full uninstall/reinstall remain untested. Fixture checks cannot substitute for those acceptance checks. This candidate is not ready for production recommendation on the strength of build/fixture results alone.

## Maintainer integration choice

The client contribution should describe the actual native NVIDIA route and these host requirements. Maintainers can choose an optional source-built executable launcher, transparent manual/source-build instructions, or another approach. This package does not assume a Sunshine protocol requirement and does not represent maintainer approval of vendor patching or SYSTEM persistence.

## Review source before choosing a build

The [complete source package](https://github.com/Bargs/native-gamestream-microphone-host/archive/refs/heads/main.zip) keeps the optional launcher beside its scripts and helper. [MANUAL-EQUIVALENCE.md](MANUAL-EQUIVALENCE.md) maps all effects and rollback, including the runtime work required by the manual route. Prefer reviewing and building the source yourself. The checked-in unsigned binaries identify the reviewed candidate; they are not a recommendation to run an unknown publisher’s executable.

The public Actions workflow builds the same source and runs isolated fixtures in Windows PowerShell and PowerShell. Its source-and-build artifact includes the source and regenerated compiler/output hashes. It never invokes the installer, launcher, service, task or live runtime patch. A successful CI run is build/fixture evidence, not native audio or installation acceptance.

Paired client work: [common-c PR173](https://github.com/moonlight-stream/moonlight-common-c/pull/173) and [macOS client source](https://github.com/Bargs/moonlight-qt/tree/native-microphone-forwarding). Maintainers are being asked whether they prefer an optional source-built launcher, manual/source-build instructions alone, or another integration path.
