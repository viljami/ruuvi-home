# Ruuvi Home Frontend

The frontend application for Ruuvi Home - a system for monitoring home environment data from Ruuvi Tags.

## Overview

This React application provides a user-friendly interface for:
- Viewing real-time sensor data from your Ruuvi Tags
- Exploring historical data with customizable date ranges
- Visualizing temperature, humidity, air pressure, and other metrics
- Configuring sensor settings and display preferences

## Technologies Used

- **React 18** - Modern UI library
- **TypeScript** - Type-safe JavaScript
- **Chart.js** - Data visualization library
- **Material UI** - Component library for consistent design
- **React Query** - Data fetching and caching
- **React Router** - Navigation and routing
- **Axios** - HTTP client
- **WebSockets** - Real-time data updates

## Quick Start

### Prerequisites

- Node.js 16+ and npm

### Installation

```bash
# Install dependencies
npm install

# Start development server
npm start
```

The application will be available at http://localhost:3000

## Development

### Project Structure

```
src/
├── components/       # Reusable UI components
├── services/         # API clients and data services
├── views/            # Page components
├── hooks/            # Custom React hooks
├── types/            # TypeScript type definitions
├── utils/            # Helper functions
├── App.tsx           # Main application component
└── index.tsx         # Application entry point
```

### Available Scripts

- `npm start` - Start development server
- `npm test` - Run tests
- `npm run build` - Build for production
- `npm run lint` - Check for code issues
- `npm run format` - Format code with Prettier

## API Integration

The frontend communicates with the Ruuvi Home backend through:

1. **REST API** - For historical data and configuration
2. **WebSockets** - For real-time sensor updates

### API Configuration

API endpoints can be configured in `.env` files:

```
# .env.development
REACT_APP_API_URL=http://localhost:8080
REACT_APP_WS_URL=ws://localhost:8080/ws
```

## Building for Production

```bash
npm run build
```

This creates an optimized production build in the `build` folder that can be served by any static file server.

## Docker

The application can be built and run using Docker:

```bash
# Build Docker image
docker build -t ruuvi-home-frontend -f ../docker/frontend.Dockerfile .

# Run container
docker run -p 3000:80 ruuvi-home-frontend
```

## Contributing

1. Follow the established project structure
2. Write clean, maintainable code with appropriate comments
3. Include TypeScript types for all components and functions
4. Write tests for new features
5. Format code before committing

## License

MIT