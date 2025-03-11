<#
	.SYNOPSIS
	Partial replacement for User Profiles management GUI.

	.DESCRIPTION
	List local user profiles sorted by last logon time. This is needed as the GUI uses the NTUSER.DAT timestamp which is now touched daily.

	Optionally remove profiles from the registry and delete the folder from the file System.

	Optionally remove user folders with no corresponding registry profile.

	Optionally calculate the disk usage of each profile folder.

	Local admin accounts are always ignored and loaded accounts are not cleaned

	Hard coded list of user SID values to ignore. Hard coded list of orphan folders to ignore e.g. Public.

	Preserves profiles used recently. Default 90 days.

	The script can fix one specific case of incomplete registry profiles.

	.PARAMETER Days
	Preserve profiles where logon date is more recent than the value days ago. Default is 90. Zero indicates "now", so negative values are not needed and will not validate.
	
	.PARAMETER All
	Synonym for -Cleanup -Orphan. Overrides those values if set.
	
	.PARAMETER Cleanup
	Call the Win32_UserProfile object Delete method for each matching profile.
	
	.PARAMETER Deboog
	Include output for coders.
	
	.PARAMETER Dirty
	Treat dirty profiles as old so they are removed if Cleanup is specified. Admin,skiplist and loaded profile exceptions are still honoured.
	
	.PARAMETER HideNoLoadTime
	Skip never used profiles. Verboze will show them anyway.
	
	.PARAMETER HideNoPath
	Skip profiles with no image path. Verboze will show them anyway.

	.PARAMETER Listadmin
	Include the local admin accounts in the listing irrespective of logon time. This output is normally suppressed.
	
	.PARAMETER Orphan
	Remove folders in c:\users with no corresponding registry profile (except Public).
	
	.PARAMETER Repair
	If CleanUp fails add registry keys.
	
	.PARAMETER Size
	Calculate disk usage for each file in c:\users.
	
	.PARAMETER Verboze
	Include extra output.
	
	.EXAMPLE
	PS> .\profiletimes.ps1 -Days 0 -Listadmin -Verboze
	
	List all profiles including local admin. Provide annotations.
	
	.EXAMPLE
	PS> .\profiletimes.ps1 -Days 9999 -Dirty
	
	Preserve all profiles (newer than 27 years) but mark dirty profiles as deletable.
	
	.EXAMPLE
	In the case where delete throws an exception. If default -Days is okay, run
	
	PS> .\profiletimes -Cleanup -Deboog
	
	This will display the item values for the profile. If Flags, State and ProfileImagePath are missing, Run
	
	PS> .\profiletimes.ps1 -Cleanup -Repair
	PS> .\profiletimes.ps1 -Cleanup
#>


param (
	[ValidateRange(0,9999)]
	[int]$Days = 90,
	[switch]$All = $false,
	[switch]$Cleanup = $false,
	[switch]$Deboog = $false,
	[switch]$Dirty = $false,
	[switch]$HideNoLoadTime,
	[switch]$HideNoPath = $false,
	[switch]$Listadmin = $false,
	[switch]$Orphan = $false,
	[switch]$Repair,
	[switch]$Size = $false,
	[switch]$Verboze = $false
)

if($All) {
	$Cleanup = $true
	$Orphan = $true
}

$skiplist =
"S-1-12-1-1111111111-1111111111-1111111111-1111111111",	#AzureAD\account1
"S-1-12-1-2222222222-2222222222-2222222222-2222222222"	#AzureAD\account2

$folderskiplist =
"",	# Cannot happen, but would be bad if it did
"Public"

$now = Get-Date
$preserve =  $now.AddDays(-$Days)

$array = @()

$profiles = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\ProfileList\*"

