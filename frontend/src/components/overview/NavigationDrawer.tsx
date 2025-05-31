import React from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import {
  Drawer,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  Typography,
  Box,
  Divider,
} from '@mui/material';
import {
  TrendingUp,
  Dashboard as DashboardIcon,
  Sensors,
  Home,
} from '@mui/icons-material';

interface NavigationItem {
  icon: React.ReactElement;
  text: string;
  path: string;
}

interface NavigationDrawerProps {
  open: boolean;
  onClose: () => void;
}

const navigationItems: NavigationItem[] = [
  {
    icon: <Home />,
    text: 'Overview',
    path: '/',
  },
  {
    icon: <DashboardIcon />,
    text: 'Dashboard',
    path: '/dashboard',
  },
  {
    icon: <TrendingUp />,
    text: 'Analytics',
    path: '/analytics',
  },
  {
    icon: <Sensors />,
    text: 'Sensors',
    path: '/sensors',
  },
];

export const NavigationDrawer: React.FC<NavigationDrawerProps> = ({
  open,
  onClose,
}) => {
  const navigate = useNavigate();
  const location = useLocation();

  const handleNavigation = (path: string) => {
    navigate(path);
    onClose();
  };

  return (
    <Drawer
      anchor="left"
      open={open}
      onClose={onClose}
      PaperProps={{
        sx: {
          bgcolor: '#1a1a1a',
          color: '#ffffff',
          width: 250,
          borderRight: '1px solid rgba(255,255,255,0.1)',
        }
      }}
    >
      <Box sx={{ p: 2 }}>
        <Typography 
          variant="h6" 
          sx={{ 
            color: '#ffffff',
            fontWeight: 300,
            opacity: 0.9
          }}
        >
          🏠 Ruuvi Home
        </Typography>
        <Typography 
          variant="caption" 
          sx={{ 
            color: '#ffffff',
            opacity: 0.6,
            display: 'block',
            mt: 0.5
          }}
        >
          Sensor Monitoring
        </Typography>
      </Box>
      
      <Divider sx={{ borderColor: 'rgba(255,255,255,0.1)' }} />
      
      <List sx={{ pt: 1 }}>
        {navigationItems.map((item) => {
          const isActive = location.pathname === item.path;
          
          return (
            <ListItem 
              key={item.path}
              button 
              onClick={() => handleNavigation(item.path)}
              sx={{
                mx: 1,
                borderRadius: 2,
                mb: 0.5,
                bgcolor: isActive ? 'rgba(144, 202, 249, 0.12)' : 'transparent',
                '&:hover': {
                  bgcolor: isActive 
                    ? 'rgba(144, 202, 249, 0.2)' 
                    : 'rgba(255, 255, 255, 0.08)'
                },
                transition: 'background-color 0.2s ease',
              }}
            >
              <ListItemIcon 
                sx={{ 
                  color: isActive ? '#90caf9' : '#ffffff',
                  opacity: isActive ? 1 : 0.7,
                  minWidth: 40
                }}
              >
                {item.icon}
              </ListItemIcon>
              <ListItemText 
                primary={item.text}
                sx={{
                  '& .MuiListItemText-primary': {
                    color: isActive ? '#90caf9' : '#ffffff',
                    opacity: isActive ? 1 : 0.8,
                    fontWeight: isActive ? 500 : 400,
                    fontSize: '0.9rem'
                  }
                }}
              />
            </ListItem>
          );
        })}
      </List>
      
      <Box sx={{ flexGrow: 1 }} />
      
      <Box sx={{ p: 2, borderTop: '1px solid rgba(255,255,255,0.1)' }}>
        <Typography 
          variant="caption" 
          sx={{ 
            color: '#ffffff',
            opacity: 0.5,
            display: 'block'
          }}
        >
          v1.0.0 • Raspberry Pi
        </Typography>
      </Box>
    </Drawer>
  );
};

export default NavigationDrawer;