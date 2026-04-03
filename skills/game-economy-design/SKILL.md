---
name: game-economy-design
description: >
  Virtual economy modeling for MMOs — currency systems, sink/faucet balance, reward
  schedules, inflation control, auction houses, and exploit prevention. Load when
  designing game economies, virtual currencies, loot systems, or player trading, or
  when the user mentions "game economy", "virtual currency", "sink and faucet",
  "inflation", "auction house", "loot table", "reward schedule", "RMT",
  "gold seller", or "player trading".
---

# Virtual Economy Design

Design and balance virtual economies that sustain long-term player engagement without collapsing into hyperinflation, deflation, or real-money-trading dominance. This skill covers currency architecture, sink/faucet modeling, reward scheduling, auction house design, and economy telemetry. For server-side persistence backing the economy, load `gamedev-server-architecture`. For multiplayer transaction networking, load `gamedev-multiplayer`.

## Currency Architecture

Every game economy starts with currency design. Get this wrong and no amount of tuning fixes the downstream problems.

### Single vs Multi-Currency

Single-currency systems (one gold coin for everything) are simple but create a single point of failure -- if gold inflates, the entire economy breaks. Multi-currency systems isolate failure domains: PvE gold inflation does not affect PvP honor points.

Most successful MMOs use 3-5 currencies:

| Currency Type | Purpose | Tradeable | Example |
|---------------|---------|-----------|---------|
| Primary (gold) | General commerce, NPC vendors, auction house | Yes | WoW Gold, FFXIV Gil |
| Bound (tokens) | Progression gating, prevents buying power | No | Valor Points, Tomestones |
| Premium (gems) | Real-money store, cosmetics, convenience | Limited | GW2 Gems, Lost Ark Crystals |
| Seasonal | Time-limited engagement loop | No | Battle pass tokens, event currency |
| Social | Guild/group activities | No | Guild marks, raid tokens |

### Bound vs Tradeable

Bound (soulbound) currency cannot be traded between players. This is the primary tool for preventing real-money trading from undermining progression. Rule of thumb: any currency that gates player power should be bound. Any currency used for cosmetics or convenience can be tradeable.

### Premium Currency Design

Premium currency bridges real money and the in-game economy. Critical design rules:

- **Fixed exchange rate in, floating rate out.** Players buy gems at $1 = 100 gems. Gems convert to gold at a market-determined rate. This lets you sell gems at a predictable price while the gold economy floats.
- **Odd pricing.** Sell gem packs in quantities that do not align cleanly with item prices (pack of 1100 gems, items cost 300). Players always have leftover gems, creating purchase pressure.
- **Never sell power directly.** The moment premium currency buys best-in-slot gear, you have pay-to-win. Cosmetics, convenience (inventory slots, fast travel), and time-savers (XP boosts) are acceptable. Gear and stats are not.

### Decision Table by Game Type

| Game Model | Primary | Bound | Premium | Seasonal | Notes |
|-----------|---------|-------|---------|----------|-------|
| F2P MMO | Gold (tradeable) | 2-3 token types | Gems/Crystals | Event tokens | Premium-to-gold exchange is critical |
| Subscription MMO | Gold (tradeable) | 1-2 token types | Optional cosmetic | Event tokens | Sub fee acts as implicit gold sink |
| B2P (buy-to-play) | Gold (tradeable) | 1-2 token types | Cosmetic-only | Expansion currency | No pressure to monetize aggressively |
| Mobile gacha | Soft currency (gold) | Hard currency (gems) | Paid gems | Banner currency | Dual-currency is the genre standard |
| Survival/sandbox | Barter (no currency) | N/A | Cosmetic-only | N/A | Player-driven economy, minimal NPC sinks |

## Sink/Faucet Modeling

The fundamental tool for economy balance is the sink/faucet spreadsheet. Every source of currency entering the economy (faucet) and every drain removing currency (sink) must be enumerated, quantified, and balanced.

### Faucet Inventory

List every way currency enters the economy, with per-player-per-hour generation rates:

| Faucet | Currency | Rate (per hour) | Gated By | Notes |
|--------|----------|-----------------|----------|-------|
| Quest rewards | Gold | 500-2000 | One-time | Front-loaded, drops off at cap |
| Mob drops | Gold | 200-800 | Kill speed | Primary steady-state faucet |
| Daily login | Gold | 100-500 | Calendar | Flat injection, not skill-gated |
| Dungeon completion | Gold + Tokens | 1000-3000 | Weekly lockout | Major burst faucet |
| Gathering/crafting | Gold (indirect) | 300-1000 | Skill level | Creates items, not currency directly |
| Auction house sales | Gold (transfer) | Variable | Market | Not a faucet -- transfers between players |
| Vendor trash | Gold | 100-400 | Inventory | NPC buys items for fixed prices |

