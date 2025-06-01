import React from 'react';
import { render, RenderOptions } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

// Create a new QueryClient for each test to ensure clean state
const createTestQueryClient = () => new QueryClient({
  defaultOptions: {
    queries: {
      retry: false,
      gcTime: 0,
    },
    mutations: {
      retry: false,
    },
  },
});

interface TestProvidersProps {
  children: React.ReactNode;
  queryClient?: QueryClient;
  initialEntries?: string[];
  withRouter?: boolean;
}

const TestProviders: React.FC<TestProvidersProps> = ({ 
  children, 
  queryClient = createTestQueryClient(),
  initialEntries = ['/'],
  withRouter = true
}) => {
  const wrappedChildren = withRouter ? (
    <MemoryRouter initialEntries={initialEntries}>
      {children}
    </MemoryRouter>
  ) : children;

  return (
    <QueryClientProvider client={queryClient}>
      {wrappedChildren}
    </QueryClientProvider>
  );
};

interface CustomRenderOptions extends Omit<RenderOptions, 'wrapper'> {
  queryClient?: QueryClient;
  initialEntries?: string[];
  withRouter?: boolean;
}

const customRender = (
  ui: React.ReactElement,
  options: CustomRenderOptions = {}
) => {
  const { queryClient, initialEntries, withRouter = true, ...renderOptions } = options;

  return render(ui, {
    wrapper: ({ children }) => (
      <TestProviders 
        queryClient={queryClient} 
        initialEntries={initialEntries}
        withRouter={withRouter}
      >
        {children}
      </TestProviders>
    ),
    ...renderOptions,
  });
};

// Specialized render function for components that already include Router
const renderWithoutRouter = (
  ui: React.ReactElement,
  options: Omit<CustomRenderOptions, 'withRouter'> = {}
) => {
  return customRender(ui, { ...options, withRouter: false });
};

// Re-export everything from testing library
export * from '@testing-library/react';

// Override the render method
export { customRender as render };

// Export utilities for advanced testing scenarios
export { TestProviders, createTestQueryClient, renderWithoutRouter };