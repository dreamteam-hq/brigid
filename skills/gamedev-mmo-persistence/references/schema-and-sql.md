# Schema and SQL — MMO Persistence

## Player and Account Schema

```sql
-- Accounts: one per human player, auth boundary
CREATE TABLE accounts (
    account_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           TEXT UNIQUE NOT NULL,
    email_verified  BOOLEAN DEFAULT FALSE,
    password_hash   TEXT NOT NULL,          -- argon2id
    totp_secret     BYTEA,                 -- optional 2FA
    created_at      TIMESTAMPTZ DEFAULT now(),
    last_login      TIMESTAMPTZ,
    banned_until    TIMESTAMPTZ,            -- NULL = not banned
    ban_reason      TEXT,
    account_flags   INTEGER DEFAULT 0       -- bitfield: admin, muted, etc.
);

-- Characters: multiple per account
CREATE TABLE characters (
    character_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id      UUID NOT NULL REFERENCES accounts(account_id),
    name            TEXT UNIQUE NOT NULL,
    class           SMALLINT NOT NULL,
    level           SMALLINT DEFAULT 1,
    experience      BIGINT DEFAULT 0,
    zone_id         INTEGER NOT NULL DEFAULT 1,
    position_x      REAL NOT NULL DEFAULT 0,
    position_y      REAL NOT NULL DEFAULT 0,
    position_z      REAL NOT NULL DEFAULT 0,
    rotation        REAL NOT NULL DEFAULT 0,
    health          INTEGER NOT NULL,
    mana            INTEGER NOT NULL,
    gold            BIGINT DEFAULT 0,
    play_time_sec   BIGINT DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT now(),
    last_played     TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ              -- soft delete
);

CREATE INDEX idx_characters_account ON characters(account_id);
CREATE INDEX idx_characters_zone ON characters(zone_id);

CREATE TABLE character_stats (
    character_id    UUID PRIMARY KEY REFERENCES characters(character_id),
    strength        SMALLINT NOT NULL DEFAULT 10,
    dexterity       SMALLINT NOT NULL DEFAULT 10,
    intelligence    SMALLINT NOT NULL DEFAULT 10,
    constitution    SMALLINT NOT NULL DEFAULT 10,
    wisdom          SMALLINT NOT NULL DEFAULT 10,
    charisma        SMALLINT NOT NULL DEFAULT 10,
    stat_points     SMALLINT DEFAULT 0
);
```

## Session Management

```sql
CREATE TABLE sessions (
    session_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id      UUID NOT NULL REFERENCES accounts(account_id),
    token_hash      BYTEA NOT NULL,          -- SHA-256 of the session token
    ip_address      INET,
    user_agent      TEXT,
    created_at      TIMESTAMPTZ DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked         BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_sessions_account ON sessions(account_id);
CREATE INDEX idx_sessions_expires ON sessions(expires_at);
```

## Ban System

```sql
CREATE TABLE bans (
    ban_id          SERIAL PRIMARY KEY,
    account_id      UUID NOT NULL REFERENCES accounts(account_id),
    banned_by       UUID REFERENCES accounts(account_id),
    reason          TEXT NOT NULL,
    evidence        JSONB,
    ban_type        TEXT NOT NULL CHECK (ban_type IN ('temporary', 'permanent', 'shadow')),
    starts_at       TIMESTAMPTZ DEFAULT now(),
    ends_at         TIMESTAMPTZ,
    appealed        BOOLEAN DEFAULT FALSE,
    appeal_result   TEXT,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_bans_account ON bans(account_id);
```

## Inventory System

