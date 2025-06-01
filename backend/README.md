# Ruuvi Data on Raspberry Pi

Collect Ruuvi Tag data send by Ruuvi Gateway to TimescaleDB on Raspberry Pi.

In between from (mosquitto) mqtt to TimescaleDB is a Rust program that decodes the Ruuvi Tag data and sends it to TimescaleDB.
