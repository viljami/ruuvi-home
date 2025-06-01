# Database Alternatives to InfluxDB

## Current Issues with InfluxDB

- **Poor Rust Support**: The `influxdb2` crate contains `unwrap()` calls in library code
- **Complex Setup**: Requires InfluxDB server, authentication, bucket management
- **Query Complexity**: Flux query language is verbose and hard to maintain
- **Heavy Resource Usage**: Not ideal for lightweight IoT deployments

## Recommended Alternatives

### 🥇 1. PostgreSQL + TimescaleDB (HIGHLY RECOMMENDED)

**Why it's the best choice:**
- ✅ Excellent Rust support with `sqlx` (zero unwraps, compile-time checked queries)
- ✅ ACID compliance and mature ecosystem
- ✅ Built-in LISTEN/NOTIFY for real-time updates
- ✅ TimescaleDB extension provides excellent time-series performance
- ✅ Standard SQL - no proprietary query language
- ✅ Easy backup/restore and monitoring

**Pros:**
- Most mature and reliable option
- Excellent documentation and community
- Can handle both time-series and relational data
- Built-in aggregation functions
- Automatic partitioning with TimescaleDB
- Industry standard

**Cons:**
- Requires PostgreSQL server setup
- Slightly more storage overhead than specialized time-series DBs

**Performance:**
- Handles millions of sensor readings efficiently
- Automatic compression with TimescaleDB (7+ day old data)
- Continuous aggregates for pre-computed hourly/daily summaries
- Excellent query performance with proper indexing
- Automatic data retention (90 days raw data by default)
- Hypertable partitioning by time for optimal performance

**Real-time Notifications:**
```rust
// PostgreSQL LISTEN/NOTIFY example
sqlx::query("LISTEN sensor_updates").execute(&pool).await?;
let mut listener = PgListener::connect_with(&pool).await?;
listener.listen("sensor_updates").await?;
let notification = listener.recv().await?;
```

### 🥈 2. SQLite (ULTRA LIGHTWEIGHT)

**Why it's great for IoT:**
- ✅ Zero configuration - single file database
- ✅ Perfect Rust support with `sqlx` or `rusqlite`
- ✅ Embedded - no server required
- ✅ ACID compliance
- ✅ Tiny footprint perfect for Raspberry Pi

**Pros:**
- Extremely lightweight (< 1MB binary)
- No network overhead
- Perfect for edge devices
- Reliable and fast for moderate loads
- Built into most systems

**Cons:**
- Single writer limitation
- No built-in time-series optimizations
- Manual cleanup of old data needed

**Best for:**
- Single Raspberry Pi deployments
- < 100,000 readings per day
- Offline-first scenarios

### 🥉 3. Redis (REAL-TIME FOCUSED)

**Why it's excellent for real-time:**
- ✅ Outstanding Rust support with `redis-rs`
- ✅ Built-in Pub/Sub for instant notifications
- ✅ Redis Streams perfect for time-series data
- ✅ In-memory performance
- ✅ Horizontal scaling capabilities

**Pros:**
- Fastest real-time notifications
- Excellent for caching latest readings
- Redis Streams provide time-series capabilities
- Great for high-frequency data
- Built-in data expiration

**Cons:**
- Primarily in-memory (higher RAM usage)
- Requires Redis server
- Less mature time-series features than dedicated solutions

**Best for:**
- High-frequency sensor data (> 1 reading/second)
- Real-time dashboards
- Microservices architectures

### 4. SurrealDB (MODERN RUST-NATIVE)

**Why it's interesting:**
- ✅ Written in Rust - native support
- ✅ Built-in real-time subscriptions
- ✅ Modern query language
- ✅ Multi-model (documents, graphs, time-series)

**Pros:**
- Cutting-edge technology
- Native Rust integration
- Real-time subscriptions built-in
- Can handle complex data relationships
- Single binary deployment

**Cons:**
- Still relatively new (less mature)
- Smaller community
- Less third-party tooling
- Learning curve for new query language

## Comparison Matrix

| Feature | PostgreSQL+TimescaleDB | SQLite | Redis | SurrealDB | InfluxDB |
|---------|------------------------|--------|--------|-----------|----------|
| Rust Support | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| Setup Complexity | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| Real-time Notifications | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| Time-series Performance | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Resource Usage | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| Ecosystem Maturity | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| Query Language | SQL | SQL | Redis Commands | SurrealQL | Flux |
| ACID Compliance | ✅ | ✅ | ❌ | ✅ | ❌ |

