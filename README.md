# HWlogs

## Description
Simple shell script to log CPU (_mpstats_ & _sensors_) and GPU (_nvidia-smi_) utilization and temperature into respective csv files. Also logs other device outputs from _sensor_. Logging is done periodically for every interval (30s default) and outputs are categorized based on dates.


## Install Dependencies
```
sudo apt install sysstat lm-sensors
# Recommend to install nvidia-smi using Ubuntu's Software & Updates
```


## Installation
```
cd ~
git clone https://github.com/luacghee/HWlogs.git
```


## Logging

### To run logger on a single run
```
chmod +x ~/HWlogs/hwlogs_run.sh
cd ~/HWlogs
./hwlogs_run.sh
# Outputs are in ~/HWlogs/logs_run
```

### To enable automatic logging and launch upon every system startup
```
chmod +x ~/HWlogs/hwlogs.sh
crontab -e
@reboot /home/user/HWLogs/hwlogs.sh
```


## Comments
* Tested on Ubuntu 22.04 with AMD k10 driver (Ryzen 9 CPU).
* To include plotting in the future.