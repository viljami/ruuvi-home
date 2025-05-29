import React, { useState, useMemo } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  Box,
  Typography,
  Grid,
  Card,
  CardContent,
  Button,
  IconButton,
  Tooltip,
  Breadcrumbs,
  Link,
  Chip,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Divider,
  Alert,
} from '@mui/material';
import {
  ArrowBack,
  Refresh,
  Timeline,
  Thermostat,
  Water,
  Speed,
  Battery90,
  Home,
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

import { useSensorMonitoring } from '../services/hooks';
import { dataHelpers } from '../services/api';
import LoadingSpinner from '../components/LoadingSpinner';
import ErrorMessage from '../components/ErrorMessage';

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

const SensorDetail: React.FC = () => {
  const { sensorId } = useParams<{ sensorId: string }>();
  const navigate = useNavigate();
  const [timeRange, setTimeRange] = useState('-1h');

  const sensorMac = sensorId ? decodeURIComponent(sensorId) : '';
  const { latest, history, isLoading, error, refetch } = useSensorMonitoring(sensorMac);

  // Filter historical data based on time range
  const filteredHistory = useMemo(() => {
    if (!history.data) return [];
    
    const now = Date.now();
    let cutoffTime = now;
    
    switch (timeRange) {
      case '-1h':
        cutoffTime = now - 60 * 60 * 1000;
        break;
      case '-6h':
        cutoffTime = now - 6 * 60 * 60 * 1000;
        break;
      case '-24h':
        cutoffTime = now - 24 * 60 * 60 * 1000;
        break;
      case '-7d':
        cutoffTime = now - 7 * 24 * 60 * 60 * 1000;
        break;
      default:
        return history.data;
    }
    
    return history.data.filter(reading => reading.timestamp * 1000 >= cutoffTime);
  }, [history.data, timeRange]);

  const handleBack = () => {
    navigate('/');
  };

  const handleRefresh = () => {
    refetch();
  };

  if (!sensorMac) {
    return (
      <ErrorMessage
        error="Invalid sensor ID"
        title="Sensor Not Found"
        onRetry={handleBack}
        retryText="Back to Dashboard"
        fullWidth
      />
    );
  }

  if (isLoading) {
    return (
      <LoadingSpinner
        text="Loading sensor data..."
        size={48}
        fullHeight={false}
      />
    );
  }

  if (error) {
    return (
      <Box sx={{ maxWidth: 600, mx: 'auto', mt: 4 }}>
        <ErrorMessage
          error={error}
          title="Failed to Load Sensor Data"
          onRetry={handleRefresh}
          fullWidth
        />
      </Box>
    );
  }

  const currentReading = latest.data;
  if (!currentReading) {
    return (
      <ErrorMessage
        error="No data available for this sensor"
        title="Sensor Data Not Found"
        onRetry={handleBack}
        retryText="Back to Dashboard"
        fullWidth
      />
    );
  }

  const sensorStatus = dataHelpers.getSensorStatus(currentReading.timestamp);
  const lastSeen = dataHelpers.formatRelativeTime(currentReading.timestamp);

  // Prepare chart data
  const chartData = {
    labels: filteredHistory.map(reading => new Date(reading.timestamp * 1000)),
    datasets: [
      {
        label: 'Temperature (°C)',
        data: filteredHistory.map(reading => reading.temperature),
        borderColor: 'rgb(255, 99, 132)',
        backgroundColor: 'rgba(255, 99, 132, 0.2)',
        yAxisID: 'y',
      },
      {
        label: 'Humidity (%)',
        data: filteredHistory.map(reading => reading.humidity),
        borderColor: 'rgb(54, 162, 235)',
        backgroundColor: 'rgba(54, 162, 235, 0.2)',
        yAxisID: 'y1',
      },
    ],
  };

  const pressureChartData = {
    labels: filteredHistory.map(reading => new Date(reading.timestamp * 1000)),
    datasets: [
      {
        label: 'Pressure (hPa)',
        data: filteredHistory.map(reading => reading.pressure),
        borderColor: 'rgb(75, 192, 192)',
        backgroundColor: 'rgba(75, 192, 192, 0.2)',
      },
    ],
  };

  const chartOptions = {
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
        text: 'Temperature & Humidity',
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
          },
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
    plugins: {
      legend: {
        position: 'top' as const,
      },
      title: {
        display: true,
        text: 'Atmospheric Pressure',
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

  return (
    <Box>
      {/* Header */}
      <Box mb={4}>
        <Breadcrumbs aria-label="breadcrumb" sx={{ mb: 2 }}>
          <Link
            component="button"
            variant="body1"
            onClick={handleBack}
            sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}
          >
            <Home fontSize="small" />
            Dashboard
          </Link>
          <Typography color="text.primary">
            {dataHelpers.formatMacAddress(sensorMac)}
          </Typography>
        </Breadcrumbs>

        <Box display="flex" justifyContent="space-between" alignItems="flex-start" flexWrap="wrap" gap={2}>
          <Box>
            <Typography variant="h4" component="h1" gutterBottom>
              <Timeline sx={{ mr: 1, verticalAlign: 'middle' }} />
              Sensor Details
            </Typography>
            <Box display="flex" alignItems="center" gap={2} flexWrap="wrap">
              <Typography variant="h6" color="primary">
                {dataHelpers.formatMacAddress(sensorMac)}
              </Typography>
              <Chip
                label={sensorStatus.toUpperCase()}
                color={
                  sensorStatus === 'online'
                    ? 'success'
                    : sensorStatus === 'warning'
                    ? 'warning'
                    : 'error'
                }
                size="small"
              />
              <Typography variant="body2" color="textSecondary">
                Last seen: {lastSeen}
              </Typography>
            </Box>
          </Box>

          <Box display="flex" alignItems="center" gap={1}>
            <Button
              variant="outlined"
              startIcon={<ArrowBack />}
              onClick={handleBack}
            >
              Back
            </Button>
            <Tooltip title="Refresh Data">
              <IconButton onClick={handleRefresh} disabled={isLoading} color="primary">
                <Refresh />
              </IconButton>
            </Tooltip>
          </Box>
        </Box>
      </Box>

      {/* Current Readings */}
      <Grid container spacing={3} sx={{ mb: 4 }}>
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Box display="flex" alignItems="center" gap={2}>
                <Thermostat
                  className={dataHelpers.getTemperatureClass(currentReading.temperature)}
                  sx={{ fontSize: 40 }}
                />
                <Box>
                  <Typography variant="h4" className={dataHelpers.getTemperatureClass(currentReading.temperature)}>
                    {currentReading.temperature.toFixed(1)}°C
                  </Typography>
                  <Typography variant="body2" color="textSecondary">
                    Temperature
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
                <Water
                  className={dataHelpers.getHumidityClass(currentReading.humidity)}
                  sx={{ fontSize: 40 }}
                />
                <Box>
                  <Typography variant="h4" className={dataHelpers.getHumidityClass(currentReading.humidity)}>
                    {currentReading.humidity.toFixed(1)}%
                  </Typography>
                  <Typography variant="body2" color="textSecondary">
                    Humidity
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
                <Speed sx={{ fontSize: 40 }} />
                <Box>
                  <Typography variant="h4">
                    {currentReading.pressure.toFixed(0)}
                  </Typography>
                  <Typography variant="body2" color="textSecondary">
                    hPa
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
                <Battery90
                  className={dataHelpers.getBatteryClass(currentReading.battery)}
                  sx={{ fontSize: 40 }}
                />
                <Box>
                  <Typography
                    variant="h4"
                    className={dataHelpers.getBatteryClass(currentReading.battery)}
                  >
                    {(currentReading.battery / 1000).toFixed(2)}V
                  </Typography>
                  <Typography variant="body2" color="textSecondary">
                    Battery
                  </Typography>
                </Box>
              </Box>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Time Range Selector */}
      <Box display="flex" justifyContent="space-between" alignItems="center" mb={3}>
        <Typography variant="h6">Historical Data</Typography>
        <FormControl size="small" sx={{ minWidth: 120 }}>
          <InputLabel>Time Range</InputLabel>
          <Select
            value={timeRange}
            label="Time Range"
            onChange={(e) => setTimeRange(e.target.value)}
          >
            <MenuItem value="-1h">Last Hour</MenuItem>
            <MenuItem value="-6h">Last 6 Hours</MenuItem>
            <MenuItem value="-24h">Last 24 Hours</MenuItem>
            <MenuItem value="-7d">Last 7 Days</MenuItem>
          </Select>
        </FormControl>
      </Box>

      {/* Charts */}
      {filteredHistory.length === 0 ? (
        <Alert severity="info" sx={{ mb: 4 }}>
          No historical data available for the selected time range.
        </Alert>
      ) : (
        <Grid container spacing={3}>
          <Grid item xs={12} lg={8}>
            <Card>
              <CardContent>
                <Box height={400}>
                  <Line data={chartData} options={chartOptions} />
                </Box>
              </CardContent>
            </Card>
          </Grid>

          <Grid item xs={12} lg={4}>
            <Card>
              <CardContent>
                <Box height={400}>
                  <Line data={pressureChartData} options={pressureChartOptions} />
                </Box>
              </CardContent>
            </Card>
          </Grid>
        </Grid>
      )}

      {/* Additional Sensor Information */}
      <Card sx={{ mt: 3 }}>
        <CardContent>
          <Typography variant="h6" gutterBottom>
            Sensor Information
          </Typography>
          <Divider sx={{ mb: 2 }} />
          <Grid container spacing={2}>
            <Grid item xs={12} sm={6} md={3}>
              <Typography variant="body2" color="textSecondary">
                Gateway MAC
              </Typography>
              <Typography variant="body1">
                {dataHelpers.formatMacAddress(currentReading.gateway_mac)}
              </Typography>
            </Grid>
            <Grid item xs={12} sm={6} md={3}>
              <Typography variant="body2" color="textSecondary">
                RSSI
              </Typography>
              <Typography variant="body1">
                {currentReading.rssi} dBm
              </Typography>
            </Grid>
            <Grid item xs={12} sm={6} md={3}>
              <Typography variant="body2" color="textSecondary">
                TX Power
              </Typography>
              <Typography variant="body1">
                {currentReading.tx_power} dBm
              </Typography>
            </Grid>
            <Grid item xs={12} sm={6} md={3}>
              <Typography variant="body2" color="textSecondary">
                Movement Counter
              </Typography>
              <Typography variant="body1">
                {currentReading.movement_counter}
              </Typography>
            </Grid>
            <Grid item xs={12} sm={6} md={3}>
              <Typography variant="body2" color="textSecondary">
                Sequence Number
              </Typography>
              <Typography variant="body1">
                {currentReading.measurement_sequence_number}
              </Typography>
            </Grid>
            <Grid item xs={12} sm={6} md={3}>
              <Typography variant="body2" color="textSecondary">
                Acceleration
              </Typography>
              <Typography variant="body1">
                {currentReading.acceleration.toFixed(2)} mg
              </Typography>
            </Grid>
            <Grid item xs={12} sm={6} md={3}>
              <Typography variant="body2" color="textSecondary">
                Last Update
              </Typography>
              <Typography variant="body1">
                {dataHelpers.formatTimestamp(currentReading.timestamp)}
              </Typography>
            </Grid>
          </Grid>
        </CardContent>
      </Card>
    </Box>
  );
};

export default SensorDetail;