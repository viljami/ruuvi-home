# Ruuvi Data on Raspberry Pi

Collect Ruuvi Tag data send by Ruuvi Gateway to TimescaleDB on Raspberry Pi.

In between from (mosquitto) mqtt to TimescaleDB is a Rust program that decodes the Ruuvi Tag data and sends it to TimescaleDB.

## 🚀 Development Quick Start

**Essential commands:**
```bash
make dev          # Full development workflow (lint + test)
make help         # Show all available commands
```

**⚠️ CRITICAL:** Always use `make lint` instead of `cargo clippy` directly!

📖 **Complete development rules:** See [AI_CODING_GUIDELINES.md](../AI_CODING_GUIDELINES.md)
