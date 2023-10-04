param (
    [switch]$ForceRemove = $false,
    [switch]$Help
)

if ($Help) {
    Write-Host "Usage: Uninstall.ps1 [-ForceRemove] [-Help]"
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -ForceRemove      Force removal without confirmation."
    Write-Host "  -Help             Display this help message."
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  Remove agents with confirmation:"
    Write-Host "  .\Uninstall.ps1"
    Write-Host ""
    Write-Host "  Remove agents' services without confirmation:"
    Write-Host "  .\Uninstall.ps1 -ForceRemove"
    exit
}

# Function to backup configuration files
function Backup-ConfigFiles {
    param (
        [string]$SourcePath,
        [string]$BackupPath,
        [bool]$Recursive=$True
    )

    # Ensure the backup directory exists or create it
    if (-not (Test-Path -Path $BackupPath -PathType Container)) {
        try {
            New-Item -Path $BackupPath -ItemType Directory
        } catch {
            Write-Host "Error creating backup directory: $_"
            return
        }
    }

    # Check if the source path exists
    if (Test-Path -Path $SourcePath -PathType Container) {
        # Get .conf files recursively from the source path
        if($Recursive){
            $configFiles = Get-ChildItem -Path $SourcePath -Filter "*.conf" -File -Recurse
        }else{
            $configFiles = Get-ChildItem -Path $SourcePath -Filter "*.conf" -File
        }

        foreach ($file in $configFiles) {
            $backupFilePath = Join-Path -Path $BackupPath -ChildPath $file.Name
            Copy-Item -Path $file.FullName -Destination $backupFilePath -Force
            Write-Host "Backup: $($file.FullName) -> $($backupFilePath)"
        }
    } else {
        Write-Host "Source path not found: $SourcePath"
    }
}


function Remove-Agent {
    param (
        [string]$ServiceName
    )

    if ($ForceRemove -or (Read-Host "Do you want to remove the '$ServiceName' service? (Y/N)").ToLower() -eq 'y') {
        # Backup configuration files before removing
        if ($ServiceName -eq "telegraf") {
            Backup-ConfigFiles -SourcePath "$env:ProgramFiles\InfluxData\telegraf" -BackupPath "C:\temp\observe\telegraf-backup"
        } elseif ($ServiceName -eq "fluent-bit") {
            Backup-ConfigFiles -SourcePath "$env:ProgramFiles\fluent-bit\conf" -BackupPath "C:\temp\observe\fluent-bit-backup"
        } elseif ($ServiceName -eq "osquery") {
            Backup-ConfigFiles -SourcePath "$env:ProgramFiles\osquery" -BackupPath "C:\temp\observe\osquery-backup" -Recursive $false
        }

        # Check if the service exists
        if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
            # Stop the service
            Stop-Service -Name $ServiceName -Force

            # Use the sc.exe utility to delete the service
            $result = & "sc.exe" delete $ServiceName

            # Check the result of the sc.exe command
            if ($result.Contains("SUCCESS")) {
                Write-Host "Service '$ServiceName' deleted successfully."
            } else {
                Write-Host "Failed to delete service '$ServiceName'. The sc.exe command returned exit code $result."
            }
        } else {
            Write-Host "$ServiceName service not found."
        }
    } else {
        Write-Host "Skipping removal of '$ServiceName' service."
    }
}

# Rest of your script...

# If -Help is specified, display help and exit
if ($Help) {
    exit
}

# Example usage:
# Remove the 'fluent-bit' service with confirmation or force removal
Remove-Agent -ServiceName "fluent-bit"

# Remove the 'telegraf' service with confirmation or force removal
Remove-Agent -ServiceName "telegraf"

# Remove 'osquery' with confirmation or force removal
Remove-Agent -ServiceName "osquery"

Write-Host "Uninstall completed. Note that some files may have been left behind."
Write-Host "The following directories may need to be manually removed:"
Write-Host "$env:ProgramFiles\fluent-bit"
Write-Host "$env:ProgramFiles\InfluxData"
Write-Host "$env:ProgramFiles\osquery"
Write-Host "config files were backed up to C:\temp\observe\" 
