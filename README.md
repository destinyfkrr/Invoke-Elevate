# Invoke-Elevate

This utility exploits the Windows Task Scheduler API to conduct a Lateral Elevation from the Local Administrator session to the NT AUTHORITY\SYSTEM account. By registering a task and bridging it to a local Named Pipe, the script captures the command output directly in memory and never touches the physical disk.

However, in the event the command payload is detected by security software, the AMSI bypass code should be implemented to disable the memory scanner prior to execution

Testing has demonstrated that the tool is fully functional on the latest Windows 11 builds when run from the UAC Bypassed Terminal, even with Windows Defender enabled

Requirement : An active PowerShell session with Local Administrator rights (High Integrity)
