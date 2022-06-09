######## params
param (
    [Parameter(Mandatory)]$customer_id, 
    [Parameter(Mandatory)]$ingest_token,
    $observe_host_name='collect.observeinc.com',
    $config_files_clean=$false,
    $ec2metadata=$false,
    $datacenter,
    $appgroup
    )

[Net.ServicePointManager]::SecurityProtocol = "Tls, Tls11, Tls12, Ssl3"
######## vars
$github = "https://github.com"
$temp_dir  = "C:\temp\observe\" #download installers here
$msiexec = "msiexec.exe"

# osquery
$osquery_installer = "osquery.msi"
$osquery_github_releases = "$github/osquery/osquery/releases/latest"
$osquery_installer_path = "$temp_dir$osquery_installer"
$osquery_destination     = "$Env:Programfiles\osquery"
$osquery_config_template = ".\osquery.conf"
$osquery_msiexec_args = "/I ${osquery_installer_path} TARGETDIR=`"${Env:Programfiles}\osquery`" /qn"


# telegraf
$telegraf_installer = "telegraf.zip"
$telegraf_github_releases = "$github/influxdata/telegraf/releases/latest"
$telegraf_extraction_dir   = "C:\Program Files\InfluxData\"
$telegraf_installer_path = "$temp_dir$telegraf_installer"
$telegraf_destination = "$Env:Programfiles\InfluxData\telegraf"
$telegraf_config_template = ".\telegraf.conf"

# fluentbit
$fluentbit_installer = "fluentbit.exe"
$fluentbit_installer_regex = '(?!\/\w+\/)*(?!v)\d+\.\d+\.\d+(?<!\.zip)'
$fluentbit_installer_path = "$temp_dir$fluentbit_installer"
$fluentbit_destination = "$Env:Programfiles\fluent-bit"
$fluentbit_config_template = ".\fluent-bit.conf"

# create temp dir if it doesn't exist
Write-Host "checking for temp directory to download agents to..."
if (-not (Test-Path -LiteralPath $temp_dir)) { 
    try {
        New-Item -Path $temp_dir -ItemType Directory -ErrorAction Stop | Out-Null #-Force
    }
    catch {
        Write-Error -Message "unable to create directory '$temp_dir'. Error was: $_" -ErrorAction Stop
    }
    "successfully created directory '$temp_dir'."
}
else {
    "'$temp_dir' exists, moving on..."
}

######## get installer URLs
Write-Host "determining latest osquery version..."
$osquery_latest_uri    = (Invoke-WebRequest -UseBasicParsing $osquery_github_releases -ErrorAction Stop).Links| Where-Object {$_.href -like "*msi"} | Select-Object href
$osquery_installer_url = $github+($osquery_latest_uri.href.ToString())

Write-Host "determining latest telegraf version..."
$telegraf_latest_uri    = (Invoke-WebRequest -UseBasicParsing $github/influxdata/telegraf/releases/latest -ErrorAction Stop).Links | Where-Object {$_.href -like "*windows_amd64*"} | Select-Object href
$telegraf_installer_url = $telegraf_latest_uri.href
$telegraf_version = $telegraf_installer_url.split("/")[-1].split("_")[0]

Write-Host "determining latest fluent-bit version..."
# fluentbit doesn't always link the exe to 
# github so we need to use the zip to get the version
$fluentbit_latest_uri        = (Invoke-WebRequest -UseBasicParsing $github/fluent/fluent-bit/releases/latest -ErrorAction Stop).Links | Where-Object {$_.href -like "*.zip"} | Select-Object href
$fluentbit_zip_installer_url = $github+($fluentbit_latest_uri.href.ToString())
$fluentbit_latest_version    = [regex]::Matches($fluentbit_zip_installer_url, $fluentbit_installer_regex).Value
$fluentbit_major_version     = $fluentbit_latest_version.split(".")
$fluentbit_major_version     = [String]::Join('.',$fluentbit_major_version, 0,2)
$fluentbit_installer_url     = "https://fluentbit.io/releases/${fluentbit_major_version}/fluent-bit-${fluentbit_latest_version}-win64.exe"
$fluentbit_installer_options = "/S /D=$fluentbit_destination"

######## download agents
if (-not (Test-Path -LiteralPath $osquery_installer_path)) {
    Write-Host "downloading osquery installer..." 
    Invoke-WebRequest $osquery_installer_url   -OutFile $osquery_installer_path -ErrorAction Stop
}else{
    Write-Host "osquery installer found, skipping download..." 
}
if (-not (Test-Path -LiteralPath $telegraf_installer_path)) { 
    Write-Host "downloading telegraf installer..." 
    Invoke-WebRequest $telegraf_installer_url  -OutFile $telegraf_installer_path -ErrorAction Stop
}else{
    Write-Host "telegraf installer found, skipping download..." 
}
if (-not (Test-Path -LiteralPath $fluentbit_installer_path)) { 
    Write-Host "downloading fluentbit installer..." 
    Invoke-WebRequest $fluentbit_installer_url -OutFile $fluentbit_installer_path -ErrorAction Stop
}else{
    Write-Host "fluentbit installer found, skipping download..." 
}

######## install agents
if (-not (Test-Path -LiteralPath $osquery_destination)) { 
    Write-Host "installling osquery..."
    Start-Process $msiexec -ArgumentList $osquery_msiexec_args -Wait -ErrorAction Stop
    Write-Host "finished installing osquery.."
}else{
    Write-Host "osquery path $osquery_destination already exists, skipping install..."
}

if (-not (Test-Path -LiteralPath $telegraf_destination)) { 
    Write-Host "installing telegraf..."
    Expand-Archive $telegraf_installer_path -DestinationPath $telegraf_destination -Force -ErrorAction Stop
    Write-Host "finished installing telegraf..."
}else{
    Write-Host "telegraf path $telegraf_destination already exists, skipping install..."
}

if (-not (Test-Path -LiteralPath $fluentbit_destination)) { 
    Write-Host "installing fluentbit..."
    Start-Process $fluentbit_installer_path -ArgumentList $fluentbit_installer_options -Wait -ErrorAction Stop
    Write-Host "finished installing fluentbit..."
}else{
    Write-Host "osquery path $fluentbit_destination already exists, skipping install..."
}
######## copy configs
Write-Host "writing osquery config..."
$osquery_config_template
$osquery_program_path
Copy-Item -Path $osquery_config_template -Destination $osquery_destination -Force -ErrorAction Stop

Write-Host "writing telegraf config..."
$telegraf_conf = Get-Content $telegraf_config_template
$telegraf_conf = $telegraf_conf -replace "<<customer_id>>", $customer_id -replace "<<ingest_token>>", $ingest_token -replace "<<observe_host_name>>" , $observe_host_name
Set-Content -Path $telegraf_destination\$telegraf_version\telegraf.conf -Value $telegraf_conf -ErrorAction Stop

Write-Host "writing fluent-bit config..."
$fluentbit_conf = Get-Content $fluentbit_config_template
$fluentbit_conf = $fluentbit_conf -replace "<<customer_id>>", $customer_id -replace "<<ingest_token>>", $ingest_token -replace "<<observe_host_name>>" , $observe_host_name
Set-Content -Path $fluentbit_destination\conf\fluent-bit.conf -Value $fluentbit_conf -ErrorAction Stop

# ######## spin up services
# restart to load the new config
if(-not (Get-Service osqueryd -ErrorAction SilentlyContinue).Status -eq "Running"){
  Write-Host "starting osqueryd service..."
    Start-Service osqueryd -ErrorAction Stop
}else{
    Write-Host "osqueryd service found, restarting..."
    Stop-Service osqueryd -ErrorAction Stop
    Start-service osqueryd -ErrorAction Stop
}

if(-not (Get-Service telegraf -ErrorAction SilentlyContinue).Status -eq "Running"){
    Write-Host "creating telegraf service..."
    Start-Process $telegraf_destination\$telegraf_version\telegraf.exe -ArgumentList "--service install --config `"C:\Program Files\InfluxData\telegraf\$telegraf_version\telegraf.conf`"" -Wait -ErrorAction Stop
    Write-Host "starting telegraf service..."
    Start-Service telegraf -ErrorAction Stop
}else{
    Write-Host "telegraf service found, restarting..."
    Restart-Service telegraf -ErrorAction Stop
}

if(-not (Get-Service fluent-bit -ErrorAction SilentlyContinue).Status -eq "Running"){
    Write-Host "fluent-bit service not running, creating and starting..."
    New-Service fluent-bit -BinaryPathName "`"$fluentbit_destination\bin\fluent-bit.exe`" -c `"$fluentbit_destination\conf\fluent-bit.conf`"" -StartupType Automatic -ErrorAction Stop
    Start-Service fluent-bit -ErrorAction Stop
} else{
    Write-Host "fluent-bit serve found, restarting"
    Restart-Service fluent-bit -ErrorAction Stop
}
 
 
