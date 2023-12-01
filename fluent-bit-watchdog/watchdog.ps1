 # EventIDs
# 1000: Failed to query prometheus endpoint
# 1001: Fluentbit stopped sending records
# 1002: Fluentbit service is not running
# 1003: Found duplicate process
# 2000: Fluentbit service hung
# 2001: Killed fluentbit process to unhang service

# Check for any existing instances of the script
$existingInstances =  Get-WmiObject Win32_Process -Filter "Name='powershell.exe' AND CommandLine LIKE '%watchdog.ps1%'" | Select-Object -ExpandProperty ProcessID
# Terminate any existing instances of the script
foreach ($instance in $existingInstances) {
    # Ignore my current instance
    if($instance -ne $PID){
        Write-EventLog -LogName "Application" -Source "Application" -EventID 1003 -EntryType Info -Message "Found another running instance (PID:${instance}), killing it."
        Stop-Process -Id $instance -Force
    }
 } 

$promUri = "http://localhost:2021/api/v1/metrics/prometheus"
$metricName = "fluentbit_output_proc_records_total"
$staleThreshold = [TimeSpan]::FromMinutes(3)
$checkInterval = [TimeSpan]::FromSeconds(30)
$promScrapeInterval = [TimeSpan]::FromSeconds(30)

# Function to scape prometheus to gather fluentbit metrics.
# If we fail, we log event 1000 to indicate that the endpoint
# is unavailable.
function Get-PrometheusMetrics {
    try{
        # we need -UseBasicParsing to bypass internet explorer first launch requirement
        $response = Invoke-WebRequest -Uri $promUri -UseBasicParsing
    }catch [System.Net.WebException] {
        Write-EventLog -LogName "Application" -Source "Application" -EventID 1000 -EntryType Warning -Message "Failed to query prometheus endpoint, restarting fluent-bit"
        Restart-Service fluent-bit
    }
    return $response.content
}

# Function to calculate metric sum
# Each output has a thread that processes metrics
# Summing up the number of processed records makes sure
# we are not restarting because of a single idle thread
function Calculate-MetricSum($metrics, $metricName) {
    $pattern = "$metricName\{[^}]*\} (\d+)"
    $sum = 0.0
    $metrics -split '\r?\n' | ForEach-Object {
    $match = [regex]::Match($_, $pattern)

    if ($match.Success) {
        $number = $match.Groups[1].Value
        $sum += $number
    }

    }
    return $sum
}

# functino to check if fluent-bit running or not
function Check-FluentbitRunning {
    return (Get-Service -Name fluent-bit).Status -eq "Running"
}

function Restart-Fluentbit {
    
    # Run in a separate process so if we are hung, we aren't stuck
    # Once fluent-bit process is killed, the hung powershell process
    # will also terminate.
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"Restart-Service fluent-bit`"" -NoNewWindow

    # Give the service more than enough time to stop
    Start-Sleep -Seconds 5

    if (Check-FluentbitRunning){
        return
    }else{
        Write-EventLog -LogName "Application" -Source "Application" -EventID 2000 -EntryType Info -Message "Fluent-bit service is hung, forcibly killing the process."
        $service_pid=  sc.exe queryex fluent-bit | Select-String 'PID\s+:\s+(\d+)' | ForEach-Object { $_.Matches.Groups[1].Value } 
        taskkill /pid $service_pid /F 
        Write-EventLog -LogName "Application" -Source "Application" -EventID 2001 -EntryType Info -Message "Killed fluent-bit process with pid ${service_pid}"
        Start-Service fluent-bit
    }
} 

$lastSum = $null
$staleTime = $null

Start-Sleep -Seconds ($promScrapeInterval+1).TotalSeconds
while ($true) {
    if (Check-FluentbitRunning){
        $metrics = Get-PrometheusMetrics
        $totalRecords = Calculate-MetricSum $metrics $metricName

        # Check if we are starting to stagnate
        if ($lastSum -ne $null -and $lastSum -eq $totalRecords) {
            # If we have just started stagnating, get a timestamp
            if ($staleTime -eq $null) {
                $staleTime = Get-Date
            }

            # If we were stagnating the lat time we checked,
            # make sure it less than what we want tolerate.
            elseif ((Get-Date) - $staleTime -ge $staleThreshold) {
                # We've breached our tolerance for stagnation, restart fluent-bit and log it
                Write-EventLog -LogName "Application" -Source "Application" -EventID 1001 -EntryType Warning -Message "Fluentbit has not processed any new records for ${staleThreshold.TotalSeconds} seconds, restarting."
                Restart-Fluentbit
                # Give prom a chance to start scraping
                Start-Sleep -Seconds ($promScrapeInterval+1).TotalSeconds
                $staleTime = $null
                }
        }
        else {
            $lastSum = $totalRecords
            # If we stop stagnating, reset
            $staleTime = $null
        }
    }else{
        Write-EventLog -LogName "Application" -Source "Application" -EventID 1002 -EntryType Warning -Message "Fluentbit not runnning, restarting fluentbit."
        Restart-Fluentbit
    }

    Start-Sleep -Seconds $checkInterval.TotalSeconds
}