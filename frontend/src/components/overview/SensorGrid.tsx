import React from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Grid,
  Card,
  CardContent,
  Typography,
  Box,
  Chip,
  IconButton,
  Tooltip,
  alpha,
} from '@mui/material';
import {
  Battery1Bar,
  Battery2Bar,
  Battery3Bar,
  BatteryFull,
  BatteryAlert,
  SignalWifi1Bar,
  SignalWifi2Bar,
  SignalWifi3Bar,
  SignalWifi4Bar,
  SignalWifiOff,
  Visibility,
  DeviceThermostat,
} from '@mui/icons-material';

interface SensorReading {
  sensor_mac: string;
  temperature: number;
  humidity: number;
  pressure: number;
  battery: number;
  rssi: number;
  timestamp: number;
}

interface SensorGridProps {
  sensors: SensorReading[];
  formatMacAddress?: (mac: string) => string;
  onSensorClick?: (sensorMac: string) => void;
  getBatteryStatus?: (battery: number) => string;
  className?: string;
}

const getBatteryIcon = (battery: number) => {
  if (battery < 2400) return <BatteryAlert color="error" />;
  if (battery < 2600) return <Battery1Bar sx={{ color: '#ff9800' }} />;
  if (battery < 2800) return <Battery2Bar sx={{ color: '#ffc107' }} />;
  if (battery < 3000) return <Battery3Bar sx={{ color: '#8bc34a' }} />;
  return <BatteryFull sx={{ color: '#4caf50' }} />;
};

const getSignalIcon = (rssi: number) => {
  if (rssi < -90) return <SignalWifiOff sx={{ color: '#f44336' }} />;
  if (rssi < -80) return <SignalWifi1Bar sx={{ color: '#ff9800' }} />;
  if (rssi < -70) return <SignalWifi2Bar sx={{ color: '#ffc107' }} />;
  if (rssi < -60) return <SignalWifi3Bar sx={{ color: '#8bc34a' }} />;
  return <SignalWifi4Bar sx={{ color: '#4caf50' }} />;
};

const getTemperatureColor = (temperature: number): string => {
  if (temperature < 10) return '#2196f3';
  if (temperature < 20) return '#00bcd4';
  if (temperature < 25) return '#4caf50';
  if (temperature < 30) return '#ff9800';
  return '#f44336';
};

