import React, { useMemo } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  useTheme,
} from '@mui/material';
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
import { format } from 'date-fns';

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

export interface SensorDataPoint {
  timestamp: string;
  temperature?: number;
  humidity?: number;
  pressure?: number;
  sensorId: string;
  sensorName?: string;
}

export interface SensorChartProps {
  data: SensorDataPoint[];
  metricType: 'temperature' | 'humidity' | 'pressure';
  title: string;
  unit: string;
  visibleSensors: Set<string>;
  height?: number;
  showLegend?: boolean;
  timeFormat?: string;
}

// Color palette for different sensors
const SENSOR_COLORS = [
  '#1f77b4', '#ff7f0e', '#2ca02c', '#d62728', '#9467bd',
  '#8c564b', '#e377c2', '#7f7f7f', '#bcbd22', '#17becf',
  '#aec7e8', '#ffbb78', '#98df8a', '#ff9896', '#c5b0d5',
];

const SensorChart: React.FC<SensorChartProps> = ({
  data,
  metricType,
  title,
  unit,
  visibleSensors,
  height = 300,
  showLegend = true,
  timeFormat = 'HH:mm',
}) => {
  const theme = useTheme();

  const chartData = useMemo(() => {
    // Group data by sensor
    const sensorData = new Map<string, SensorDataPoint[]>();

    data.forEach(point => {
      if (visibleSensors.has(point.sensorId)) {
        if (!sensorData.has(point.sensorId)) {
          sensorData.set(point.sensorId, []);
        }
        sensorData.get(point.sensorId)!.push(point);
      }
    });

    // Create datasets for each sensor
    const datasets = Array.from(sensorData.entries()).map(([sensorId, points], index) => {
      const colorIndex = index % SENSOR_COLORS.length;
      const color = SENSOR_COLORS[colorIndex];

      const sensorName = points[0]?.sensorName || sensorId;

      return {
        label: sensorName,
        data: points
          .map(point => ({
            x: new Date(point.timestamp),
            y: point[metricType],
          }))
          .filter(point => point.y !== undefined)
          .sort((a, b) => a.x.getTime() - b.x.getTime()),
        borderColor: color,
        backgroundColor: color + '20',
        borderWidth: 2,
        pointRadius: 2,
        pointHoverRadius: 4,
        fill: false,
        tension: 0.1,
      };
    });

    return { datasets };
  }, [data, metricType, visibleSensors]);

  const options = useMemo(() => ({
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        display: showLegend,
        position: 'top' as const,
        labels: {
          color: theme.palette.text.primary,
          usePointStyle: true,
          pointStyle: 'line',
          font: {
            size: 12,
          },
        },
      },
      title: {
        display: false,
      },
      tooltip: {
        mode: 'index' as const,
        intersect: false,
        backgroundColor: theme.palette.background.paper,
        titleColor: theme.palette.text.primary,
        bodyColor: theme.palette.text.primary,
        borderColor: theme.palette.divider,
        borderWidth: 1,
        cornerRadius: 8,
        callbacks: {
          title: (context: any) => {
            if (context[0]) {
              return format(new Date(context[0].parsed.x), 'MMM dd, HH:mm');
            }
            return '';
          },
          label: (context: any) => {
            const value = context.parsed.y;
            const label = context.dataset.label;
            return `${label}: ${value?.toFixed(1)} ${unit}`;
          },
        },
      },
    },
    scales: {
      x: {
        type: 'time' as const,
        time: {
          displayFormats: {
            hour: timeFormat,
            day: 'MMM dd',
            week: 'MMM dd',
            month: 'MMM yyyy',
          },
        },
        grid: {
          color: theme.palette.divider,
          drawBorder: false,
        },
        ticks: {
          color: theme.palette.text.secondary,
          maxTicksLimit: 8,
          font: {
            size: 11,
          },
        },
      },
      y: {
        beginAtZero: false,
        grid: {
          color: theme.palette.divider,
          drawBorder: false,
        },
        ticks: {
          color: theme.palette.text.secondary,
          callback: function(value: any) {
            return `${value} ${unit}`;
          },
          font: {
            size: 11,
          },
        },
      },
    },
    interaction: {
      mode: 'index' as const,
      intersect: false,
    },
    elements: {
      point: {
        hoverBackgroundColor: theme.palette.background.paper,
        hoverBorderWidth: 3,
      },
    },
  }), [theme, showLegend, unit, timeFormat]);

  const hasData = chartData.datasets.some(dataset => dataset.data.length > 0);

  if (!hasData) {
    return (
      <Card>
        <CardContent>
          <Typography variant="h6" gutterBottom>
            {title}
          </Typography>
          <Box
            sx={{
              height,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: 'text.secondary',
            }}
          >
            <Typography>No data available for selected sensors</Typography>
          </Box>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardContent>
        <Typography variant="h6" gutterBottom>
          {title}
        </Typography>
        <Box sx={{ height, position: 'relative' }}>
          <Line data={chartData} options={options} />
        </Box>
      </CardContent>
    </Card>
  );
};

export default SensorChart;
