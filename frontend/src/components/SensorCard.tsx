import React from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Card,
  CardContent,
  Typography,
  Box,
  Chip,
  Grid,
  IconButton,
  Tooltip,
  CircularProgress,
  Alert,
  Button,
} from '@mui/material';
import {
  Thermostat,
  Water,
  Speed,
  Battery90,
  Battery60,
  Battery30,
  BatteryAlert,
  SignalWifi4Bar,
  SignalWifiOff,
  Refresh,
  MoreHoriz,
  Error as ErrorIcon,
  WifiOff,
} from '@mui/icons-material';
import { SensorReading, dataHelpers } from '../services/api';

interface SensorCardProps {
  sensor?: SensorReading;
  isLoading?: boolean;
  error?: any;
  onRefresh?: () => void;
  compact?: boolean;
}

const SensorCard: React.FC<SensorCardProps> = ({
  sensor,
  isLoading = false,
  error,
  onRefresh,
  compact = false,
}) => {
  const navigate = useNavigate();

  const handleCardClick = () => {
    if (sensor) {
      navigate(`/sensor/${encodeURIComponent(sensor.sensor_mac)}`);
    }
  };

  const handleRefreshClick = (event: React.MouseEvent) => {
    event.stopPropagation();
    onRefresh?.();
  };

  // Handle error state
  if (error && !sensor) {
    const isNetworkError = error?.status === 0 || error?.message?.includes('network') || error?.message?.includes('fetch');

    return (
      <Card
        sx={{
          height: compact ? 'auto' : 280,
          display: 'flex',
          flexDirection: 'column',
          border: '1px solid',
          borderColor: 'error.light',
        }}
      >
        <CardContent sx={{ flexGrow: 1, p: compact ? 2 : 3, display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
          <Box display="flex" flexDirection="column" alignItems="center" textAlign="center">
            {isNetworkError ? (
              <WifiOff color="error" sx={{ fontSize: 40, mb: 1 }} />
            ) : (
              <ErrorIcon color="error" sx={{ fontSize: 40, mb: 1 }} />
            )}
            <Typography variant="h6" color="error" gutterBottom>
              {isNetworkError ? 'Connection Error' : 'Sensor Error'}
            </Typography>
            <Typography variant="body2" color="textSecondary" sx={{ mb: 2 }}>
              {isNetworkError
                ? 'Unable to connect to sensor'
                : error?.message || 'Failed to load sensor data'
              }
            </Typography>
            {onRefresh && (
              <Button
                variant="outlined"
                size="small"
                startIcon={<Refresh />}
                onClick={handleRefreshClick}
                color="error"
              >
                Retry
              </Button>
            )}
          </Box>
        </CardContent>
      </Card>
    );
  }

  // Handle loading state without sensor data
  if (isLoading && !sensor) {
    return (
      <Card
        sx={{
          height: compact ? 'auto' : 280,
          display: 'flex',
          flexDirection: 'column',
        }}
      >
        <CardContent sx={{ flexGrow: 1, p: compact ? 2 : 3, display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
          <Box display="flex" flexDirection="column" alignItems="center" textAlign="center">
            <CircularProgress size={40} sx={{ mb: 2 }} />
            <Typography variant="body2" color="textSecondary">
              Loading sensor data...
            </Typography>
          </Box>
        </CardContent>
      </Card>
    );
  }

  // Handle case where no sensor data and no error (shouldn't happen but defensive)
  if (!sensor) {
    return (
      <Card
        sx={{
          height: compact ? 'auto' : 280,
          display: 'flex',
          flexDirection: 'column',
          opacity: 0.6,
        }}
      >
        <CardContent sx={{ flexGrow: 1, p: compact ? 2 : 3, display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
          <Box display="flex" flexDirection="column" alignItems="center" textAlign="center">
            <Typography variant="body2" color="textSecondary">
              No sensor data available
            </Typography>
            {onRefresh && (
              <Button
                variant="text"
                size="small"
                startIcon={<Refresh />}
                onClick={handleRefreshClick}
                sx={{ mt: 1 }}
              >
                Refresh
              </Button>
            )}
          </Box>
        </CardContent>
      </Card>
    );
  }

  const sensorStatus = dataHelpers.getSensorStatus(sensor.timestamp);
  const isOnline = sensorStatus === 'online';
  const lastSeen = dataHelpers.formatRelativeTime(sensor.timestamp);

  const getBatteryIcon = (battery: number) => {
    if (battery > 2800) return <Battery90 />;
    if (battery > 2600) return <Battery60 />;
    if (battery > 2400) return <Battery30 />;
    return <BatteryAlert />;
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'online':
        return 'success';
      case 'warning':
        return 'warning';
      case 'offline':
        return 'error';
      default:
        return 'default';
    }
  };

  return (
    <Card
      className={`sensor-card fade-in ${isLoading ? 'loading' : ''}`}
      onClick={handleCardClick}
      sx={{
        position: 'relative',
        cursor: 'pointer',
        height: compact ? 'auto' : 280,
        display: 'flex',
        flexDirection: 'column',
        border: error ? '1px solid' : undefined,
        borderColor: error ? 'warning.light' : undefined,
      }}
    >
      {isLoading && (
        <Box className="loading-overlay">
          <CircularProgress size={24} />
        </Box>
      )}

      {error && (
        <Alert
          severity="warning"
          sx={{ m: 1, mb: 0 }}
          action={
            onRefresh && (
              <IconButton size="small" onClick={handleRefreshClick}>
                <Refresh fontSize="small" />
              </IconButton>
            )
          }
        >
          <Typography variant="caption">
            {error?.message?.includes('network') ? 'Connection issue' : 'Data may be stale'}
          </Typography>
        </Alert>
      )}

      <CardContent sx={{ flexGrow: 1, p: compact ? 2 : 3 }}>
        {/* Header */}
        <Box display="flex" justifyContent="space-between" alignItems="flex-start" mb={2}>
          <Box>
            <Typography
              variant="h6"
              component="h2"
              sx={{
                fontSize: compact ? '1rem' : '1.1rem',
                fontWeight: 600,
                mb: 0.5,
              }}
            >
              {dataHelpers.formatMacAddress(sensor.sensor_mac)}
            </Typography>
            <Box display="flex" alignItems="center" gap={1}>
              <Chip
                label={sensorStatus.toUpperCase()}
                color={getStatusColor(sensorStatus) as any}
                size="small"
                icon={isOnline ? <SignalWifi4Bar /> : <SignalWifiOff />}
              />
              <Typography variant="caption" color="textSecondary">
                {lastSeen}
              </Typography>
            </Box>
          </Box>
          {onRefresh && (
            <IconButton
              size="small"
              onClick={handleRefreshClick}
              sx={{ opacity: 0.7, '&:hover': { opacity: 1 } }}
            >
              <Refresh fontSize="small" />
            </IconButton>
          )}
        </Box>

        {/* Metrics Grid */}
        <Grid container spacing={compact ? 1 : 2}>
          {/* Temperature */}
          <Grid item xs={6}>
            <Box display="flex" alignItems="center" gap={1}>
              <Thermostat
                className={dataHelpers.getTemperatureClass(sensor.temperature)}
                fontSize="small"
              />
              <Box>
                <Typography
                  variant={compact ? 'body2' : 'h6'}
                  className={`metric-value ${dataHelpers.getTemperatureClass(sensor.temperature)}`}
                >
                  {sensor.temperature.toFixed(1)}°C
                </Typography>
                <Typography variant="caption" color="textSecondary">
                  Temperature
                </Typography>
              </Box>
            </Box>
          </Grid>

          {/* Humidity */}
          <Grid item xs={6}>
            <Box display="flex" alignItems="center" gap={1}>
              <Water
                className={dataHelpers.getHumidityClass(sensor.humidity)}
                fontSize="small"
              />
              <Box>
                <Typography
                  variant={compact ? 'body2' : 'h6'}
                  className={`metric-value ${dataHelpers.getHumidityClass(sensor.humidity)}`}
                >
                  {sensor.humidity.toFixed(1)}%
                </Typography>
                <Typography variant="caption" color="textSecondary">
                  Humidity
                </Typography>
              </Box>
            </Box>
          </Grid>

          {!compact && (
            <>
              {/* Pressure */}
              <Grid item xs={6}>
                <Box display="flex" alignItems="center" gap={1}>
                  <Speed fontSize="small" />
                  <Box>
                    <Typography variant="body1" className="metric-value">
                      {sensor.pressure.toFixed(0)}
                    </Typography>
                    <Typography variant="caption" color="textSecondary">
                      hPa
                    </Typography>
                  </Box>
                </Box>
              </Grid>

              {/* Battery */}
              <Grid item xs={6}>
                <Box display="flex" alignItems="center" gap={1}>
                  <Box className={dataHelpers.getBatteryClass(sensor.battery)}>
                    {getBatteryIcon(sensor.battery)}
                  </Box>
                  <Box>
                    <Typography
                      variant="body1"
                      className={`metric-value ${dataHelpers.getBatteryClass(sensor.battery)}`}
                    >
                      {(sensor.battery / 1000).toFixed(2)}V
                    </Typography>
                    <Typography variant="caption" color="textSecondary">
                      Battery
                    </Typography>
                  </Box>
                </Box>
              </Grid>
            </>
          )}
        </Grid>

        {/* Additional Info (only for full cards) */}
        {!compact && (
          <Box mt={2} pt={2} borderTop="1px solid #eee">
            <Box display="flex" justifyContent="space-between" alignItems="center">
              <Typography variant="caption" color="textSecondary">
                RSSI: {sensor.rssi} dBm
              </Typography>
              <Typography variant="caption" color="textSecondary">
                Movement: {sensor.movement_counter}
              </Typography>
              <Tooltip title="View Details">
                <IconButton size="small" sx={{ opacity: 0.5 }}>
                  <MoreHoriz fontSize="small" />
                </IconButton>
              </Tooltip>
            </Box>
          </Box>
        )}
      </CardContent>
    </Card>
  );
};

export default SensorCard;