export const SensorGrid: React.FC<SensorGridProps> = ({
  sensors,
  formatMacAddress = (mac) => mac.toUpperCase(),
  onSensorClick,
  getBatteryStatus = (battery) => battery < 2400 ? 'Critical' : battery < 2700 ? 'Low' : 'Good',
  className,
}) => {
  const navigate = useNavigate();

  const handleSensorClick = (sensorMac: string) => {
    if (onSensorClick) {
      onSensorClick(sensorMac);
    } else {
      navigate(`/sensor/${sensorMac}`);
    }
  };

  const getTimeSinceReading = (timestamp: number): string => {
    const now = Date.now();
    const diff = now - (timestamp * 1000);
    const minutes = Math.floor(diff / 60000);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);

    if (days > 0) return `${days}d ago`;
    if (hours > 0) return `${hours}h ago`;
    if (minutes > 0) return `${minutes}m ago`;
    return 'Just now';
  };

  const isOffline = (timestamp: number): boolean => {
    const now = Date.now();
    const diff = now - (timestamp * 1000);
    return diff > 10 * 60 * 1000; // 10 minutes
  };

  if (sensors.length === 0) {
    return (
      <Box
        className={className}
        sx={{
          textAlign: 'center',
          py: 4,
          color: 'rgba(255, 255, 255, 0.6)'
        }}
      >
        <DeviceThermostat sx={{ fontSize: 48, mb: 2, opacity: 0.5 }} />
        <Typography variant="h6" sx={{ mb: 1 }}>
          No Sensors Found
        </Typography>
        <Typography variant="body2">
          Connect your Ruuvi sensors to start monitoring.
        </Typography>
      </Box>
    );
  }

  return (
    <Grid container spacing={2} className={className}>
      {sensors.map((sensor) => {
        const offline = isOffline(sensor.timestamp);
        const temperatureColor = getTemperatureColor(sensor.temperature);

        return (
          <Grid item xs={12} sm={6} md={4} lg={3} key={sensor.sensor_mac}>
            <Card
              sx={{
                height: '100%',
                bgcolor: offline
                  ? 'rgba(26, 26, 26, 0.4)'
                  : 'rgba(26, 26, 26, 0.8)',
                backdropFilter: 'blur(20px)',
                border: offline
                  ? '1px solid rgba(244, 67, 54, 0.3)'
                  : '1px solid rgba(255, 255, 255, 0.1)',
                borderRadius: 3,
                transition: 'all 0.3s ease',
                cursor: 'pointer',
                opacity: offline ? 0.6 : 1,
                '&:hover': {
                  transform: 'translateY(-2px)',
                  boxShadow: '0 8px 32px rgba(0, 0, 0, 0.4)',
                  border: '1px solid rgba(144, 202, 249, 0.3)',
                },
              }}
              onClick={() => handleSensorClick(sensor.sensor_mac)}
            >
              <CardContent sx={{ p: 2 }}>
                <Box display="flex" justifyContent="space-between" alignItems="flex-start" mb={1}>
                  <Typography
                    variant="caption"
                    sx={{
                      color: offline ? '#f44336' : '#ffffff',
                      opacity: offline ? 1 : 0.7,
                      fontWeight: offline ? 500 : 400
                    }}
                  >
                    {formatMacAddress(sensor.sensor_mac)}
                  </Typography>

                  <Box display="flex" gap={0.5}>
                    <Tooltip title={`Battery: ${sensor.battery}mV (${getBatteryStatus(sensor.battery)})`}>
                      <Box>{getBatteryIcon(sensor.battery)}</Box>
                    </Tooltip>
                    <Tooltip title={`Signal: ${sensor.rssi}dBm`}>
                      <Box>{getSignalIcon(sensor.rssi)}</Box>
                    </Tooltip>
                  </Box>
                </Box>

                <Box display="flex" flexDirection="column" gap={1}>
                  <Box display="flex" justifyContent="space-between" alignItems="center">
                    <Typography
                      variant="h4"
                      sx={{
                        color: offline ? 'rgba(255, 255, 255, 0.4)' : temperatureColor,
                        fontWeight: 300,
                        lineHeight: 1
                      }}
                    >
                      {offline ? '--' : sensor.temperature.toFixed(1)}
                    </Typography>
                    <Typography
                      variant="caption"
                      sx={{
                        color: offline ? 'rgba(255, 255, 255, 0.4)' : temperatureColor,
                        alignSelf: 'flex-start',
                        mt: 0.5
                      }}
                    >
                      °C
                    </Typography>
                  </Box>

                  <Box display="flex" gap={1} flexWrap="wrap">
                    <Chip
                      label={offline ? '--% RH' : `${sensor.humidity.toFixed(1)}% RH`}
                      size="small"
                      variant="outlined"
                      sx={{
                        fontSize: '0.7rem',
                        height: 24,
                        color: offline ? 'rgba(255, 255, 255, 0.4)' : '#00bcd4',
                        borderColor: offline ? 'rgba(255, 255, 255, 0.2)' : '#00bcd4',
                        bgcolor: offline ? 'transparent' : alpha('#00bcd4', 0.1)
                      }}
                    />
                    <Chip
                      label={offline ? '-- hPa' : `${sensor.pressure.toFixed(0)} hPa`}
                      size="small"
                      variant="outlined"
                      sx={{
                        fontSize: '0.7rem',
                        height: 24,
                        color: offline ? 'rgba(255, 255, 255, 0.4)' : '#9c27b0',
                        borderColor: offline ? 'rgba(255, 255, 255, 0.2)' : '#9c27b0',
                        bgcolor: offline ? 'transparent' : alpha('#9c27b0', 0.1)
                      }}
                    />
                  </Box>

                  <Box display="flex" justifyContent="space-between" alignItems="center" mt={1}>
                    <Typography
                      variant="caption"
                      sx={{
                        color: offline ? '#f44336' : 'rgba(255, 255, 255, 0.5)',
                        fontSize: '0.7rem'
                      }}
                    >
                      {offline ? 'Offline' : getTimeSinceReading(sensor.timestamp)}
                    </Typography>

                    <Tooltip title="View Details">
                      <IconButton
                        size="small"
                        onClick={(e) => {
                          e.stopPropagation();
                          handleSensorClick(sensor.sensor_mac);
                        }}
                        sx={{
                          color: 'rgba(255, 255, 255, 0.6)',
                          '&:hover': {
                            color: '#90caf9',
                            bgcolor: 'rgba(144, 202, 249, 0.1)'
                          }
                        }}
                      >
                        <Visibility fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
        );
      })}
    </Grid>
  );
};

export default SensorGrid;
