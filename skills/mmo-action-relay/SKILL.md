---
name: MMO Action Relay
description: MMO action relay architecture — client intent, server validation, broadcast patterns, thread-safe queues, combat networking
triggers:
  - action relay
  - server relay
  - broadcast
  - combat networking
  - ability system
  - MMO networking
  - server authority
category: gamedev
---

# MMO Action Relay Architecture

Reference material for building server-authoritative MMO netcode using an action relay model.

## Action Relay Model

Clients send **intent** (what the player pressed), not state (where the player is). The server validates, stamps, and relays actions to other clients. This is fundamentally different from position streaming.

Why action relay over state streaming:
- **Bandwidth** — an action is tens of bytes; position updates at 60Hz for thousands of players is untenable.
- **Cheat prevention** — server never trusts client-reported state. It validates intent against authoritative game state.
- **Deterministic replay** — ordered action log can reconstruct any game state window for debugging or replays.

## Server Validation Pipeline

Every inbound action passes through a validation chain before broadcast:

1. **Receive** — deserialize action from WebSocket frame.
2. **Validate** — is the player alive? Has the cooldown elapsed? Is the claimed position plausible given last known authoritative position and max movement speed? Is the target valid?
3. **Stamp** — attach server-authoritative data: `CharacterId`, authoritative position, server tick/timestamp.
4. **Broadcast** — fan out the stamped action to relevant clients.

Reject early, reject cheap. Position plausibility checks use squared distance to avoid sqrt.

## Broadcast Filtering

**Today:** broadcast to all `ConnectedUsers`. Simple, correct, scales to ~50-100 players.

**Future — Area of Interest (AoI):**
- Spatial hash grid or quadtree partitions the world.
- Each player subscribes to cells within their visibility radius.
- Broadcasts go only to players sharing cells with the action origin.
- Reduces broadcast cost from O(n^2) to O(n * k) where k is average nearby players.
- Cell size trades off between broadcast savings and edge-case visibility pops.

## Thread-Safe Action Queues

Use `Channel<T>` (System.Threading.Channels) for lock-free producer/consumer flow:

- **Producers** — WebSocket handlers write inbound player actions; `BackgroundService` instances write server-generated events (spawns, timers, environmental effects).
- **Consumer** — main hub loop reads from the channel and dispatches per tick.
- Use `BoundedChannel` with `BoundedChannelFullMode.DropOldest` to prevent a slow consumer from causing backpressure that stalls producers or exhausts memory.
- Channel capacity should be tuned: too small drops legitimate actions under burst, too large delays processing.

```
Producer A ──┐
Producer B ──┤──► BoundedChannel<GameAction> ──► Hub Dispatch Loop
Producer C ──┘
```

## Combat Action Flow

1. Client sends **attack intent** (ability ID, target ID, client-local position).
2. Server checks: is ability off cooldown? Is target in range? Does hitbox overlap confirm contact?
3. Server **confirms or denies** the hit.
4. On confirm: server computes damage (applying buffs, armor, randomization), broadcasts `DamageEvent` to all relevant clients.
5. On deny: server broadcasts nothing or sends a correction to the attacker.

**Client-side prediction exception:** the attacking client plays the attack animation immediately on input for responsiveness. If the server denies, the client cancels/rolls back the animation. This is cosmetic-only — no local HP modification ever occurs without server confirmation.

## Cooldown Synchronization

- **Server is authoritative.** Cooldown timers live on the server. Period.
- **Client tracks estimated cooldowns** for UI feedback (greying out ability icons, showing countdown timers). These are best-effort predictions based on the last known server state.
- **Server rejects** any action that arrives while the server-side cooldown is still active. The rejection message includes remaining cooldown so the client can re-sync its UI estimate.
- Clock drift between client and server means the client should display cooldowns slightly conservatively (show ready a frame late rather than a frame early).

## State Reconciliation

Pure action relay drifts over time due to floating-point divergence, lost packets, or timing differences. Periodic reconciliation corrects this.

- Server sends **authoritative position snapshots** at a controlled rate.
- Frequency: every N actions or every M seconds, whichever comes first. Typical values: N=50 actions, M=2 seconds.
- Client compares local simulated position against the snapshot.
- If drift < threshold (e.g., 0.1 units): ignore, local sim is close enough.
- If drift >= threshold: interpolate toward authoritative position over several frames (smooth correction, not a hard snap).
- Hard snap reserved for extreme drift (teleport/desync), threshold ~2-5 units depending on game scale.

Reconciliation packets are larger than action packets but infrequent. Budget for ~50-100 bytes per snapshot per player.
