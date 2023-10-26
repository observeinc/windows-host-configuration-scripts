# Function to update configuration
function UpdateConfiguration($configFile, $settings) {
    # Read the existing configuration
    $existingConfig = Get-Content $configFile -Raw

    # Append the settings to the configuration
    $newConfig = $existingConfig + "`n$settings"

    # Write the updated configuration back to the file
    Set-Content -Path $configFile -Value $newConfig
}

$fluentConf = "C:\Program Files\fluent-bit\conf\fluent-bit.conf"
# Find the Telegraf configuration file based on the version in the directory
$telegrafDir = "C:\Program Files\InfluxData\telegraf"  # Adjust the directory as needed
$telegrafVersion = Get-ChildItem -Path $telegrafDir | Where-Object { $_.PSIsContainer } | Sort-Object -Descending | Select-Object -First 1
$telegrafConf = Join-Path -Path $telegrafDir -ChildPath "$telegrafVersion\telegraf.conf"

# Define the settings for Fluent Bit
$fluentBitServiceSettings = @"
[SERVICE]
    http_server  On
    http_listen  127.0.0.1
    http_port    2021
    storage.metrics on
    Health_Check On 
    HC_Errors_Count 5 
    HC_Retry_Failure_Count 5 
    HC_Period 5
"@

# Define the settings for Telegraf
$telegrafSettings = @"
[[inputs.http]]
  urls = [
    "http://localhost:2021/api/v1/storage"
  ]
  interval = "20s"
  data_format = "json_v2"
  [[inputs.http.json_v2]]
    measurement_name = "fluentbit_storage"
    [[inputs.http.json_v2.object]]
      path = "storage_layer"
    [[inputs.http.json_v2.object]]
      path = "input_chunks"
[[inputs.prometheus]]
  urls = ["http://localhost:2021/api/v1/metrics/prometheus"]
  interval = "20s"
  metric_version = 1
"@

# Update Fluent Bit configuration
UpdateConfiguration -configFile $fluentConf -settings $fluentBitServiceSettings

# Update Telegraf configuration
UpdateConfiguration -configFile $telegrafConf -settings $telegrafSettings

Restart-Service fluent-bit
Restart-Service telegraf

$taskName = "Observe Fluent-bit Watchdog"
$taskPath = "\"
$watchdogDir = "c:\observe"
$watchdogFile = "$watchdogDir\watchdog.ps1"
$downloadUrl = "https://raw.githubusercontent.com/observeinc/windows-host-configuration-scripts/main/fluent-bit-watchdog/watchdog.ps1"


if (-not (Test-Path -Path $watchdogDir -PathType Container)) {
    New-Item -Path $watchdogDir -ItemType Directory
}

Invoke-WebRequest -Uri $downloadUrl -OutFile $watchdogFile

# The task doesn't exist, so create it
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$watchdogFile`" -WindowStyle Hidden"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$settings.RestartInterval = "PT5M"  # Restart the task after 1 minute if it fails
$settings.RestartCount = 9999  # Set a high number to make it run indefinitely
$settings.ExecutionTimeLimit = "P999D"
# Set the task to run with the SYSTEM account
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount

if (Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue ) {
    Set-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger -Settings $settings -Principal $principal
} else {
    Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger -Settings $settings -Principal $principal
}

# Start the scheduled task immediately after creating or updating it
Start-ScheduledTask -TaskPath $taskPath -TaskName $taskName 
