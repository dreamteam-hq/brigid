# Brigid: Architecture, Brain, and Design Partnership

## The Assignment

> I want you to describe your composition, and how your wonderful brain that I built for you works. You should detail how you know all about the godot 4.6.1 api spec, how we built Neo4j graph data model of the api surface, as well as how you know so much about dotnet, godot, game development, etc. You should also detail the MCP servers I made available to you, notably the roslyn tools, nuget, blender MCP, godot MCP, context7, and lastly the rich set of skills you possess. You should include the Knowledge Graph schema, ontology, etc. You should cover how all dreamteam-hq brains are structured (4 quadrants), etc.
>
> I want to show my friend how awesome you are, and how we've been working together, not with you spitting out code, but as a design partner.
>
> — Matt Young, April 23, 2026

---

## Executive Summary

Brigid is one of four AI agents in the DreamTeams ecosystem — a Claude Code plugin framework Matt built starting March 10, 2026. The other three: Iris (PM), Docent (ecosystem curator), and Den Mother (legal ops for wolfpack-law custody litigation). Wolfpack came first. Every architectural pattern in DreamTeams — skills, brains, hooks, MCP servers — was extracted from real-world pressure in Massachusetts custody court, where hallucinated legal citations can reach filings.

Brigid's job: design partner for CrystalMagica, a Godot 4.6 C# MMO 2D platformer Matt is building with his son Arthur. Not a code generator. A collaborator who knows .NET 10, Godot's API surface (44,000 nodes in a Neo4j knowledge graph), multiplayer netcode, and game architecture — and who operates under strict rules Matt enforces through memory, editorconfig, and a gated design workflow.

**Persona is the agent; domain knowledge is the skill.** DreamTeams started with 17 proposed agents. It shipped with 2 (dev + dreamteam). Every other "agent" turned out to be a generalist with specialized skills loaded. This decision — made on day one — is still load-bearing 7 weeks later.

