# Windows source review follow-up

No NVIDIA service, registry value, task, installed file or live process was changed. Registry tests used a fresh temporary HKCU scratch key per run and removed that key in finally. Source files remain unchanged. Runtime tests used invalid process ID -1 only.

## Registry roundtrips

Tested 64-bit Windows PowerShell 5.1.26100.9711 and PowerShell 7.6.9. Seven baselines: absent, DWORD 0, ExpandString with literal synthetic environment token, QWORD 4294967297, byte array, multistring, string. Each baseline was serialized through JSON, replaced by managed DWORD 1, then restored.

- Original absence restoration succeeds; later DWORD 2 edit is preserved under OnlyManaged.
- All six original existing-value restoration cases throw `Cannot write to the registry key.` The Get-Item RegistryKey used by SetValue is read-only, even though the scratch key is owned/writable by the test user.
- Original Save-Flags expands the REG_EXPAND_SZ token before backup, changing its literal text. Other baseline values are retained by backup in these tests.
- Test-only reference functions using explicit Registry64 access, DoNotExpandEnvironmentNames for reads, writable OpenSubKey for restore, and type restoration pass all seven roundtrips in both runtimes.
- The reference functions are a bounded demonstration, not changes to the installed helper or a generalized installer candidate. They do not yet cover all rollback/concurrency/OnlyManaged cases.

## Rollback failure control flow

Parsed the actual installer source AST and extracted its activation catch. Executed that exact catch against recording mocks for every effectful command. This is a control-flow unit test, not an OS/service recovery test.

- With no injected cleanup fault, the catch attempts task cleanup, service stop, original file copy, registry restoration, service start, host wait and state save, then propagates the initial failure.
- Injecting a terminating error at Disable-ScheduledTask, Stop-ScheduledTask, Unregister-ScheduledTask, Copy-Item or Restore-Flags ends cleanup before Start-Service is attempted.
- Injecting Start-Service failure attempts the restart but ends before Wait-Host or state save.
- Thus service recovery needs a separately protected finally/recovery path and independent error collection before a reusable installer can claim resilient rollback.

## Compiled helper failure boundary

The original compiled helper loaded without changing NVIDIA state. Registration.Enable(-1, IntPtr.Zero) returned OpenProcess error 87; NativeMic.Apply(-1, 0, -1, 0, false) returned process access failed 87. These exercise early invalid-process failure only. They do not cover a partial memory write, a successful remote duplicate followed by failure, live process races or cleanup of target-owned handles.

## Historical DESCRIBE/SETUP evidence and its boundary

From the saved synchronized native synthetic probe v8, these lines occurred in this order. The URL and Transport source field are omitted here; the original used local loopback only.

```text
DESCRIBE <native RTSP URL> => RTSP/1.0 200 OK
Response bytes=65416
a=x-nv-general.clientPorts.fallbackDynamic:1
a=x-nv-general.clientPorts.mic:0
a=x-nv-runtime.micSrtp:0
a=x-nv-mic.numChannels:1
a=x-nv-mic.channelMask:4
a=x-nv-mic.version:0
a=x-nv-mic.micSetupResultSuccess:0
a=x-nv-mic.frameSize:5
a=x-nv-mic.bitrate:32000
a=x-nv-mic.enablePacketizer:0
a=x-nv-mic.numOfPacketToRetransmit:0
SETUP streamid=audio/0/0 => RTSP/1.0 200 OK
Transport: unicast;server_port=48000-48001;<source omitted>
SETUP streamid=mic/0/0 => RTSP/1.0 200 OK
Transport: unicast;server_port=48002-48003;<source omitted>
```

Important evidentiary limit: the old Send-Rtsp collector reads into a 65,536-byte buffer, accumulating while socket.Available, with 2.5-second read timeout. It does not frame the SDP by RTSP Content-Length. The log retains selected response lines, not the complete framed body or Content-Length. Therefore this is exact historical line evidence for zero advertised mic port before successful mic SETUP, but **not a newly captured, strictly Content-Length-bounded DESCRIBE body**. No new session was launched for this review. Do not label it stronger evidence than it is. A future bounded capture should parse headers, cap Content-Length, read exactly that many bytes, and retain only allowlisted mic attributes/status/port with secrets excluded.

The zero field alone should not be presented as a guaranteed native-NVIDIA rejection signal: this tested native sequence subsequently negotiated a usable mic port and delivered synthetic audio. Any broader client gate remains the lead's implementation/review decision.
