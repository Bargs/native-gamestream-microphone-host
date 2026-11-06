[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'management.ps1')
$results=New-Object 'System.Collections.Generic.List[object]'
function Check($name,$condition){if(!$condition){throw ('Fixture failed: '+$name)};$results.Add(@{Name=$name;Passed=$true})}
function Hash([byte[]]$bytes){$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}finally{$sha.Dispose()}}
function Refuses($name,$operation){$refused=$false;try{& $operation | Out-Null}catch{$refused=$true};Check $name $refused}
foreach($file in Get-ChildItem $PSScriptRoot -Filter '*.ps1'){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors);Check ('Parse '+$file.Name) ($errors.Count -eq 0)}
$manifest=Verify-Package $PSScriptRoot
Check 'Manifest includes source/build/installer/runtime/optional EXE' (@($manifest.Files.PSObject.Properties).Count -eq 12)
function Get-FileHash {
 param([string]$LiteralPath,[string]$Path)
 if(!$LiteralPath){$LiteralPath=$Path}
 if((Split-Path $LiteralPath -Leaf) -eq 'watch.ps1'){return [pscustomobject]@{Hash=('0'*64)}}
 Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath
}
try{Refuses 'Tampered package hash refused' {Verify-Package $PSScriptRoot}}finally{Remove-Item Function:\Get-FileHash}
Check 'Fresh install policy' ((Get-InstallAction $null $false) -eq 'Fresh')
Check 'Installed policy verifies without activation' ((Get-InstallAction @{PackageId=$PackageId;Phase='Installed'} $false) -eq 'VerifyExisting')
Check 'Restored candidate can retry' ((Get-InstallAction @{PackageId=$PackageId;Phase='RolledBack'} $false) -eq 'Retry')
Refuses 'Unknown installer preserved' {Get-InstallAction @{PackageId='other';Phase='Installed'} $false}
Refuses 'Unknown phase preserved' {Get-InstallAction @{PackageId=$PackageId;Phase='other'} $false}
Refuses 'Recovery requires recorded baseline' {Get-InstallAction $null $true}
foreach($phase in @('Staging','Installing','RecoveryRequired')){
 Refuses ('Partial '+$phase+' requires explicit recovery') {Get-InstallAction @{PackageId=$PackageId;Phase=$phase} $false}
 Check ('Partial '+$phase+' has recovery route') ((Get-InstallAction @{PackageId=$PackageId;Phase=$phase} $true) -eq 'Recover')
}
[byte[]]$original=New-Object byte[] 64;[byte[]]$patch=@(0x41,0xB0,0x01,0x90);[byte[]]$expected=@(0x45,0x0F,0xB6,0x00)
[Array]::Copy($expected,0,$original,16,4);[byte[]]$target=$original.Clone();[Array]::Copy($patch,0,$target,16,4)
$oh=Hash $original;$ph=Hash $target
$actual=New-PatchedBytes $original $oh $ph 16
Check 'Synthetic patch exact result' ((Hash $actual) -eq $ph)
Check 'Patch preserves input bytes' ((Hash $original) -eq $oh)
Check 'Already patched idempotent' ((Hash (New-PatchedBytes $target $oh $ph 16)) -eq $ph)
[byte[]]$unknown=$original.Clone();$unknown[0]=1
Refuses 'Unknown complete hash refused' {New-PatchedBytes $unknown $oh $ph 16}
Refuses 'Incorrect expected opcode refused' {New-PatchedBytes $unknown (Hash $unknown) $ph 17}
Refuses 'Out of range offset refused' {New-PatchedBytes $original $oh $ph 1000}
Refuses 'Incorrect patched hash refused' {New-PatchedBytes $original $oh ('0'*64) 16}

