param (
    [Parameter(Mandatory)]$customer_id, 
    [Parameter(Mandatory)]$ingest_token,
    $observe_host_name='collect.observeinc.com',
    $config_files_clean=$false,
    $ec2metadata=$false,
    $cloud_metadata=$false,
    $datacenter="AWS",
    $appgroup=$null,
    $local=$false,
    $force=$false,
    $branch="main"
    )

    if($observe_host_name -eq 'collect.observeinc.com'){
        $observe_host_name="${customer_id}.${observe_host_name}"
    }

    $osquery_version = "5.8.2"
    $telegraf_version = "1.26.0"
    $fluentbit_version = "2.0.9"
    
    $temp_dir  = "C:\temp\observe"
    $osquery_msiexec_args = "/I ${temp_dir}\osquery-$osquery_version.msi TARGETDIR=```"${Env:Programfiles}\osquery```" /qn"
    
    $agents = @{ 
        osquery = @{
            AgentName = "osquery"
            TestDestination = "${Env:Programfiles}\osquery"
            Version = $osquery_version
            InstallerUrl = "https://pkg.osquery.io/windows/osquery-${osquery_version}.msi"
            DownloadDest = "$temp_dir\osquery-${osquery_version}.msi"
            InstallationExpression = "Start-Process `"msiexec.exe`" -ArgumentList `"$osquery_msiexec_args`" -Wait -ErrorAction Stop"
            ConfigTemplate ="https://raw.githubusercontent.com/observeinc/windows-host-configuration-scripts/$branch/osquery.conf"
            FlagsTemplate = "https://raw.githubusercontent.com/observeinc/windows-host-configuration-scripts/$branch/osquery.flags"
            ConfigDest = "${Env:Programfiles}\osquery\osquery.conf"
            FlagDest = "${Env:Programfiles}\osquery\osquery.flags"
            ServiceName = "osqueryd"
            LocalFile = "./osquery.conf"
            LocalFlagFile = "./osquery.flags"
        }
        telegraf = @{
            AgentName = "telegraf"
            TestDestination = "${Env:Programfiles}\InfluxData\telegraf\telegraf-${telegraf_version}"
            Version = $telegraf_version
            InstallerUrl = "https://dl.influxdata.com/telegraf/releases/telegraf-${telegraf_version}_windows_amd64.zip"
            DownloadDest =  "$temp_dir\telegraf-${telegraf_version}.zip"
            InstallationExpression = "Expand-Archive $temp_dir\telegraf-${telegraf_version}.zip -DestinationPath `"$Env:Programfiles\InfluxData\telegraf`" -Force -ErrorAction Stop"
            ConfigTemplate = "https://raw.githubusercontent.com/observeinc/windows-host-configuration-scripts/$branch/telegraf.conf"
            ConfigDest = "${Env:Programfiles}\InfluxData\telegraf\telegraf-${telegraf_version}\conf\telegraf.conf"
            CreateServiceExpression = "Start-Process `"${Env:Programfiles}\InfluxData\telegraf\telegraf-${telegraf_version}\telegraf.exe`" -ArgumentList `"--service install --config-directory ```"${Env:Programfiles}\InfluxData\telegraf\telegraf-$telegraf_version\conf\```""" -Wait -ErrorAction Stop"
            ServiceName = "telegraf"
            LocalFile = "./telegraf.conf"
        }
        fluentbit = @{
            AgentName = "fluentbit"
            TestDestination = "${Env:Programfiles}\fluent-bit"
            Version = $fluentbit_version
            InstallerUrl ="https://fluentbit.io/releases/2.0/fluent-bit-${fluentbit_version}-win64.exe"
            DownloadDest = "$temp_dir\fluent-bit-${fluentbit_version}.exe"
            InstallationExpression = "Start-Process $temp_dir\fluent-bit-${fluentbit_version}.exe -ArgumentList `"/S /D=```"$Env:Programfiles\fluent-bit```"`" -Wait -ErrorAction Stop"
            ConfigTemplate = "https://raw.githubusercontent.com/observeinc/windows-host-configuration-scripts/$branch/fluent-bit.conf"
            ConfigDest = "${Env:Programfiles}\fluent-bit\conf\fluent-bit.conf"
            CreateServiceExpression = "New-Service fluent-bit -BinaryPathName `"```"${Env:Programfiles}\fluent-bit\bin\fluent-bit.exe```" -c ```"${Env:Programfiles}\fluent-bit\conf\fluent-bit.conf```"`" -StartupType Automatic -ErrorAction Stop"
            ServiceName = "fluent-bit"
            LocalFile = "./fluent-bit.conf"
        }
    }

function Create-Services {
    
    param(
        $agent
    )

    if(-not (Get-Service $agent.ServiceName -ErrorAction SilentlyContinue)){
        Write-Host "$($agent.ServiceName) does not exist, trying to create.."
        Write-Host $agent.CreateServiceExpression
        Invoke-Expression $agent.CreateServiceExpression
    }

    if(-not ((Get-Service $agent.ServiceName -ErrorAction SilentlyContinue).Status -eq "Running")){
         Write-Host "service $($agent.ServiceName) not running, trying to restart.."
    }else{
        Write-Host "service $($agent.ServiceName) is running, trying to restart.."
    }
    Stop-Service $agent.ServiceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-service $agent.ServiceName -ErrorAction Stop
    Get-Service $agent.ServiceName
    

}

function Confirm-Overwrite {
    param (
        $agent,
        $file
    )
    if($force){
        return $true
    }else{
        Write-Host "found config for $agent in $file"
        $confirmation = Read-Host "would you like to overwrite? [y/N]:"
        if($confirmation -eq "y"){
            Write-Host "Overwriting $file..."
            return $true
        }else{
            "skipping configuration for $file"
            return $false
        }
    }
}