## Implementation Examples

### PostgreSQL with sqlx + TimescaleDB (Recommended)

```rust
// Clean, no-unwrap code
let sensors = sqlx::query_as!(
    Event,
    "SELECT * FROM sensor_data WHERE timestamp > $1 ORDER BY timestamp DESC LIMIT $2",
    start_time,
    limit
)
.fetch_all(&pool)
.await?; // Returns Result, no unwraps!

// Time bucketing with TimescaleDB - aggregate data by intervals
let hourly_data = store.get_time_bucketed_data(
    "AA:BB:CC:DD:EE:FF",
    &TimeInterval::Hours(1),
    start_time,
    end_time
).await?;

// Use pre-computed continuous aggregates for better performance
let daily_stats = store.get_daily_aggregates(
    "AA:BB:CC:DD:EE:FF",
    start_time,
    end_time
).await?;

// Real-time notifications
let mut listener = PgListener::connect_with(&pool).await?;
listener.listen("sensor_updates").await?;
while let Ok(notification) = listener.recv().await {
    // Handle new sensor data
}

// Time bucket query with flexible intervals
let temp_trend = sqlx::query!(
    r#"
    SELECT
        time_bucket('15 minutes', timestamp) AS bucket,
        AVG(temperature) AS avg_temp
    FROM sensor_data
    WHERE sensor_mac = $1 AND timestamp > NOW() - INTERVAL '24 hours'
    GROUP BY bucket
    ORDER BY bucket
    "#,
    sensor_mac
)
.fetch_all(&pool)
.await?;
```

### SQLite with sqlx

```rust
// Embedded, zero-config database
let pool = SqlitePool::connect("sqlite:sensors.db").await?;

let sensors = sqlx::query_as!(
    Event,
    "SELECT * FROM sensor_data WHERE sensor_mac = ? ORDER BY timestamp DESC LIMIT ?",
    sensor_mac,
    limit
)
.fetch_all(&pool)
.await?;
```

### Redis with real-time streams

```rust
// Redis Streams for time-series + Pub/Sub for notifications
let mut conn = client.get_multiplexed_async_connection().await?;

// Add to stream
conn.xadd("sensor_data:ABC123", "*", &[
    ("temperature", "22.5"),
    ("timestamp", &timestamp.to_string())
]).await?;

// Real-time subscription
let mut pubsub = conn.into_pubsub();
pubsub.subscribe("sensor_events").await?;
```

## Migration Strategy

### Phase 1: Parallel Implementation
1. Implement new store alongside InfluxDB
2. Write data to both systems
3. Compare results and performance

### Phase 2: API Migration
1. Update API to read from new store
2. Keep InfluxDB as backup
3. Monitor for issues

### Phase 3: Complete Switch
1. Stop writing to InfluxDB
2. Remove InfluxDB dependencies
3. Clean up old code

## Final Recommendation

**For production Ruuvi deployments: PostgreSQL + TimescaleDB**

**Reasons:**
1. **Rock-solid reliability** - PostgreSQL is battle-tested
2. **Perfect Rust support** - sqlx provides compile-time query checking with zero unwraps
3. **Real-time capabilities** - LISTEN/NOTIFY for instant updates
4. **Time-series optimized** - TimescaleDB hypertables, time_bucket(), continuous aggregates
5. **Automatic optimization** - Compression, retention policies, pre-computed aggregates
6. **Future-proof** - Can handle growth and additional features
7. **Easy operations** - Standard tools for backup, monitoring, scaling

**TimescaleDB Features:**
- **Hypertables**: Automatic time-based partitioning
- **time_bucket()**: Flexible time aggregation (minutes, hours, days)
- **Continuous Aggregates**: Pre-computed summaries for fast queries
- **Compression**: Automatic compression of old data (saves 90%+ space)
- **Retention Policies**: Automatic cleanup of old data

**For lightweight/embedded deployments: SQLite**
- Perfect for single Raspberry Pi setups
- Zero maintenance overhead
- Still excellent Rust support

**For high-frequency real-time: Redis**
- When you need sub-second latency
- High-throughput sensor networks
- Microservices architectures

The PostgreSQL + TimescaleDB combination gives you the best of all worlds: reliability, performance, real-time capabilities, and excellent Rust support without any unwraps in the critical path.