# An in-memory RegistryKey-shaped fixture: no OS registry access or native process calls.
Add-Type -TypeDefinition @'
using System;
using Microsoft.Win32;
public class NativeMicRegistryFixture {
 public bool Exists; public object Value; public RegistryValueKind Kind; public bool Writable; public int Disposals;
 public string[] GetValueNames(){return Exists?new string[]{"fixture"}:new string[0];}
 public RegistryValueKind GetValueKind(string name){return Kind;}
 public object GetValue(string name){return Value;}
 public object GetValue(string name,object fallback,RegistryValueOptions options){
  return Kind==RegistryValueKind.ExpandString && options!=RegistryValueOptions.DoNotExpandEnvironmentNames ? Environment.ExpandEnvironmentVariables((string)Value):Value;
 }
 public void SetValue(string name,object value,RegistryValueKind kind){if(!Writable)throw new Exception("Read-only fixture");Exists=true;Value=value;Kind=kind;}
 public void DeleteValue(string name,bool fail){if(!Writable)throw new Exception("Read-only fixture");Exists=false;Value=null;}
 public void Dispose(){Disposals++;}
}
'@
$FlagNames=@('fixture');$script:key=New-Object NativeMicRegistryFixture
function Open-Flags([bool]$writable){$script:key.Writable=$writable;return $script:key}
$cases=@(
 @{Name='absent';Exists=$false;Kind='DWord';Value=$null},
 @{Name='DWORD0';Exists=$true;Kind='DWord';Value=[int]0},
 @{Name='DWORD signed boundary';Exists=$true;Kind='DWord';Value=[int]-1},
 @{Name='literal ExpandString';Exists=$true;Kind='ExpandString';Value='%SYNTHETIC_LITERAL%\tail'},
 @{Name='QWORD';Exists=$true;Kind='QWord';Value=[long]4294967297},
 @{Name='binary';Exists=$true;Kind='Binary';Value=[byte[]]@(0,128,255)},
 @{Name='REG_NONE';Exists=$true;Kind='None';Value=[byte[]]@(0,128,255)},
 @{Name='multistring';Exists=$true;Kind='MultiString';Value=[string[]]@('alpha','beta')},
 @{Name='string';Exists=$true;Kind='String';Value='synthetic'}
)
foreach($case in $cases){
 $key.Exists=$case.Exists;$key.Kind=[Microsoft.Win32.RegistryValueKind]$case.Kind;$key.Value=$case.Value
 $saved=Save-Flags | ConvertTo-Json -Depth 8 | ConvertFrom-Json
 Set-Flags;Restore-Flags $saved -OnlyManaged
 $same=$key.Exists -eq $case.Exists
 if($case.Exists){$same=$same -and ($key.Kind.ToString() -eq $case.Kind) -and ((ConvertTo-Json $key.Value -Compress) -ceq (ConvertTo-Json $case.Value -Compress))}
 Check ('JSON registry roundtrip '+$case.Name) $same
}
$key.Exists=$false;$saved=Save-Flags | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$key.Writable=$true;$key.SetValue('fixture',2,[Microsoft.Win32.RegistryValueKind]::DWord)
Restore-Flags $saved -OnlyManaged;Check 'Later registry edit preserved' ($key.Value -eq 2)
Refuses 'Incomplete baseline refused' {Restore-Flags ([pscustomobject]@{})}

foreach($fault in @('none','DisableTask','StopTask','StopService','RestoreFile','RestoreRegistry','RemoveTask','StartService','WaitHost')){
 $trace=New-Object 'System.Collections.Generic.List[string]';$ops=@{}
 foreach($operationName in @('DisableTask','StopTask','StopService','RestoreFile','RestoreRegistry','RemoveTask','StartService','WaitHost')){
  $ops[$operationName]={$trace.Add($operationName);if($operationName -eq $fault){throw 'Synthetic failure'}}.GetNewClosure()
 }
 $failures=Invoke-RecoveryPlan $ops
 Check ('Recovery always attempts service restart after '+$fault) ($trace.Contains('StartService'))
 Check ('Recovery always attempts readiness after '+$fault) ($trace.Contains('WaitHost'))
 if($fault -eq 'StopService'){Check 'Failed stop defers vendor file/registry restore' (!$trace.Contains('RestoreFile') -and !$trace.Contains('RestoreRegistry'))}
 if($fault -eq 'none'){Check 'Normal recovery has no errors' ($failures.Count -eq 0)}else{Check ('Recovery collects '+$fault) ($failures.Count -gt 0)}
}
Refuses 'Same-root retry guarded' {Assert-ExternalInstallSource $PSScriptRoot $PSScriptRoot}
Assert-ExternalInstallSource $PSScriptRoot (Join-Path $PSScriptRoot 'other');Check 'External source retry accepted' $true
$readyTime=[datetime]'2026-01-01T00:00:00Z'
$ready=@{Phase='SourceReady';RunToken='new-run';RuntimeHash='new-build';SourcePID=123;SourceStartTicks=12345;UpdatedUtc=$readyTime.AddSeconds(1).ToString('o')}
Check 'Current readiness accepted by pure predicate' (Test-ReadyStatus ([pscustomobject]$ready) 'new-run' 'new-build' $readyTime)
Check 'Stale run token refused' (!(Test-ReadyStatus ([pscustomobject]$ready) 'different-run' 'new-build' $readyTime))
Check 'Different helper build refused' (!(Test-ReadyStatus ([pscustomobject]$ready) 'new-run' 'different-build' $readyTime))
Check 'Old readiness timestamp refused' (!(Test-ReadyStatus ([pscustomobject]$ready) 'new-run' 'new-build' $readyTime.AddSeconds(2)))
$ready.SourcePID=0;Check 'Readiness without source PID refused' (!(Test-ReadyStatus ([pscustomobject]$ready) 'new-run' 'new-build' $readyTime))
$ready.SourcePID='malformed';Check 'Malformed readiness refused without throwing' (!(Test-ReadyStatus ([pscustomobject]$ready) 'new-run' 'new-build' $readyTime))