Critical distinction: player-to-player trading (auction house) is not a faucet. It moves existing currency between players. Only NPC payments and system rewards create new currency.

### Sink Inventory

| Sink | Currency | Rate (per hour) | Participation | Notes |
|------|----------|-----------------|---------------|-------|
| Repair costs | Gold | 100-500 | Mandatory | Scales with gear level |
| Consumables (potions, food) | Gold | 200-600 | Semi-mandatory | Raiding requires flasks/food |
| Auction house tax | Gold | 5-15% of sales | Voluntary | Primary endgame sink |
| Fast travel | Gold | 50-200 | Voluntary | Convenience sink |
| Crafting material costs | Gold | Variable | Voluntary | NPC-sold reagents |
| Cosmetic vendors | Gold | One-time | Voluntary | Mounts, transmogs, housing |
| Respec/reroll | Gold | One-time | Voluntary | Character customization |
| Guild costs | Gold | Weekly | Social | Bank tabs, perks |
| Durability decay | Gold | Passive | Mandatory | Items degrade, require replacement |

### Calculating Equilibrium

Target a steady-state ratio where total faucet output slightly exceeds total sink consumption at the median player. A 1.05-1.15 faucet/sink ratio means players slowly accumulate wealth, which feels rewarding. Below 1.0 creates deflation (players feel poor). Above 1.3 creates rapid inflation.

```
Daily Gold Generation (median player):
  Quest rewards:     1,500 (assumes 1hr questing)
  Mob drops:           600
  Dungeon:           2,000 (one daily dungeon)
  Vendor trash:        300
  Daily login:         200
  ─────────────────────────
  Total In:          4,600

Daily Gold Consumption (median player):
  Repairs:             400
  Consumables:         500
  AH tax (est.):       300
  Fast travel:         150
  Crafting reagents:   200
  ─────────────────────────
  Total Out:         1,550

Ratio: 4,600 / 1,550 = 2.97  ← DANGER: heavy inflation
```

A ratio of 2.97 means the economy will inflate rapidly. Solutions: increase sink rates (higher repair costs, higher AH tax), decrease faucet rates (lower quest rewards), or add new sinks (see Inflation Control below).

### Time-to-Earn Targets

Define how long a median player should take to earn key purchases. Work backward from these targets to set faucet rates:

| Item Category | Target Time-to-Earn | Price (Gold) |
|---------------|---------------------|--------------|
| Basic mount | 2-3 days | 5,000 |
| Rare mount | 2-3 weeks | 50,000 |
| Endgame consumables (daily) | 30 min | 500 |
| Best craftable gear | 1-2 weeks | 30,000 |
| Cosmetic set | 1 week | 15,000 |
| Housing (basic) | 1 month | 200,000 |

If your faucet/sink math puts a basic mount at 2 weeks instead of 2-3 days, faucet rates are too low or prices are too high.

## Inflation Control Mechanisms

Inflation is the default state of most game economies. Players generate currency faster than they spend it, prices rise, new players cannot afford anything, and the economy stratifies. Controlling inflation is the primary ongoing challenge.

### Money Sinks

The direct approach: remove currency from the economy.

| Sink Type | Effectiveness | Player Perception | Notes |
|-----------|---------------|-------------------|-------|
| Repair costs | Medium | Negative (feels punitive) | Scale with content difficulty |
| AH listing fees | High | Neutral (cost of doing business) | 5% list + 5% sale is standard |
| Consumables | Medium | Neutral (necessary expense) | Must be meaningful, not just gold tax |
| Cosmetics | High | Positive (aspirational purchases) | Gold-sink mounts, housing, transmog |
| Limited-time offers | Very High | Positive (FOMO, but be careful) | Rotating vendor with expensive items |
| Crafting failures | Medium | Negative if too punitive | Enhancement/upgrade systems that consume gold on failure |
| Progressive repair | High | Mixed | Repair cost scales with server-wide gold supply |

### Supply Caps

Limit how fast currency enters the economy:

