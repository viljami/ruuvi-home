import React from 'react';
import { Box, CircularProgress, Typography } from '@mui/material';

interface LoadingSpinnerProps {
  size?: number;
  text?: string;
  color?: 'primary' | 'secondary' | 'inherit';
  fullHeight?: boolean;
}

const LoadingSpinner: React.FC<LoadingSpinnerProps> = ({
  size = 40,
  text = 'Loading...',
  color = 'primary',
  fullHeight = false,
}) => {
  return (
    <Box
      display="flex"
      flexDirection="column"
      alignItems="center"
      justifyContent="center"
      gap={2}
      sx={{
        height: fullHeight ? '100vh' : 'auto',
        minHeight: fullHeight ? 'auto' : 200,
        py: 4,
      }}
    >
      <CircularProgress size={size} color={color} />
      {text && (
        <Typography variant="body2" color="textSecondary" textAlign="center">
          {text}
        </Typography>
      )}
    </Box>
  );
};

export default LoadingSpinner;
