To install the fluent-bit watchdog, run the command below. The script will do the following:

 - update fluent-bit config to export internal metrics to `localhost:2021`
 - update telegraf config to ship those metrics to Observe
 - creates a scheduled task to monitor fluent-bit
    - restart fluent-bit if `fluentbit_output_proc_records_total` stagnates for 3 minutes


1. To install, simply run:
   ```powershell
Invoke-Expression (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/observeinc/windows-host-configuration-scripts/main/fluent-bit-watchdog/intstall.ps1").Content
   ```

NOTE: This assumes you have installed the Observe agents located in the root of this repository.