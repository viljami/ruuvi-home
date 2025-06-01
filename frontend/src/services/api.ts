import axios, { AxiosResponse } from 'axios';

// API Configuration
const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:8080';

const api = axios.create({
  baseURL: API_BASE_URL,
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Types
export interface SensorReading {
  sensor_mac: string;
  gateway_mac: string;
  timestamp: number;
  temperature: number;
  humidity: number;
  pressure: number;
  battery: number;
  tx_power: number;
  movement_counter: number;
  measurement_sequence_number: number;
  acceleration: number;
  acceleration_x: number;
  acceleration_y: number;
  acceleration_z: number;
  rssi: number;
}

export interface HistoricalQuery {
  start?: string;
  end?: string;
  limit?: number;
}

export interface ApiError {
  message: string;
  status?: number;
}

// Helper function to handle API errors
const handleApiError = (error: any): ApiError => {
  if (error.response) {
    return {
      message: error.response.data?.message || 'Server error occurred',
      status: error.response.status,
    };
  } else if (error.request) {
    return {
      message: 'Unable to connect to server',
      status: 0,
    };
  } else {
    return {
      message: error.message || 'An unexpected error occurred',
    };
  }
};

// API Functions
export const apiService = {
  // Health check
  async checkHealth(): Promise<string> {
    try {
      const response: AxiosResponse<string> = await api.get('/health');
      return response.data;
    } catch (error) {
      throw handleApiError(error);
    }
  },

  // Get list of active sensors
  async getSensors(): Promise<SensorReading[]> {
    try {
      const response: AxiosResponse<SensorReading[]> = await api.get('/api/sensors');
      return response.data;
    } catch (error) {
      throw handleApiError(error);
    }
  },

  // Get latest reading for a specific sensor
  async getLatestReading(sensorMac: string): Promise<SensorReading> {
    try {
      const response: AxiosResponse<SensorReading> = await api.get(
        `/api/sensors/${encodeURIComponent(sensorMac)}/latest`
      );
      return response.data;
    } catch (error) {
      throw handleApiError(error);
    }
  },

  // Get historical data for a specific sensor
  async getHistoricalData(
    sensorMac: string,
    query: HistoricalQuery = {}
  ): Promise<SensorReading[]> {
    try {
      const params = new URLSearchParams();
      if (query.start) params.append('start', query.start);
      if (query.end) params.append('end', query.end);
      if (query.limit) params.append('limit', query.limit.toString());

      const url = `/api/sensors/${encodeURIComponent(sensorMac)}/history${
        params.toString() ? `?${params.toString()}` : ''
      }`;

      const response: AxiosResponse<SensorReading[]> = await api.get(url);
      return response.data;
    } catch (error) {
      throw handleApiError(error);
    }
  },
};

// Helper functions for data processing
export const dataHelpers = {
  // Format timestamp to readable date
  formatTimestamp(timestamp: number): string {
    return new Date(timestamp * 1000).toLocaleString();
  },

  // Format timestamp to relative time
  formatRelativeTime(timestamp: number): string {
    const now = Date.now();
    const diff = now - timestamp * 1000;
    const minutes = Math.floor(diff / 60000);
    const hours = Math.floor(diff / 3600000);
    const days = Math.floor(diff / 86400000);

    if (minutes < 1) return 'Just now';
    if (minutes < 60) return `${minutes}m ago`;
    if (hours < 24) return `${hours}h ago`;
    return `${days}d ago`;
  },

  // Check if sensor is online (received data in last 10 minutes)
  isSensorOnline(timestamp: number): boolean {
    const now = Date.now();
    const diff = now - timestamp * 1000;
    return diff < 10 * 60 * 1000; // 10 minutes
  },

  // Get temperature color class
  getTemperatureClass(temperature: number): string {
    if (temperature < 0) return 'temp-cold';
    if (temperature < 20) return 'temp-normal';
    if (temperature < 30) return 'temp-warm';
    return 'temp-hot';
  },

  // Get humidity class
  getHumidityClass(humidity: number): string {
    if (humidity < 30) return 'humidity-low';
    if (humidity < 60) return 'humidity-normal';
    return 'humidity-high';
  },

  // Get battery class
  getBatteryClass(battery: number): string {
    if (battery < 2400) return 'battery-critical'; // Below 2.4V
    if (battery < 2700) return 'battery-low'; // Below 2.7V
    return 'battery-good';
  },

  // Format MAC address for display
  formatMacAddress(mac: string): string {
    return mac.toUpperCase();
  },

  // Get sensor status
  getSensorStatus(timestamp: number): 'online' | 'offline' | 'warning' {
    const now = Date.now();
    const diff = now - timestamp * 1000;

    if (diff < 5 * 60 * 1000) return 'online'; // Less than 5 minutes
    if (diff < 30 * 60 * 1000) return 'warning'; // Less than 30 minutes
    return 'offline';
  },
};

export default apiService;
