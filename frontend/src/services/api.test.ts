import { dataHelpers } from './api';

describe('Data Helpers', () => {
  describe('formatTimestamp', () => {
    it('should format timestamp to readable date', () => {
      const timestamp = 1640995200; // 2022-01-01 00:00:00 UTC
      const result = dataHelpers.formatTimestamp(timestamp);

      expect(result).toContain('2022');
      expect(typeof result).toBe('string');
    });
  });

  describe('formatRelativeTime', () => {
    it('should return "Just now" for very recent timestamps', () => {
      const recentTimestamp = Math.floor(Date.now() / 1000) - 30; // 30 seconds ago
      const result = dataHelpers.formatRelativeTime(recentTimestamp);

      expect(result).toBe('Just now');
    });

    it('should return minutes for recent timestamps', () => {
      const timestamp = Math.floor(Date.now() / 1000) - 300; // 5 minutes ago
      const result = dataHelpers.formatRelativeTime(timestamp);

      expect(result).toBe('5m ago');
    });

    it('should return hours for older timestamps', () => {
      const timestamp = Math.floor(Date.now() / 1000) - 7200; // 2 hours ago
      const result = dataHelpers.formatRelativeTime(timestamp);

      expect(result).toBe('2h ago');
    });

    it('should return days for very old timestamps', () => {
      const timestamp = Math.floor(Date.now() / 1000) - 172800; // 2 days ago
      const result = dataHelpers.formatRelativeTime(timestamp);

      expect(result).toBe('2d ago');
    });
  });

  describe('isSensorOnline', () => {
    it('should return true for recent timestamp', () => {
      const recentTimestamp = Math.floor(Date.now() / 1000) - 300; // 5 minutes ago

      expect(dataHelpers.isSensorOnline(recentTimestamp)).toBe(true);
    });

    it('should return false for old timestamp', () => {
      const oldTimestamp = Math.floor(Date.now() / 1000) - 3600; // 1 hour ago

      expect(dataHelpers.isSensorOnline(oldTimestamp)).toBe(false);
    });
  });

  describe('getTemperatureClass', () => {
    it('should return temp-cold for freezing temperatures', () => {
      expect(dataHelpers.getTemperatureClass(-5)).toBe('temp-cold');
      expect(dataHelpers.getTemperatureClass(-10)).toBe('temp-cold');
    });

    it('should return temp-normal for comfortable temperatures', () => {
      expect(dataHelpers.getTemperatureClass(15)).toBe('temp-normal');
      expect(dataHelpers.getTemperatureClass(18)).toBe('temp-normal');
    });

    it('should return temp-warm for warm temperatures', () => {
      expect(dataHelpers.getTemperatureClass(25)).toBe('temp-warm');
      expect(dataHelpers.getTemperatureClass(28)).toBe('temp-warm');
    });

    it('should return temp-hot for hot temperatures', () => {
      expect(dataHelpers.getTemperatureClass(35)).toBe('temp-hot');
      expect(dataHelpers.getTemperatureClass(40)).toBe('temp-hot');
    });
  });

  describe('getHumidityClass', () => {
    it('should return humidity-low for low humidity', () => {
      expect(dataHelpers.getHumidityClass(25)).toBe('humidity-low');
      expect(dataHelpers.getHumidityClass(20)).toBe('humidity-low');
    });

    it('should return humidity-normal for normal humidity', () => {
      expect(dataHelpers.getHumidityClass(45)).toBe('humidity-normal');
      expect(dataHelpers.getHumidityClass(50)).toBe('humidity-normal');
    });

    it('should return humidity-high for high humidity', () => {
      expect(dataHelpers.getHumidityClass(75)).toBe('humidity-high');
      expect(dataHelpers.getHumidityClass(80)).toBe('humidity-high');
    });
  });

  describe('getBatteryClass', () => {
    it('should return battery-critical for very low battery', () => {
      expect(dataHelpers.getBatteryClass(2300)).toBe('battery-critical');
      expect(dataHelpers.getBatteryClass(2200)).toBe('battery-critical');
    });

    it('should return battery-low for low battery', () => {
      expect(dataHelpers.getBatteryClass(2500)).toBe('battery-low');
      expect(dataHelpers.getBatteryClass(2600)).toBe('battery-low');
    });

    it('should return battery-good for good battery', () => {
      expect(dataHelpers.getBatteryClass(2800)).toBe('battery-good');
      expect(dataHelpers.getBatteryClass(3000)).toBe('battery-good');
    });
  });

  describe('formatMacAddress', () => {
    it('should format MAC address to uppercase', () => {
      expect(dataHelpers.formatMacAddress('aa:bb:cc:dd:ee:ff')).toBe('AA:BB:CC:DD:EE:FF');
      expect(dataHelpers.formatMacAddress('12:34:56:78:90:ab')).toBe('12:34:56:78:90:AB');
    });

    it('should handle already uppercase MAC addresses', () => {
      expect(dataHelpers.formatMacAddress('AA:BB:CC:DD:EE:FF')).toBe('AA:BB:CC:DD:EE:FF');
    });
  });

  describe('getSensorStatus', () => {
    it('should return online for very recent data', () => {
      const now = Date.now();
      const recentTimestamp = Math.floor((now - 2 * 60 * 1000) / 1000); // 2 minutes ago

      expect(dataHelpers.getSensorStatus(recentTimestamp)).toBe('online');
    });

    it('should return warning for moderately old data', () => {
      const now = Date.now();
      const warningTimestamp = Math.floor((now - 15 * 60 * 1000) / 1000); // 15 minutes ago

      expect(dataHelpers.getSensorStatus(warningTimestamp)).toBe('warning');
    });

    it('should return offline for very old data', () => {
      const now = Date.now();
      const offlineTimestamp = Math.floor((now - 45 * 60 * 1000) / 1000); // 45 minutes ago

      expect(dataHelpers.getSensorStatus(offlineTimestamp)).toBe('offline');
    });
  });
});