```sql
-- Item definitions: static data, loaded at server start
CREATE TABLE item_templates (
    item_id         INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    item_type       SMALLINT NOT NULL,
    rarity          SMALLINT NOT NULL,
    max_stack        INTEGER DEFAULT 1,
    base_stats      JSONB,
    level_req       SMALLINT DEFAULT 1,
    class_req       SMALLINT[],
    sell_price      INTEGER DEFAULT 0,
    flags           INTEGER DEFAULT 0
);

-- Player inventory: instance data
CREATE TABLE inventory (
    inventory_id    BIGSERIAL PRIMARY KEY,
    character_id    UUID NOT NULL REFERENCES characters(character_id),
    item_id         INTEGER NOT NULL REFERENCES item_templates(item_id),
    slot_type       SMALLINT NOT NULL,       -- bag, equipped, bank, mail
    slot_index      SMALLINT NOT NULL,
    quantity         INTEGER DEFAULT 1,
    durability      SMALLINT,
    enchantments    JSONB,
    created_at      TIMESTAMPTZ DEFAULT now(),
    bound           BOOLEAN DEFAULT FALSE,
    UNIQUE(character_id, slot_type, slot_index)
);

CREATE INDEX idx_inventory_character ON inventory(character_id);

-- Trading items between two players
BEGIN;
DELETE FROM inventory WHERE inventory_id = $1 AND character_id = $seller_id;
INSERT INTO inventory (character_id, item_id, slot_type, slot_index, quantity, bound)
VALUES ($buyer_id, $item_id, 0, $next_slot, $quantity, FALSE);
UPDATE characters SET gold = gold - $price WHERE character_id = $buyer_id AND gold >= $price;
UPDATE characters SET gold = gold + $price WHERE character_id = $seller_id;
COMMIT;

CREATE TABLE inventory_audit (
    audit_id        BIGSERIAL PRIMARY KEY,
    character_id    UUID NOT NULL,
    action          TEXT NOT NULL,
    item_id         INTEGER NOT NULL,
    quantity        INTEGER NOT NULL,
    counterparty_id UUID,
    gold_delta      BIGINT,
    metadata        JSONB,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_audit_character ON inventory_audit(character_id);
CREATE INDEX idx_audit_created ON inventory_audit(created_at);
```

## Quest and Achievement Schema

```sql
CREATE TABLE quest_templates (
    quest_id        INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    description     TEXT,
    quest_type      SMALLINT NOT NULL,
    level_req       SMALLINT DEFAULT 1,
    prerequisites   INTEGER[],
    objectives      JSONB NOT NULL,
    rewards         JSONB NOT NULL,
    cooldown_sec    INTEGER
);

CREATE TABLE quest_progress (
    character_id    UUID NOT NULL REFERENCES characters(character_id),
    quest_id        INTEGER NOT NULL REFERENCES quest_templates(quest_id),
    state           SMALLINT NOT NULL DEFAULT 1,
    objective_progress JSONB,
    accepted_at     TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    turned_in_at    TIMESTAMPTZ,
    PRIMARY KEY (character_id, quest_id)
);

CREATE TABLE achievement_templates (
    achievement_id  INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    description     TEXT,
    category        TEXT NOT NULL,
    criteria        JSONB NOT NULL,
    points          INTEGER DEFAULT 10,
    reward_title    TEXT,
    reward_item_id  INTEGER
);

CREATE TABLE character_achievements (
    character_id    UUID NOT NULL REFERENCES characters(character_id),
    achievement_id  INTEGER NOT NULL REFERENCES achievement_templates(achievement_id),
    progress        INTEGER DEFAULT 0,
    completed       BOOLEAN DEFAULT FALSE,
    completed_at    TIMESTAMPTZ,
    PRIMARY KEY (character_id, achievement_id)
);
```

## World State Schema

