import React from 'react';
import {
  AppBar,
  Toolbar,
  Typography,
  Box,
  IconButton,
  Tooltip,
} from '@mui/material';
import {
  Refresh,
  Menu as MenuIcon,
} from '@mui/icons-material';

interface OverviewHeaderProps {
  onMenuClick: () => void;
  onRefreshClick: () => void;
  isLoading?: boolean;
  title?: string;
  subtitle?: string;
}

export const OverviewHeader: React.FC<OverviewHeaderProps> = ({
  onMenuClick,
  onRefreshClick,
  isLoading = false,
  title = 'Ruuvi Home',
  subtitle = 'Sensor Monitoring Dashboard',
}) => {
  return (
    <AppBar 
      position="static" 
      elevation={0}
      sx={{ 
        bgcolor: 'transparent',
        borderBottom: '1px solid rgba(255,255,255,0.05)'
      }}
    >
      <Toolbar sx={{ justifyContent: 'space-between' }}>
        <Box display="flex" alignItems="center">
          <IconButton
            edge="start"
            color="inherit"
            onClick={onMenuClick}
            sx={{ 
              mr: 2,
              opacity: 0.6,
              '&:hover': { opacity: 1 },
              transition: 'opacity 0.2s ease'
            }}
            aria-label="Open navigation menu"
          >
            <MenuIcon />
          </IconButton>
          <Typography 
            variant="h6" 
            component="h1" 
            sx={{ 
              opacity: 0.4,
              fontWeight: 300,
              fontSize: '1rem',
              '&:hover': { opacity: 0.7 },
              transition: 'opacity 0.2s ease'
            }}
          >
            {title}
          </Typography>
        </Box>
        
        <Box display="flex" alignItems="center" gap={2}>
          <Typography 
            variant="body2" 
            sx={{ 
              opacity: 0.6,
              fontSize: '0.8rem',
              display: { xs: 'none', sm: 'block' }
            }}
          >
            {subtitle}
          </Typography>
          
          <Tooltip title="Refresh Data">
            <IconButton
              onClick={onRefreshClick}
              disabled={isLoading}
              color="inherit"
              size="small"
              sx={{ 
                opacity: isLoading ? 0.3 : 0.6,
                '&:hover': { opacity: 1 },
                transition: 'opacity 0.2s ease'
              }}
              aria-label="Refresh sensor data"
            >
              <Refresh 
                fontSize="small" 
                sx={{
                  animation: isLoading ? 'spin 1s linear infinite' : 'none',
                  '@keyframes spin': {
                    '0%': {
                      transform: 'rotate(0deg)',
                    },
                    '100%': {
                      transform: 'rotate(360deg)',
                    },
                  },
                }}
              />
            </IconButton>
          </Tooltip>
        </Box>
      </Toolbar>
    </AppBar>
  );
};

export default OverviewHeader;