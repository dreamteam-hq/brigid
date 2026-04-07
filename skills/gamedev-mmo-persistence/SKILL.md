---
name: gamedev-mmo-persistence
description: >
  MMO persistence layer — database schema patterns for players, inventories,
  guilds, quests, and achievements; account/auth systems; persistent world state;
  social systems (friends, parties, guilds, trade); chat architecture; leaderboards
  with Redis; and zero-downtime live data migration. Load when designing MMO
  databases, implementing account systems, building guild/social features, adding
  chat, creating leaderboards, or migrating live game data. Triggers on "MMO
  database", "game database schema", "player inventory", "guild system", "game
  chat", "leaderboard", "MMO persistence", "game account system", "world state",
  or "game data migration".
triggers:
  - MMO database
  - game database schema
  - player inventory
  - guild system
  - game chat
  - leaderboard
  - MMO persistence
  - game account system
  - world state
  - game data migration
version: "1.0.0"
---

# MMO Persistence Layer

Design and implement the data persistence backbone for massively multiplayer games — from player accounts through world state to social systems and live migration. This skill covers schema design, not server networking (load `gamedev-server-architecture`) or client sync (load `gamedev-multiplayer`). For economy-specific persistence (currency balancing, auction houses, sink/faucet), load `game-economy-design`.

## Database Technology Selection

Choosing the right storage engine is the first architectural decision. Most MMOs use a polyglot approach.

### Decision Table

| Data Type | Recommended Store | Rationale |
|-----------|-------------------|-----------|
| Player accounts, characters | PostgreSQL / MySQL | ACID transactions, relational integrity |
| Inventory, equipment | PostgreSQL (JSONB) or relational | Flexible schema for item properties |
| Guild structure, social graph | PostgreSQL + Redis cache | Relational for truth, cache for hot reads |
| Chat messages | Cassandra / ScyllaDB | Append-heavy, time-ordered, high throughput |
| Session state, presence | Redis | Volatile, sub-ms reads, TTL expiry |
| Leaderboards | Redis Sorted Sets | O(log N) rank operations |
| World/zone state | PostgreSQL + periodic snapshots | Transactional consistency for world saves |
| Quest progress, achievements | PostgreSQL | Relational joins against quest definitions |
| Analytics, telemetry | ClickHouse / TimescaleDB | Time-series, columnar compression |
| Audit/transaction log | Append-only table or Kafka | Immutable, chronological, compliance |

### Connection Pooling

Never let game servers open unbounded database connections. Use a connection pooler (PgBouncer for PostgreSQL) between game servers and the database.

```
Game Server (100 logical connections)
  → PgBouncer (transaction pooling, 20 physical connections)
    → PostgreSQL (max_connections = 200 across all poolers)
```

Target: 10-20 physical connections per game server process.

## Player and Account Schema

**Design principle — Separate identity from state:** Accounts represent the human (auth, billing, bans). Characters represent in-game entities (stats, position, inventory). An account can have multiple characters; admin actions (bans, suspensions) target the account, not individual characters.

Key tables: `accounts`, `characters`, `character_stats`.

Base stats in a normalized table. Computed stats (with gear bonuses, buffs) are derived at runtime, never persisted.

See [references/schema-and-sql.md](references/schema-and-sql.md) for full DDL.

## Account and Authentication

### Password Hashing

Use argon2id exclusively. Do not use bcrypt, scrypt, or SHA-256.

```
Algorithm: argon2id
Memory:    64 MiB (m=65536)
Iterations: 3 (t=3)
Parallelism: 4 (p=4)
Salt:      16 bytes, cryptographically random
Output:    32 bytes
```

Re-hash passwords on login if stored parameters are weaker than current policy. This silently upgrades legacy hashes.

### Session Management

Store a SHA-256 hash of the session token, not the token itself. If the sessions table leaks, attackers cannot forge sessions. Tokens expire after 24 hours of inactivity.

### Ban Types

- **Temporary**: Account locked for a duration. Player sees a ban message with expiry.
- **Permanent**: Account locked indefinitely. Requires manual appeal review.
- **Shadow**: Account can still log in but is invisible to other players. Use sparingly for investigation (catching bot networks).

Check bans at login AND periodically during play (a ban issued while a player is online should take effect within minutes).

See [references/schema-and-sql.md](references/schema-and-sql.md) for session and ban table schemas.

## Inventory System

### Slot-Based vs Bag-Based

**Slot-based** (fixed grid): Each item occupies a numbered slot. Simple, predictable capacity. Use for equipment slots and fixed-size bags.

**Bag-based** (expandable): Players acquire more bags. More complex but creates a monetizable progression. Most MMOs use bag-based for general inventory with slot-based for equipment.

### Item Transactions

Every item movement (loot, trade, mail, destroy, vendor) must be an atomic database transaction. Always log to an audit table for dispute resolution and exploit detection.

See [references/schema-and-sql.md](references/schema-and-sql.md) for `item_templates`, `inventory`, trade transaction SQL, and `inventory_audit` schema.

## Quest Progress and Achievements

