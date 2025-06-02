import React, { useState, useMemo } from 'react';
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
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Alert,
} from '@mui/material';
import {
  Refresh,
  Dashboard as DashboardIcon,
  Sensors,
  CloudDone,
  CloudOff,
  TrendingUp,
} from '@mui/icons-material';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip as ChartTooltip,
  Legend,
  TimeScale,
} from 'chart.js';
import { Line } from 'react-chartjs-2';
import 'chartjs-adapter-date-fns';

import { useDashboardData, useAllSensorsHistory } from '../services/hooks';
import { dataHelpers } from '../services/api';
import LoadingSpinner from '../components/LoadingSpinner';
import { ErrorBoundary, InlineError, DataError } from '../components/ErrorBoundary';

// Register Chart.js components
ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  ChartTooltip,
  Legend,
  TimeScale
);

// Color palette for different sensors
const SENSOR_COLORS = [
  '#1f77b4', '#ff7f0e', '#2ca02c', '#d62728', '#9467bd',
  '#8c564b', '#e377c2', '#7f7f7f', '#bcbd22', '#17becf',
  '#aec7e8', '#ffbb78', '#98df8a', '#ff9896', '#c5b0d5',
];

const TIME_RANGES = [
  { value: '6h', label: '6 Hours', hours: 6 },
  { value: '24h', label: '24 Hours', hours: 24 },
  { value: '7d', label: '7 Days', hours: 24 * 7 },
  { value: '1m', label: '1 Month', hours: 24 * 30 },
];