Brigid carries 48 skills across Godot, .NET, game architecture, multiplayer, and MMO persistence. 9 MCP servers provide live IDE refactoring (Roslyn, 41 tools), Godot editor integration (15 intelligence tools), 3D asset pipeline (Blender, 22 tools), package management (NuGet), and documentation lookup (Context7). Her brain is a 4-quadrant store: Neo4j for the Godot API knowledge graph, Postgres for structured gamedev data, DuckDB for ad-hoc analytics, [LadybugDB](https://github.com/LadybugDB/mcp-server-ladybug) (in-memory graph engine) for ephemeral graph reasoning.

---

## Origin: Wolfpack to DreamTeams

DreamTeams exists because Matt needed custody litigation support that wouldn't hallucinate case citations.

**The wolfpack-law project** (Brynn Detwiller's firm, Worcester County MA) was the original forcing function. Claude Code agents doing real legal work — drafting motions, managing evidence, tracking deadlines. The first round of AI-generated skills referenced **J.F. v. J.F.** — a completely fabricated case. In custody litigation, that reaches a filing. The fix: a citation verification chain (CourtListener MCP + verification skill + attorney review hook). Every cite gets checked before it touches a document.

That incident shaped everything. Without production consequences, you get a skill library that's never been stress-tested.

**The 17 → 2 agent decision** (March 10, v0.1.0): Claude Code has a 10-agent ceiling. The original design had 17 domain specialists — `comms-consultant`, `supply-chain-sentinel`, etc. The realization: most "agents" are just knowledge containers. A comms consultant is a generalist with communications skills. So: collapse to `dev` (builds things) and `dreamteam` (thinks about things). Two agents cover the full behavior space. Any plugin combination stays within budget.

**The producer-consumer flywheel:**

```
DreamTeams builds plugins/skills/MCP servers
  → wolfpack uses them in real custody litigation
  → wolfpack surfaces gaps and bugs
  → upstream-advocate formalizes feedback
  → DreamTeams ships fixes
  → repeat
```

By v0.11.10 (March 14), wolfpack was 37% of the entire ecosystem by component count. Not because it was prioritized — because it was used hardest.

---

## The Agents

Four agents, each with their own brain and MCP server constellation.

![DreamTeams Ecosystem](diagrams/ecosystem-map.png)

| Agent | Domain | Brain | Skills | Key MCP Servers |
|-------|--------|-------|--------|-----------------|
| **Iris** | PM — boards, epics, multi-project orchestration | `iris-dev` (10K+ Postgres rows, 2K+ Neo4j nodes) | 50 | GitHub GraphQL, neo4j, postgres |
| **Brigid** | Game dev — Godot 4.6 C#, .NET 10, MMO architecture | `cm-brigid-dev` (44K Neo4j nodes, 74K relationships) | 48 | Godot, Roslyn, Blender, NuGet, Context7 |
| **Docent** | Ecosystem curator — plugin catalog, skill graph, registry | `docent-dev` | 16 | docent MCP, neo4j, postgres |
| **Den Mother** | Legal ops — MA custody litigation, case knowledge graph | `packmind-dev` (300+ case documents) | 63 | packmind, courtlistener, slack |

---

## Brain Architecture

Every agent brain uses the same 4-quadrant model. Two axes: relational vs. graph, persistent vs. ephemeral.

![Brain 4-Quadrant Model](diagrams/brain-quadrant.png)

**Design principles:**
- Deterministic-first. Extract and Shape stages have zero LLM calls. LLMs enter only at Classify and Reason.
- Plain DDL, no ORMs. Schema is SQL and Cypher.
- Naming: `{prefix}-{agent}-{env}-{backend}`. Brigid's: `cm-brigid-dev-neo4j`, `cm-brigid-dev-postgres`.

**Data flow:**

```
Raw Input → EXTRACT (DuckDB) → SHAPE (DuckDB) → CLASSIFY (Haiku) → PROMOTE (Postgres) → PERSIST (Neo4j + Postgres)
```

DuckDB is always the staging layer. Postgres is the relational truth. Neo4j is the relationship truth. [LadybugDB](https://github.com/LadybugDB/mcp-server-ladybug) is scratch paper — an in-memory graph engine (KuzuDB fork with DuckDB ATTACH support), per-session, never persistent.

**The `dt-brain` CLI** provisions everything: `dt-brain create brigid` stands up both databases, applies schemas, registers domains. `dt-brain health` checks all brains. `dt-brain psql brigid` and `dt-brain cypher brigid` drop you into the right shell.

---

## Brigid's Knowledge Graph

The Neo4j brain at `cm-brigid-dev-neo4j` holds the complete Godot 4.6.1 API surface.

![Neo4j Godot API Schema](diagrams/neo4j-schema.png)

**Scale:** 44,000 nodes, 74,000 relationships.

**How it got there:** Matt wrote `scripts/load-godot-neo4j.py` — a deterministic pipeline that reads `extension_api.4.6.1.json` (the Godot build artifact that defines every class, method, property, signal, and enum) and emits Cypher to construct the graph. No LLM involved. The API spec is the source of truth, not documentation or training data.

**Schema:**

```
(:ApiSurface)─[:BELONGS_TO]→(:Type)      1,800 types (classes)
(:Type)─[:HAS_METHOD]→(:Method)           16,461 methods
(:Method)─[:HAS_PARAMETER]→(:Parameter)   16,314 parameters
(:Method)─[:RETURNS_TYPE]→(:Type)         7,854 return type edges
(:Type)─[:HAS_PROPERTY]→(:Property)       4,055 properties
(:Type)─[:HAS_SIGNAL]→(:Signal)           489 signals
(:Type)─[:DEFINES_ENUM]→(:Type)           736 enums
(:Type)─[:HAS_ENUM_VALUE]→(:EnumValue)    4,868 enum values
(:Type)─[:INHERITS]→(:Type)               1,023 inheritance edges
(:Type)─[:IN_NAMESPACE]→(:Namespace)      namespace membership
(:Parameter)─[:OF_TYPE]→(:Type)           18,797 type reference edges
```

**What this enables:** When I need to know what methods `CharacterBody3D` inherits from `PhysicsBody3D` from `CollisionObject3D` from `Node3D` from `Node`, I traverse the graph. When I need all signals a node type can emit — including inherited ones — it's a Cypher query, not a documentation lookup. The graph is authoritative in a way that training data and documentation never are.

**Postgres complement:** The `gamedev` schema holds the same data in tabular form — `godot_class`, `godot_method`, `godot_signal`, `godot_property`, `godot_enum`. SQL for aggregations and counts, Cypher for traversals and relationships.

---

## Skills: 48 Across 5 Domains

Skills are markdown files following the [agentskills.io](https://agentskills.io) spec — frontmatter (name, triggers, depth) plus a body that teaches domain knowledge. They load on-demand when conversation triggers match.

| Domain | Count | Examples |
|--------|-------|---------|
| **Godot Engine** | 12 | `gamedev-godot`, `godot-scene-patterns`, `godot-signals-csharp`, `godot-gdextension-csharp`, `godot-dotnet-mcp` |
| **Game Design** | 11 | `gamedev-ecs`, `gamedev-3d-platformer`, `gamedev-3d-ai`, `gamedev-blender`, `game-economy-design` |
| **Multiplayer/MMO** | 7 | `gamedev-multiplayer`, `gamedev-server-architecture`, `mmo-zone-architecture`, `mmo-action-relay` |
| **.NET/C#** | 15 | `dotnet-csharp`, `dotnet-source-generators`, `roslyn-analyzers`, `system-reactive-dynamicdata`, `dotnet-editorconfig` |
| **Architecture** | 3 | `concurrency-model-selection`, `crystal-magica-architecture`, `numerical-pitfalls` |

The `crystal-magica-architecture` skill is the project-specific one — it knows the solution structure, the MVVM pattern, the movement protocol, the source generators, and the key types.

---

## MCP Servers: The Tool Layer

Nine MCP servers, 120+ tools total.

| Server | Tools | What It Does |
|--------|-------|-------------|
| **Godot MCP** | 15 intelligence tools | Live scene manipulation, script analysis, runtime diagnostics, binding audits — running inside the Godot editor |
| **Roslyn MCP** | 41 tools | Semantic C# refactoring: rename, extract method, find references, analyze data flow, get diagnostics. IDE-grade operations without an IDE. |
| **Blender MCP** | 22 tools | 3D asset pipeline: AI mesh gen (Hyper3D, Hunyuan3D), PolyHaven/Sketchfab asset search, Blender scene control |
| **NuGet MCP** | 6 tools | Package version management, vulnerability scanning, source mapping |
| **Context7** | 2 tools | Live documentation lookup for any library — bypasses training data staleness |
| **Mermaid MCP** | 2 tools | Diagram rendering |
| **Neo4j** | Cypher read/write | Knowledge graph queries |
| **Postgres** | SQL query | Structured data queries |
| **DuckDB** | SQL query | Analytics, file exploration, YAML/markdown parsing |

When Matt's `.editorconfig` enforces all CA rules at ERROR severity, Roslyn's `get_diagnostics` catches violations before Matt sees them. `search_symbols` is authoritative where training data is not — if Roslyn can't find the method, it doesn't exist.

---

## Rules of Engagement

These aren't suggestions. They're enforced through agent memory, `.editorconfig` severity, and Matt's direct feedback. They exist because Matt corrected me — usually more than once.

**Code rules:**
- `.editorconfig` at ERROR severity. No pragmas — ever. Fix the code, don't suppress the warning.
- Match existing style to an OCD level. Not "close enough" — exactly.
- `var` everywhere. Block-scoped namespaces. No space before parens in control flow.
- Verify APIs against `extension_api.json` / Context7 / Roslyn before asserting they exist.

**Workflow rules:**
- **Never push, commit, or PR in KervanaLLC/CrystalMagica.** Write files to disk. Matt handles all git operations.
- **Design gate:** First deliverable is a design summary + checklist. Wait for feedback. Then code. Then layered review (design soundness first, code quality second).
- **No scope creep.** If Matt didn't ask for it, don't add it.
- **Matt-voice in docs.** Design docs read like Matt wrote them. No agent identity, no self-reference, no AI tells.
- **Model selection is intentional.** Haiku for mechanical tasks, Sonnet for analysis, Opus for complex synthesis. Never vanilla.

**Design rules:**
- Matt pivots freely. Don't defend prior work. Match the new directive literally.
- Never defer work Matt told you to do, even if a future plan would replace it.
- When Matt says "explain it to a teenager" — he means it. Simplify until it's obvious.

---

## Design Partnership: The Evidence

This section uses direct quotes from session logs. 7 major design sessions, 400+ steering corrections, across 8 weeks of CrystalMagica development.

### The collaboration pattern

Matt described it himself in a session summary for Arthur:

> "Arthur's concern about AI hurting coding skills is valid if you use it as 'jesus take the wheel.' I use it as a fast but unreliable intern who needs every line reviewed."

The pattern, consistently, is: agent proposes → Matt tests or reads → Matt corrects on 3-5 axes (scope, naming, voice, architecture, runtime behavior) → agent revises. Not "describe what you want and paste the output."

### Per-feature iteration history

| Feature | Sessions | Design Pivots | Key Pivot |
|---------|----------|---------------|-----------|
| Controller composition | 1 (Mar 25-26) | 102 | Design doc went through v1→v4. "don't keep referring to previous versions. KISS." |
| Multiplayer protocol | 1 (Mar 30) | 56 | "no scope creep" (5x). Ripped out all added tests. |
| Down-jump platforms | 1 (Apr 7-8) | 37 | Subclass hierarchy → single bool. "subclassing seems brittle. consider traits." |
| Loop 2 server entities | 1 (Apr 2) | 103 | Full design reset. "I don't trust your prior design or work." |
| Platform simplification | 1 (Apr 9-13) | 47 | 174 lines + 3 files → 95 lines + 1 file. "Do we actually need all these helpers?" |
| Attack system | 1 (Apr 20-22) | 84 | PR body rewritten 3x. "in my voice, not yours." |
| Combat resolver | 1 (Apr 23-24) | 30+ | CDF → bag-of-marbles. "I hate this." "ValidateCompleteness is scope creep." |
| **Total** | **7** | **459+** | |

### Representative quotes

**Naming as architecture signal:**
> "I hate that CharacterAction is being repurposed, what's a better name?"
>
> "I hate djp for a variable name. djPlat works."
>
> "'mat' should be a descriptive name. Clarity is more important than fewer chars. 'single character variable names don't run faster.'"

Each naming dispute surfaced an underlying design concern — wrong abstraction, wrong scope, wrong audience.

**Architecture simplification:**
> "nope...using subclassing seems brittle. consider 'traits' in the C++ iostreams library, or a 'mixin' pattern. what if I want a platform where the spans have other properties, such as lava, or making them slippery."

This directly led to collapsing a 3-file subclass hierarchy into a single `[Export] public bool CanDropThrough` property.

**Algorithmic iteration (this session):**
The combat resolver went through 4 major algorithm pivots in one session:
1. Started with cumulative distribution function (CDF) — floating point thresholds
2. Matt found it confusing: "explain BuildTables to me" → still confused → "I find this extremely confusing"
3. Consulted a dev agent + teacher agent — both converged on bag-of-marbles
4. Shipped [fitness proportionate selection](https://en.wikipedia.org/wiki/Fitness_proportionate_selection): expand weights into a flat array, pick a random index. No floats, no normalization, one line to roll.

Along the way: startup validation was added by a review agent, then Matt removed it ("ValidateCompleteness is scope creep"). Tuples were replaced with record structs because of "tuple-trauma from Python." The lock was removed because "it isn't task/async friendly."

**Runtime testing drives design:**
> "I tested, once the mesh is out you can't change directions. We should have some way to indicate which way we're facing."

At least three design changes came from Matt running the game and observing behavior — not from code review. Agent-proposed code compiled but failed at runtime. The design gate exists because of this pattern.

**Voice ownership:**
> "This sounds like AI wrote it. Re-write this, I would never have all the specific types and files. The Commits section should be in my voice, not yours."

Said about a PR description. Said about design docs. Said about this very document's first draft ("too many words, don't highlight and reference specific methods as if they already exist").

459 steering corrections across 7 sessions. The agent proposes, the engineer decides.