# Loop through each profile
Foreach ($profile in $profiles) {
	# Get the SID
	try {
		$SID = New-Object System.Security.Principal.SecurityIdentifier($profile.PSChildName)
	}
	# Key is not a SID, *.bak for example?
	catch {
		Write-Host "New-Object SID $($profile.PSChildName) threw an error" -ForegroundColor "Red"
		if($Deboog) {
			Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\ProfileList\$($profile.PSChildName)"
		}
	}
	# Convert SID to Friendly name
	try {
		$FriendlyName = $SID.Translate([System.Security.Principal.NTAccount])
	}
	catch {
		Write-Host "Translate threw an error $($profile.PSChildName)" -ForegroundColor "Red"
	}

	# Trim and store variables
	$SidTrimmed = $SID.Value
	$FriendlyNameTrimmed = $FriendlyName.Value
	
	$array+= (
		[pscustomobject]@{
			SidTrimmed = $SidTrimmed
			FriendlyNameTrimmed = $FriendlyNameTrimmed
			ProfileImagePath = $profile.ProfileImagePath
			ProfileLoadTime = ([int64]$profile.LocalProfileLoadTimeHigh -shl 32) -bor ([int64]$profile.LocalProfileLoadTimeLow)
			ProfileUnloadTime = ([int64]$profile.LocalProfileUnLoadTimeHigh -shl 32) -bor ([int64]$profile.LocalProfileUnLoadTimeLow)
		}
	)
}

# When deleting do oldest first, otherwise list oldest last
if($Cleanup) {
	$descending = $false
} else {
	$descending = $true
}

foreach ($profile in $array | sort -Property ProfileLoadTime -Descending:$($descending)) {
	$ProfileLoadDate = [DateTime]::FromFileTimeUTC($profile.ProfileLoadTime)
	$ProfileUnLoadDate = [DateTime]::FromFileTimeUTC($profile.ProfileUnLoadTime)

	# Never operate on local system accounts
	if ( $profile.SidTrimmed -like "S-1-5*") {
		if($Listadmin) {
			Write-Host "LOCAL ADMIN" -ForegroundColor "Yellow"
			Write-Output "SID: $($profile.SidTrimmed)"
			Write-Output "Friendly Name: $($profile.FriendlyNameTrimmed)"
			Write-Output "Profile Image Path: $($profile.ProfileImagePath)"
			Write-Output "Profile Load Date: $ProfileLoadDate"
			Write-Output "Profile UnLoad Date: $ProfileUnLoadDate"
			Write-Output ""
		}
		continue
	}

	if($Verboze -or $HideNoPath) {
		if ($($profile.ProfileImagePath) -like "") {
			Write-Host "NO PATH $($profile.FriendlyNameTrimmed) $($profile.SidTrimmed)" -ForegroundColor "Yellow"

			if(! $Verboze) { continue }
		} else {
			if ((Test-Path -Path "$($profile.ProfileImagePath)") -eq $false) {
				Write-Host "WIDOW $($profile.FriendlyNameTrimmed) $($profile.ProfileImagePath) $($profile.SidTrimmed)" -ForegroundColor "Yellow"
			}
		}
	}

	if($Verboze -or $HideNoLoadTime) {
		if($($profile.ProfileLoadTime) -eq 0) {
			Write-Host "NO LOADTIME $($profile.FriendlyNameTrimmed) $($profile.ProfileImagePath) $($profile.SidTrimmed))" -ForegroundColor "Yellow"
			
			if(! $Verboze) { continue }
		}
	}
	
	if ($($profile.ProfileLoadTime) -ne 0 -and ($($profile.ProfileUnLoadTime) -lt $($profile.ProfileLoadTime))) {
		if($Dirty) {
			Write-Host "Changing Profile Load Date from [$($ProfileLoadDate)] to force removal $($profile.FriendlyNameTrimmed) $($profile.ProfileImagePath) $($profile.SidTrimmed)" -ForegroundColor "Yellow"
			$ProfileLoadDate = Get-Date([DateTime]::FromFileTimeUTC(0))
		} elseif($Verboze) {
		Write-Host "Profile was not cleanly unloaded [$($ProfileLoadDate)] [$($ProfileUnloadDate)] $($profile.FriendlyNameTrimmed) $($profile.ProfileImagePath) $($profile.SidTrimmed)" -ForegroundColor "Yellow"
		}
	}

	if ($ProfileLoadDate -lt $preserve) {
		if ($skiplist -contains $profile.SidTrimmed) {
			if ($Verboze -or $Dirty) {
				write-host "Skip: $($profile.FriendlyNameTrimmed) $($profile.ProfileImagePath) $($profile.SidTrimmed)" -ForegroundColor "Yellow"
				}
			if (! $Verboze) { continue }
		} elseif($Cleanup) {
			$object = Get-WMIObject -Class Win32_UserProfile -filter "SID='$($profile.SidTrimmed)'"
			# Catches session time > $Days
			if ($object.Loaded) {
				if ($Verboze -or $Dirty) {
					Write-Host "Profile is loaded, not deleting $($profile.FriendlyNameTrimmed) $($profile.ProfileImagePath) $($profile.SidTrimmed)" -ForegroundColor "Yellow"
					}
				if (! $Verboze) { continue }
			} else {
				Write-Host "Deleting $($profile.FriendlyNameTrimmed) $($profile.ProfileImagePath) $($profile.SidTrimmed)" -ForegroundColor "Red"
				try {
					$object.Delete()
				}
				catch {
					Write-Host "Delete method threw exception" -ForegroundColor "Yellow"						
					
					if($Repair) {
						Write-Host "Adding registry keys. Rerun the script." -ForegroundColor "Red"
						
						New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($profile.SidTrimmed)" -Name Flags -PropertyType DWord -Force
						New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($profile.SidTrimmed)" -Name State -PropertyType DWord -Force
						New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($profile.SidTrimmed)" -Name ProfileImagePath -PropertyType ExpandString -Force
					} elseif ($Deboog) {
						Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\ProfileList\$($profile.SidTrimmed)"
					}
				}
			continue
			}
		}
	} else {
		if (! $Verboze) { continue }
		Write-Host "Keep" -ForegroundColor "Yellow"
	}

	# Fall through to here when continue is not called
	
	# days to use to preserve the record. Will change at load time each day.
	$age = [Math]::Ceiling(($now - $ProfileLoadDate).TotalDays)

	Write-Output "SID: $($profile.SidTrimmed)"
	Write-Output "Friendly Name: $($profile.FriendlyNameTrimmed)"
	Write-Output "Profile Image Path: $($profile.ProfileImagePath)"
	Write-Output "Profile Load Date: $ProfileLoadDate"
	Write-Output "Profile UnLoad Date: $ProfileUnLoadDate"
	Write-Host "$($age)" -ForegroundColor "Yellow"
	Write-Output ""
}

