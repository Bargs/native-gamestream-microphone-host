$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$vendor='C:\Program Files\NVIDIA Corporation\NvStreamSrv'
$container='C:\Program Files\NVIDIA Corporation\NvContainer\nvcontainer.exe'
$streamer=Join-Path $vendor 'nvstreamer.exe'
$audio='C:\Windows\System32\nvaudcap64v.dll'
. (Join-Path $root 'management.ps1')
Assert-ProtectedTree $root
$package=Verify-Package $root
$config=Get-Content (Join-Path $root 'runtime-config.json') -Raw | ConvertFrom-Json
if($config.PackageId -ne $PackageId){throw 'Runtime configuration identity differs'}
$userSid=(New-Object Security.Principal.SecurityIdentifier($config.TargetUserSid)).Value
$agentPaths=@((Join-Path $vendor 'Plugins\SSAU\NvStreamUserAgentPlugin.dll'),(Join-Path $vendor 'SsauPlugins\GameStream\NvStreamUserAgentPlugin.dll'))
$pins=@{
 $streamer='37E62C2F107EB2EBE4F185C965AAAEDE5689818DD32BA5A0925E9F90C8E4E99F'
 $container='B023A93E13EE20A16791E98FBB6231FB83613E84255BBE8C8EA87930D4467E7A'
 $audio='6114183B57A9F485263B7891EB4D8F68CBCED50FFE65083BC21FE1DC5EB69839'
 (Join-Path $root 'NativeInterop.dll')=$package.Files.'NativeInterop.dll'
}
function Log($message) {
 $path=Join-Path $root 'runtime.log'
 if((Test-Path $path) -and (Get-Item $path).Length -gt 1048576){Move-Item -LiteralPath $path -Destination (Join-Path $root 'runtime.previous.log') -Force}
 Add-Content -LiteralPath $path -Value (([datetime]::UtcNow.ToString('o'))+' '+$message)
}
function Verify-Pins {
 [void](Verify-Package $root)
 foreach($path in $pins.Keys){if((Get-FileHash -LiteralPath $path).Hash -ne $pins[$path]){throw "Unsupported installed file version: $path"}}
 foreach($path in $agentPaths){if((Test-Path $path) -and (Get-FileHash $path).Hash -ne 'EDEB124040E78C11332D29C92256FBE377EB9C0284ECE29F4E6EB64BD99A264C'){throw 'Unsupported NVIDIA agent version'}}
 if(!(@($agentPaths | Where-Object {Test-Path $_}).Count)){throw 'NVIDIA agent is unavailable'}
}
function Get-Sid($process) {
 $cim=Get-CimInstance Win32_Process -Filter ("ProcessId="+$process.Id)
 (Invoke-CimMethod -InputObject $cim -MethodName GetOwnerSid).Sid
}
function Save-State($phase,$sourceId,$targetId) {
 $sourceTicks=0;if($sourceId -gt 0){$sourceTicks=(Get-Process -Id $sourceId -ErrorAction Stop).StartTime.ToUniversalTime().Ticks}
 @{Phase=$phase;SourcePID=$sourceId;SourceStartTicks=$sourceTicks;StreamerPID=$targetId;RunToken=$config.RunToken;RuntimeHash=$package.Files.'NativeInterop.dll';UpdatedUtc=[datetime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'status.json')
}
$mutex=New-Object Threading.Mutex($false,'Global\BargarArt.NativeGameStreamMic')
if(!$mutex.WaitOne(0)){exit 0}
try {
 Verify-Pins
 Add-Type -Path (Join-Path $root 'NativeInterop.dll')
 Log 'Fixed-purpose native microphone helper started; no audio receiver or command listener'
 $sources=@{};$targets=@{};$lastPinCheck=[datetime]::MinValue;$lastError=''
 while($true) {
  if(([datetime]::UtcNow-$lastPinCheck).TotalSeconds -gt 10){Verify-Pins;$lastPinCheck=[datetime]::UtcNow}
  foreach($process in @(Get-Process nvcontainer -ErrorAction SilentlyContinue)) {
   try {
    if($process.SessionId -lt 1 -or $process.Path -ine $container){continue}
    $identity="$($process.Id):$($process.StartTime.ToUniversalTime().Ticks)"
    if($sources.ContainsKey($identity)){continue}
    $owner=Get-Sid $process;if($owner -notin @($userSid,'S-1-5-18')){continue}
    $module=@($process.Modules | Where-Object {$_.ModuleName -ieq 'NvStreamUserAgentPlugin.dll' -and $_.FileName -iin $agentPaths})
    if($module.Count -ne 1){continue}
    Verify-Pins
    [PermanentRegistration]::Enable($process.Id,$module[0].BaseAddress)
    $sources[$identity]=@{PID=$process.Id;Session=$process.SessionId;StartTicks=$process.StartTime.ToUniversalTime().Ticks}
    Log "NVIDIA microphone registration enabled PID=$($process.Id)"
    Save-State 'SourceReady' $process.Id 0
   } catch {if($_.Exception.GetBaseException().Message -like '*restart vendor processes*'){throw};if($_.Exception.Message -ne $lastError){Log $_.Exception.GetBaseException().Message;$lastError=$_.Exception.Message}}
  }
  $signature='none'
  try {
   $logFile='C:\ProgramData\NVIDIA Corporation\NvStream\NvStreamerCurrent.log'
   $line=(Select-String -LiteralPath $logFile -SimpleMatch 'Starting new streaming session' -ErrorAction Stop | Select-Object -Last 1).Line
   if($line){$sha=[Security.Cryptography.SHA256]::Create();try{$signature=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($line)))}finally{$sha.Dispose()}}
  } catch {}
  foreach($process in @(Get-Process nvstreamer -ErrorAction SilentlyContinue)) {
   try {
    if($process.Path -ine $streamer -or (Get-Sid $process) -ne $userSid){continue}
    $identity="$($process.Id):$($process.StartTime.ToUniversalTime().Ticks)"
    if($targets.ContainsKey($identity) -and $targets[$identity] -eq $signature){continue}
    $source=@($sources.Values | Where-Object {$_.Session -eq $process.SessionId -and (Get-Process -Id $_.PID -ErrorAction SilentlyContinue)})
    if($source.Count -ne 1){continue}
    $sourceProcess=Get-Process -Id $source[0].PID
    if($sourceProcess.Path -ine $container -or $sourceProcess.StartTime.ToUniversalTime().Ticks -ne $source[0].StartTicks){continue}
    $sourceAudio=@($sourceProcess.Modules | Where-Object {$_.ModuleName -ieq 'nvaudcap64v.dll' -and $_.FileName -ieq $audio})
    $targetAudio=@($process.Modules | Where-Object {$_.ModuleName -ieq 'nvaudcap64v.dll' -and $_.FileName -ieq $audio})
    if($sourceAudio.Count -ne 1 -or $targetAudio.Count -ne 1){continue}
    Verify-Pins
    $refresh=$true
    $message=[PermanentNativeMic]::Apply($sourceProcess.Id,$sourceAudio[0].BaseAddress.ToInt64(),$process.Id,$targetAudio[0].BaseAddress.ToInt64(),$refresh)
    $targets[$identity]=$signature
    Log $message
    Save-State 'StreamReady' $sourceProcess.Id $process.Id
    $lastError=''
   } catch {if($_.Exception.GetBaseException().Message -like '*restart vendor processes*'){throw};if($_.Exception.Message -ne $lastError){Log $_.Exception.GetBaseException().Message;$lastError=$_.Exception.Message}}
  }
  Start-Sleep -Milliseconds 200
 }
} catch {
 Log ('Helper stopped without changing unsupported files: '+$_.Exception.GetBaseException().Message)
 Save-State 'Stopped' 0 0
 exit 2
} finally {$mutex.ReleaseMutex();$mutex.Dispose()}
