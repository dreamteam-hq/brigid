---
name: MMO Zone Architecture
description: MMO zone architecture — spatial partitioning, area of interest, zone transitions, instancing, load balancing
triggers:
  - zone
  - zone architecture
  - area of interest
  - spatial partitioning
  - instancing
  - zone transition
  - world architecture
category: gamedev
---

# MMO Zone Architecture

Domain knowledge reference for MMO zone/world architecture. NO MCP servers.

1. **Single-zone vs multi-zone** — CrystalMagica today is single-zone (one MapHub, all players see everything). Future: multiple zones with handoff. Start simple, partition when player count demands it.

2. **Area of Interest (AoI)** — Instead of broadcasting every action to every player, only send to players within a spatial region. Reduces bandwidth from O(n²) to O(n). Implementation: spatial hash grid or quadtree. Cell size = visibility range.

3. **Spatial hash grid** — Divide world into fixed-size cells. Entity position → cell index. Broadcast to entities in same cell + adjacent cells. O(1) lookup, O(1) update on move. Simple and fast for 2D worlds.

4. **Zone transitions** — seamless (entity exists in both zones briefly during handoff) vs loading screen (disconnect/reconnect). Seamless requires zone overlap regions and state transfer protocol. Loading screen is simpler and fine for instanced dungeons.

5. **Instancing** — same zone template, multiple independent copies. Dungeons, arenas, personal spaces. Server creates instance on demand, assigns players, destroys when empty. Instance ID included in all messages.

6. **Load balancing** — monitor player density per zone server. When a zone exceeds capacity: split (expensive, needs spatial boundary) or spin up parallel instance. Stateful nature of game servers makes horizontal scaling harder than web services.

7. **CrystalMagica roadmap** — loop-02 is single entity, single zone. loop-03 adds spawn/despawn lifecycle. AoI comes when player count exceeds ~50 per zone. Instancing comes with dungeons.
