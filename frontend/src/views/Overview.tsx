import React, { useState, useMemo, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Box,
  Typography,
  Card,
  CardContent,
  IconButton,
  Tooltip,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  FormControlLabel,
  Alert,
  Switch,
  Drawer,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  AppBar,
  Toolbar,
  alpha,
} from '@mui/material';
import {
  Refresh,
  BatteryAlert,
  SignalWifiStatusbarConnectedNoInternet4,
  TrendingUp,
  Menu as MenuIcon,
  Dashboard as DashboardIcon,
  Sensors,
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
import ErrorMessage from '../components/ErrorMessage';
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
  { value: '6m', label: '6 Months', hours: 24 * 30 * 6 },
  { value: '1y', label: '1 Year', hours: 24 * 365 },
];

const Overview: React.FC = () => {
  const navigate = useNavigate();
  const [timeRange, setTimeRange] = useState('24h');
  const [showPressureChart, setShowPressureChart] = useState(false);
  const [visibleSensors, setVisibleSensors] = useState<Set<string>>(new Set());
  const [drawerOpen, setDrawerOpen] = useState(false);

  const {
    sensors,
    isLoading: dashboardLoading,
    error: dashboardError,
    refetchAll,
  } = useDashboardData();

  const { data: allHistoryData, isLoading: historyLoading, error: historyError } = useAllSensorsHistory(timeRange);

  // Initialize visible sensors when sensor data loads
  React.useEffect(() => {
    if (sensors.data && visibleSensors.size === 0) {
      setVisibleSensors(new Set(sensors.data.map(s => s.sensor_mac)));
    }
  }, [sensors.data, visibleSensors.size]);

  const handleRefresh = useCallback(() => {
    refetchAll();
  }, [refetchAll]);



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
        pointRadius: 2,
        pointBorderWidth: 1,
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
        pointRadius: 2,
        pointBorderWidth: 1,
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
          color: '#ffffff',
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
        backgroundColor: 'rgba(0, 0, 0, 0.9)',
        titleColor: '#ffffff',
        bodyColor: '#ffffff',
        borderColor: 'rgba(255, 255, 255, 0.2)',
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
        ticks: {
          color: '#ffffff',
          font: {
            size: 11
          }
        },
        grid: {
          color: 'rgba(255, 255, 255, 0.1)',
        },
      },
      y: {
        type: 'linear' as const,
        display: true,
        position: 'left' as const,
        title: {
          display: true,
          text: 'Temperature (°C)',
          color: '#ffffff',
          font: {
            size: 12
          }
        },
        ticks: {
          color: '#ffffff',
          font: {
            size: 11
          }
        },
        grid: {
          color: 'rgba(255, 255, 255, 0.1)',
        },
      },
      y1: {
        type: 'linear' as const,
        display: true,
        position: 'right' as const,
        title: {
          display: true,
          text: 'Humidity (%)',
          color: '#ffffff',
          font: {
            size: 12
          }
        },
        ticks: {
          color: '#ffffff',
          font: {
            size: 11
          }
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
        position: 'top' as const,
      },
      title: {
        display: true,
        text: 'Atmospheric Pressure Overview',
      },
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
        text="Loading overview data..."
        size={48}
        fullHeight={false}
      />
    );
  }

  if (dashboardError && !sensors.data) {
    return (
      <Box sx={{ maxWidth: 600, mx: 'auto', mt: 4 }}>
        <ErrorMessage
          error={dashboardError}
          title="Failed to Load Overview Data"
          onRetry={handleRefresh}
          fullWidth
        />
      </Box>
    );
  }

  const sensorData = sensors.data || [];

  // Calculate warning sensors
  const lowBatterySensors = sensorData.filter(s => s.battery < 2400);
  const lowSignalSensors = sensorData.filter(s => s.rssi < -80);

  return (
    <Box 
      sx={{ 
        minHeight: '100vh',
        bgcolor: '#0a0a0a',
        color: '#ffffff',
        position: 'relative'
      }}
    >
      {/* Ambient Header Bar */}
      <AppBar 
        position="static" 
        elevation={0}
        sx={{ 
          bgcolor: 'transparent',
          borderBottom: '1px solid rgba(255,255,255,0.05)'
        }}
      >
        <Toolbar sx={{ justifyContent: 'space-between' }}>
          <Box display="flex" alignItems="center">
            <IconButton
              edge="start"
              color="inherit"
              onClick={() => setDrawerOpen(true)}
              sx={{ 
                mr: 2,
                opacity: 0.6,
                '&:hover': { opacity: 1 }
              }}
            >
              <MenuIcon />
            </IconButton>
            <Typography 
              variant="h6" 
              component="h1" 
              sx={{ 
                opacity: 0.4,
                fontWeight: 300,
                fontSize: '1rem',
                '&:hover': { opacity: 0.7 }
              }}
            >
              Ruuvi Home
            </Typography>
          </Box>
          
          <Box display="flex" alignItems="center" gap={1}>
            <Tooltip title="Refresh Data">
              <IconButton
                onClick={handleRefresh}
                disabled={dashboardLoading}
                color="inherit"
                size="small"
                sx={{ 
                  opacity: 0.6,
                  '&:hover': { opacity: 1 }
                }}
              >
                <Refresh fontSize="small" />
              </IconButton>
            </Tooltip>
          </Box>
        </Toolbar>
      </AppBar>

      {/* Navigation Drawer */}
      <Drawer
        anchor="left"
        open={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        PaperProps={{
          sx: {
            bgcolor: '#1a1a1a',
            color: '#ffffff',
            width: 250
          }
        }}
      >
        <List>
          <ListItem button onClick={() => { navigate('/'); setDrawerOpen(false); }}>
            <ListItemIcon sx={{ color: '#ffffff' }}>
              <TrendingUp />
            </ListItemIcon>
            <ListItemText primary="Overview" />
          </ListItem>
          <ListItem button onClick={() => { navigate('/dashboard'); setDrawerOpen(false); }}>
            <ListItemIcon sx={{ color: '#ffffff' }}>
              <DashboardIcon />
            </ListItemIcon>
            <ListItemText primary="Dashboard" />
          </ListItem>
          <ListItem button onClick={() => setDrawerOpen(false)}>
            <ListItemIcon sx={{ color: '#ffffff' }}>
              <Sensors />
            </ListItemIcon>
            <ListItemText primary="Sensors" />
          </ListItem>
        </List>
      </Drawer>

      {/* Ambient Warning Indicators */}
      {(lowBatterySensors.length > 0 || lowSignalSensors.length > 0 || dashboardError || historyError) && (
        <Box sx={{ 
          position: 'fixed', 
          top: 80, 
          right: 16, 
          zIndex: 1000,
          maxWidth: 300
        }}>
          {(dashboardError || historyError) && (
            <Alert 
              severity="error" 
              variant="filled"
              sx={{ 
                mb: 1,
                bgcolor: alpha('#d32f2f', 0.8),
                '& .MuiAlert-message': { fontSize: '0.875rem' }
              }}
            >
              Connection issue
            </Alert>
          )}
          
          {lowBatterySensors.length > 0 && (
            <Alert 
              severity="warning" 
              variant="filled"
              icon={<BatteryAlert />}
              sx={{ 
                mb: 1,
                bgcolor: alpha('#ed6c02', 0.8),
                '& .MuiAlert-message': { fontSize: '0.875rem' }
              }}
            >
              {lowBatterySensors.length} sensors low battery
            </Alert>
          )}
          
          {lowSignalSensors.length > 0 && (
            <Alert 
              severity="warning" 
              variant="filled"
              icon={<SignalWifiStatusbarConnectedNoInternet4 />}
              sx={{ 
                mb: 1,
                bgcolor: alpha('#ed6c02', 0.8),
                '& .MuiAlert-message': { fontSize: '0.875rem' }
              }}
            >
              {lowSignalSensors.length} sensors low signal
            </Alert>
          )}
        </Box>
      )}

      {/* Ambient Controls */}
      <Box sx={{ 
        position: 'fixed', 
        bottom: 20, 
        left: 20, 
        zIndex: 1000,
        display: 'flex',
        gap: 2,
        flexWrap: 'wrap'
      }}>
        <Card sx={{ 
          bgcolor: alpha('#1a1a1a', 0.9), 
          backdropFilter: 'blur(10px)',
          border: '1px solid rgba(255,255,255,0.1)'
        }}>
          <CardContent sx={{ p: 2, '&:last-child': { pb: 2 } }}>
            <FormControl size="small" sx={{ minWidth: 120 }}>
              <InputLabel sx={{ color: '#ffffff' }}>Time Range</InputLabel>
              <Select
                value={timeRange}
                label="Time Range"
                onChange={(e) => setTimeRange(e.target.value)}
                sx={{ 
                  color: '#ffffff',
                  '& .MuiOutlinedInput-notchedOutline': {
                    borderColor: 'rgba(255,255,255,0.3)'
                  },
                  '&:hover .MuiOutlinedInput-notchedOutline': {
                    borderColor: 'rgba(255,255,255,0.5)'
                  }
                }}
              >
                {TIME_RANGES.map(range => (
                  <MenuItem key={range.value} value={range.value}>
                    {range.label}
                  </MenuItem>
                ))}
              </Select>
            </FormControl>
          </CardContent>
        </Card>

        <Card sx={{ 
          bgcolor: alpha('#1a1a1a', 0.9), 
          backdropFilter: 'blur(10px)',
          border: '1px solid rgba(255,255,255,0.1)'
        }}>
          <CardContent sx={{ p: 2, '&:last-child': { pb: 2 } }}>
            <FormControlLabel
              control={
                <Switch
                  checked={showPressureChart}
                  onChange={(e) => setShowPressureChart(e.target.checked)}
                  size="small"
                  sx={{
                    '& .MuiSwitch-switchBase.Mui-checked': {
                      color: '#90caf9'
                    },
                    '& .MuiSwitch-switchBase.Mui-checked + .MuiSwitch-track': {
                      backgroundColor: '#90caf9'
                    }
                  }}
                />
              }
              label={<Typography variant="caption" sx={{ color: '#ffffff' }}>Pressure</Typography>}
            />
          </CardContent>
        </Card>
      </Box>

      {/* Main Chart - Full Screen */}
      <ErrorBoundary
        fallback={
          <Box sx={{ 
            height: 'calc(100vh - 120px)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            bgcolor: '#0a0a0a'
          }}>
            <InlineError
              error="Chart failed to render"
              title="Chart Error"
              onRetry={handleRefresh}
              severity="error"
            />
          </Box>
        }
      >
        <Box sx={{ 
          height: 'calc(100vh - 120px)',
          p: 2,
          bgcolor: '#0a0a0a'
        }}>
          {historyLoading ? (
            <Box display="flex" alignItems="center" justifyContent="center" height="100%">
              <LoadingSpinner text="Loading chart data..." size={32} fullHeight={false} />
            </Box>
          ) : historyError ? (
            <Box display="flex" alignItems="center" justifyContent="center" height="100%">
              <InlineError
                error={historyError}
                title="Failed to Load Chart Data"
                onRetry={handleRefresh}
                severity="error"
              />
            </Box>
          ) : chartData ? (
            <Line data={chartData} options={mainChartOptions} />
          ) : (
            <Box display="flex" alignItems="center" justifyContent="center" height="100%">
              <DataError
                message="No data available for selected time range"
                onRetry={handleRefresh}
                compact={false}
              />
            </Box>
          )}
        </Box>
      </ErrorBoundary>

      {/* Pressure Chart */}
      {showPressureChart && (
        <ErrorBoundary
          fallback={
            <Card>
              <CardContent>
                <InlineError
                  error="Pressure chart failed to render"
                  title="Chart Error"
                  onRetry={handleRefresh}
                  severity="error"
                />
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
                ) : historyError ? (
                  <Box display="flex" alignItems="center" justifyContent="center" height="100%">
                    <InlineError
                      error={historyError}
                      title="Failed to Load Pressure Data"
                      onRetry={handleRefresh}
                      severity="error"
                    />
                  </Box>
                ) : pressureChartData ? (
                  <Line data={pressureChartData} options={pressureChartOptions} />
                ) : (
                  <Box display="flex" alignItems="center" justifyContent="center" height="100%">
                    <DataError
                      message="No pressure data available"
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

      {/* Sensor Summary - Scrollable Overlay */}
      <Box sx={{ 
        position: 'fixed', 
        top: 120, 
        left: 16, 
        maxHeight: 'calc(100vh - 200px)',
        maxWidth: 250,
        overflowY: 'auto',
        zIndex: 1000,
        opacity: 0.1,
        '&:hover': { opacity: 1 },
        transition: 'opacity 0.3s ease'
      }}>
        {sensorData.map(sensor => (
          <Card key={sensor.sensor_mac} sx={{ 
            mb: 1, 
            bgcolor: alpha('#1a1a1a', 0.9),
            backdropFilter: 'blur(10px)',
            border: '1px solid rgba(255,255,255,0.1)'
          }}>
            <CardContent sx={{ p: 1.5, '&:last-child': { pb: 1.5 } }}>
              <Typography variant="caption" sx={{ color: '#ffffff', opacity: 0.7 }}>
                {dataHelpers.formatMacAddress(sensor.sensor_mac)}
              </Typography>
              <Box display="flex" gap={2} mt={0.5}>
                <Typography variant="body2" sx={{ color: '#90caf9' }}>
                  {sensor.temperature.toFixed(1)}°C
                </Typography>
                <Typography variant="body2" sx={{ color: '#81c784' }}>
                  {sensor.humidity.toFixed(1)}%
                </Typography>
              </Box>
            </CardContent>
          </Card>
        ))}
      </Box>
    </Box>
  );
};

export default Overview;