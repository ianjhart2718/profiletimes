# profiletimes
List local user profiles sorted by registry last logon time. This is needed as the GUI uses the NTUSER.DAT timestamp which is now touched daily.

Optionally remove matching profiles or orphan home folders.
## Caveats
With no parameters the script will run in readonly mode. Ensure you are happy before enabling registry cleanup or home folder deletion.

The safest usage case is to use the script to identify suitable candidates and then use the GUI to delete them.

I am not a powershell guru. I am also new to GitHub. I no longer have access to suitable test systems (I'm retired).
## Intended target systems
It's a powershell script tested on Windows 11 Education and Enterprise. It should work on any version of Windows where the profiles are in the same registry location and the WMI object exists, but do test carefully.
## Usage
Open an administrator CMD prompt. Run powershell.exe with suitable parameters (or use runpowershell.bat)
There's comment based help available.

Get-Help .\profiletimes.ps1 -Detailed

To get a feel for the script run:

.\profiletimes.ps1 -Days 0 -Verboze -Deboog -Listadmin

This gives you maximum verbosity. With -Days 0 no profiles are preserved i.e. hidden from the output. -Listadmin includes local system accounts that are normally suppressed. -Verboze provides annotations and -Deboog adds extra comments. Note the default for the Days parameter is 90. 

Profile listings include "days" output in yellow. Use this to set the -Days parameter so one profile is listed. If you're happy to remove the listed profile(s) and home folder(s), add the -Cleanup parameter and run again.

If the output indicates orphan home folders, you can remove them by including the -Orphan parameter, with or without -Cleanup.

Here's another way you can use the script.

.\profiletimes.ps1 -Days 9999 -Dirty

This preserves (hides) profiles newer than 27 years, which should be all of them, but marks dirty profiles as ancient (425 years old). This lets you select those profiles where the log off wasn't clean. These are sometimes corrupt. Again add -Cleanup to make it live.

Note that the currently logged on user will match this, but separate code protects it from deletion.

That should be enough to get you going. More will follow.
