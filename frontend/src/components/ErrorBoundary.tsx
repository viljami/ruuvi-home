import React, { Component, ReactNode } from 'react';
import {
  Alert,
  AlertTitle,
  Box,
  Button,
  Typography,
  Chip,
  Stack,
  Collapse,
  IconButton,
} from '@mui/material';
import {
  Error as ErrorIcon,
  Warning as WarningIcon,
  Refresh,
  WifiOff,
  ExpandMore,
  ExpandLess,
  BugReport,
} from '@mui/icons-material';

// Types
interface ErrorInfo {
  componentStack: string;
}

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
  onError?: (error: Error, errorInfo: ErrorInfo) => void;
  showDetails?: boolean;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
  showDetails: boolean;
}

interface InlineErrorProps {
  error: any;
  title?: string;
  message?: string;
  onRetry?: () => void;
  retryText?: string;
  size?: 'small' | 'medium' | 'large';
  severity?: 'error' | 'warning' | 'info';
  showIcon?: boolean;
  compact?: boolean;
}

interface NetworkErrorProps {
  onRetry?: () => void;
  compact?: boolean;
}

interface DataErrorProps {
  message?: string;
  onRetry?: () => void;
  compact?: boolean;
}

// Error Boundary Component
export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = {
      hasError: false,
      error: null,
      errorInfo: null,
      showDetails: false,
    };
  }

  static getDerivedStateFromError(error: Error): Partial<ErrorBoundaryState> {
    return {
      hasError: true,
      error,
    };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    this.setState({
      error,
      errorInfo,
    });

    if (this.props.onError) {
      this.props.onError(error, errorInfo);
    }

    // Log to console in development
    if (process.env.NODE_ENV === 'development') {
      console.error('ErrorBoundary caught an error:', error, errorInfo);
    }
  }

  handleReload = () => {
    window.location.reload();
  };

  handleReset = () => {
    this.setState({
      hasError: false,
      error: null,
      errorInfo: null,
      showDetails: false,
    });
  };

  toggleDetails = () => {
    this.setState(prev => ({ showDetails: !prev.showDetails }));
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <Box sx={{ p: 3, maxWidth: 600, mx: 'auto' }}>
          <Alert severity="error" sx={{ mb: 2 }}>
            <AlertTitle>Something went wrong</AlertTitle>
            <Typography variant="body2" sx={{ mb: 2 }}>
              An unexpected error occurred in the application. You can try refreshing the page or contact support if the problem persists.
            </Typography>
            
            <Stack direction="row" spacing={1} sx={{ mb: 2 }}>
              <Button
                variant="contained"
                size="small"
                startIcon={<Refresh />}
                onClick={this.handleReload}
              >
                Refresh Page
              </Button>
              <Button
                variant="outlined"
                size="small"
                onClick={this.handleReset}
              >
                Try Again
              </Button>
              {this.props.showDetails !== false && (
                <Button
                  variant="text"
                  size="small"
                  startIcon={<BugReport />}
                  onClick={this.toggleDetails}
                  endIcon={this.state.showDetails ? <ExpandLess /> : <ExpandMore />}
                >
                  {this.state.showDetails ? 'Hide' : 'Show'} Details
                </Button>
              )}
            </Stack>

            <Collapse in={this.state.showDetails}>
              <Box sx={{ p: 2, bgcolor: 'grey.50', borderRadius: 1, mt: 1 }}>
                <Typography variant="caption" component="div" sx={{ mb: 1 }}>
                  <strong>Error:</strong> {this.state.error?.message}
                </Typography>
                {this.state.errorInfo && (
                  <Typography variant="caption" component="pre" sx={{ 
                    fontSize: '0.75rem', 
                    overflow: 'auto',
                    maxHeight: 200,
                    whiteSpace: 'pre-wrap',
                  }}>
                    {this.state.errorInfo.componentStack}
                  </Typography>
                )}
              </Box>
            </Collapse>
          </Alert>
        </Box>
      );
    }

    return this.props.children;
  }
}

