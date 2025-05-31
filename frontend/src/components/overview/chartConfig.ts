// Chart configuration constants for Overview dashboard
export const SENSOR_COLORS = [
  '#3b82f6', // blue
  '#ef4444', // red  
  '#10b981', // green
  '#f59e0b', // yellow
  '#8b5cf6', // purple
  '#06b6d4', // cyan
  '#f97316', // orange
  '#84cc16', // lime
];

export const CHART_COMMON_OPTIONS = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: {
    mode: 'index' as const,
    intersect: false,
  },
  elements: {
    point: {
      radius: 2,
      borderWidth: 1,
    },
    line: {
      tension: 0.1,
    },
  },
};

export const MAIN_CHART_OPTIONS = {
  ...CHART_COMMON_OPTIONS,
  plugins: {
    legend: {
      position: 'bottom' as const,
      labels: {
        color: '#ffffff',
        padding: 20,
        font: {
          size: 12
        },
        filter: function(legendItem: any) {
          return legendItem.text.includes('Temperature');
        }
      }
    },
    tooltip: {
      backgroundColor: 'rgba(0, 0, 0, 0.8)',
      titleColor: '#ffffff',
      bodyColor: '#ffffff',
      borderColor: 'rgba(255, 255, 255, 0.1)',
      borderWidth: 1,
      callbacks: {
        title: function(context: any) {
          return new Date(context[0].parsed.x).toLocaleString();
        },
        label: function(context: any) {
          const sensor = context.dataset.label.split(' ')[0];
          const metric = context.dataset.label.includes('Temperature') ? 'Temperature' : 'Humidity';
          const unit = metric === 'Temperature' ? '°C' : '%';
          return `${sensor} ${metric}: ${context.parsed.y.toFixed(1)}${unit}`;
        }
      }
    }
  },
  scales: {
    x: {
      type: 'time' as const,
      time: {
        displayFormats: {
          hour: 'HH:mm',
          day: 'MMM dd'
        }
      },
      grid: {
        color: 'rgba(255, 255, 255, 0.1)',
      },
      ticks: {
        color: '#ffffff',
        maxTicksLimit: 8,
      }
    },
    y: {
      type: 'linear' as const,
      display: true,
      position: 'left' as const,
      title: {
        display: true,
        text: 'Temperature (°C)',
        color: '#ffffff',
      },
      grid: {
        color: 'rgba(255, 255, 255, 0.1)',
      },
      ticks: {
        color: '#ffffff',
      }
    },
    y1: {
      type: 'linear' as const,
      display: true,
      position: 'right' as const,
      title: {
        display: true,
        text: 'Humidity (%)',
        color: '#ffffff',
      },
      grid: {
        drawOnChartArea: false,
      },
      ticks: {
        color: '#ffffff',
      }
    }
  }
};

export const PRESSURE_CHART_OPTIONS = {
  ...CHART_COMMON_OPTIONS,
  plugins: {
    legend: {
      position: 'bottom' as const,
      labels: {
        color: '#ffffff',
        padding: 20,
        font: {
          size: 12
        }
      }
    },
    tooltip: {
      backgroundColor: 'rgba(0, 0, 0, 0.8)',
      titleColor: '#ffffff',
      bodyColor: '#ffffff',
      borderColor: 'rgba(255, 255, 255, 0.1)',
      borderWidth: 1,
      callbacks: {
        title: function(context: any) {
          return new Date(context[0].parsed.x).toLocaleString();
        },
        label: function(context: any) {
          const sensor = context.dataset.label.split(' ')[0];
          return `${sensor} Pressure: ${context.parsed.y.toFixed(1)} hPa`;
        }
      }
    }
  },
  scales: {
    x: {
      type: 'time' as const,
      time: {
        displayFormats: {
          hour: 'HH:mm',
          day: 'MMM dd'
        }
      },
      grid: {
        color: 'rgba(255, 255, 255, 0.1)',
      },
      ticks: {
        color: '#ffffff',
        maxTicksLimit: 8,
      }
    },
    y: {
      type: 'linear' as const,
      display: true,
      position: 'left' as const,
      title: {
        display: true,
        text: 'Pressure (hPa)',
        color: '#ffffff',
      },
      grid: {
        color: 'rgba(255, 255, 255, 0.1)',
      },
      ticks: {
        color: '#ffffff',
      }
    }
  }
};

export const TIME_RANGE_OPTIONS = [
  { value: '6h', label: '6 Hours' },
  { value: '24h', label: '24 Hours' },
  { value: '7d', label: '7 Days' },
  { value: '1m', label: '1 Month' },
  { value: '6m', label: '6 Months' },
  { value: '1y', label: '1 Year' },
];