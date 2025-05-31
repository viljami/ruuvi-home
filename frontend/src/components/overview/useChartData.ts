import { useMemo } from 'react';
import { SENSOR_COLORS } from './chartConfig';

interface ChartDataPoint {
  x: Date;
  y: number;
}

interface ChartDataset {
  label: string;
  data: ChartDataPoint[];
  borderColor: string;
  backgroundColor: string;
  yAxisID?: string;
  borderDash?: number[];
  pointRadius?: number;
  pointBorderWidth?: number;
}

interface ChartData {
  datasets: ChartDataset[];
}

interface SensorReading {
  timestamp: number;
  temperature: number;
  humidity: number;
  pressure: number;
}

interface Sensor {
  sensor_mac: string;
}

interface UseChartDataProps {
  allHistoryData: { [sensorMac: string]: SensorReading[] } | undefined;
  sensorsData: Sensor[] | undefined;
  visibleSensors: Set<string>;
  showPressureChart: boolean;
  formatMacAddress: (mac: string) => string;
}

interface UseChartDataReturn {
  mainChartData: ChartData | null;
  pressureChartData: ChartData | null;
}

export const useChartData = ({
  allHistoryData,
  sensorsData,
  visibleSensors,
  showPressureChart,
  formatMacAddress,
}: UseChartDataProps): UseChartDataReturn => {
  
  // Prepare main chart data (temperature and humidity)
  const mainChartData = useMemo(() => {
    if (!allHistoryData || !sensorsData) return null;

    const datasets: ChartDataset[] = [];
    let colorIndex = 0;

    sensorsData.forEach(sensor => {
      if (!visibleSensors.has(sensor.sensor_mac)) return;

      const sensorHistory = allHistoryData[sensor.sensor_mac] || [];
      const color = SENSOR_COLORS[colorIndex % SENSOR_COLORS.length];
      const sensorName = formatMacAddress(sensor.sensor_mac);

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
  }, [allHistoryData, sensorsData, visibleSensors, formatMacAddress]);

  // Prepare pressure chart data
  const pressureChartData = useMemo(() => {
    if (!allHistoryData || !sensorsData || !showPressureChart) return null;

    const datasets: ChartDataset[] = [];
    let colorIndex = 0;

    sensorsData.forEach(sensor => {
      if (!visibleSensors.has(sensor.sensor_mac)) return;

      const sensorHistory = allHistoryData[sensor.sensor_mac] || [];
      const color = SENSOR_COLORS[colorIndex % SENSOR_COLORS.length];
      const sensorName = formatMacAddress(sensor.sensor_mac);

      datasets.push({
        label: `${sensorName} Pressure`,
        data: sensorHistory.map(reading => ({
          x: new Date(reading.timestamp * 1000),
          y: reading.pressure,
        })),
        borderColor: color,
        backgroundColor: color + '20',
        pointRadius: 2,
        pointBorderWidth: 1,
      });

      colorIndex++;
    });

    return { datasets };
  }, [allHistoryData, sensorsData, visibleSensors, showPressureChart, formatMacAddress]);

  return {
    mainChartData,
    pressureChartData,
  };
};