if ($Verboze) {
	Write-Host "N.B. US date format.`n" -ForegroundColor "Yellow"
}

$folders = gci -Path C:\Users\ -Attributes Directory

if ($Deboog) {
	Write-Host "Found $($array.length) Registry entries" -ForegroundColor "Red"
	Write-Host "Found $($folders.length) folders in c:\users" -ForegroundColor "Red"
}

foreach ($folder in $folders) {
	if ( ! ($array.ProfileImagePath -like "*$($folder.Name)")) {
		if ($folderskiplist -contains $($folder.Name)) {
			if($Verboze) {
				Write-Host "Skipping orphan folder $($folder.Name)" -ForegroundColor "Yellow"
			}
			continue
		}

	# Fall through to here when continue is not called
	if($Orphan) {
			Write-Host "Deleting orphan folder c:\users\$($folder.Name)"  -ForegroundColor "Red"
			Remove-Item -Path "c:\users\$($folder.Name)" -Force -Recurse -ErrorAction SilentlyContinue
		} else {
			Write-host "Orphan folder: $($folder.Name)" -ForegroundColor "Yellow"
		}
	}
}

if($Size) {
	Write-Host "`nCTRL-C to quit" -ForegroundColor "Yellow"

	Foreach ($profile in $array | sort -Property ProfileUnloadTime) {

		# If ProfileImagePath is empty, dir lists the current working directory	
		if ($($profile.ProfileImagePath) -like "") {
			continue
		}

		Write-Output "$($profile.FriendlyNameTrimmed) $($profile.ProfileImagePath)"

		# Hack to work around offline files (OneDrive)		
		$dirlist = cmd.exe /c "dir $($profile.ProfileImagePath) /s /a-o"
		$pathsize = $dirlist[-2]
		
		Write-Output "$pathsize"
	}
}

if($Deboog) {
	$end = Get-Date
	$runtime = ($end - $now).TotalSeconds

	Write-Host "$($now) $($end)" -ForegroundColor "Red"
	Write-Host "Runtime $($runtime)s" -ForegroundColor "Red"
}