[CmdletBinding()]
param([string]$TargetUserSid,[switch]$DryRun,[switch]$Recover,[switch]$AcknowledgeExperimentalRuntime)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'management.ps1')
$manifest=Verify-Package $PSScriptRoot
if($DryRun){
 Verify-VendorFiles
 $hash=(Get-FileHash $NvidiaExe).Hash
 if($hash -notin @($OriginalHash,$PatchedHash)){throw 'Unsupported NVIDIA executable; no changes made'}
 'Dry run: package/dependency hashes accepted. No writes performed. Installation still requires an idle host, administrator approval, target user validation and runtime acknowledgement.'
 return
}
Require-Admin
if(!$AcknowledgeExperimentalRuntime){throw 'Review README.md and supply -AcknowledgeExperimentalRuntime: concurrent runtime patching and handle refresh remain experimental'}
$statePath=Join-Path $InstallRoot 'install-state.json'
if(Test-Path $InstallRoot){
 Assert-ProtectedTree $InstallRoot
 if(!(Test-Path $statePath)){throw 'Existing directory has no candidate state; contents preserved'}
 $state=Get-Content $statePath -Raw | ConvertFrom-Json
 $decision=Get-InstallAction $state ([bool]$Recover)
 if($decision -eq 'Recover'){if((Host-State) -ne '0'){throw 'Quit the streamed application before recovery'};Recover-Installation $state;return}
 if($decision -eq 'VerifyExisting'){
  $installedManifest=Verify-Package $InstallRoot
  foreach($name in $manifest.Files.PSObject.Properties.Name){if($manifest.Files.$name -ne $installedManifest.Files.$name){throw 'Another candidate build is installed; use explicit recovery before replacement'}}
  if((Get-FileHash $NvidiaExe).Hash -ne $PatchedHash){throw 'Installed vendor file differs; use explicit recovery'}
  $config=Get-Content (Join-Path $InstallRoot 'runtime-config.json') -Raw | ConvertFrom-Json
  if($TargetUserSid -and $TargetUserSid -ne $config.TargetUserSid){throw 'Existing target account differs; preserved'}
  $task=Get-OwnedTask;if(!$task){throw 'Candidate task is unavailable; use explicit recovery'}
  'This candidate is already installed; no changes made.';return
 }
}else{[void](Get-InstallAction $null ([bool]$Recover))}
Assert-ExternalInstallSource $PSScriptRoot $InstallRoot
if(Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue){throw 'Existing task preserved; inspect its owning installation'}
Verify-VendorFiles
if((Host-State) -ne '0'){throw 'Quit the streamed application before installation; Windows work can remain open'}
$sid=Resolve-TargetSid $TargetUserSid
if((Get-FileHash $NvidiaExe).Hash -ne $OriginalHash){throw 'Exact original NVIDIA executable required before installation'}
$baseline=Save-Flags
if(!(Test-Path $InstallRoot)){New-Item -ItemType Directory -Path $InstallRoot | Out-Null}
Secure-Directory $InstallRoot
# State is committed before copying payloads or mutating vendor state.
$state=@{PackageId=$PackageId;Phase='Staging';RegistryBaseline=$baseline;RecoveryErrors=@();TargetUserSid=$sid;OriginalHash=$OriginalHash;PatchedHash=$PatchedHash}
Write-JsonAtomic $state $statePath
foreach($name in @($manifest.Files.PSObject.Properties.Name)+@('package.json')){$destination=Join-Path $InstallRoot $name;Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $destination -Force;Secure-File $destination}
$backup=Join-Path $InstallRoot 'backup';New-Item -ItemType Directory -Path $backup -Force | Out-Null
$originalBackup=Join-Path $backup 'nvstreamer.original.exe'
if(!(Test-Path $originalBackup)){Copy-Item -LiteralPath $NvidiaExe -Destination $originalBackup}
if((Get-FileHash $originalBackup).Hash -ne $OriginalHash){throw 'Preserved original backup differs'}
$patched=New-PatchedBytes ([IO.File]::ReadAllBytes($originalBackup))
$candidate=Join-Path $backup 'nvstreamer.patched.exe';[IO.File]::WriteAllBytes($candidate,$patched)
$runToken=[guid]::NewGuid().ToString('N')
if(Test-Path (Join-Path $InstallRoot 'status.json')){Copy-Item -LiteralPath (Join-Path $InstallRoot 'status.json') -Destination (Join-Path $InstallRoot ('status.previous.'+[guid]::NewGuid().ToString('N')+'.json'))}
Write-JsonAtomic @{TargetUserSid=$sid;PackageId=$PackageId;RunToken=$runToken} (Join-Path $InstallRoot 'runtime-config.json')
Secure-Tree $InstallRoot
[void](Verify-Package $InstallRoot)
$state.Phase='Installing';Write-JsonAtomic $state $statePath
$activationStarted=$false
$activationUtc=[datetime]::UtcNow
try {
 if((Host-State) -ne '0'){throw 'Stream became active before activation'}
 $activationStarted=$true
 Stop-Service NvContainerLocalSystem -ErrorAction Stop
 Copy-Item -LiteralPath $candidate -Destination $NvidiaExe -Force
 if((Get-FileHash $NvidiaExe).Hash -ne $PatchedHash){throw 'Installed patched hash differs'}
 Set-Flags
 $action=New-ScheduledTaskAction -Execute "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $InstallRoot 'watch.ps1')+'"')
 $triggers=@((New-ScheduledTaskTrigger -AtStartup),(New-ScheduledTaskTrigger -AtLogOn -User $sid))
 $principal=New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
 $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([timespan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden
 Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description $TaskDescription | Out-Null
 $scheduler=New-Object -ComObject Schedule.Service;$scheduler.Connect();$scheduler.GetFolder('\').GetTask($TaskName).SetSecurityDescriptor('D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GR;;;BU)',0)
 Start-ScheduledTask -TaskName $TaskName
 Start-Service NvContainerLocalSystem -ErrorAction Stop
 Wait-Host
 $deadline=[datetime]::UtcNow.AddSeconds(60)
 do{$status=$null;try{$status=Get-Content (Join-Path $InstallRoot 'status.json') -Raw | ConvertFrom-Json}catch{};if((Test-ReadyStatus $status $runToken $manifest.Files.'NativeInterop.dll' $activationUtc) -and (Confirm-ReadySource $status $sid)){break};if([datetime]::UtcNow -ge $deadline){throw 'Fresh native source readiness timeout'};Start-Sleep -Seconds 1}while($true)
 $state.Phase='Installed';Write-JsonAtomic $state $statePath
 'Candidate installed. Verify input separately. No reboot performed.'
}catch {
 $activationFailure=$_.Exception.GetBaseException().Message
 if(!$activationStarted){$state.Phase='Staging';Write-JsonAtomic $state $statePath;throw ('Activation deferred; active host preserved: '+$activationFailure)}
 try{Recover-Installation $state}catch{throw ('Activation failed: '+$activationFailure+'. '+$_.Exception.GetBaseException().Message)}
 throw ('Activation failed and recovery completed: '+$activationFailure)
}
