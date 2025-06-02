import React from 'react';
import { BrowserRouter as Router, Routes, Route, useLocation, useNavigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';
import { Container, AppBar, Toolbar, Typography, Box, Button, Alert, AlertTitle } from '@mui/material';
import Dashboard from './views/Dashboard';
import SensorDetail from './views/SensorDetail';
import Overview from './views/Overview';
import { ReactQueryDevtools } from '@tanstack/react-query-devtools';
import { ErrorBoundary } from './components/ErrorBoundary';

// Create React Query client with default options
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchInterval: 30000, // Auto-refresh every 30 seconds
      refetchOnWindowFocus: false,
      retry: 3,
      staleTime: 5000,
    },
  },
  // Global error handler
  mutationCache: undefined,
});

// Create Material-UI dark theme for ambient display
const theme = createTheme({
  palette: {
    mode: 'dark',
    primary: {
      main: '#90caf9',
    },
    secondary: {
      main: '#f48fb1',
    },
    background: {
      default: '#0a0a0a',
      paper: '#1a1a1a',
    },
    text: {
      primary: '#ffffff',
      secondary: 'rgba(255, 255, 255, 0.7)',
    },
    error: {
      main: '#f44336',
    },
    warning: {
      main: '#ff9800',
    },
    success: {
      main: '#4caf50',
    },
  },
  typography: {
    fontFamily: '"Inter", "Roboto", "Helvetica", "Arial", sans-serif',
    h4: {
      fontWeight: 300,
      fontSize: '1.75rem',
    },
    h6: {
      fontWeight: 400,
      fontSize: '1rem',
    },
    body1: {
      fontSize: '0.875rem',
    },
    body2: {
      fontSize: '0.75rem',
    },
  },
  components: {
    MuiCssBaseline: {
      styleOverrides: {
        body: {
          backgroundColor: '#0a0a0a',
          backgroundImage: 'radial-gradient(circle at 20% 80%, rgba(120, 119, 198, 0.1), transparent 50%), radial-gradient(circle at 80% 20%, rgba(255, 255, 255, 0.05), transparent 50%)',
        },
      },
    },
    MuiCard: {
      styleOverrides: {
        root: {
          borderRadius: 16,
          backgroundColor: 'rgba(26, 26, 26, 0.8)',
          backdropFilter: 'blur(20px)',
          border: '1px solid rgba(255, 255, 255, 0.1)',
          boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3)',
        },
      },
    },
    MuiButton: {
      styleOverrides: {
        root: {
          borderRadius: 12,
          textTransform: 'none',
          fontWeight: 400,
        },
        outlined: {
          borderColor: 'rgba(255, 255, 255, 0.2)',
          '&:hover': {
            borderColor: 'rgba(255, 255, 255, 0.4)',
            backgroundColor: 'rgba(255, 255, 255, 0.05)',
          },
        },
      },
    },
    MuiAppBar: {
      styleOverrides: {
        root: {
          backgroundColor: 'transparent',
          boxShadow: 'none',
        },
      },
    },
    MuiDrawer: {
      styleOverrides: {
        paper: {
          backgroundColor: '#1a1a1a',
          backdropFilter: 'blur(20px)',
          border: 'none',
        },
      },
    },
    MuiAlert: {
      styleOverrides: {
        root: {
          borderRadius: 12,
        },
      },
    },
  },
});