function Configure-AgentsTemplates {

    param (
        $agent
    )

    $continue = $false

    if(Test-Path -LiteralPath $agent.ConfigDest){
        $continue = Confirm-Overwrite -agent $agent.AgentName -file $agent.ConfigDest
    }else{
        $continue = $true
    }
    if($continue){
        $observe_host_name = $observe_host_name -Replace "https://", "" -Replace ".com/", ".com"
        $configTemplate = if($local ){ Get-Content $agent.LocalFile} else{(Invoke-WebRequest -UseBasicParsing $agent.configTemplate).Content}
        $configTemplate = $configTemplate -replace "<<customer_id>>", $customer_id -replace "<<ingest_token>>", $ingest_token -replace "<<observe_host_name>>" , $observe_host_name
        if($ec2metadata){
             $configTemplate = $configTemplate -replace "#####", ""
             $configTemplate  = $configTemplate  -replace "  datacenter = `"AWS`"", "  datacenter = `"$datacenter`""
        }

        if($null -ne $appgroup){
            $configTemplate = $configTemplate -replace "#    Record appgroup ha-proxy", "    Record appgroup $appgroup"
        }
        if($datacenter -ne "AWS"){
            $configTemplate = $configTemplate -replace "    Record datacenter AWS", "    Record datacenter $datacenter"
            $configTemplate  = $configTemplate  -replace "  datacenter = `"AWS`"", "  datacenter = `"$datacenter`""
        }

        Set-Content -Path $agent.ConfigDest -Value $configTemplate -Force -ErrorAction Stop
    }
    if(($agent.AgentName -eq "osquery") -and (Test-Path -LiteralPath $agent.FlagDest)){
        $continue = Confirm-Overwrite -agent $agent.AgentName -file $agent.FlagDest
        if($continue){
            $osqueryFlagTemplate = if($local){ Get-Content $agent.LocalFlagFile } else{(Invoke-WebRequest -UseBasicParsing $agent.FlagsTemplate).Content}
            Set-Content -Path $agent.FlagDest -Value $osqueryFlagTemplate -Force -ErrorAction Stop
        }
    }
}

function Download-AgentInstallers {

    param (
        $agent
    )
    if (-not (Test-Path -LiteralPath $agent.DownloadDest)) { 
        Write-Host "downloading $($agent.AgentName) version $($agent.Version)..."
        Invoke-WebRequest $agent.InstallerUrl -Outfile $agent.DownloadDest -ErrorAction Stop
    }else{
        Write-Host "found $($agent.DownloadDest), skipping download for $($agent.AgentName)..."
    }

}

function Install-Agents {

    param (
        $agent
    )

    write-host $agent.InstallationExpression

    Invoke-Expression $agent.InstallationExpression
}

function Check-TempDir {

    param (
        $temp_dir
    )
    Write-Host "checking for temp directory to download agents to..."
    if (-not (Test-Path -LiteralPath $temp_dir)) { 
        try {
            New-Item -Path $temp_dir -ItemType Directory -ErrorAction Stop | Out-Null #-Force
        }
        catch {
            Write-Error -Message "unable to create directory '$temp_dir'. Error was: $_" -ErrorAction Stop
        }
        "successfully created directory '$temp_dir'..."
    }
    else {
        "'$temp_dir' exists, moving on..."
    }
}

function Check-AgentInstalled {

    param(
        $agent
    )

    return (Test-Path $agent.TestDestination -ErrorAction SilentlyContinue)

}

Check-TempDir $temp_dir

foreach ($agent in $agents.Keys) {
   foreach ($agentProps in $agents[$agent]){
        if(Check-AgentInstalled $agentProps){
            Write-Host "$agent is already installed, skipping installation"
        }else{
            Download-AgentInstallers $agentProps -Wait
            Install-Agents $agentProps
        }
        Configure-AgentsTemplates $agentProps
        Create-Services $agentProps
   }
}

if($config_files_clean){
    Write-Host "Removing temp files..."
    Remove-Item $temp_dir -Recurse
} 


if ($cloud_metadata) {
    $metadata_command = "? ."
    $metadata_commands = @(
        # Azure
        '$body = Invoke-RestMethod -Headers @{"Metadata"="true"} -Method GET -Uri "http://169.254.169.254/metadata/instance?api-version=2021-02-01" | ConvertTo-Json -Depth 64 -Compress',
        # GCP
        '$body = Invoke-RestMethod -Headers @{"Metadata-Flavor" = "Google"} -Uri "http://metadata.google.internal/computeMetadata/v1/?recursive=true" | ConvertTo-Json -Depth 64 -Compress',
        # AWS
        '$token = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "60"} -Method PUT -Uri http://169.254.169.254/latest/api/token; $body = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/dynamic/instance-identity/document | ConvertTo-Json -Depth 64 -Compress'
    )
    foreach ($command in $metadata_commands) {
        try {
            Invoke-Expression $command | Out-Null
            $metadata_command = $command + "; Invoke-RestMethod -Headers @{'Authorization' = 'Bearer $ingest_token'} -ContentType application/json -Method POST -Body " + '$body' + " -Uri $observe_host_name/v1/http/cloud_metadata"
            break
        } catch {}
    }
    Write-Host "Using the following cloud metadata command: $metadata_command"
    try {
        Unregister-ScheduledJob observe-cloud-metadata
    } catch {}
    Register-ScheduledJob -Name observe-cloud-metadata -ScriptBlock {
        param ($command)
        Invoke-Expression $command
    } -RunNow -RunEvery (New-TimeSpan -Minutes 5) -ArgumentList $metadata_command
}
