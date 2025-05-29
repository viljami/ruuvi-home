import { useQuery, UseQueryResult } from "@tanstack/react-query";
import { apiService, SensorReading, HistoricalQuery, ApiError } from "./api";

// Enhanced error types
interface EnhancedApiError extends ApiError {
  isNetworkError?: boolean;
  isRetryable?: boolean;
  timestamp?: number;
}

// Network status detection
const isNetworkError = (error: any): boolean => {
  return (
    error?.status === 0 ||
    error?.code === "NETWORK_ERROR" ||
    error?.message?.includes("network") ||
    error?.message?.includes("fetch") ||
    error?.message?.includes("connection")
  );
};

// Enhanced error handler
const enhanceError = (error: any): EnhancedApiError => {
  const enhanced: EnhancedApiError = {
    ...error,
    isNetworkError: isNetworkError(error),
    isRetryable: error?.status !== 404 && error?.status !== 403,
    timestamp: Date.now(),
  };

  return enhanced;
};

// Query keys for React Query
export const queryKeys = {
  health: ["health"] as const,
  sensors: ["sensors"] as const,
  sensorLatest: (sensorMac: string) => ["sensor", sensorMac, "latest"] as const,
  sensorHistory: (sensorMac: string, query?: HistoricalQuery) =>
    ["sensor", sensorMac, "history", query] as const,
  allSensorsHistory: (timeRange: string) =>
    ["allSensors", "history", timeRange] as const,
};

// Health check hook
export const useHealth = (): UseQueryResult<string, EnhancedApiError> => {
  return useQuery({
    queryKey: queryKeys.health,
    queryFn: apiService.checkHealth,
    refetchInterval: 60000, // Check every minute
    staleTime: 30000, // Consider fresh for 30 seconds
    retry: 3,
    retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),
  });
};

// Get all sensors hook
export const useSensors = (): UseQueryResult<
  SensorReading[],
  EnhancedApiError
> => {
  return useQuery({
    queryKey: queryKeys.sensors,
    queryFn: apiService.getSensors,
    refetchInterval: 30000, // Refetch every 30 seconds
    staleTime: 15000, // Consider fresh for 15 seconds
    retry: 3,
    retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 10000),
  });
};

// Get latest reading for a specific sensor
export const useSensorLatest = (
  sensorMac: string,
  enabled: boolean = true,
): UseQueryResult<SensorReading, EnhancedApiError> => {
  return useQuery({
    queryKey: queryKeys.sensorLatest(sensorMac),
    queryFn: () => apiService.getLatestReading(sensorMac),
    enabled: enabled && Boolean(sensorMac),
    refetchInterval: 30000, // Refetch every 30 seconds
    staleTime: 15000,
    retry: (failureCount, error) => {
      // Don't retry 404s for specific sensors
      if (error?.status === 404) return false;
      return failureCount < 2;
    },
    retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 8000),
  });
};

// Get historical data for a specific sensor
export const useSensorHistory = (
  sensorMac: string,
  query: HistoricalQuery = {},
  enabled: boolean = true,
): UseQueryResult<SensorReading[], EnhancedApiError> => {
  return useQuery({
    queryKey: queryKeys.sensorHistory(sensorMac, query),
    queryFn: () => apiService.getHistoricalData(sensorMac, query),
    enabled: enabled && Boolean(sensorMac),
    staleTime: 60000, // Historical data can be stale for 1 minute
    retry: (failureCount, error) => {
      if (error?.status === 404) return false;
      return failureCount < 2;
    },
    retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 15000),
  });
};

// Hook for getting multiple sensors' latest readings
export const useMultipleSensorsLatest = (
  sensorMacs: string[],
): {
  [key: string]: UseQueryResult<SensorReading, EnhancedApiError>;
} => {
  const results: {
    [key: string]: UseQueryResult<SensorReading, EnhancedApiError>;
  } = {};

  sensorMacs.forEach((mac) => {
    // eslint-disable-next-line react-hooks/rules-of-hooks
    results[mac] = useSensorLatest(mac);
  });

  return results;
};

// Custom hook for real-time sensor monitoring
export const useSensorMonitoring = (sensorMac: string) => {
  const latestQuery = useSensorLatest(sensorMac);
  const historyQuery = useSensorHistory(sensorMac, { limit: 24 }); // Last 24 readings

  return {
    latest: latestQuery,
    history: historyQuery,
    isLoading: latestQuery.isLoading || historyQuery.isLoading,
    error: latestQuery.error || historyQuery.error,
    refetch: () => {
      latestQuery.refetch();
      historyQuery.refetch();
    },
  };
};

