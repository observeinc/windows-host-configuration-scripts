# EventIDs
# 1000: Failed to query prometheus endpoint
# 1001: Fluentbit stopped sending records
# 1002: Fluentbit service is not running

$promUri = "http://localhost:2021/api/v1/metrics/prometheus"
$metricName = "fluentbit_output_proc_records_total"
$staleThreshold = [TimeSpan]::FromMinutes(3)
$checkInterval = [TimeSpan]::FromSeconds(30)
$promScrapeInterval = [TimeSpan]::FromSeconds(30)

# If fluent-bit isn't running we start, we wait with an
# exponential backoff
$backoffCounter = 1
$backoffMultiplier = 0.5
$backoffLimit = [TimeSpan]::FromMinutes(5)

# Function to scape prometheus to gather fluentbit metrics.
# If we fail, we log event 1000 to indicate that the endpoint
# is unavailable.
function Get-PrometheusMetrics {
    try{
        $response = Invoke-WebRequest -Uri $promUri
    }catch [System.Net.WebException] {
        Write-EventLog -LogName "Application" -Source "Application" -EventID 1000 -EntryType Warning -Message "Failed to query prometheus endpoint."
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

$lastSum = $null
$staleTime = $null

Start-Sleep -Seconds ($promScrapeInterval+1).TotalSeconds
$sleepTime = $checkInterval
while ($true) {
    # If the service was never running, 
    # we shouldn't bother doing anything until it starts
   $sleepTime = [TimeSpan]::FromSeconds([Math]::Ceiling($sleepTime.TotalSeconds * $backoffCounter))
    if (Check-FluentbitRunning){
        # reset backoff counter if we previously failed
        $backoffCounter =1 
        $sleepTime = $checkInterval
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
                Restart-Service fluent-bit
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
        Write-EventLog -LogName "Application" -Source "Application" -EventID 1002 -EntryType Warning -Message "Fluentbit not runnning, waiting $($sleepTime.TotalSeconds) seconds and retrying."
        if ($sleepTime -lt $backoffLimit.TotalSeconds){
            $backoffCounter += $backoffMultiplier
         }
    }

    Start-Sleep -Seconds $sleepTime.TotalSeconds
}
 