const Dashboard: React.FC = () => {
  const [timeRange, setTimeRange] = useState('24h');
  const [showPressureChart, setShowPressureChart] = useState(false);
  const [visibleSensors, setVisibleSensors] = useState<Set<string>>(new Set());

  const {
    sensors,
    health,
    isLoading: dashboardLoading,
    error: dashboardError,
    refetchAll,
    sensorCount,
    onlineSensors,
    hasUsableData,
    dataQuality,
    hasPartialData,
  } = useDashboardData();

  const {
    data: allHistoryData,
    isLoading: historyLoading,
    error: historyError
  } = useAllSensorsHistory(timeRange);

  // Initialize visible sensors when sensor data loads
  React.useEffect(() => {
    if (sensors.data && visibleSensors.size === 0) {
      setVisibleSensors(new Set(sensors.data.map(s => s.sensor_mac)));
    }
  }, [sensors.data, visibleSensors.size]);

  const handleRefresh = () => {
    refetchAll();
  };

  const toggleSensorVisibility = (sensorMac: string) => {
    const newVisibleSensors = new Set(visibleSensors);
    if (newVisibleSensors.has(sensorMac)) {
      newVisibleSensors.delete(sensorMac);
    } else {
      newVisibleSensors.add(sensorMac);
    }
    setVisibleSensors(newVisibleSensors);
  };

  const toggleAllSensors = () => {
    if (sensors.data) {
      if (visibleSensors.size === sensors.data.length) {
        setVisibleSensors(new Set());
      } else {
        setVisibleSensors(new Set(sensors.data.map(s => s.sensor_mac)));
      }
    }
  };

  // Prepare main chart data
  const chartData = useMemo(() => {
    if (!allHistoryData || !sensors.data) return null;

    const datasets: any[] = [];
    let colorIndex = 0;

    sensors.data.forEach(sensor => {
      if (!visibleSensors.has(sensor.sensor_mac)) return;

      const sensorHistory = allHistoryData[sensor.sensor_mac] || [];
      const color = SENSOR_COLORS[colorIndex % SENSOR_COLORS.length];
      const sensorName = dataHelpers.formatMacAddress(sensor.sensor_mac);

      // Temperature dataset
      datasets.push({
        label: `${sensorName} Temperature`,
        data: sensorHistory.map(reading => ({
          x: new Date(reading.timestamp * 1000),
          y: reading.temperature,
        })),
        borderColor: color,
        backgroundColor: color + '20',
        yAxisID: 'y',
        pointRadius: 1,
        pointBorderWidth: 1,
        borderWidth: 2,
      });

      // Humidity dataset
      datasets.push({
        label: `${sensorName} Humidity`,
        data: sensorHistory.map(reading => ({
          x: new Date(reading.timestamp * 1000),
          y: reading.humidity,
        })),
        borderColor: color,
        backgroundColor: color + '20',
        borderDash: [5, 5],
        yAxisID: 'y1',
        pointRadius: 1,
        pointBorderWidth: 1,
        borderWidth: 2,
      });

      colorIndex++;
    });

    return { datasets };
  }, [allHistoryData, sensors.data, visibleSensors]);

  // Prepare pressure chart data
  const pressureChartData = useMemo(() => {
    if (!allHistoryData || !sensors.data || !showPressureChart) return null;

    const datasets: any[] = [];
    let colorIndex = 0;

    sensors.data.forEach(sensor => {
      if (!visibleSensors.has(sensor.sensor_mac)) return;

      const sensorHistory = allHistoryData[sensor.sensor_mac] || [];
      const color = SENSOR_COLORS[colorIndex % SENSOR_COLORS.length];
      const sensorName = dataHelpers.formatMacAddress(sensor.sensor_mac);

      datasets.push({
        label: `${sensorName} Pressure`,
        data: sensorHistory.map(reading => ({
          x: new Date(reading.timestamp * 1000),
          y: reading.pressure,
        })),
        borderColor: color,
        backgroundColor: color + '20',
        pointRadius: 1,
        pointBorderWidth: 1,
        borderWidth: 2,
      });

      colorIndex++;
    });

    return { datasets };
  }, [allHistoryData, sensors.data, visibleSensors, showPressureChart]);

  const mainChartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    interaction: {
      mode: 'index' as const,
      intersect: false,
    },
    plugins: {
      legend: {
        position: 'bottom' as const,
        labels: {
          padding: 20,
          font: {
            size: 12
          },
          filter: function(legendItem: any) {
            return legendItem.text.includes('Temperature');
          }
        }
      },
      title: {
        display: false,
      },
      tooltip: {
        backgroundColor: 'rgba(255, 255, 255, 0.95)',
        titleColor: '#000000',
        bodyColor: '#000000',
        borderColor: 'rgba(0, 0, 0, 0.1)',
        borderWidth: 1,
        callbacks: {
          title: function(context: any) {
            return new Date(context[0].parsed.x).toLocaleString();
          },
          label: function(context: any) {
            const sensor = context.dataset.label.split(' ')[0];
            const metric = context.dataset.label.includes('Temperature') ? 'Temperature' : 'Humidity';
            const unit = metric === 'Temperature' ? '°C' : '%';
            return `${sensor} ${metric}: ${context.parsed.y.toFixed(1)}${unit}`;
          }
        }
      }
    },
    scales: {
      x: {
        type: 'time' as const,
        time: {
          displayFormats: {
            minute: 'HH:mm',
            hour: 'HH:mm',
            day: 'MMM dd',
            month: 'MMM',
          },
        },
        grid: {
          display: true,
        },
      },
      y: {
        type: 'linear' as const,
        display: true,
        position: 'left' as const,
        title: {
          display: true,
          text: 'Temperature (°C)',
        },
        grid: {
          display: true,
        },
      },
      y1: {
        type: 'linear' as const,
        display: true,
        position: 'right' as const,
        title: {
          display: true,
          text: 'Humidity (%)',
        },
        grid: {
          drawOnChartArea: false,
        },
      },
    },
  };

  const pressureChartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    interaction: {
      mode: 'index' as const,
      intersect: false,
    },
    plugins: {
      legend: {
        position: 'bottom' as const,
        labels: {
          padding: 20,
          font: {
            size: 12
          }
        }
      },
      title: {
        display: true,
        text: 'Atmospheric Pressure',
      },
      tooltip: {
        backgroundColor: 'rgba(255, 255, 255, 0.95)',
        titleColor: '#000000',
        bodyColor: '#000000',
        borderColor: 'rgba(0, 0, 0, 0.1)',
        borderWidth: 1,
        callbacks: {
          title: function(context: any) {
            return new Date(context[0].parsed.x).toLocaleString();
          },
          label: function(context: any) {
            const sensor = context.dataset.label.split(' ')[0];
            return `${sensor} Pressure: ${context.parsed.y.toFixed(1)} hPa`;
          }
        }
      }
    },
    scales: {
      x: {
        type: 'time' as const,
        time: {
          displayFormats: {
            minute: 'HH:mm',
            hour: 'HH:mm',
            day: 'MMM dd',
            month: 'MMM',
          },
        },
      },
      y: {
        title: {
          display: true,
          text: 'Pressure (hPa)',
        },
      },
    },
  };

  if (dashboardLoading && !sensors.data) {
    return (
      <LoadingSpinner
        text="Loading dashboard data..."
        size={48}
        fullHeight={false}
      />
    );
  }

  const sensorData = sensors.data || [];
  const isHealthy = health.data === 'OK';

  return (
    <Box>
      {/* Dashboard Header */}
      <ErrorBoundary
        fallback={
          <Box mb={4}>
            <Typography variant="h4" component="h1">
              <DashboardIcon sx={{ mr: 1, verticalAlign: 'middle' }} />
              Sensor Dashboard
            </Typography>
          </Box>
        }
      >
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
              Monitor all sensors with combined temperature and humidity tracking
            </Typography>
          </Box>

          <Box display="flex" alignItems="center" gap={2}>
            <Tooltip title="Refresh All Data">
              <IconButton
                onClick={handleRefresh}
                disabled={dashboardLoading}
                color="primary"
              >
                <Refresh />
              </IconButton>
            </Tooltip>
          </Box>
        </Box>
      </ErrorBoundary>

      {/* System Status */}
      <ErrorBoundary
        fallback={
          <Alert severity="warning" sx={{ mb: 4 }}>
            System status unavailable
          </Alert>
        }
      >
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
      </ErrorBoundary>

      {/* Chart Controls */}
      <ErrorBoundary
        fallback={
          <Box mb={3}>
            <Alert severity="warning">Chart controls unavailable</Alert>
          </Box>
        }
      >
        <Box display="flex" flexWrap="wrap" gap={2} alignItems="center" mb={3}>
          <FormControl size="small" sx={{ minWidth: 120 }}>
            <InputLabel>Time Range</InputLabel>
            <Select
              value={timeRange}
              label="Time Range"
              onChange={(e) => setTimeRange(e.target.value)}
            >
              {TIME_RANGES.map(range => (
                <MenuItem key={range.value} value={range.value}>
                  {range.label}
                </MenuItem>
              ))}
            </Select>
          </FormControl>

          <FormControlLabel
            control={
              <Switch
                checked={showPressureChart}
                onChange={(e) => setShowPressureChart(e.target.checked)}
                size="small"
              />
            }
            label="Show Pressure Chart"
          />

          {sensors.data && sensors.data.length > 0 && (
            <>
              <Button
                variant="outlined"
                size="small"
                onClick={toggleAllSensors}
              >
                {visibleSensors.size === sensors.data.length ? 'Hide All' : 'Show All'}
              </Button>

              <Box display="flex" flexWrap="wrap" gap={1}>
                {sensors.data.map(sensor => (
                  <Chip
                    key={sensor.sensor_mac}
                    label={dataHelpers.formatMacAddress(sensor.sensor_mac)}
                    onClick={() => toggleSensorVisibility(sensor.sensor_mac)}
                    variant={visibleSensors.has(sensor.sensor_mac) ? 'filled' : 'outlined'}
                    size="small"
                    color={visibleSensors.has(sensor.sensor_mac) ? 'primary' : 'default'}
                  />
                ))}
              </Box>
            </>
          )}
        </Box>
      </ErrorBoundary>

      {/* Error Display for Data Issues */}
      {(dashboardError || historyError || hasPartialData) && (
        <ErrorBoundary>
          <Alert
            severity={dashboardError && !hasUsableData ? "error" : "warning"}
            sx={{ mb: 3 }}
            action={
              <Button color="inherit" size="small" onClick={handleRefresh}>
                Retry
              </Button>
            }
          >
            {dashboardError && !hasUsableData
              ? `Dashboard error: ${dashboardError.message}`
              : hasPartialData && dataQuality === 'partial'
              ? `Some sensors failed to load - showing ${sensorData.length} available sensors`
              : historyError
              ? `Chart data error: ${historyError.message}`
              : 'Data quality issue detected'
            }
          </Alert>
        </ErrorBoundary>
      )}

      {/* Main Temperature & Humidity Chart */}
      <ErrorBoundary
        fallback={
          <Card sx={{ mb: 3 }}>
            <CardContent>
              <Box display="flex" alignItems="center" justifyContent="center" height={400}>
                <InlineError
                  error="Chart component failed to load"
                  title="Chart Error"
                  onRetry={handleRefresh}
                  severity="error"
                />
              </Box>
            </CardContent>
          </Card>
        }
      >
        <Card sx={{ mb: 3 }}>
          <CardContent>
            <Box display="flex" alignItems="center" gap={1} mb={2}>
              <TrendingUp />
              <Typography variant="h6">
                Temperature & Humidity Overview
              </Typography>
            </Box>

            <Box height={500}>
              {historyLoading ? (
                <Box display="flex" alignItems="center" justifyContent="center" height="100%">
                  <LoadingSpinner text="Loading chart data..." size={32} fullHeight={false} />
                </Box>
              ) : chartData && chartData.datasets.length > 0 ? (
                <Line data={chartData} options={mainChartOptions} />
              ) : (
                <Box display="flex" alignItems="center" justifyContent="center" height="100%">
                  <DataError
                    message={!hasUsableData
                      ? "No sensors available"
                      : visibleSensors.size === 0
                      ? "No sensors selected - use the controls above to show sensors"
                      : "No data available for selected sensors and time range"
                    }
                    onRetry={handleRefresh}
                    compact={false}
                  />
                </Box>
              )}
            </Box>
          </CardContent>
        </Card>
      </ErrorBoundary>

      {/* Pressure Chart (Optional) */}
      {showPressureChart && (
        <ErrorBoundary
          fallback={
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center" justifyContent="center" height={400}>
                  <InlineError
                    error="Pressure chart failed to load"
                    title="Chart Error"
                    onRetry={handleRefresh}
                    severity="error"
                  />
                </Box>
              </CardContent>
            </Card>
          }
        >
          <Card>
            <CardContent>
              <Box height={400}>
                {historyLoading ? (
                  <Box display="flex" alignItems="center" justifyContent="center" height="100%">
                    <LoadingSpinner text="Loading pressure data..." size={32} fullHeight={false} />
                  </Box>
                ) : pressureChartData && pressureChartData.datasets.length > 0 ? (
                  <Line data={pressureChartData} options={pressureChartOptions} />
                ) : (
                  <Box display="flex" alignItems="center" justifyContent="center" height="100%">
                    <DataError
                      message="No pressure data available for selected sensors"
                      onRetry={handleRefresh}
                      compact={false}
                    />
                  </Box>
                )}
              </Box>
            </CardContent>
          </Card>
        </ErrorBoundary>
      )}

      {/* No Sensors State */}
      {!hasUsableData && !dashboardLoading && (
        <ErrorBoundary>
          <Box textAlign="center" py={8}>
            <Sensors sx={{ fontSize: 64, color: 'text.secondary', mb: 2 }} />
            <Typography variant="h6" color="textSecondary" gutterBottom>
              {dashboardError ? 'Unable to Load Sensors' : 'No Sensors Found'}
            </Typography>
            <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
              {dashboardError
                ? 'Check your connection and make sure the API server is running.'
                : 'Make sure your MQTT simulator is running and sensors are sending data.'
              }
            </Typography>
            <Button
              variant="outlined"
              startIcon={<Refresh />}
              onClick={handleRefresh}
            >
              Refresh
            </Button>
          </Box>
        </ErrorBoundary>
      )}

      {/* Auto-refresh Indicator */}
      <ErrorBoundary>
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
            <Box className={`refresh-dot ${!dashboardLoading ? 'active' : ''}`} />
            <Typography variant="caption">
              {dashboardLoading ? 'Updating...' : 'Live'}
            </Typography>
          </Box>
        </Box>
      </ErrorBoundary>
    </Box>
  );
};

export default Dashboard;
