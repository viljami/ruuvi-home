import React from 'react';
import {
  Box,
  Alert,
  AlertTitle,
  Typography,
  Chip,
  IconButton,
  Collapse,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  Tooltip,
} from '@mui/material';
import {
  BatteryAlert,
  SignalWifiStatusbarConnectedNoInternet4,
  ExpandMore,
  ExpandLess,
  Visibility,
} from '@mui/icons-material';

interface SensorReading {
  sensor_mac: string;
  battery: number;
  rssi: number;
  temperature: number;
  humidity: number;
  pressure: number;
  timestamp: number;
}

interface WarningStatusProps {
  sensors: SensorReading[];
  onSensorClick?: (sensorMac: string) => void;
  formatMacAddress?: (mac: string) => string;
  className?: string;
}

interface WarningData {
  type: 'battery' | 'signal';
  title: string;
  description: string;
  sensors: SensorReading[];
  icon: React.ReactElement;
  severity: 'warning' | 'error';
}

const BATTERY_CRITICAL_THRESHOLD = 2400; // mV
const BATTERY_LOW_THRESHOLD = 2700; // mV
const SIGNAL_POOR_THRESHOLD = -80; // dBm
const SIGNAL_CRITICAL_THRESHOLD = -90; // dBm

export const WarningStatus: React.FC<WarningStatusProps> = ({
  sensors,
  onSensorClick,
  formatMacAddress = (mac) => mac.toUpperCase(),
  className,
}) => {
  const [expandedWarnings, setExpandedWarnings] = React.useState<Set<string>>(new Set());

  const toggleWarningExpansion = (warningType: string) => {
    const newExpanded = new Set(expandedWarnings);
    if (newExpanded.has(warningType)) {
      newExpanded.delete(warningType);
    } else {
      newExpanded.add(warningType);
    }
    setExpandedWarnings(newExpanded);
  };

  const criticalBatterySensors = sensors.filter(s => s.battery < BATTERY_CRITICAL_THRESHOLD);
  const lowBatterySensors = sensors.filter(s => 
    s.battery >= BATTERY_CRITICAL_THRESHOLD && s.battery < BATTERY_LOW_THRESHOLD
  );
  const criticalSignalSensors = sensors.filter(s => s.rssi < SIGNAL_CRITICAL_THRESHOLD);
  const poorSignalSensors = sensors.filter(s => 
    s.rssi >= SIGNAL_CRITICAL_THRESHOLD && s.rssi < SIGNAL_POOR_THRESHOLD
  );

  const warnings: WarningData[] = [];

  if (criticalBatterySensors.length > 0) {
    warnings.push({
      type: 'battery',
      title: 'Critical Battery Level',
      description: `${criticalBatterySensors.length} sensor(s) have critically low battery`,
      sensors: criticalBatterySensors,
      icon: <BatteryAlert />,
      severity: 'error',
    });
  }

  if (lowBatterySensors.length > 0) {
    warnings.push({
      type: 'battery',
      title: 'Low Battery Level',
      description: `${lowBatterySensors.length} sensor(s) have low battery`,
      sensors: lowBatterySensors,
      icon: <BatteryAlert />,
      severity: 'warning',
    });
  }

  if (criticalSignalSensors.length > 0) {
    warnings.push({
      type: 'signal',
      title: 'Critical Signal Strength',
      description: `${criticalSignalSensors.length} sensor(s) have very poor signal`,
      sensors: criticalSignalSensors,
      icon: <SignalWifiStatusbarConnectedNoInternet4 />,
      severity: 'error',
    });
  }

  if (poorSignalSensors.length > 0) {
    warnings.push({
      type: 'signal',
      title: 'Poor Signal Strength',
      description: `${poorSignalSensors.length} sensor(s) have weak signal`,
      sensors: poorSignalSensors,
      icon: <SignalWifiStatusbarConnectedNoInternet4 />,
      severity: 'warning',
    });
  }

  if (warnings.length === 0) {
    return (
      <Alert 
        severity="success" 
        sx={{ 
          bgcolor: 'rgba(76, 175, 80, 0.1)',
          border: '1px solid rgba(76, 175, 80, 0.2)',
          color: '#ffffff',
          '& .MuiAlert-icon': {
            color: '#4caf50'
          }
        }}
      >
        <AlertTitle>All Systems Normal</AlertTitle>
        All sensors are operating within normal parameters.
      </Alert>
    );
  }

  const renderSensorList = (sensors: SensorReading[], warningType: string) => {
    const isExpanded = expandedWarnings.has(warningType);
    
    return (
      <Box>
        <Box 
          display="flex" 
          alignItems="center" 
          gap={1}
          sx={{ cursor: 'pointer' }}
          onClick={() => toggleWarningExpansion(warningType)}
        >
          <Typography variant="body2" sx={{ flexGrow: 1 }}>
            {sensors.length} affected sensor{sensors.length > 1 ? 's' : ''}
          </Typography>
          <IconButton size="small" sx={{ color: 'inherit' }}>
            {isExpanded ? <ExpandLess /> : <ExpandMore />}
          </IconButton>
        </Box>
        
        <Collapse in={isExpanded}>
          <List dense sx={{ mt: 1 }}>
            {sensors.map((sensor) => (
              <ListItem
                key={sensor.sensor_mac}
                sx={{
                  bgcolor: 'rgba(255, 255, 255, 0.05)',
                  borderRadius: 1,
                  mb: 0.5,
                  '&:hover': {
                    bgcolor: 'rgba(255, 255, 255, 0.1)',
                  }
                }}
              >
                <ListItemIcon sx={{ minWidth: 36 }}>
                  {warningType.includes('battery') ? <BatteryAlert /> : <SignalWifiStatusbarConnectedNoInternet4 />}
                </ListItemIcon>
                <ListItemText
                  primary={formatMacAddress(sensor.sensor_mac)}
                  secondary={
                    <Box display="flex" gap={1} alignItems="center">
                      {warningType.includes('battery') && (
                        <Chip
                          label={`${sensor.battery}mV`}
                          size="small"
                          variant="outlined"
                          sx={{ 
                            fontSize: '0.7rem',
                            height: 20,
                            color: 'inherit',
                            borderColor: 'currentColor'
                          }}
                        />
                      )}
                      {warningType.includes('signal') && (
                        <Chip
                          label={`${sensor.rssi}dBm`}
                          size="small"
                          variant="outlined"
                          sx={{ 
                            fontSize: '0.7rem',
                            height: 20,
                            color: 'inherit',
                            borderColor: 'currentColor'
                          }}
                        />
                      )}
                      <Typography variant="caption" sx={{ opacity: 0.7 }}>
                        {new Date(sensor.timestamp * 1000).toLocaleTimeString()}
                      </Typography>
                    </Box>
                  }
                />
                {onSensorClick && (
                  <Tooltip title="View Sensor Details">
                    <IconButton
                      size="small"
                      onClick={(e) => {
                        e.stopPropagation();
                        onSensorClick(sensor.sensor_mac);
                      }}
                      sx={{ color: 'inherit', opacity: 0.7, '&:hover': { opacity: 1 } }}
                    >
                      <Visibility fontSize="small" />
                    </IconButton>
                  </Tooltip>
                )}
              </ListItem>
            ))}
          </List>
        </Collapse>
      </Box>
    );
  };

  return (
    <Box className={className}>
      {warnings.map((warning, index) => {
        const warningKey = `${warning.type}-${warning.severity}-${index}`;
        
        return (
          <Alert
            key={warningKey}
            severity={warning.severity}
            icon={warning.icon}
            sx={{
              mb: 2,
              bgcolor: warning.severity === 'error' 
                ? 'rgba(244, 67, 54, 0.1)' 
                : 'rgba(255, 152, 0, 0.1)',
              border: warning.severity === 'error' 
                ? '1px solid rgba(244, 67, 54, 0.2)' 
                : '1px solid rgba(255, 152, 0, 0.2)',
              color: '#ffffff',
              '& .MuiAlert-icon': {
                color: warning.severity === 'error' ? '#f44336' : '#ff9800'
              }
            }}
          >
            <AlertTitle>{warning.title}</AlertTitle>
            <Typography variant="body2" sx={{ mb: 1 }}>
              {warning.description}
            </Typography>
            {renderSensorList(warning.sensors, warningKey)}
          </Alert>
        );
      })}
    </Box>
  );
};

export default WarningStatus;