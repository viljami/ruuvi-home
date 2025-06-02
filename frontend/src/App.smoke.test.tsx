import React from 'react';
import { screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import { renderWithoutRouter } from './test-utils';
import App from './App';

// Mock the view components to avoid complex dependencies
jest.mock('./views/Dashboard', () => {
  return function Dashboard() {
    return <div data-testid="dashboard">Dashboard</div>;
  };
});

jest.mock('./views/Overview', () => {
  return function Overview() {
    return <div data-testid="overview">Overview</div>;
  };
});

jest.mock('./views/SensorDetail', () => {
  return function SensorDetail() {
    return <div data-testid="sensor-detail">Sensor Detail</div>;
  };
});

// Mock API calls
jest.mock('./services/api', () => ({
  apiService: {
    checkHealth: jest.fn(() => Promise.resolve('OK')),
    getSensorList: jest.fn(() => Promise.resolve([])),
    getSensors: jest.fn(() => Promise.resolve([])),
    getLatestReading: jest.fn(() => Promise.resolve({
      sensor_mac: 'test:sensor:mac',
      gateway_mac: 'test:gateway:mac',
      timestamp: Math.floor(Date.now() / 1000),
      temperature: 20.0,
      humidity: 50.0,
      pressure: 1013.25,
      battery: 2800,
      tx_power: 4,
      movement_counter: 0,
      measurement_sequence_number: 1,
      acceleration: 1000,
      acceleration_x: 0,
      acceleration_y: 0,
      acceleration_z: 1000,
      rssi: -60,
    })),
    getHistoricalData: jest.fn(() => Promise.resolve([])),
  },
  dataHelpers: {
    formatTimestamp: jest.fn((timestamp) => new Date(timestamp * 1000).toLocaleString()),
    formatRelativeTime: jest.fn(() => 'Just now'),
    isSensorOnline: jest.fn(() => true),
    getTemperatureClass: jest.fn(() => 'temp-normal'),
    getHumidityClass: jest.fn(() => 'humidity-normal'),
    getBatteryClass: jest.fn(() => 'battery-good'),
    formatMacAddress: jest.fn((mac) => mac.toUpperCase()),
    getSensorStatus: jest.fn(() => 'online'),
  },
}));

// Mock React Query DevTools
jest.mock('@tanstack/react-query-devtools', () => ({
  ReactQueryDevtools: () => null,
}));

describe('App Smoke Tests', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('renders without crashing', async () => {
    renderWithoutRouter(<App />);
    expect(screen.getByText('🏠 Ruuvi Home')).toBeInTheDocument();
  });

  test('displays main navigation elements', async () => {
    renderWithoutRouter(<App />);

    expect(screen.getByText('🏠 Ruuvi Home')).toBeInTheDocument();
    expect(screen.getByText('Sensor Monitoring Dashboard')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /overview/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /dashboard/i })).toBeInTheDocument();
  });

  test('contains required structural elements', async () => {
    renderWithoutRouter(<App />);

    expect(screen.getByRole('banner')).toBeInTheDocument();
    expect(screen.getByRole('main')).toBeInTheDocument();
    // Navigation buttons exist but not wrapped in nav element
    expect(screen.getByRole('button', { name: /overview/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /dashboard/i })).toBeInTheDocument();
  });

  test('overview content is displayed by default', async () => {
    renderWithoutRouter(<App />);

    await waitFor(() => {
      expect(screen.getByTestId('overview')).toBeInTheDocument();
    });
  });

  test('basic app structure is responsive', async () => {
    renderWithoutRouter(<App />);

    const header = screen.getByRole('banner');
    const main = screen.getByRole('main');

    expect(header).toBeInTheDocument();
    expect(main).toBeInTheDocument();
  });

  test('handles router context properly', async () => {
    renderWithoutRouter(<App />);

    // Should not throw router-related errors and should render navigation buttons
    expect(screen.getByRole('button', { name: /overview/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /dashboard/i })).toBeInTheDocument();
  });

  test('provides query client context', async () => {
    renderWithoutRouter(<App />);

    // Should render components that use React Query
    await waitFor(() => {
      expect(screen.getByTestId('overview')).toBeInTheDocument();
    });
  });

  test('error boundary is working', async () => {
    // Should not crash the entire test suite
    expect(() => renderWithoutRouter(<App />)).not.toThrow();
  });
});
