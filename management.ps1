$InstallRoot=Join-Path $env:ProgramFiles 'BargarArtNativeGameStreamMic'
$TaskName='BargarArt.NativeGameStreamMic'
$PackageId='NativeGameStreamMic.Candidate.1'
$TaskDescription=$PackageId+': Experimental version-pinned native NVIDIA microphone registration and handle sharing; no separate receiver'
$NvidiaExe=Join-Path $env:ProgramFiles 'NVIDIA Corporation\NvStreamSrv\nvstreamer.exe'
$RegistrySubKey='SOFTWARE\NVIDIA Corporation\NvStreamSrv'
$FlagNames=@('EnableGFNMicStreamerSupport','EnableGFNMicSupport')
$OriginalHash='692BCEE24D826B639EFCA7C77D3E1131EF464924DE647233822C6E660C0333F3'
$PatchedHash='37E62C2F107EB2EBE4F185C965AAAEDE5689818DD32BA5A0925E9F90C8E4E99F'
function Require-Admin {
 if(![Environment]::Is64BitProcess){throw 'Use 64-bit Windows PowerShell'}
 if(!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator approval is required for installation or recovery'}
}
function Host-State {
 $web=New-Object Net.WebClient
 try{[xml]$info=$web.DownloadString('http://127.0.0.1:47989/serverinfo');return [string]$info.root.currentgame}finally{$web.Dispose()}
}
function Wait-Host {
 $deadline=[datetime]::UtcNow.AddSeconds(40)
 do{try{[void](Host-State);return}catch{Start-Sleep -Seconds 1}}while([datetime]::UtcNow -lt $deadline)
 throw 'NVIDIA host did not become available'
}
function Write-JsonAtomic($value,$path) {
 $temporary=$path+'.new'
 if(Test-Path -LiteralPath $temporary){throw 'An interrupted state write requires inspection before continuing'}
 $value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporary -Encoding UTF8
 Secure-File $temporary
 Move-Item -LiteralPath $temporary -Destination $path -Force
}
function Verify-Package($root) {
 $manifest=Get-Content (Join-Path $root 'package.json') -Raw | ConvertFrom-Json
 if($manifest.PackageId -ne $PackageId){throw 'Package identity differs'}
 $required=@('install.ps1','uninstall.ps1','management.ps1','watch.ps1','NativeMic.cs','Registration.cs','RuntimeSafety.cs','Launcher.cs','build.ps1','NativeInterop.dll','NativeMicSetup.exe','tests.ps1')
 if(@($manifest.Files.PSObject.Properties).Count -ne $required.Count){throw 'Package manifest file set differs'}
 foreach($name in $required){
  $expected=$manifest.Files.$name
  if($expected -notmatch '^[A-Fa-f0-9]{64}$'){throw "Invalid package hash: $name"}
  $path=Join-Path $root $name
  if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Package links are unsupported'}
  if((Get-FileHash -LiteralPath $path).Hash -ne $expected){throw "Package file differs: $name"}
 }
 return $manifest
}
function Resolve-TargetSid($requested) {
 if(!$requested){$account=(Get-CimInstance Win32_ComputerSystem).UserName;if(!$account){throw 'Specify -TargetUserSid when no console user is available'};$requested=(New-Object Security.Principal.NTAccount($account)).Translate([Security.Principal.SecurityIdentifier]).Value}
 $sid=New-Object Security.Principal.SecurityIdentifier($requested)
 if(!$sid.IsAccountSid() -or $sid.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20')){throw 'Select an ordinary local or domain user account SID'}
 [void]$sid.Translate([Security.Principal.NTAccount])
 return $sid.Value
}
function Get-InstallAction($state,[bool]$recover) {
 if($null -eq $state){if($recover){throw 'No candidate state exists'};return 'Fresh'}
 if($state.PackageId -ne $PackageId){throw 'Existing installation belongs to another installer; preserved'}
 if($state.Phase -notin @('Staging','Installing','Installed','RecoveryRequired','RolledBack')){throw 'Unknown installation phase; preserved'}
 if($recover){return 'Recover'}
 if($state.Phase -eq 'Installed'){return 'VerifyExisting'}
 if($state.Phase -eq 'RolledBack'){return 'Retry'}
 throw 'Partial installation preserved. Use explicit recovery before retrying.'
}
function Assert-OwnedTask($task) {
 $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $InstallRoot 'watch.ps1')+'"'
 if($task.TaskName -cne $TaskName -or $task.TaskPath -cne '\' -or $task.Description -cne $TaskDescription -or $task.Principal.UserId -notin @('SYSTEM','S-1-5-18') -or [string]$task.Principal.RunLevel -ne 'Highest' -or [string]$task.Principal.LogonType -ne 'ServiceAccount' -or @($task.Actions).Count -ne 1 -or $task.Actions[0].Execute -ine "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" -or $task.Actions[0].Arguments -cne $arguments -or [string]$task.Actions[0].WorkingDirectory -ne ''){throw 'Foreign scheduled task preserved: candidate identity/action/principal differs'}
}
function Get-OwnedTask {
 $tasks=@(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop | Where-Object {$_.TaskName -ceq $TaskName})
 if(!$tasks.Count){return $null}
 if($tasks.Count -ne 1){throw 'Ambiguous scheduled task identity; preserved'}
 Assert-OwnedTask $tasks[0]
 return $tasks[0]
}
function Assert-ExternalInstallSource($source,$destination) {
 $left=[IO.Path]::GetFullPath($source).TrimEnd('\')
 $right=[IO.Path]::GetFullPath($destination).TrimEnd('\')
 if($left -ieq $right){throw 'Use the external reviewed package folder for installation after recovery; retained installed source is for inspection/recovery only'}
}
function Test-ReadyStatus($status,$runToken,$runtimeHash,[datetime]$notBefore) {
 try{
 if(!$status -or $status.Phase -ne 'SourceReady' -or $status.RunToken -cne $runToken -or $status.RuntimeHash -cne $runtimeHash -or [long]$status.SourcePID -le 0 -or [long]$status.SourceStartTicks -le 0){return $false}
 return ([datetime]::Parse([string]$status.UpdatedUtc).ToUniversalTime() -ge $notBefore.ToUniversalTime())
 }catch{return $false}
}
function Confirm-ReadySource($status,$sid) {
 try{
  $process=Get-Process -Id $status.SourcePID -ErrorAction Stop
  if($process.Path -ine (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NvContainer\nvcontainer.exe') -or $process.SessionId -lt 1 -or $process.StartTime.ToUniversalTime().Ticks -ne [long]$status.SourceStartTicks){return $false}
  $cim=Get-CimInstance Win32_Process -Filter ('ProcessId='+$process.Id) -ErrorAction Stop
  return ((Invoke-CimMethod -InputObject $cim -MethodName GetOwnerSid -ErrorAction Stop).Sid -in @($sid,'S-1-5-18'))
 }catch{return $false}
}
function Open-Flags([bool]$writable) {
 $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
 try{$key=$base.OpenSubKey($RegistrySubKey,$writable);if(!$key){throw 'NVIDIA registry key is unavailable'};return $key}finally{$base.Dispose()}
}
function Save-Flags {
 $key=Open-Flags $false
 try{$saved=@{};foreach($name in $FlagNames){$entry=@{Exists=($key.GetValueNames() -contains $name)};if($entry.Exists){$entry.Kind=$key.GetValueKind($name).ToString();$entry.Value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)};$saved[$name]=$entry};return $saved}finally{$key.Dispose()}
}
function Set-Flags {
 $key=Open-Flags $true
 try{foreach($name in $FlagNames){$key.SetValue($name,[int]1,[Microsoft.Win32.RegistryValueKind]::DWord)}}finally{$key.Dispose()}
}
function Convert-RegistryData($kind,$value) {
 switch($kind){
  'DWord' {return [int]$value}
  'QWord' {return [long]$value}
  'Binary' {return ,([byte[]]$value)}
  'None' {return ,([byte[]]$value)}
  'MultiString' {return ,([string[]]$value)}
  'String' {return [string]$value}
  'ExpandString' {return [string]$value}
  default {throw 'Unsupported registry baseline type'}
 }
}
function Restore-Flags($saved,[switch]$OnlyManaged) {
 $key=Open-Flags $true
 try{foreach($name in $FlagNames){
  $entry=$saved.$name;if($null -eq $entry){throw 'Registry baseline is incomplete'}
  if($OnlyManaged -and (!($key.GetValueNames() -contains $name) -or $key.GetValueKind($name) -ne [Microsoft.Win32.RegistryValueKind]::DWord -or $key.GetValue($name) -ne 1)){continue}
  if($entry.Exists){$data=Convert-RegistryData $entry.Kind $entry.Value;$key.SetValue($name,$data,[Microsoft.Win32.RegistryValueKind]$entry.Kind)}else{$key.DeleteValue($name,$false)}
 }}finally{$key.Dispose()}
}
function New-PatchedBytes([byte[]]$bytes,$expectedHash=$OriginalHash,$resultHash=$PatchedHash,[int]$offset=1136171) {
 $sha=[Security.Cryptography.SHA256]::Create()
 try{
  $hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')
  if($hash -eq $resultHash){return ,$bytes.Clone()}
  if($hash -ne $expectedHash){throw 'Unsupported original NVIDIA version; no bytes changed'}
  if($offset -lt 0 -or $bytes.Length -lt $offset+4){throw 'Patch offset is outside the file'}
  $original=[byte[]]@(0x45,0x0F,0xB6,0x00);$patch=[byte[]]@(0x41,0xB0,0x01,0x90)
  for($i=0;$i -lt 4;$i++){if($bytes[$offset+$i] -ne $original[$i]){throw 'Original patch bytes differ'}}
  $candidate=[byte[]]$bytes.Clone();[Array]::Copy($patch,0,$candidate,$offset,4)
  if(([BitConverter]::ToString($sha.ComputeHash($candidate))).Replace('-','') -ne $resultHash){throw 'Patched hash differs'}
  return ,$candidate
 }finally{$sha.Dispose()}
}
function Invoke-RecoveryPlan($operations) {
 # All cleanup actions are independently guarded; service restart is always attempted last.
 $failures=New-Object 'System.Collections.Generic.List[string]'
 $stopped=$false
 foreach($name in @('DisableTask','StopTask','StopService','RestoreFile','RestoreRegistry','RemoveTask')){
  if($name -in @('RestoreFile','RestoreRegistry') -and !$stopped){$failures.Add("$name deferred because service stop was not confirmed");continue}
  try{& $operations[$name];if($name -eq 'StopService'){$stopped=$true}}catch{$failures.Add($name+': '+$_.Exception.GetBaseException().Message)}
 }
 try{& $operations.StartService}catch{$failures.Add('StartService: '+$_.Exception.GetBaseException().Message)}
 try{& $operations.WaitHost}catch{$failures.Add('WaitHost: '+$_.Exception.GetBaseException().Message)}
 return ,$failures.ToArray()
}
function Recover-Installation($state) {
 if($state.PackageId -ne $PackageId){throw 'Recovery state belongs to another installer'}
 $operations=@{
  DisableTask={$task=Get-OwnedTask;if($task){Disable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null}}
  StopTask={$task=Get-OwnedTask;if($task){Stop-ScheduledTask -InputObject $task -ErrorAction Stop}}
  StopService={Stop-Service NvContainerLocalSystem -ErrorAction Stop}
  RestoreFile={
   $current=(Get-FileHash $NvidiaExe).Hash
   if($current -eq $PatchedHash){$backup=Join-Path $InstallRoot 'backup\nvstreamer.original.exe';if((Get-FileHash $backup).Hash -ne $OriginalHash){throw 'Original backup differs'};Copy-Item -LiteralPath $backup -Destination $NvidiaExe -Force;if((Get-FileHash $NvidiaExe).Hash -ne $OriginalHash){throw 'Restored executable differs'}}
   elseif($current -ne $OriginalHash){throw 'A different vendor version was preserved; manual inspection is required'}
  }
  RestoreRegistry={Restore-Flags $state.RegistryBaseline -OnlyManaged}
  RemoveTask={$task=Get-OwnedTask;if($task){Unregister-ScheduledTask -InputObject $task -Confirm:$false -ErrorAction Stop}}
  StartService={Start-Service NvContainerLocalSystem -ErrorAction Stop}
  WaitHost={Wait-Host}
 }
 $failures=Invoke-RecoveryPlan $operations
 $state.Phase=if($failures.Count){'RecoveryRequired'}else{'RolledBack'}
 $state.RecoveryErrors=@($failures)
 Write-JsonAtomic $state (Join-Path $InstallRoot 'install-state.json')
 if($failures.Count){throw ('Recovery requires inspection: '+($failures -join '; '))}
}
function Secure-Directory($path) {
 if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Installation links are unsupported'}
 $acl=New-Object Security.AccessControl.DirectorySecurity;$acl.SetAccessRuleProtection($true,$false)
 foreach($sid in @('S-1-5-18','S-1-5-32-544')){$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)),'FullControl','ContainerInherit,ObjectInherit','None','Allow')))}
 $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')),'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')))
 $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')));Set-Acl -LiteralPath $path -AclObject $acl
}
function Assert-ProtectedTree($path) {
 foreach($item in @(Get-Item -LiteralPath $path)+@(Get-ChildItem -LiteralPath $path -Recurse -Force)){
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Installation links are unsupported'}
  $acl=Get-Acl -LiteralPath $item.FullName
  if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'Installation owner requires inspection'}
  $mutating=[Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
  foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
   if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544') -and ($rule.FileSystemRights -band $mutating)){throw 'Installation grants non-administrator mutation rights'}
  }
 }
}
function Secure-Tree($path) {
 Secure-Directory $path
 foreach($dir in Get-ChildItem -LiteralPath $path -Directory -Recurse){Secure-Directory $dir.FullName}
 foreach($file in Get-ChildItem -LiteralPath $path -File -Recurse){Secure-File $file.FullName}
 Assert-ProtectedTree $path
}
function Secure-File($path) {
  $file=Get-Item -LiteralPath $path
  if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Installation links are unsupported'}
  $acl=New-Object Security.AccessControl.FileSecurity;$acl.SetAccessRuleProtection($true,$false)
  foreach($sid in @('S-1-5-18','S-1-5-32-544')){$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)),'FullControl','Allow')))}
  $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')),'ReadAndExecute','Allow')))
  $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')));Set-Acl -LiteralPath $file.FullName -AclObject $acl
}
function Verify-VendorFiles {
 $pins=@{
  (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NvContainer\nvcontainer.exe')='B023A93E13EE20A16791E98FBB6231FB83613E84255BBE8C8EA87930D4467E7A'
  (Join-Path $env:windir 'System32\nvaudcap64v.dll')='6114183B57A9F485263B7891EB4D8F68CBCED50FFE65083BC21FE1DC5EB69839'
 }
 foreach($path in $pins.Keys){if((Get-FileHash $path).Hash -ne $pins[$path]){throw 'Unsupported NVIDIA dependency version'}}
 $found=$false
 foreach($relative in @('Plugins\SSAU\NvStreamUserAgentPlugin.dll','SsauPlugins\GameStream\NvStreamUserAgentPlugin.dll')){
  $path=Join-Path (Split-Path $NvidiaExe) $relative
  if(Test-Path $path){$found=$true;if((Get-FileHash $path).Hash -ne 'EDEB124040E78C11332D29C92256FBE377EB9C0284ECE29F4E6EB64BD99A264C'){throw 'Unsupported native agent version'}}
 }
 if(!$found){throw 'Native agent was not found'}
}