```sql
CREATE TABLE zone_state (
    zone_id         INTEGER NOT NULL,
    entity_type     SMALLINT NOT NULL,
    entity_id       INTEGER NOT NULL,
    state_data      JSONB NOT NULL,
    updated_at      TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (zone_id, entity_type, entity_id)
);

CREATE TABLE npc_state (
    npc_instance_id BIGINT PRIMARY KEY,
    npc_template_id INTEGER NOT NULL,
    zone_id         INTEGER NOT NULL,
    position_x      REAL NOT NULL,
    position_y      REAL NOT NULL,
    position_z      REAL NOT NULL,
    health          INTEGER NOT NULL,
    state_data      JSONB,
    respawn_at      TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE game_timers (
    timer_id        BIGSERIAL PRIMARY KEY,
    timer_type      TEXT NOT NULL,
    target_type     TEXT NOT NULL,
    target_id       TEXT NOT NULL,
    fires_at        TIMESTAMPTZ NOT NULL,
    payload         JSONB,
    processed       BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_timers_pending ON game_timers(fires_at) WHERE NOT processed;

-- Bulk character position save (batched)
INSERT INTO characters (character_id, zone_id, position_x, position_y, position_z, rotation, last_played)
VALUES ($1, $2, $3, $4, $5, $6, now()), ($7, $8, $9, $10, $11, $12, now())
ON CONFLICT (character_id) DO UPDATE SET
    zone_id = EXCLUDED.zone_id,
    position_x = EXCLUDED.position_x,
    position_y = EXCLUDED.position_y,
    position_z = EXCLUDED.position_z,
    rotation = EXCLUDED.rotation,
    last_played = EXCLUDED.last_played;
```

## Social System Schema

```sql
CREATE TABLE friendships (
    account_id_1    UUID NOT NULL REFERENCES accounts(account_id),
    account_id_2    UUID NOT NULL REFERENCES accounts(account_id),
    created_at      TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (account_id_1, account_id_2),
    CHECK (account_id_1 < account_id_2)  -- canonical ordering prevents duplicates
);

CREATE TABLE friend_requests (
    request_id      BIGSERIAL PRIMARY KEY,
    from_account    UUID NOT NULL REFERENCES accounts(account_id),
    to_account      UUID NOT NULL REFERENCES accounts(account_id),
    message         TEXT,
    status          SMALLINT DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT now(),
    UNIQUE(from_account, to_account)
);

CREATE TABLE blocks (
    blocker_id      UUID NOT NULL REFERENCES accounts(account_id),
    blocked_id      UUID NOT NULL REFERENCES accounts(account_id),
    created_at      TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id)
);

-- Redis presence (not SQL)
-- HSET presence:{account_id} status "online" zone_id "5" character "Thorin" last_seen {timestamp}
-- EXPIRE presence:{account_id} 120

-- Redis party (ephemeral — not persisted to DB)
-- HSET party:{party_id} leader {character_id} created_at {timestamp}
-- SADD party:{party_id}:members {char_id_1} {char_id_2}
-- SET character:{character_id}:party {party_id}

CREATE TABLE raid_groups (
    raid_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT,
    leader_id       UUID NOT NULL REFERENCES characters(character_id),
    instance_id     INTEGER,
    created_at      TIMESTAMPTZ DEFAULT now(),
    expires_at      TIMESTAMPTZ
);

CREATE TABLE raid_members (
    raid_id         UUID NOT NULL REFERENCES raid_groups(raid_id),
    character_id    UUID NOT NULL REFERENCES characters(character_id),
    role            SMALLINT,
    joined_at       TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (raid_id, character_id)
);

CREATE TABLE guilds (
    guild_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT UNIQUE NOT NULL,
    tag             TEXT UNIQUE,
    leader_id       UUID NOT NULL REFERENCES characters(character_id),
    motd            TEXT,
    description     TEXT,
    level           SMALLINT DEFAULT 1,
    experience      BIGINT DEFAULT 0,
    bank_gold       BIGINT DEFAULT 0,
    max_members     INTEGER DEFAULT 100,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE guild_ranks (
    guild_id        UUID NOT NULL REFERENCES guilds(guild_id) ON DELETE CASCADE,
    rank_index      SMALLINT NOT NULL,
    name            TEXT NOT NULL,
    permissions     INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (guild_id, rank_index)
);

CREATE TABLE guild_members (
    guild_id        UUID NOT NULL REFERENCES guilds(guild_id) ON DELETE CASCADE,
    character_id    UUID NOT NULL REFERENCES characters(character_id),
    rank_index      SMALLINT NOT NULL DEFAULT 5,
    joined_at       TIMESTAMPTZ DEFAULT now(),
    note            TEXT,
    weekly_contrib  BIGINT DEFAULT 0,
    total_contrib   BIGINT DEFAULT 0,
    PRIMARY KEY (guild_id, character_id)
);
CREATE UNIQUE INDEX idx_guild_member_char ON guild_members(character_id);

CREATE TABLE guild_bank_tabs (
    guild_id        UUID NOT NULL REFERENCES guilds(guild_id) ON DELETE CASCADE,
    tab_index       SMALLINT NOT NULL,
    name            TEXT DEFAULT 'Bank Tab',
    icon            TEXT,
    PRIMARY KEY (guild_id, tab_index)
);

CREATE TABLE guild_bank_items (
    guild_id        UUID NOT NULL,
    tab_index       SMALLINT NOT NULL,
    slot_index      SMALLINT NOT NULL,
    item_id         INTEGER NOT NULL REFERENCES item_templates(item_id),
    quantity        INTEGER DEFAULT 1,
    deposited_by    UUID REFERENCES characters(character_id),
    deposited_at    TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (guild_id, tab_index, slot_index),
    FOREIGN KEY (guild_id, tab_index) REFERENCES guild_bank_tabs(guild_id, tab_index)
);

CREATE TABLE guild_bank_log (
    log_id          BIGSERIAL PRIMARY KEY,
    guild_id        UUID NOT NULL REFERENCES guilds(guild_id),
    character_id    UUID NOT NULL REFERENCES characters(character_id),
    action          TEXT NOT NULL,
    item_id         INTEGER,
    quantity        INTEGER,
    gold_amount     BIGINT,
    created_at      TIMESTAMPTZ DEFAULT now()
);
```

