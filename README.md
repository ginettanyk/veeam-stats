How to monitor a Veeam Environment using Powershell, Telegraf, InfluxDB and Grafana
===================

![alt tag](https://www.jorgedelacruz.es/wp-content/uploads/2017/02/27/veeam-grafana-004.png)

This project consists in a Powershell script to retrieve the Veeam Backup & Replication information about last jobs, etc, and save it into JSON which we send to InfluxDB using Telegraf, then in Grafana: a Dashboard is created to present all the information.

----------

### Getting started


* Download the veeam-stats.ps1 file and change the BRHost with your own fqdn or IP
* Run the veeam-stats.ps1 to check that you can retrieve the information properly
* Edit telegraf.conf to look up the powershell script and restart the telegraf service. 
* Make sure to have the correct, full path to the powershell script.
* In larger environments you may need to tune the interval and timeout and set them higher times 600s for example
```
 [[inputs.exec]]
  commands = ["powershell C:/veeam-stats.ps1"]
  name_override = "veeamstats"
  interval = "60s"
  timeout = "60s"
  data_format = "influx"
```
* Download the grafana_veeam_dashboard JSON file (should be with this project) and import it into Grafana
* Add a new data source that should be pointing to your influx database where telegraf is sending the results.
* Now go edit your Grafana JSON Dashboard and enjoy :)

----------

### Additional Information
* You can find the original code for PRTG here, thank you so much Markus Kraus: https://github.com/mycloudrevolution/Advanced-PRTG-Sensors/blob/master/Veeam/PRTG-VeeamBRStats.ps1
* Big thanks to Shawn, creating a awesome Reporting Script: http://blog.smasterson.com/2016/02/16/veeam-v9-my-veeam-report-v9-0-1/


* All original contributers can be reached through their respective websites. 
* Thanks to Markus and Shawn and others for making this possible!! 
Nick
# veeam-stats