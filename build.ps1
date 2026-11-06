[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if(![Environment]::Is64BitProcess){throw 'Build with 64-bit PowerShell'}
$compiler=Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$root=$PSScriptRoot
Push-Location $root
try{
 & $compiler /nologo /target:library /platform:x64 /out:NativeInterop.dll NativeMic.cs Registration.cs RuntimeSafety.cs
 if($LASTEXITCODE -ne 0){throw 'Runtime helper compilation failed'}
 & $compiler /nologo /target:exe /platform:x64 /out:NativeMicSetup.exe Launcher.cs
 if($LASTEXITCODE -ne 0){throw 'Optional setup launcher compilation failed'}
 $files=@{}
 foreach($name in @('install.ps1','uninstall.ps1','management.ps1','watch.ps1','NativeMic.cs','Registration.cs','RuntimeSafety.cs','Launcher.cs','build.ps1','NativeInterop.dll','NativeMicSetup.exe','tests.ps1')){$files[$name]=(Get-FileHash $name).Hash}
 @{PackageId='NativeGameStreamMic.Candidate.1';Files=$files} | ConvertTo-Json -Depth 6 | Set-Content package.json -Encoding UTF8
 $inputs=@{};foreach($name in @('NativeMic.cs','Registration.cs','RuntimeSafety.cs','Launcher.cs','build.ps1')){$inputs[$name]=(Get-FileHash $name).Hash}
 @{CompilerVersion=(Get-Item $compiler).VersionInfo.FileVersion;CompilerSHA256=(Get-FileHash $compiler).Hash;Architecture='x64';Framework='Microsoft .NET Framework v4 compiler';PowerShell=$PSVersionTable.PSVersion.ToString();Inputs=$inputs;Outputs=@{NativeInterop=(Get-FileHash NativeInterop.dll).Hash;OptionalLauncher=(Get-FileHash NativeMicSetup.exe).Hash};Deterministic=$false;Recipe='build.ps1: csc /target:library /platform:x64 NativeMic.cs Registration.cs RuntimeSafety.cs; csc /target:exe /platform:x64 Launcher.cs'} | ConvertTo-Json -Depth 6 | Set-Content build-provenance.json -Encoding UTF8
 'Built runtime DLL and optional launcher, regenerated complete package manifest.'
}finally{Pop-Location}