- **Daily/weekly earn caps.** Cap total earnable gold per day (e.g., daily quest gold caps at 5,000). Prevents no-lifers from inflating 10x faster than casuals.
- **Diminishing returns on farming.** After N kills of the same mob type per hour, drop rates decrease. Prevents bot-farming specific high-value mobs.
- **Weekly lockouts.** Dungeons and raids that award significant currency are limited to once per week. This is the standard in MMOs for good reason.
- **Account-wide caps.** Cap total gold across all characters on an account. Prevents alt armies from multiplying faucets.

### Diminishing Returns

Apply DR to repeated activities within a time window:

```
First 10 dungeon runs/week:  100% gold reward
Runs 11-20:                   50% gold reward
Runs 21-30:                   25% gold reward
Runs 31+:                     10% gold reward
```

This preserves the experience for moderate players while throttling power-farmers.

### Progressive Pricing

Items cost more as server-wide wealth grows. Track total gold in the economy (see Telemetry section). When gold supply exceeds targets, NPC vendor prices increase proportionally. This creates an automatic stabilizer -- as inflation rises, sinks deepen.

### Decision Table

| Symptom | Primary Fix | Secondary Fix |
|---------|------------|---------------|
| Steady inflation (2-5%/week) | Increase AH tax, add cosmetic sinks | Reduce top-end faucets |
| Rapid inflation (>10%/week) | Emergency: cap daily earnings, add gold-sink event | Find and fix the broken faucet |
| Deflation | Reduce repair costs, add faucets | Inject currency via events |
| Wealth inequality (high Gini) | Add catch-up faucets for low-level players | Progressive sinks on wealthy players |
| Stagnant market (low velocity) | Reduce AH fees, add new desirable items | Seasonal resets |

## Reward Schedule Design

How and when players receive rewards determines engagement, retention, and spending patterns. Reward schedules are behavioral psychology applied to game design.

### Reinforcement Schedules

| Schedule | Pattern | Player Behavior | Best For |
|----------|---------|-----------------|----------|
| Fixed Ratio | Reward every N actions | Steady grind, predictable | Crafting (make 10, get reward) |
| Variable Ratio | Reward after random N actions | Compulsive engagement, slot-machine effect | Loot drops, gacha |
| Fixed Interval | Reward every T time | Login spikes at reset, dead time between | Daily/weekly quests |
| Variable Interval | Reward at random times | Constant checking behavior | World events, rare spawns |

Most games combine all four. Daily quests (fixed interval) keep players logging in. Loot drops (variable ratio) keep them playing. Crafting (fixed ratio) gives a sense of control. World bosses (variable interval) create excitement.

### Daily/Weekly Reset Patterns

Structure resets to create natural play sessions:

- **Daily reset:** 3-5 quick tasks (15-30 min). Rewards: modest gold, daily tokens.
- **Weekly reset:** 1-3 significant activities (1-3 hours total across the week). Rewards: major tokens, gear upgrades.
- **Monthly/seasonal:** Long-term goals. Rewards: exclusive cosmetics, titles.

Stagger resets across time zones. A single global reset creates server load spikes and punishes players in unfavorable time zones.

### Catch-Up Mechanics

Players who take breaks must be able to return without feeling hopelessly behind:

- **Rest XP:** Accumulate bonus XP while offline (WoW model). Caps at 1.5 levels of rest.
- **Increased token rates:** Returning players earn 2x tokens for the first week back.
- **Catch-up gear:** Vendors sell previous-tier gear for cheap, letting returners skip to current content.
- **Seasonal resets:** Each season introduces a new currency, equalizing all players at season start.

Never make catch-up trivial (undermines current players) or impossible (kills returning players). Target: a returning player should reach current-content readiness in 1-2 weeks, not 1-2 days or 1-2 months.

### Power Curves

Progression speed varies by game design intent:

| Curve | Shape | Feel | Use Case |
|-------|-------|------|----------|
| Linear | Constant XP/level | Predictable, can feel grindy | Sandbox games, skill-based |
| Logarithmic | Fast early, slow late | Quick hook, long endgame | Most MMOs |
| S-Curve | Slow start, fast middle, slow end | Tutorial buffer, satisfying mid-game, prestige endgame | Story-driven MMOs |
| Exponential | Slow early, fast late | Feels increasingly rewarding | Idle/incremental games |

For MMOs, the S-curve is typically best. The slow start teaches mechanics. The fast middle provides dopamine. The slow end creates aspirational long-term goals.

### Pity Timers