Quest state machine: `UNAVAILABLE → AVAILABLE → ACCEPTED → IN_PROGRESS → COMPLETED → TURNED_IN` (ABANDONED returns to AVAILABLE with cooldown).

Track achievement progress incrementally. Maintain an in-memory map of `event_type → [relevant_achievement_ids]` — check only those on each game event, not all achievements.

See [references/schema-and-sql.md](references/schema-and-sql.md) for `quest_templates`, `quest_progress`, `achievement_templates`, and `character_achievements` schemas.

## Persistent World State

### World Save Strategy

MMO world state is too large to save on every change. Use a tiered persistence strategy:

| Tier | What | Frequency | Method |
|------|------|-----------|--------|
| Critical | Player inventory, gold, equipment | Every transaction | Synchronous DB write within transaction |
| Important | Character position, quest progress | Every 30-60 seconds | Batched async writes |
| Periodic | Zone state, NPC state | Every 5 minutes | Bulk upsert per zone |
| Snapshot | Full world state | Every 30 minutes | pg_dump or logical replication to backup |

**Dirty tracking**: Only persist entities that changed since last save. Each entity carries a `dirty` flag set by mutation and cleared on save. A save pass batches dirty entities and executes bulk upserts.

### Server-Side Timers

Store timers in a dedicated table (respawn, cooldowns, auction expiry, buff durations). A timer worker queries `fires_at <= now() AND NOT processed`, processes each timer, and marks it processed on a 1-second loop. For high-timer-volume games (10,000+ concurrent timers), use Redis sorted sets instead of PostgreSQL polling.

### Crash Recovery

Worst-case data loss = save interval of each tier. Critical data has zero loss (synchronous saves). Position may roll back up to 60 seconds. Zone state may roll back up to 5 minutes.

On restart: load zone state → load character positions → rebuild timer queue → resume NPC state → players reconnect.

See [references/schema-and-sql.md](references/schema-and-sql.md) for `zone_state`, `npc_state`, `game_timers`, and bulk character position upsert.

## Social Systems

### Friend Lists and Presence

Use canonical ordering constraint (`account_id_1 < account_id_2`) so friendship A→B and B→A store as one row.

Track online presence in Redis (not the database): `HSET presence:{account_id}` with 2-minute TTL refreshed by heartbeat.

Blocks suppress: friend requests, party invites, guild invites, trade requests, direct messages, and /who searches. Cache the block list in Redis on login.

### Party/Group System

Parties are ephemeral — store in Redis, not the database. When the leader disconnects, promote the longest-active member. For raid groups (which span multiple play sessions), persist to the database with a weekly reset expiry.

### Guild System

Key tables: `guilds`, `guild_ranks`, `guild_members`, `guild_bank_tabs`, `guild_bank_items`, `guild_bank_log`.

**Guild permissions bitfield:**

| Bit | Permission | Value |
|-----|-----------|-------|
| 0 | INVITE_MEMBERS | 1 |
| 1 | KICK_MEMBERS | 2 |
| 2 | PROMOTE_MEMBERS | 4 |
| 3 | EDIT_MOTD | 8 |
| 4 | WITHDRAW_BANK_GOLD | 16 |
| 5 | WITHDRAW_BANK_ITEMS | 32 |
| 6 | DEPOSIT_BANK_ITEMS | 64 |
| 7 | EDIT_RANKS | 128 |
| 8 | DECLARE_WAR | 256 |
| 9 | MANAGE_EVENTS | 512 |
| 10 | EDIT_DESCRIPTION | 1024 |

**Default ranks:** Guild Master (2047), Officer (543), Veteran (577), Member (64), Initiate (0).

Set per-rank daily withdrawal limits. Log every transaction. Guild leaders can view the bank log to detect theft.

### Trade System

Direct player-to-player trading uses a two-phase commit:
1. **Offer**: Both sides place items/gold, see each other's offers
2. **Confirm**: Both click Accept; server validates inventories still contain offered items; executes atomic swap

If either player modifies their offer after the other has accepted, reset both accepts. This prevents bait-and-switch scams.

Add trade cooldowns (30 seconds) to prevent automated gold laundering. Flag trades with extreme value asymmetry for review.

See [references/schema-and-sql.md](references/schema-and-sql.md) for full social system schemas.

## Chat Architecture

### Channel Types

| Channel | Scope | Persistence | Rate Limit |
|---------|-------|-------------|------------|
| Say | 50m radius | None | 5/sec |
| Yell | 200m radius | None | 1/sec |
| Zone | Entire zone | None | 2/sec |
| World/Global | All zones | None | 1/sec |
| Party | Party members | Session only | 10/sec |
| Guild | Guild members | 7 days | 5/sec |
| Whisper (DM) | Two players | 30 days | 5/sec |
| Trade | Designated channel | None | 1/5sec |
| System | Server → all players | Permanent log | N/A |

### Message Routing

For multi-server deployments, use Redis Pub/Sub for cross-server chat delivery. Each game server subscribes to channels relevant to its player population.

### Profanity Filter Tiers

```
Tier 1 (Mild):    Minor profanity → replace with "***", deliver message
Tier 2 (Moderate): Slurs, harassment → block message, warn sender
Tier 3 (Severe):  Threats, doxxing → block message, auto-mute 10min, alert moderator
```

