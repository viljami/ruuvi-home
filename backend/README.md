# Ruuvi Data on Raspberry Pi

Collect Ruuvi Tag data send by Ruuvi Gateway to InfluxDB on Raspberry Pi.
Dashboard is InfluxDB's UI.

In between from (mosquitto) mqtt to InfluxDB is a Rust program that decodes the Ruuvi Tag data and sends it to InfluxDB.

Dependencies

* Install [InfluxDB](https://docs.influxdata.com/influxdb/v2/install/?t=Linux)
    * Configure at /etc/default/influxdb2 (default settings ok)
    * Service starts at localhost port 8087

```bash
# After installing
sudo service influxdb start
# Verify
sudo service influxdb status
```