For any random reward system (loot boxes, gacha, boss drops), implement a pity timer that guarantees a reward after N failed attempts:

- Track consecutive failures per player per reward type
- At threshold (e.g., 80 pulls), guarantee the rare reward
- Optionally increase probability gradually (soft pity at 60, hard pity at 80)
- Always disclose pity mechanics to players (regulatory requirement in many jurisdictions)

Pity timers prevent the statistical tail where unlucky players never get the reward. Without them, ~1% of players will have an experience 3-5x worse than median, generating support tickets and churn.

## Auction House and Player Trading

Player-to-player trading is where economies get complex. A well-designed auction house (AH) is the backbone of a healthy player economy. A poorly designed one enables exploitation.

### Order Book Design

Two primary models:

**Bid/Ask (Order Book):** Players post buy orders and sell orders at specific prices. Transactions execute when a buy price meets a sell price. This is how real stock exchanges work.
- Pros: Price discovery, market depth visibility, efficient
- Cons: Complex UI, intimidating for casual players
- Example: EVE Online, GW2 Trading Post

**Simple Listing:** Sellers list items at a fixed price. Buyers browse and purchase.
- Pros: Simple UI, accessible
- Cons: No buy orders, sellers must guess prices, slower price discovery
- Example: WoW Auction House (pre-revamp), most MMOs

For most games, start with simple listing and add buy orders later if the economy matures. EVE's order book works because EVE players self-select for complexity.

### Fee Structure

Fees are the primary currency sink in a trading economy:

| Fee Type | Rate | Purpose |
|----------|------|---------|
| Listing fee | 1-5% of list price | Prevents spam listings, penalizes overpricing |
| Sale tax | 2-10% of sale price | Primary gold sink, funds NPC economy |
| Cancellation fee | 50-100% of listing fee | Prevents price manipulation via cancel/relist |
| Deposit (refundable on sale) | 5-15% of list price | Discourages unrealistic pricing |

A combined 5-10% effective tax rate (listing + sale) is standard. Below 3% and the AH is not a meaningful sink. Above 15% and players avoid the AH, trading directly instead (which you cannot tax).

### Trade Restrictions

Prevent abuse without destroying the trading experience:

- **Account age minimum.** New accounts cannot trade for 24-72 hours. Blocks throwaway gold-selling accounts.
- **Level minimum.** Characters below level 10-20 cannot use the AH. Blocks low-effort bot accounts.
- **Daily trade volume caps.** Limit total gold traded per day. Scaling cap based on account age/level.
- **Item binding.** Best gear is soulbound (untradeable). Only consumables, materials, and cosmetics trade freely.
- **Cross-server restrictions.** In games with server shards, limit trading to same-server or same-region to prevent arbitrage exploits.

### Anti-RMT Patterns

Real-money trading (gold selling) is the persistent threat to every game economy:

- **Suspicious transaction flagging.** Flag trades where gold transfers greatly exceed item value (player lists a gray item for 100,000 gold).
- **Velocity detection.** Flag accounts that receive gold from many unique sources in a short window.
- **Bot detection heuristics.** Accounts that farm 18+ hours/day, follow identical pathing, or have zero social interaction.
- **Price manipulation detection.** Flag accounts that buy out entire item categories (market cornering) or post items at 1000x normal price.
- **Two-factor authentication.** Require 2FA for trades above a threshold. Prevents compromised account exploitation.
- **Trade cooldowns.** After a large trade, impose a 1-hour cooldown before the gold can be traded again. Breaks fast-laundering chains.

## Economy Telemetry

You cannot manage what you do not measure. Economy health requires real-time monitoring with clear alert thresholds.

### Core Metrics

| Metric | What It Measures | Healthy Range | Alert Threshold |
|--------|-----------------|---------------|-----------------|
| Gini coefficient | Wealth inequality (0 = equal, 1 = one player has all) | 0.3-0.5 | > 0.7 |
| Median wealth by level | Whether progression feels rewarding | Monotonically increasing | Flat or decreasing |
| Velocity of money | Transactions per unit of currency per day | 0.1-0.5 | < 0.05 (stagnant) or > 1.0 (panic) |
| CPI (item price index) | Track prices of a basket of 20-30 key items over time | Stable or slow increase (1-3%/week) | > 5%/week (inflation) or < -2%/week (deflation) |
| Currency creation rate | Total new gold entering per day | Within 10% of design target | > 25% above target |
| Currency destruction rate | Total gold removed per day | 70-90% of creation rate | < 50% of creation (sinks failing) |
| Active trader ratio | % of players using the AH | 30-60% | < 15% (AH irrelevant) |
| Median time-to-earn | Hours to earn key items | Within 20% of design targets | > 50% deviation |