Store filter lists in Redis for hot reloading without server restart.

**Rate limiting**: Use Redis sliding window per character per channel. Drop messages silently when rate exceeded — this discourages spam more effectively than error messages.

For high-volume games, use Cassandra / ScyllaDB instead of PostgreSQL for chat storage (partition by channel and time bucket). TTL by channel type.

See [references/schema-and-sql.md](references/schema-and-sql.md) for `chat_messages` schema.

## Leaderboards

### Redis Sorted Sets

O(log N) rank queries for any leaderboard size. `ZADD` to update score. `ZREVRANK` for rank. `ZREVRANGE` for top N.

### Leaderboard Types

| Leaderboard | Score Source | Reset Cadence | Sort |
|-------------|-------------|---------------|------|
| PvP Rating | ELO/Glicko-2 | Seasonal (8-12 weeks) | Descending |
| Arena Wins | Win count | Seasonal | Descending |
| Achievement Points | Total achievement score | Never | Descending |
| Dungeon Speed | Clear time in seconds | Weekly or per-patch | Ascending |
| Crafting | Items crafted count | Never | Descending |
| Guild Level | Guild XP total | Never | Descending |

At season end: snapshot to PostgreSQL → distribute rewards → delete Redis sorted set → create new set.

### Anti-Cheat Validation

Never trust client-reported scores. All leaderboard updates must originate from server-side game logic. Rate-limit score updates and flag statistical outliers.

See [references/schema-and-sql.md](references/schema-and-sql.md) for Redis commands and `leaderboard_snapshots` schema.

## Data Migration for Live Games

### The Challenge

MMO databases cannot have maintenance windows. Schema changes must be backward-compatible and deployed without downtime.

### Expand-Contract Pattern

```
Phase 1: EXPAND   — Add new columns/tables. Deploy code that writes to both old and new.
Phase 2: MIGRATE  — Backfill new columns from old data (batched, throttled). Verify integrity.
Phase 3: CONTRACT — Remove old columns/tables. Deploy code that only uses new schema.
```

### Dangerous Operations (Never Run on Live Tables)

| Operation | Risk | Safe Alternative |
|-----------|------|------------------|
| `ADD COLUMN ... NOT NULL` (without default) | Full table rewrite, exclusive lock | Add nullable first, backfill, then set NOT NULL |
| `ALTER COLUMN TYPE` | Full table rewrite | Add new column, backfill, swap in code, drop old |
| `CREATE INDEX` | Blocks writes on large tables | `CREATE INDEX CONCURRENTLY` (PostgreSQL) |
| `DROP COLUMN` | Irreversible | Rename to `_deprecated_`, drop after verification |
| `TRUNCATE TABLE` | Instant data loss | Batched DELETE with WHERE clause |

See [references/schema-and-sql.md](references/schema-and-sql.md) for expand-contract SQL examples, batched backfill Python, and `schema_migrations` table.

## Anti-Patterns

| Anti-Pattern | Why It Fails | Better Approach |
|-------------|-------------|-----------------|
| Storing passwords as MD5/SHA-256 | Crackable with GPU brute force | argon2id with per-user salt, 64 MiB memory cost |
| Client-side inventory validation | Players duplicate items via modified client | All inventory operations are server-authoritative, atomic DB transactions |
| Saving all state every tick | 10,000 players × 60 Hz = 600,000 writes/sec | Tiered persistence: critical sync, position batched, zone periodic |
| Single global database | Cross-continental latency, single point of failure | Regional databases with cross-region replication for accounts only |
| Unbounded friend/block lists | O(N) queries on every social check | Cap at 200 friends, 500 blocks; paginate all social queries |
| No audit logging | Cannot investigate item duplication or gold exploits | Append-only audit log for every currency and item transaction |
| Storing session tokens in plaintext | Database leak = instant account takeover | Store SHA-256 of token; compare hashes on validation |
| Mutable leaderboard scores from client | Players submit fake scores | All scores computed server-side; leaderboard ZADD from authoritative game logic only |
| Schema changes with table locks | Minutes of downtime on ALTER TABLE | Expand-contract migrations; `CREATE INDEX CONCURRENTLY` |
| Polling for chat messages | N players × 10 QPS database load | Redis Pub/Sub for real-time delivery; DB only for history |
| No trade cooldowns or value checks | Gold laundering via rapid trades | 30-second cooldown; flag asymmetric trades for review |
| Storing computed stats in DB | Stale data bugs on gear changes | Persist base stats only; compute effective stats at runtime |

## Cross-References

| Skill | When to Load |
|-------|-------------|
| `gamedev-server-architecture` | Server hosting model, tick loops, TCP/UDP networking, connection lifecycle |
| `gamedev-multiplayer` | Client-side networking, state synchronization, lag compensation, Godot multiplayer API |
| `game-economy-design` | Currency balancing, sink/faucet modeling, auction house design, inflation control |
| `gamedev-ecs` | Entity Component System architecture for organizing game state in memory before persistence |
| `dotnet-architecture` | Clean Architecture patterns for structuring the persistence layer in .NET game servers |