// Hook for getting historical data for all sensors
export const useAllSensorsHistory = (
  timeRange: string,
): UseQueryResult<
  { [sensorMac: string]: SensorReading[] },
  EnhancedApiError
> => {
  const sensorsQuery = useSensors();

  return useQuery({
    queryKey: queryKeys.allSensorsHistory(timeRange),
    queryFn: async () => {
      if (!sensorsQuery.data) {
        const error = new Error("No sensors data available");
        throw enhanceError(error);
      }

      // Calculate time parameters based on range
      const now = Date.now();
      let startTime: Date;

      switch (timeRange) {
        case "6h":
          startTime = new Date(now - 6 * 60 * 60 * 1000);
          break;
        case "24h":
          startTime = new Date(now - 24 * 60 * 60 * 1000);
          break;
        case "7d":
          startTime = new Date(now - 7 * 24 * 60 * 60 * 1000);
          break;
        case "1m":
          startTime = new Date(now - 30 * 24 * 60 * 60 * 1000);
          break;
        case "6m":
          startTime = new Date(now - 6 * 30 * 24 * 60 * 60 * 1000);
          break;
        case "1y":
          startTime = new Date(now - 365 * 24 * 60 * 60 * 1000);
          break;
        default:
          startTime = new Date(now - 24 * 60 * 60 * 1000);
      }

      const query: HistoricalQuery = {
        start: startTime.toISOString(),
        end: new Date(now).toISOString(),
      };

      // Fetch historical data for all sensors in parallel
      const promises = sensorsQuery.data.map(async (sensor) => {
        try {
          const history = await apiService.getHistoricalData(
            sensor.sensor_mac,
            query,
          );
          return { sensorMac: sensor.sensor_mac, history, success: true };
        } catch (error) {
          const enhanced = enhanceError(error);
          console.warn(
            `Failed to fetch history for sensor ${sensor.sensor_mac}:`,
            enhanced,
          );
          return {
            sensorMac: sensor.sensor_mac,
            history: [],
            success: false,
            error: enhanced,
          };
        }
      });

      const results = await Promise.all(promises);

      // Check if too many sensors failed
      const failedSensors = results.filter((r) => !r.success);
      if (failedSensors.length === results.length && results.length > 0) {
        // All sensors failed - this is likely a systemic issue
        const error = new Error(
          `Failed to load data for all ${results.length} sensors`,
        );
        throw enhanceError(error);
      }

      // Convert to object with sensor MAC as key
      const historyData: { [sensorMac: string]: SensorReading[] } = {};
      results.forEach(({ sensorMac, history }) => {
        historyData[sensorMac] = history;
      });

      return historyData;
    },
    enabled: Boolean(sensorsQuery.data && sensorsQuery.data.length > 0),
    staleTime: 120000, // Historical data can be stale for 2 minutes
    retry: 2,
    retryDelay: (attemptIndex) => Math.min(2000 * 2 ** attemptIndex, 30000),
  });
};

// Hook for dashboard overview
export const useDashboardData = () => {
  const sensorsQuery = useSensors();
  const healthQuery = useHealth();

  const sensorMacs =
    sensorsQuery.data?.map((sensor) => sensor.sensor_mac) || [];

  // Enhanced error detection
  const error = sensorsQuery.error || healthQuery.error;
  const isNetworkIssue = error && isNetworkError(error);
  const hasPartialData = Boolean(sensorsQuery.data?.length && error);

  return {
    sensors: sensorsQuery,
    health: healthQuery,
    isLoading: sensorsQuery.isLoading || healthQuery.isLoading,
    error: error,
    isNetworkError: isNetworkIssue,
    hasPartialData: hasPartialData,
    refetchAll: () => {
      sensorsQuery.refetch();
      healthQuery.refetch();
    },
    sensorCount: sensorMacs.length,
    onlineSensors:
      sensorsQuery.data?.filter((sensor) => {
        const now = Date.now();
        const diff = now - sensor.timestamp * 1000;
        return diff < 10 * 60 * 1000; // Online if data received in last 10 minutes
      }).length || 0,
    offlineSensors:
      sensorMacs.length -
      (sensorsQuery.data?.filter((sensor) => {
        const now = Date.now();
        const diff = now - sensor.timestamp * 1000;
        return diff < 10 * 60 * 1000;
      }).length || 0),
    lastFetchTime: sensorsQuery.dataUpdatedAt || healthQuery.dataUpdatedAt,
  };
};
