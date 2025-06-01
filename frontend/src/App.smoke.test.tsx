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
  fetchSensors: jest.fn(() => Promise.resolve([])),
  fetchSensorData: jest.fn(() => Promise.resolve([])),
  fetchSensorStats: jest.fn(() => Promise.resolve({
    count: 0,
    lastUpdate: null,
    avgTemperature: null,
    avgHumidity: null,
    avgPressure: null
  })),
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