# Exercise production Recover-Installation and Get-OwnedTask against OS-command mocks.
function Get-ScheduledTask {
 $script:taskQueries++
 if($script:taskMode -eq 'absent'){return}
 $task=$script:ownedTask | ConvertTo-Json -Depth 8 | ConvertFrom-Json
 if($script:taskMode -eq 'foreign-exe' -or ($script:taskMode -eq 'swap' -and $script:taskQueries -ge 2)){$task.Actions[0].Execute='C:\synthetic-foreign.exe'}
 if($script:taskMode -eq 'foreign-principal'){$task.Principal.UserId='synthetic-user'}
 if($script:taskMode -eq 'foreign-arguments'){$task.Actions[0].Arguments='synthetic-foreign'}
 if($script:taskMode -eq 'foreign-description'){$task.Description='synthetic-foreign'}
 return $task
}
function Disable-ScheduledTask {$mutations.Add('Disable')}
function Stop-ScheduledTask {$mutations.Add('Stop')}
function Unregister-ScheduledTask {$mutations.Add('Remove')}
function Stop-Service {$recoveryCalls.Add('StopService')}
function Start-Service {$recoveryCalls.Add('StartService')}
function Wait-Host {$recoveryCalls.Add('WaitHost')}
function Restore-Flags {$recoveryCalls.Add('RestoreRegistry')}
function Get-FileHash {return [pscustomobject]@{Hash=$OriginalHash}}
function Write-JsonAtomic {$recoveryCalls.Add('SaveState')}
$script:ownedTask=@{TaskName=$TaskName;TaskPath='\';Description=$TaskDescription;Principal=@{UserId='SYSTEM';RunLevel='Highest';LogonType='ServiceAccount'};Actions=@(@{Execute="$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe";Arguments=('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $InstallRoot 'watch.ps1')+'"');WorkingDirectory=''})}
foreach($mode in @('owned','absent','foreign-exe','foreign-principal','foreign-arguments','foreign-description','swap')){
 $script:taskMode=$mode;$script:taskQueries=0;$mutations=New-Object 'System.Collections.Generic.List[string]';$recoveryCalls=New-Object 'System.Collections.Generic.List[string]'
 $recoveryState=[pscustomobject]@{PackageId=$PackageId;Phase='Installed';RegistryBaseline=@{};RecoveryErrors=@()}
 $threw=$false;try{Recover-Installation $recoveryState}catch{$threw=$true}
 Check ('Production recovery restarts after task identity case '+$mode) ($recoveryCalls.Contains('StartService') -and $recoveryCalls.Contains('WaitHost'))
 if($mode -eq 'owned'){Check 'Owned task has three guarded mutations' ($mutations.Count -eq 3 -and !$threw)}
 elseif($mode -eq 'absent'){Check 'Absent task does not cause mutations' ($mutations.Count -eq 0 -and !$threw)}
 elseif($mode -eq 'swap'){Check 'Task replacement between mutations preserved' ($mutations.Count -eq 1 -and $threw -and $recoveryState.Phase -eq 'RecoveryRequired')}
 else{Check ('Foreign task preserved and recorded '+$mode) ($mutations.Count -eq 0 -and $threw -and $recoveryState.RecoveryErrors.Count -eq 3 -and $recoveryState.Phase -eq 'RecoveryRequired')}
}
Remove-Item Function:\Get-FileHash
Add-Type -Path (Join-Path $PSScriptRoot 'NativeInterop.dll')
Check 'Byte comparison rejects differing length' (![NativePatchSafety]::Equal([byte[]]@(1),[byte[]]@(1,2)))
Check 'Byte comparison rejects unknown bytes' (![NativePatchSafety]::Equal([byte[]]@(1),[byte[]]@(2)))
Check 'Byte comparison accepts exact bytes' ([NativePatchSafety]::Equal([byte[]]@(1),[byte[]]@(1)))
$tokens=$null;$errors=$null
$installerAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'install.ps1'),[ref]$tokens,[ref]$errors)
$activationTry=@($installerAst.FindAll({param($n) $n -is [Management.Automation.Language.TryStatementAst] -and $n.CatchClauses.Count -gt 0 -and $n.Extent.Text.Contains('$activationFailure=')},$true))[-1]
$catchText=$activationTry.CatchClauses[0].Body.Extent.Text
$catchBody=[scriptblock]::Create($catchText.Substring(1,$catchText.Length-2))
function Write-JsonAtomic {$calls.Add('SaveState')}
function Recover-Installation {$calls.Add('Recover')}
foreach($started in @($false,$true)){
 $activationStarted=$started;$calls=New-Object 'System.Collections.Generic.List[string]';$state=@{Phase='Installing'};$statePath='synthetic'
 try{try{throw 'Synthetic activation fault'}catch{& $catchBody}}catch{}
 if(!$started){Check 'Original activation catch preserves newly active host before service change' (!$calls.Contains('Recover') -and $state.Phase -eq 'Staging')}
 else{Check 'Original activation catch recovers after service change begins' ($calls.Contains('Recover'))}
}
@{Scope='Parser, byte arrays, in-memory registry fixture and recording cleanup mocks only. No registry, task, service, process-memory or install calls.';Runtime=$PSVersionTable.PSVersion.ToString();Checks=$results.Count;Results=$results.ToArray()} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $PSScriptRoot ('fixture-results-'+$PSVersionTable.PSVersion.Major+'.json')) -Encoding UTF8
Write-Output ('Passed '+$results.Count+' isolated checks.')
