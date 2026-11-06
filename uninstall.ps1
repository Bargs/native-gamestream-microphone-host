[CmdletBinding()]
param([switch]$DryRun)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'management.ps1')
[void](Verify-Package $PSScriptRoot)
if($DryRun){'Dry run: package verified. Uninstall restores only managed vendor bytes/flags, removes the owned task, attempts service restart independently and retains backups. No writes performed.';return}
Require-Admin
Assert-ProtectedTree $InstallRoot
$state=Get-Content (Join-Path $InstallRoot 'install-state.json') -Raw | ConvertFrom-Json
if($state.PackageId -ne $PackageId){throw 'Existing installation belongs to another installer; preserved'}
if((Host-State) -ne '0'){throw 'Quit the streamed application before recovery'}
if($state.Phase -eq 'RolledBack'){'Candidate already restored; backups retained.';return}
Recover-Installation $state
'Original managed state restored; task removed; backups and source retained.'
