import { useQuery, UseQueryResult } from "@tanstack/react-query";
import { apiService, SensorReading, HistoricalQuery, ApiError } from "./api";

// Enhanced error types
interface EnhancedApiError extends ApiError {
  isNetworkError?: boolean;
  isRetryable?: boolean;
  timestamp?: number;
  severity?: 'low' | 'medium' | 'high' | 'critical';
  category?: 'network' | 'server' | 'client' | 'timeout' | 'unknown';
}

// Network status detection
const isNetworkError = (error: any): boolean => {
  return (
    error?.status === 0 ||
    error?.code === "NETWORK_ERROR" ||
    error?.message?.includes("network") ||
    error?.message?.includes("fetch") ||
    error?.message?.includes("connection") ||
    error?.message?.includes("timeout")
  );
};

// Error classification
const classifyError = (error: any): { category: string; severity: string; isRetryable: boolean } => {
  const isNetwork = isNetworkError(error);
  const status = error?.status || 0;

  if (isNetwork) {
    return {
      category: 'network',
      severity: 'high',
      isRetryable: true,
    };
  }

  if (status >= 500) {
    return {
      category: 'server',
      severity: 'medium',
      isRetryable: true,
    };
  }

  if (status === 404) {
    return {
      category: 'client',
      severity: 'low',
      isRetryable: false,
    };
  }

  if (status === 403 || status === 401) {
    return {
      category: 'client',
      severity: 'critical',
      isRetryable: false,
    };
  }

  if (error?.message?.includes('timeout')) {
    return {
      category: 'timeout',
      severity: 'medium',
      isRetryable: true,
    };
  }

  return {
    category: 'unknown',
    severity: 'medium',
    isRetryable: true,
  };
};

// Enhanced error handler
const enhanceError = (error: any): EnhancedApiError => {
  const classification = classifyError(error);

  const enhanced: EnhancedApiError = {
    ...error,
    isNetworkError: classification.category === 'network',
    isRetryable: classification.isRetryable,
    severity: classification.severity as any,
    category: classification.category as any,
    timestamp: Date.now(),
  };

  return enhanced;
};

// Retry delay calculation with exponential backoff and jitter
const calculateRetryDelay = (attemptIndex: number, error?: any): number => {
  const baseDelay = 1000;
  const maxDelay = 30000;
  const jitter = Math.random() * 0.1; // 10% jitter

  // Faster retries for network errors
  const multiplier = error?.category === 'network' ? 1.5 : 2;

  const delay = Math.min(baseDelay * Math.pow(multiplier, attemptIndex), maxDelay);
  return Math.floor(delay * (1 + jitter));
};

// Smart retry function
const shouldRetry = (failureCount: number, error: any): boolean => {
  const enhanced = enhanceError(error);

  // Don't retry client errors (except timeouts)
  if (!enhanced.isRetryable) {
    return false;
  }

  // More retries for network issues
  const maxRetries = enhanced.category === 'network' ? 5 : 3;

  return failureCount < maxRetries;
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

// Get all sensors hook with enhanced error handling
export const useSensors = (): UseQueryResult<
  SensorReading[],
  EnhancedApiError
> => {
  return useQuery({
    queryKey: queryKeys.sensors,
    queryFn: async () => {
      try {
        const result = await apiService.getSensors();
        return result;
      } catch (error) {
        throw enhanceError(error);
      }
    },
    refetchInterval: 30000, // Refetch every 30 seconds
    staleTime: 15000, // Consider fresh for 15 seconds
    retry: shouldRetry,
    retryDelay: calculateRetryDelay,
    // Enable background refetching for resilience
    refetchOnWindowFocus: true,
    refetchOnReconnect: true,
    // Keep previous data while refetching
    keepPreviousData: true,
  });
};

// Get latest reading for a specific sensor with graceful failure
export const useSensorLatest = (
  sensorMac: string,
  enabled: boolean = true,
): UseQueryResult<SensorReading, EnhancedApiError> => {
  return useQuery({
    queryKey: queryKeys.sensorLatest(sensorMac),
    queryFn: async () => {
      try {
        const result = await apiService.getLatestReading(sensorMac);
        return result;
      } catch (error) {
        const enhanced = enhanceError(error);
        // Log sensor-specific failures for monitoring
        if (process.env.NODE_ENV === 'development') {
          console.warn(`Sensor ${sensorMac} failed:`, enhanced);
        }
        throw enhanced;
      }
    },
    enabled: enabled && Boolean(sensorMac),
    refetchInterval: 30000, // Refetch every 30 seconds
    staleTime: 15000,
    retry: shouldRetry,
    retryDelay: calculateRetryDelay,
    keepPreviousData: true,
    // Graceful handling of sensor failures
    useErrorBoundary: false,
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

// Hook for getting historical data for all sensors with resilient error handling
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

      // Helper function to fetch sensor data with retries
      const fetchSensorHistoryWithRetries = async (sensorMac: string) => {
        const maxRetries = 2;
        let lastError: any = null;

        const attemptFetch = async (attemptNumber: number): Promise<any> => {
          try {
            const history = await apiService.getHistoricalData(sensorMac, query);
            return { sensorMac, history, success: true, error: null };
          } catch (error) {
            const enhancedError = enhanceError(error);
            lastError = enhancedError;

            // If it's a non-retryable error, throw immediately
            if (!enhancedError.isRetryable) {
              throw enhancedError;
            }

            // If we've exhausted retries, throw
            if (attemptNumber >= maxRetries) {
              throw enhancedError;
            }

            // Wait before retry
            await new Promise(resolve =>
              setTimeout(resolve, calculateRetryDelay(attemptNumber, enhancedError))
            );

            // Recursive retry
            return attemptFetch(attemptNumber + 1);
          }
        };

        try {
          return await attemptFetch(0);
        } catch (error) {
          // All retries failed, but don't fail the entire request
          if (process.env.NODE_ENV === 'development') {
            console.warn(
              `Failed to fetch history for sensor ${sensorMac} after ${maxRetries + 1} attempts:`,
              lastError,
            );
          }

          return {
            sensorMac,
            history: [],
            success: false,
            error: lastError,
          };
        }
      };

      // With the new API structure, sensorsQuery.data already contains successful sensor readings
      // Fetch historical data for all available sensors in parallel with individual error handling
      const promises = sensorsQuery.data.map((sensor) =>
        fetchSensorHistoryWithRetries(sensor.sensor_mac)
      );

      const results = await Promise.all(promises);

      // Analyze failures
      const failedSensors = results.filter((r) => !r.success);
      const successfulSensors = results.filter((r) => r.success);

      // Only throw if ALL sensors failed AND it's likely a systemic issue
      if (failedSensors.length === results.length && results.length > 0) {
        // Check if failures are all network-related (systemic)
        const networkFailures = failedSensors.filter(r => r.error?.isNetworkError);
        if (networkFailures.length === failedSensors.length) {
          const error = new Error(
            `Network error: Failed to load data for all ${results.length} sensors`,
          );
          throw enhanceError(error);
        }
      }

      // Convert to object with sensor MAC as key
      const historyData: { [sensorMac: string]: SensorReading[] } = {};
      results.forEach(({ sensorMac, history }) => {
        historyData[sensorMac] = history;
      });

      // Log partial failures for monitoring
      if (failedSensors.length > 0 && successfulSensors.length > 0) {
        console.info(`Partial success: ${successfulSensors.length}/${results.length} sensors loaded successfully`);
      }

      return historyData;
    },
    enabled: Boolean(sensorsQuery.data && sensorsQuery.data.length > 0),
    staleTime: 120000, // Historical data can be stale for 2 minutes
    retry: shouldRetry,
    retryDelay: calculateRetryDelay,
    keepPreviousData: true,
    // Don't use error boundary for partial failures
    useErrorBoundary: (error: any) => {
      const enhanced = enhanceError(error);
      // Only use error boundary for critical systemic failures
      return enhanced.severity === 'critical';
    },
  });
};