## Chat Schema

```sql
CREATE TABLE chat_messages (
    message_id      BIGSERIAL PRIMARY KEY,
    channel_type    SMALLINT NOT NULL,
    channel_id      TEXT NOT NULL,
    sender_id       UUID NOT NULL,
    sender_name     TEXT NOT NULL,
    content         TEXT NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_chat_channel ON chat_messages(channel_type, channel_id, created_at DESC);
```

## Leaderboard Schema

```sql
-- Redis sorted sets for live rankings
-- ZADD leaderboard:pvp:season_12 1500 "character_uuid_1"
-- ZREVRANK leaderboard:pvp:season_12 "character_uuid_1"  → rank
-- ZREVRANGE leaderboard:pvp:season_12 0 9 WITHSCORES     → top 10

-- Seasonal snapshot to PostgreSQL
CREATE TABLE leaderboard_snapshots (
    snapshot_id     SERIAL PRIMARY KEY,
    board_type      TEXT NOT NULL,
    season          INTEGER NOT NULL,
    character_id    UUID NOT NULL,
    final_rank      INTEGER NOT NULL,
    final_score     BIGINT NOT NULL,
    rewards_granted JSONB,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_lb_snapshot ON leaderboard_snapshots(board_type, season, final_rank);
```

## Data Migration

```sql
-- Phase 1: EXPAND (non-blocking)
ALTER TABLE characters ADD COLUMN premium_gems BIGINT DEFAULT 0;

-- Phase 2: MIGRATE (batched backfill in Python)
-- while True:
--     rows_updated = db.execute("""
--         UPDATE characters SET new_column = compute_from(old_column)
--         WHERE new_column IS NULL
--         AND character_id IN (
--             SELECT character_id FROM characters WHERE new_column IS NULL LIMIT 1000
--         )
--     """, [batch_size])
--     if rows_updated == 0: break
--     time.sleep(0.1)

-- Phase 3: CONTRACT
ALTER TABLE characters ALTER COLUMN premium_gems SET NOT NULL;

CREATE TABLE schema_migrations (
    version         INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    applied_at      TIMESTAMPTZ DEFAULT now(),
    applied_by      TEXT NOT NULL,
    execution_ms    INTEGER,
    rollback_sql    TEXT
);
```
