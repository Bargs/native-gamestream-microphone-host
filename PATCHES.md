# Version pins and native handoff

Observed GameStream version 7.1.437.0, GeForce Experience 3.25.1.27, native audio 4.37.0.0. Compatibility beyond this exact set is unverified.

| File | SHA256 |
| --- | --- |
| nvstreamer.exe original | 692BCEE24D826B639EFCA7C77D3E1131EF464924DE647233822C6E660C0333F3 |
| nvstreamer.exe patched | 37E62C2F107EB2EBE4F185C965AAAEDE5689818DD32BA5A0925E9F90C8E4E99F |
| NvStreamUserAgentPlugin.dll | EDEB124040E78C11332D29C92256FBE377EB9C0284ECE29F4E6EB64BD99A264C |
| nvaudcap64v.dll | 6114183B57A9F485263B7891EB4D8F68CBCED50FFE65083BC21FE1DC5EB69839 |
| nvcontainer.exe | B023A93E13EE20A16791E98FBB6231FB83613E84255BBE8C8EA87930D4467E7A |

## Disk and registry

nvstreamer.exe: image base 0x140000000; VA 0x14011622B, RVA 0x11622B, file offset decimal 1136171. Exactly four bytes `45 0F B6 00` become `41 B0 01 90`, forcing the voice-chat configuration branch true. Complete patched hash above was verified; all other file bytes matched the original.

Registry key `HKLM\SOFTWARE\NVIDIA Corporation\NvStreamSrv`: `EnableGFNMicStreamerSupport` and `EnableGFNMicSupport`, each DWORD 1. Both were absent in the observed baseline.

## Runtime registration

In verified native nvcontainer user-agent plugin, RVA 0xD6D1C: `40 32 ED` becomes `40 B5 01`. This enables microphone registration in the GameStream branch. Known patched bytes are accepted idempotently; differing bytes are refused. Signed on-disk plugin is untouched. Source: Registration.cs. Both plugin search paths are disclosed in watch.ps1.

## Runtime control-handle sharing

Native registration holds the driver control handle. A second control open in the receiver does not provide the working route; duplicate the registered source handle into nvstreamer and reuse it.

NativeMic.cs scans committed private RW/WriteCopy source memory for the native wrapper: API version 0x010801A8 at wrapper+8; API table pointer at wrapper+0 with matching header and function pointers audio base+0x11260 (OpenSession) and +0x115B0 (RegisterEndpoint); native session at wrapper+0x18; registration flag at +0x20 equals 1; control handle at session+0x20. Exactly one distinct session candidate is required. Full heuristic and handle bounds are in source. This mechanism remains experimental.

DuplicateHandle uses DUPLICATE_SAME_ACCESS. Target-process nvaudcap64v.dll RVA 0xB7E0 expected 17 bytes: `40 55 53 57 48 8D 6C 24 B9 48 81 EC B0 00 00 00 48`. This candidate compares all 17 baseline bytes. Replacement 17 bytes: `48 B8 <8-byte little-endian duplicate handle> 48 89 41 20 31 C0 C3`. This sets [rcx+0x20] to the shared handle and returns success. No audio DLL change on disk. A recognized replacement can be refreshed; this candidate watcher always requests refresh when applying after a session change or helper restart. Pre-write failures release a newly duplicated handle; once a write is attempted it is retained to avoid invalidating a possible native reference. Inspect README.md for the unresolved concurrency and refresh-lifetime boundaries.

Watcher pins and owner/session checks constrain candidate processes; source/target process handles are opened with native access masks disclosed in C#. New stream starts refresh the handle through a hash of the latest native streaming-session log line. No raw vendor log is exported here.