// Hook for dashboard overview with resilient error handling
export const useDashboardData = () => {
  const sensorsQuery = useSensors();
  const healthQuery = useHealth();

  const sensorMacs =
    sensorsQuery.data?.map((sensor) => sensor.sensor_mac) || [];

  // Enhanced error detection and classification
  const sensorsError = sensorsQuery.error;
  const healthError = healthQuery.error;

  // Prioritize sensors error over health error
  const primaryError = sensorsError || healthError;
  const isNetworkIssue = primaryError && isNetworkError(primaryError);
  const hasPartialData = Boolean(sensorsQuery.data?.length && sensorsError);

  // With the new API structure, partial failures are handled gracefully
  // So if we have sensor data, consider it a success even with some errors
  const hasUsableData = Boolean(sensorsQuery.data && sensorsQuery.data.length > 0);

  // Calculate sensor status with error tolerance
  const calculateSensorStatus = () => {
    if (!sensorsQuery.data) return { online: 0, offline: 0 };

    const now = Date.now();
    const onlineThreshold = 10 * 60 * 1000; // 10 minutes

    let online = 0;
    let offline = 0;

    sensorsQuery.data.forEach((sensor) => {
      const diff = now - sensor.timestamp * 1000;
      if (diff < onlineThreshold) {
        online++;
      } else {
        offline++;
      }
    });

    return { online, offline };
  };

  const sensorStatus = calculateSensorStatus();

  return {
    sensors: sensorsQuery,
    health: healthQuery,
    isLoading: sensorsQuery.isLoading || healthQuery.isLoading,
    error: hasUsableData ? null : primaryError, // Don't show error if we have usable data
    isNetworkError: isNetworkIssue,
    hasPartialData: hasPartialData,

    // Enhanced refetch with error handling
    refetchAll: async () => {
      try {
        await Promise.allSettled([
          sensorsQuery.refetch(),
          healthQuery.refetch(),
        ]);
      } catch (error) {
        console.warn('Refetch failed:', error);
        // Don't throw - let individual queries handle their errors
      }
    },

    sensorCount: sensorMacs.length,
    onlineSensors: sensorStatus.online,
    offlineSensors: sensorStatus.offline,
    lastFetchTime: sensorsQuery.dataUpdatedAt || healthQuery.dataUpdatedAt,

    // Additional error state information
    healthStatus: healthQuery.data === 'OK' ? 'healthy' : 'error',
    dataFreshness: sensorsQuery.dataUpdatedAt
      ? Date.now() - sensorsQuery.dataUpdatedAt
      : null,

    // Recovery status
    isRecovering: Boolean(
      (sensorsQuery.isRefetching || healthQuery.isRefetching) &&
      !sensorsQuery.isLoading &&
      !healthQuery.isLoading
    ),

    // Data quality indicators
    hasUsableData: hasUsableData,
    dataQuality: hasUsableData ? (hasPartialData ? 'partial' : 'complete') : 'none',
  };
};
