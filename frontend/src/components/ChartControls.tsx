import React from 'react';
import {
  Box,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  FormControlLabel,
  Switch,
  IconButton,
  Tooltip,
  Chip,
  Stack,
  SelectChangeEvent,
} from '@mui/material';
import { Refresh } from '@mui/icons-material';

export interface TimeRange {
  value: string;
  label: string;
  hours: number;
}

export interface ChartControlsProps {
  timeRange: string;
  onTimeRangeChange: (value: string) => void;
  showPressureChart: boolean;
  onShowPressureChartChange: (show: boolean) => void;
  visibleSensors: Set<string>;
  onVisibleSensorsChange: (sensors: Set<string>) => void;
  availableSensors: Array<{ id: string; name: string; mac: string }>;
  onRefresh: () => void;
  isLoading?: boolean;
}

const TIME_RANGES: TimeRange[] = [
  { value: '6h', label: '6 Hours', hours: 6 },
  { value: '24h', label: '24 Hours', hours: 24 },
  { value: '7d', label: '7 Days', hours: 24 * 7 },
  { value: '1m', label: '1 Month', hours: 24 * 30 },
  { value: '6m', label: '6 Months', hours: 24 * 30 * 6 },
  { value: '1y', label: '1 Year', hours: 24 * 365 },
];

const ChartControls: React.FC<ChartControlsProps> = ({
  timeRange,
  onTimeRangeChange,
  showPressureChart,
  onShowPressureChartChange,
  visibleSensors,
  onVisibleSensorsChange,
  availableSensors,
  onRefresh,
  isLoading = false,
}) => {
  const handleTimeRangeChange = (event: SelectChangeEvent) => {
    onTimeRangeChange(event.target.value);
  };

  const handleSensorToggle = (sensorId: string) => {
    const newVisibleSensors = new Set(visibleSensors);
    if (newVisibleSensors.has(sensorId)) {
      newVisibleSensors.delete(sensorId);
    } else {
      newVisibleSensors.add(sensorId);
    }
    onVisibleSensorsChange(newVisibleSensors);
  };

  const toggleAllSensors = () => {
    if (visibleSensors.size === availableSensors.length) {
      // Hide all sensors
      onVisibleSensorsChange(new Set());
    } else {
      // Show all sensors
      onVisibleSensorsChange(new Set(availableSensors.map(s => s.id)));
    }
  };

  return (
    <Box sx={{ mb: 3 }}>
      <Stack
        direction={{ xs: 'column', sm: 'row' }}
        spacing={2}
        alignItems={{ xs: 'stretch', sm: 'center' }}
        sx={{ mb: 2 }}
      >
        {/* Time Range Selector */}
        <FormControl size="small" sx={{ minWidth: 120 }}>
          <InputLabel>Time Range</InputLabel>
          <Select
            value={timeRange}
            label="Time Range"
            onChange={handleTimeRangeChange}
          >
            {TIME_RANGES.map((range) => (
              <MenuItem key={range.value} value={range.value}>
                {range.label}
              </MenuItem>
            ))}
          </Select>
        </FormControl>

        {/* Chart Type Controls */}
        <FormControlLabel
          control={
            <Switch
              checked={showPressureChart}
              onChange={(e) => onShowPressureChartChange(e.target.checked)}
              size="small"
            />
          }
          label="Show Pressure"
        />

        {/* Refresh Button */}
        <Tooltip title="Refresh Data">
          <IconButton
            onClick={onRefresh}
            disabled={isLoading}
            size="small"
            sx={{
              '&:hover': {
                backgroundColor: 'rgba(255, 255, 255, 0.1)',
              },
            }}
          >
            <Refresh />
          </IconButton>
        </Tooltip>
      </Stack>

      {/* Sensor Visibility Controls */}
      {availableSensors.length > 0 && (
        <Box>
          <Stack
            direction="row"
            spacing={1}
            alignItems="center"
            sx={{ mb: 1 }}
          >
            <Chip
              label={visibleSensors.size === availableSensors.length ? 'Hide All' : 'Show All'}
              onClick={toggleAllSensors}
              size="small"
              variant="outlined"
              sx={{
                borderColor: 'rgba(255, 255, 255, 0.3)',
                color: 'text.primary',
                '&:hover': {
                  borderColor: 'rgba(255, 255, 255, 0.5)',
                  backgroundColor: 'rgba(255, 255, 255, 0.05)',
                },
              }}
            />
          </Stack>

          <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
            {availableSensors.map((sensor) => (
              <Chip
                key={sensor.id}
                label={sensor.name || sensor.mac}
                onClick={() => handleSensorToggle(sensor.id)}
                variant={visibleSensors.has(sensor.id) ? 'filled' : 'outlined'}
                size="small"
                sx={{
                  borderColor: visibleSensors.has(sensor.id)
                    ? 'primary.main'
                    : 'rgba(255, 255, 255, 0.3)',
                  backgroundColor: visibleSensors.has(sensor.id)
                    ? 'primary.main'
                    : 'transparent',
                  color: visibleSensors.has(sensor.id)
                    ? 'primary.contrastText'
                    : 'text.primary',
                  '&:hover': {
                    borderColor: 'primary.main',
                    backgroundColor: visibleSensors.has(sensor.id)
                      ? 'primary.dark'
                      : 'rgba(255, 255, 255, 0.05)',
                  },
                  mb: 0.5,
                }}
              />
            ))}
          </Stack>
        </Box>
      )}
    </Box>
  );
};

export default ChartControls;
