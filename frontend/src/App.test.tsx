import React from "react";
import { render, screen } from "@testing-library/react";
import "@testing-library/jest-dom";

import App from "./App";

// Mock all the problematic dependencies
jest.mock("@tanstack/react-query", () => ({
  QueryClient: jest.fn(),
  QueryClientProvider: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
  useQuery: () => ({
    data: [],
    isLoading: false,
    error: null,
    refetch: jest.fn(),
  }),
}));

jest.mock("@tanstack/react-query-devtools", () => ({
  ReactQueryDevtools: () => null,
}));

jest.mock("react-router-dom", () => ({
  BrowserRouter: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
  Routes: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
  Route: () => null,
}));

jest.mock("./views/Dashboard", () => {
  return function Dashboard() {
    return <div data-testid="dashboard">Dashboard</div>;
  };
});

jest.mock("./views/SensorDetail", () => {
  return function SensorDetail() {
    return <div data-testid="sensor-detail">Sensor Detail</div>;
  };
});

describe("App", () => {
  test("renders without crashing", () => {
    const { container } = render(<App />);
    expect(container).toBeInTheDocument();
  });

  test("contains app title", () => {
    render(<App />);
    expect(screen.getByText("🏠 Ruuvi Home")).toBeInTheDocument();
  });
});