const AppContent: React.FC = () => {
  const location = useLocation();
  const navigate = useNavigate();

  return (
    <ErrorBoundary
      fallback={
        <Box sx={{ p: 3, textAlign: 'center' }}>
          <Alert severity="error">
            <AlertTitle>Application Error</AlertTitle>
            The application encountered an unexpected error. Please refresh the page.
          </Alert>
        </Box>
      }
    >
      <Box sx={{ flexGrow: 1 }}>
        {/* App Bar */}
        <ErrorBoundary
          fallback={
            <AppBar position="static" elevation={1}>
              <Toolbar>
                <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
                  🏠 Ruuvi Home
                </Typography>
                <Typography variant="body2" sx={{ opacity: 0.8 }}>
                  Navigation Error
                </Typography>
              </Toolbar>
            </AppBar>
          }
        >
          <AppBar position="static" elevation={1}>
            <Toolbar>
              <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
                🏠 Ruuvi Home
              </Typography>

              {/* Navigation Buttons */}
              <ErrorBoundary
                fallback={
                  <Typography variant="body2" sx={{ mr: 2, opacity: 0.6 }}>
                    Navigation unavailable
                  </Typography>
                }
              >
                <Box sx={{ display: 'flex', gap: 1, mr: 2 }}>
                  <Button
                    color="inherit"
                    onClick={() => navigate('/')}
                    variant={location.pathname === '/' ? 'outlined' : 'text'}
                    sx={{
                      borderColor: location.pathname === '/' ? 'rgba(255,255,255,0.5)' : 'transparent',
                      '&:hover': { backgroundColor: 'rgba(255,255,255,0.1)' }
                    }}
                  >
                    Overview
                  </Button>
                  <Button
                    color="inherit"
                    onClick={() => navigate('/dashboard')}
                    variant={location.pathname === '/dashboard' ? 'outlined' : 'text'}
                    sx={{
                      borderColor: location.pathname === '/dashboard' ? 'rgba(255,255,255,0.5)' : 'transparent',
                      '&:hover': { backgroundColor: 'rgba(255,255,255,0.1)' }
                    }}
                  >
                    Dashboard
                  </Button>
                </Box>
              </ErrorBoundary>

              <Typography variant="body2" sx={{ opacity: 0.8 }}>
                Sensor Monitoring Dashboard
              </Typography>
            </Toolbar>
          </AppBar>
        </ErrorBoundary>

        {/* Main Content */}
        <Container maxWidth="xl" sx={{ mt: 4, mb: 4 }} role="main">
          <ErrorBoundary
            fallback={
              <Box sx={{ p: 4, textAlign: 'center' }}>
                <Alert severity="error">
                  <AlertTitle>Content Loading Error</AlertTitle>
                  Unable to load the requested page. Please try refreshing or navigate to a different section.
                  <Box sx={{ mt: 2 }}>
                    <Button variant="outlined" onClick={() => navigate('/')} sx={{ mr: 1 }}>
                      Go to Overview
                    </Button>
                    <Button variant="outlined" onClick={() => navigate('/dashboard')}>
                      Go to Dashboard
                    </Button>
                  </Box>
                </Alert>
              </Box>
            }
          >
            <Routes>
              <Route
                path="/"
                element={
                  <ErrorBoundary
                    fallback={
                      <Alert severity="error">
                        <AlertTitle>Overview Error</AlertTitle>
                        The overview page failed to load. Try the <Button onClick={() => navigate('/dashboard')}>Dashboard</Button> instead.
                      </Alert>
                    }
                  >
                    <Overview />
                  </ErrorBoundary>
                }
              />
              <Route
                path="/dashboard"
                element={
                  <ErrorBoundary
                    fallback={
                      <Alert severity="error">
                        <AlertTitle>Dashboard Error</AlertTitle>
                        The dashboard failed to load. Try the <Button onClick={() => navigate('/')}>Overview</Button> instead.
                      </Alert>
                    }
                  >
                    <Dashboard />
                  </ErrorBoundary>
                }
              />
              <Route
                path="/sensor/:sensorId"
                element={
                  <ErrorBoundary
                    fallback={
                      <Alert severity="error">
                        <AlertTitle>Sensor Detail Error</AlertTitle>
                        Unable to load sensor details. <Button onClick={() => navigate('/dashboard')}>Return to Dashboard</Button>
                      </Alert>
                    }
                  >
                    <SensorDetail />
                  </ErrorBoundary>
                }
              />
            </Routes>
          </ErrorBoundary>
        </Container>
      </Box>
    </ErrorBoundary>
  );
};

function App() {
  return (
    <ErrorBoundary
      fallback={
        <Box sx={{ p: 3, textAlign: 'center' }}>
          <Alert severity="error">
            <AlertTitle>Application Error</AlertTitle>
            The application encountered a critical error. Please refresh the page.
          </Alert>
        </Box>
      }
    >
      <QueryClientProvider client={queryClient}>
        <ThemeProvider theme={theme}>
          <CssBaseline />
          <Router>
            <AppContent />
          </Router>

          {/* React Query DevTools (only in development) */}
          {process.env.NODE_ENV === 'development' && (
            <ReactQueryDevtools initialIsOpen={false} />
          )}
        </ThemeProvider>
      </QueryClientProvider>
    </ErrorBoundary>
  );
}

export default App;
