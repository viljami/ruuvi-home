import React, { useState } from 'react';
import {
  Box,
  Typography,
  Grid,
  Chip,
  Button,
  IconButton,
  Tooltip,
  Card,
  CardContent,
  Switch,
  FormControlLabel,
} from '@mui/material';
import {
  Refresh,
  Dashboard as DashboardIcon,
  Sensors,
  CloudDone,
  CloudOff,
} from '@mui/icons-material';
import { useDashboardData } from '../services/hooks';
import SensorCard from '../components/SensorCard';
import LoadingSpinner from '../components/LoadingSpinner';
import ErrorMessage from '../components/ErrorMessage';
import { ErrorBoundary } from '../components/ErrorBoundary';

const Dashboard: React.FC = () => {
  const [compactView, setCompactView] = useState(false);
  const {
    sensors,
    health,
    isLoading,
    error,
    refetchAll,
    sensorCount,
    onlineSensors,
  } = useDashboardData();

  const handleRefresh = () => {
    refetchAll();
  };

  const handleSensorRefresh = (sensorMac: string) => {
    // Individual sensor refresh will be handled by React Query automatically
    sensors.refetch();
  };

  if (isLoading) {
    return (
      <LoadingSpinner
        text="Loading sensor data..."
        size={48}
        fullHeight={false}
      />
    );
  }

  if (error && !sensors.data) {
    return (
      <Box sx={{ maxWidth: 600, mx: 'auto', mt: 4 }}>
        <ErrorMessage
          error={error}
          title="Failed to Load Dashboard"
          onRetry={handleRefresh}
          fullWidth
        />
      </Box>
    );
  }

  const sensorData = sensors.data || [];
  const isHealthy = health.data === 'OK';

  return (
    <Box>
      {/* Dashboard Header */}
      <Box
        display="flex"
        justifyContent="space-between"
        alignItems="center"
        mb={4}
        flexWrap="wrap"
        gap={2}
      >
        <Box>
          <Typography variant="h4" component="h1" gutterBottom>
            <DashboardIcon sx={{ mr: 1, verticalAlign: 'middle' }} />
            Sensor Dashboard
          </Typography>
          <Typography variant="body1" color="textSecondary">
            Monitor your Ruuvi sensors in real-time
          </Typography>
        </Box>

        <Box display="flex" alignItems="center" gap={2}>
          <FormControlLabel
            control={
              <Switch
                checked={compactView}
                onChange={(e) => setCompactView(e.target.checked)}
                size="small"
              />
            }
            label="Compact"
          />
          <Tooltip title="Refresh All Data">
            <IconButton
              onClick={handleRefresh}
              disabled={isLoading}
              color="primary"
            >
              <Refresh />
            </IconButton>
          </Tooltip>
        </Box>
      </Box>

      {/* System Status */}
      <Grid container spacing={3} sx={{ mb: 4 }}>
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Box display="flex" alignItems="center" gap={2}>
                {isHealthy ? (
                  <CloudDone color="success" />
                ) : (
                  <CloudOff color="error" />
                )}
                <Box>
                  <Typography variant="h6" component="div">
                    System Status
                  </Typography>
                  <Chip
                    label={isHealthy ? 'Healthy' : 'Error'}
                    color={isHealthy ? 'success' : 'error'}
                    size="small"
                  />
                </Box>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Box display="flex" alignItems="center" gap={2}>
                <Sensors color="primary" />
                <Box>
                  <Typography variant="h6" component="div">
                    Total Sensors
                  </Typography>
                  <Typography variant="h4" color="primary">
                    {sensorCount}
                  </Typography>
                </Box>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Box display="flex" alignItems="center" gap={2}>
                <Box
                  sx={{
                    width: 12,
                    height: 12,
                    borderRadius: '50%',
                    bgcolor: 'success.main',
                  }}
                />
                <Box>
                  <Typography variant="h6" component="div">
                    Online Sensors
                  </Typography>
                  <Typography variant="h4" color="success.main">
                    {onlineSensors}
                  </Typography>
                </Box>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Box display="flex" alignItems="center" gap={2}>
                <Box
                  sx={{
                    width: 12,
                    height: 12,
                    borderRadius: '50%',
                    bgcolor: 'error.main',
                  }}
                />
                <Box>
                  <Typography variant="h6" component="div">
                    Offline Sensors
                  </Typography>
                  <Typography variant="h4" color="error.main">
                    {sensorCount - onlineSensors}
                  </Typography>
                </Box>
              </Box>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Sensors Grid */}
      {sensorData.length === 0 ? (
        <Box textAlign="center" py={8}>
          <Sensors sx={{ fontSize: 64, color: 'text.secondary', mb: 2 }} />
          <Typography variant="h6" color="textSecondary" gutterBottom>
            No Sensors Found
          </Typography>
          <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
            Make sure your MQTT simulator is running and sensors are sending data.
          </Typography>
          <Button
            variant="outlined"
            startIcon={<Refresh />}
            onClick={handleRefresh}
          >
            Refresh
          </Button>
        </Box>
      ) : (
        <>
          <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
            <Typography variant="h6" component="h2">
              Sensor Readings
            </Typography>
            <Typography variant="body2" color="textSecondary">
              Auto-refreshes every 30 seconds
            </Typography>
          </Box>

          <Grid container spacing={3}>
            {sensorData.map((sensor) => (
              <Grid
                item
                xs={12}
                sm={compactView ? 12 : 6}
                md={compactView ? 6 : 4}
                lg={compactView ? 4 : 3}
                key={sensor.sensor_mac}
              >
                <ErrorBoundary
                  fallback={
                    <SensorCard
                      error={{ message: 'Component error occurred' }}
                      onRefresh={() => handleSensorRefresh(sensor.sensor_mac)}
                      compact={compactView}
                    />
                  }
                >
                  <SensorCard
                    sensor={sensor}
                    isLoading={sensors.isFetching}
                    error={error ? { message: 'Data may be stale' } : undefined}
                    onRefresh={() => handleSensorRefresh(sensor.sensor_mac)}
                    compact={compactView}
                  />
                </ErrorBoundary>
              </Grid>
            ))}

            {/* Show loading cards if we're loading and have no data */}
            {isLoading && sensorData.length === 0 &&
              Array.from({ length: 3 }).map((_, index) => (
                <Grid
                  item
                  xs={12}
                  sm={compactView ? 12 : 6}
                  md={compactView ? 6 : 4}
                  lg={compactView ? 4 : 3}
                  key={`loading-${index}`}
                >
                  <SensorCard
                    isLoading={true}
                    compact={compactView}
                  />
                </Grid>
              ))
            }
          </Grid>
        </>
      )}

      {/* Auto-refresh Indicator */}
      <Box
        position="fixed"
        bottom={24}
        right={24}
        sx={{
          bgcolor: 'background.paper',
          border: '1px solid',
          borderColor: 'divider',
          borderRadius: 2,
          px: 2,
          py: 1,
          boxShadow: 2,
        }}
      >
        <Box className="auto-refresh-indicator">
          <Box className={`refresh-dot ${!isLoading ? 'active' : ''}`} />
          <Typography variant="caption">
            {isLoading ? 'Updating...' : 'Live'}
          </Typography>
        </Box>
      </Box>
    </Box>
  );
};

export default Dashboard;