// Inline Error Component for API/Data Errors
export const InlineError: React.FC<InlineErrorProps> = ({
  error,
  title,
  message,
  onRetry,
  retryText = 'Try Again',
  size = 'medium',
  severity = 'error',
  showIcon = true,
  compact = false,
}) => {
  const getErrorMessage = () => {
    if (message) return message;
    
    if (typeof error === 'string') return error;
    
    if (error?.message) return error.message;
    
    if (error?.status === 0) return 'Unable to connect to server';
    if (error?.status === 404) return 'Data not found';
    if (error?.status === 500) return 'Server error occurred';
    
    return 'An unexpected error occurred';
  };

  const getTitle = () => {
    if (title) return title;
    
    if (error?.status === 0) return 'Connection Error';
    if (error?.status === 404) return 'Not Found';
    if (error?.status >= 500) return 'Server Error';
    
    return 'Error';
  };

  const isNetworkError = error?.status === 0 || error?.message?.includes('network') || error?.message?.includes('fetch');

  const getIcon = () => {
    if (!showIcon) return undefined;
    
    if (isNetworkError) return <WifiOff />;
    if (severity === 'warning') return <WarningIcon />;
    return <ErrorIcon />;
  };

  if (compact) {
    return (
      <Box sx={{ p: 1, textAlign: 'center' }}>
        <Typography variant="caption" color="error" sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
          {showIcon && getIcon()}
          {getErrorMessage()}
        </Typography>
        {onRetry && (
          <Button size="small" onClick={onRetry} sx={{ mt: 0.5, fontSize: '0.75rem' }}>
            {retryText}
          </Button>
        )}
      </Box>
    );
  }

  return (
    <Alert 
      severity={severity}
      icon={getIcon()}
      sx={{ 
        my: size === 'small' ? 1 : 2,
        '& .MuiAlert-message': { width: '100%' }
      }}
    >
      <AlertTitle>{getTitle()}</AlertTitle>
      <Typography variant="body2" sx={{ mb: onRetry ? 1 : 0 }}>
        {getErrorMessage()}
      </Typography>
      
      {error?.status && (
        <Chip 
          label={`Error ${error.status}`} 
          size="small" 
          color="error" 
          variant="outlined"
          sx={{ mt: 0.5, mr: 1 }}
        />
      )}
      
      {onRetry && (
        <Button
          variant="outlined"
          size="small"
          startIcon={<Refresh />}
          onClick={onRetry}
          sx={{ mt: 1 }}
        >
          {retryText}
        </Button>
      )}
    </Alert>
  );
};

// Network Error Component
export const NetworkError: React.FC<NetworkErrorProps> = ({ onRetry, compact = false }) => {
  if (compact) {
    return (
      <Box sx={{ p: 1, textAlign: 'center', color: 'error.main' }}>
        <WifiOff sx={{ fontSize: 16, mr: 0.5 }} />
        <Typography variant="caption">Connection lost</Typography>
        {onRetry && (
          <IconButton size="small" onClick={onRetry} sx={{ ml: 0.5 }}>
            <Refresh fontSize="small" />
          </IconButton>
        )}
      </Box>
    );
  }

  return (
    <InlineError
      error={{ status: 0, message: 'Unable to connect to server. Please check your internet connection.' }}
      title="Connection Error"
      onRetry={onRetry}
      retryText="Reconnect"
      severity="error"
    />
  );
};

// Data Error Component
export const DataError: React.FC<DataErrorProps> = ({ 
  message = 'No data available', 
  onRetry, 
  compact = false 
}) => {
  if (compact) {
    return (
      <Box sx={{ p: 2, textAlign: 'center', color: 'text.secondary' }}>
        <Typography variant="body2">{message}</Typography>
        {onRetry && (
          <Button size="small" onClick={onRetry} sx={{ mt: 1 }}>
            Refresh
          </Button>
        )}
      </Box>
    );
  }

  return (
    <InlineError
      error={message}
      title="No Data"
      onRetry={onRetry}
      retryText="Refresh"
      severity="info"
    />
  );
};

// Loading Error Component (for when data fails to load)
export const LoadingError: React.FC<{ onRetry?: () => void; compact?: boolean }> = ({ 
  onRetry, 
  compact = false 
}) => {
  return (
    <InlineError
      error="Failed to load data"
      title="Loading Failed"
      onRetry={onRetry}
      retryText="Retry"
      severity="warning"
      compact={compact}
    />
  );
};

export default ErrorBoundary;