### Wealth Distribution Dashboard

Track wealth in brackets:

```
Level 1-20:   Median 500g,    P90 2,000g,    P99 10,000g
Level 21-40:  Median 5,000g,  P90 20,000g,   P99 80,000g
Level 41-60:  Median 25,000g, P90 100,000g,  P99 500,000g
Max Level:    Median 100,000g, P90 1,000,000g, P99 10,000,000g
```

When P99/Median ratio exceeds 100:1 within a level bracket, wealth concentration is extreme and likely driven by exploits or RMT.

### Price Index Tracking

Select a basket of representative items and track their prices daily:

- 5 consumables (health potion, mana potion, buff food, flask, bandage)
- 5 raw materials (ore, herb, leather, wood, cloth)
- 5 crafted items (basic weapon, armor piece, bag, enchant, gem)
- 5 endgame items (raid consumable, high-end material, rare recipe output)

Compute a weighted price index (CPI-style). Plot weekly. An upward trend beyond 3%/week signals inflation that needs intervention.

### Alert Thresholds

Set automated alerts for:

- Currency creation rate exceeds 125% of target for 3 consecutive days
- Gini coefficient exceeds 0.7
- CPI increases more than 5% in a single week
- Any single account accumulates more than 100x median wealth for their level
- AH transaction volume drops below 50% of 30-day average
- New currency duplication exploits (sudden spike in creation rate without corresponding player activity)

## Common Failure Modes

### Hyperinflation from Duplication Bugs

The most catastrophic failure. A bug allows players to duplicate currency or items. Within hours, exploiters generate billions of gold. Prices skyrocket. The economy is destroyed.

**Prevention:**
- Transaction logging on every currency change (source, amount, before/after balance)
- Server-side validation of all currency operations (never trust the client)
- Rate limiting on rapid successive transactions
- Automated detection: flag accounts whose gold increases faster than the theoretical maximum faucet rate

**Response:**
- Immediately disable trading and the auction house
- Identify all accounts that exploited the bug via transaction logs
- Roll back exploiter accounts to pre-exploit state
- If widespread: full server rollback to pre-exploit snapshot
- Communicate transparently with players about what happened and what was done

### Deflation from Over-Sinking

Sinks are too aggressive. Players hoard currency because spending feels punishing. Market activity drops. New items are not listed because sellers cannot recoup crafting costs. The economy stagnates.

**Prevention:**
- Monitor velocity of money. Dropping velocity is the early warning sign.
- Ensure no single sink exceeds 30% of a player's income. Repairs should not cost more than 30% of what a dungeon run earns.
- Playtest sink rates with median players, not hardcore testers.

**Response:**
- Reduce the overtuned sink (cut repair costs, lower AH fees)
- Inject a one-time stimulus (double gold weekend, bonus quest rewards)
- Add new faucets that feel earned, not like a handout

### Gold Seller Economic Attacks

Professional gold sellers do not just farm -- they manipulate markets:

- **Market cornering.** Buy all supply of a critical material, relist at 10x price. Players must buy from the gold seller or go without.
- **Price dumping.** Flood a market with below-cost items to destroy competitors, then raise prices once they leave.
- **Inflation acceleration.** Deliberately inject massive gold to devalue the currency, making their real-money prices more attractive.

