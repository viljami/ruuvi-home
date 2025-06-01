import React from 'react';
import {
  Alert,
  AlertTitle,
  Box,
  Button,
  Typography,
  Paper,
} from '@mui/material';
import {
  Error,
  Warning,
  Info,
  Refresh,
  WifiOff,
  CloudOff,
} from '@mui/icons-material';
import { ApiError } from '../services/api';

interface ErrorMessageProps {
  error: ApiError | Error | string;
  title?: string;
  severity?: 'error' | 'warning' | 'info';
  onRetry?: () => void;
  retryText?: string;
  showIcon?: boolean;
  variant?: 'standard' | 'filled' | 'outlined';
  fullWidth?: boolean;
}

const ErrorMessage: React.FC<ErrorMessageProps> = ({
  error,
  title,
  severity = 'error',
  onRetry,
  retryText = 'Try Again',
  showIcon = true,
  variant = 'standard',
  fullWidth = false,
}) => {
  // Extract error message and determine appropriate icon
  const getErrorDetails = () => {
    if (typeof error === 'string') {
      return {
        message: error,
        isNetworkError: false,
        status: undefined,
      };
    }

    if (error instanceof Error) {
      return {
        message: error.message,
        isNetworkError: error.message.includes('network') || error.message.includes('fetch'),
        status: undefined,
      };
    }

    // ApiError type
    const apiError = error as ApiError;
    return {
      message: apiError.message,
      isNetworkError: apiError.status === 0 || apiError.message.includes('connect'),
      status: apiError.status,
    };
  };

  const { message, isNetworkError, status } = getErrorDetails();

  // Determine icon based on error type
  const getIcon = () => {
    if (!showIcon) return undefined;

    if (isNetworkError) {
      return status === 0 ? <WifiOff /> : <CloudOff />;
    }

    switch (severity) {
      case 'warning':
        return <Warning />;
      case 'info':
        return <Info />;
      case 'error':
      default:
        return <Error />;
    }
  };

  // Get user-friendly title
  const getTitle = () => {
    if (title) return title;

    if (isNetworkError) {
      return status === 0 ? 'Connection Error' : 'Server Error';
    }

    switch (severity) {
      case 'warning':
        return 'Warning';
      case 'info':
        return 'Information';
      case 'error':
      default:
        return 'Error';
    }
  };

  // Get user-friendly message
  const getUserFriendlyMessage = () => {
    if (isNetworkError) {
      if (status === 0) {
        return 'Unable to connect to the server. Please check your internet connection.';
      }
      return 'Server is temporarily unavailable. Please try again later.';
    }

    if (status === 404) {
      return 'The requested data could not be found.';
    }

    if (status === 500) {
      return 'Server error occurred. Please try again later.';
    }

    return message || 'An unexpected error occurred.';
  };

  const content = (
    <Alert
      severity={severity}
      variant={variant}
      icon={getIcon()}
      sx={{
        width: fullWidth ? '100%' : 'auto',
        '& .MuiAlert-message': {
          width: '100%',
        },
      }}
    >
      <AlertTitle>{getTitle()}</AlertTitle>
      <Typography variant="body2" sx={{ mb: onRetry ? 2 : 0 }}>
        {getUserFriendlyMessage()}
      </Typography>

      {status && (
        <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: onRetry ? 1 : 0 }}>
          Error Code: {status}
        </Typography>
      )}

      {onRetry && (
        <Box mt={1}>
          <Button
            variant="outlined"
            size="small"
            startIcon={<Refresh />}
            onClick={onRetry}
            color={severity === 'error' ? 'error' : 'primary'}
          >
            {retryText}
          </Button>
        </Box>
      )}
    </Alert>
  );

  if (fullWidth) {
    return (
      <Paper elevation={0} sx={{ p: 2, bgcolor: 'transparent' }}>
        {content}
      </Paper>
    );
  }

  return content;
};

export default ErrorMessage;
