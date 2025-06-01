FROM python:3.9-alpine

WORKDIR /app

# Copy requirements first for better layer caching
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy simulator script and tests
COPY simulator.py .
COPY tests/ ./tests/

# Make simulator executable
RUN chmod +x simulator.py

# Environment variables with defaults
ENV MQTT_BROKER=mosquitto
ENV MQTT_PORT=1883
ENV MQTT_TOPIC=ruuvi/gateway/data
ENV PUBLISH_INTERVAL=5.0
ENV NUM_SENSORS=3
ENV GATEWAY_MAC=AA:BB:CC:DD:EE:FF
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Run the simulator
CMD ["python", "simulator.py"]