**Prevention:**
- Purchase volume limits per item per day per account
- Price change rate limits (items cannot be relisted at more than 200% of recent average price)
- Suspicious accumulation detection (one account buying 90%+ of a material's supply)

### Unintended Faucet Discovery

Players find an exploit that generates currency faster than intended: a quest that can be repeated, a vendor buy/sell loop with positive margins, a crafting recipe that produces more value than its inputs.

**Prevention:**
- Automated anomaly detection on per-player gold generation rates
- Vendor buy/sell price audits (ensure NPCs never buy an item for more than they sell it)
- Quest completion rate monitoring (a quest completed 100x by one player is a bug)
- Crafting profit margin analysis (no recipe should reliably profit without market risk)

## Free-to-Play Monetization

### Premium Currency Design

Premium currency is the bridge between real money and the game. Design it carefully:

- **Clear, simple exchange rate.** $1 = 100 gems (not $1 = 73 gems). Players should intuit value.
- **Denomination strategy.** Sell packs at $5 (500), $10 (1100), $20 (2300), $50 (6000). Bonus gems at higher tiers incentivize larger purchases. Odd numbers create leftover gems.
- **In-game exchange.** Allow premium-to-gold exchange at a player-driven rate. This lets free players earn premium items through gameplay (they provide gold liquidity) and lets paying players skip grind (they provide premium currency liquidity). GW2's gem exchange is the gold standard.

### Monetization Tiers

| Tier | What It Sells | Player Perception | Revenue Impact |
|------|---------------|-------------------|----------------|
| Cosmetic-only | Skins, mounts, housing | Positive (fair) | Moderate, stable |
| Convenience | Inventory slots, fast travel, XP boosts | Neutral to mixed | High |
| Time-saving | Level boosts, crafting speedups | Controversial | High, risky |
| Power (pay-to-win) | Best gear, stat boosts | Strongly negative | Short-term high, long-term destructive |

Stay in cosmetic and convenience tiers. The moment paying players have a statistical combat advantage over free players, the game loses competitive integrity and community trust.

### Battle Pass Economics

A seasonal battle pass creates predictable revenue and engagement:

- **Free track:** Basic rewards (currency, consumables). Keeps free players engaged.
- **Premium track ($10-15/season):** Exclusive cosmetics, mounts, emotes. Must feel worth the price.
- **Duration:** 8-12 weeks. Shorter creates FOMO pressure. Longer loses urgency.
- **Completion rate target:** A player who plays 1 hour/day should complete the pass with 1-2 weeks to spare. If only hardcore players finish, casual buyers feel cheated.
- **Never put gameplay power on the premium track.** This is the battle pass equivalent of pay-to-win.

### Regulatory Compliance

Loot box regulation is expanding globally:

| Jurisdiction | Requirement |
|-------------|-------------|
| Belgium, Netherlands | Paid loot boxes banned (classified as gambling) |
| China | Must disclose exact drop rates |
| Japan | Kompu gacha (combining random items for a prize) banned |
| UK | Under review; age-gating likely |
| US | FTC scrutiny; state-level bills emerging |
| Australia | Senate inquiry recommended regulation |
| South Korea | Must disclose probabilities, government audits |

**Safe practices regardless of jurisdiction:**
- Disclose all drop rates publicly
- Implement and disclose pity timers
- Never sell loot boxes to minors without parental controls
- Offer direct-purchase alternatives for all loot box items (even at higher price)
- Keep records of all randomized purchase outcomes for audit

## Anti-Patterns

| Anti-Pattern | Why It Fails | Better Approach |
|-------------|-------------|-----------------|
| Single currency for everything | One inflation vector destroys the whole economy | 3-5 purpose-specific currencies |
| No sinks at endgame | All faucets, no drains = hyperinflation within months | Endgame cosmetic sinks, progressive repair, AH taxes |
| Selling power for premium currency | Destroys competitive integrity, drives away non-payers | Cosmetic and convenience monetization only |
| Fixed NPC prices with rising player wealth | Players outgrow NPC economy in weeks, vendors become irrelevant | Progressive pricing tied to server wealth metrics |
| No trade restrictions on new accounts | Gold sellers create accounts, dump gold, and delete | 24-72hr trade lockout, level minimums, volume caps |
| Flat drop rates without pity | 1% of players never get the reward, generating rage and churn | Pity timer guaranteeing reward after N attempts |
| Manual economy balancing only | Humans react too slowly to exploits and market shifts | Automated telemetry, alerts, and progressive sinks |
| Ignoring secondary markets | Players trade outside the game (Discord, forums) to avoid AH tax | Keep AH fees below 10% to keep trading in-game where you can monitor it |
| Seasonal resets without carry-forward | Players feel their time was wasted when progress evaporates | Let seasonal currency convert to permanent (at reduced rate) |
| No separation between earned and bought currency | Cannot distinguish organic economy health from whale spending | Track earned vs premium currency flows separately in telemetry |

## Cross-References

| Skill | When to Load |
|-------|-------------|
| `gamedev-server-architecture` | Server-side persistence, database design for economy state, transaction processing |
| `gamedev-multiplayer` | Networking for trade transactions, auction house real-time updates |
| `gamedev-mmo-persistence` | Saving player inventories, currency balances, transaction history |
| `gamedev-2d-platformer` | Simpler economy design for non-MMO games (shop systems, upgrade currencies) |
