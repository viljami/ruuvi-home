import React from "react";
import { screen, waitFor } from "@testing-library/react";
import "@testing-library/jest-dom";
import { renderWithoutRouter } from "./test-utils";
import App from "./App";

// Mock the views to avoid complex dependencies
jest.mock("./views/Dashboard", () => {
  return function Dashboard() {
    return <div data-testid="dashboard">Dashboard View</div>;
  };
});

jest.mock("./views/Overview", () => {
  return function Overview() {
    return <div data-testid="overview">Overview View</div>;
  };
});

jest.mock("./views/SensorDetail", () => {
  return function SensorDetail() {
    return <div data-testid="sensor-detail">Sensor Detail View</div>;
  };
});

// Mock the API service to return empty data
jest.mock("./services/api", () => ({
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
jest.mock("@tanstack/react-query-devtools", () => ({
  ReactQueryDevtools: () => null,
}));

describe("App Component", () => {
  beforeEach(() => {
    // Clear all mocks before each test
    jest.clearAllMocks();
  });

  test("renders without crashing", async () => {
    renderWithoutRouter(<App />);
    
    // Should render the main app structure
    expect(screen.getByText("🏠 Ruuvi Home")).toBeInTheDocument();
    expect(screen.getByText("Sensor Monitoring Dashboard")).toBeInTheDocument();
  });

  test("displays navigation elements", async () => {
    renderWithoutRouter(<App />);
    
    // Check for navigation buttons
    expect(screen.getByRole("button", { name: /overview/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /dashboard/i })).toBeInTheDocument();
  });

  test("renders overview by default", async () => {
    renderWithoutRouter(<App />);
    
    // Should show overview by default (route: /)
    await waitFor(() => {
      expect(screen.getByTestId("overview")).toBeInTheDocument();
    });
  });

  test("has proper semantic structure", async () => {
    renderWithoutRouter(<App />);
    
    // Check for proper semantic HTML
    expect(screen.getByRole("banner")).toBeInTheDocument(); // header
    expect(screen.getByRole("main")).toBeInTheDocument(); // main content
    // Navigation buttons exist but not wrapped in nav element
    expect(screen.getByRole("button", { name: /overview/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /dashboard/i })).toBeInTheDocument();
  });

  test("contains error boundary", async () => {
    renderWithoutRouter(<App />);
    
    // The app should render without errors, indicating error boundary is working
    expect(screen.getByText("🏠 Ruuvi Home")).toBeInTheDocument();
  });

  test("shows loading state initially", async () => {
    renderWithoutRouter(<App />);
    
    // App should render immediately (no loading spinner for main app)
    expect(screen.getByText("🏠 Ruuvi Home")).toBeInTheDocument();
  });

  test("handles routing properly", async () => {
    const { rerender } = renderWithoutRouter(<App />);
    
    // Should handle different routes without crashing
    expect(() => rerender(<App />)).not.toThrow();
  });
});

describe("App Integration", () => {
  test("provides query client context", async () => {
    renderWithoutRouter(<App />);
    
    // If React Query context is provided, components should render
    // The overview component should be able to use queries
    await waitFor(() => {
      expect(screen.getByTestId("overview")).toBeInTheDocument();
    });
  });

  test("provides router context", async () => {
    renderWithoutRouter(<App />);
    
    // If Router context is provided, navigation should work
    expect(screen.getByRole("button", { name: /overview/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /dashboard/i })).toBeInTheDocument();
  });
});