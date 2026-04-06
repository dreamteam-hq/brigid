---
name: brain-status
description: Show Brigid brain health — node counts, table sizes, schema status
allowed-tools:
  - Bash
  - Read
---

Show Brigid's brain health by querying both graph and relational stores.

**Usage:**
- `/brain-status` — full summary of Neo4j nodes/relationships and Postgres table sizes

**What it does:**

Query Brigid's Neo4j and Postgres brain databases and print a formatted health summary.

**Implementation:**

### Step 1 — Neo4j Graph Store

Use the available Neo4j read Cypher MCP tool to run these queries:

**Node counts by label:**
```cypher
MATCH (n)
RETURN labels(n)[0] AS label, count(*) AS count
ORDER BY count DESC
```

**Relationship counts by type:**
```cypher
MATCH ()-[r]->()
RETURN type(r) AS relationship, count(*) AS count
ORDER BY count DESC
```

**Total counts:**
```cypher
MATCH (n) RETURN count(n) AS total_nodes
```

```cypher
MATCH ()-[r]->() RETURN count(r) AS total_relationships
```

### Step 2 — Postgres Relational Store

Use the available Postgres query MCP tool to run:

**Table row counts:**
```sql
SELECT schemaname, relname AS table_name, n_live_tup AS row_count
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC;
```

**Table sizes:**
```sql
SELECT tablename,
       pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC;
```

### Step 3 — Format Output

Print a summary table like:

```
=== Brigid Brain Status ===

--- Neo4j Graph Store ---
Total nodes: 1,234
Total relationships: 5,678

Nodes by Label:
  Label               Count
  ──────────────────  ─────
  Skill               245
  Concept             189
  Pattern             134
  ...

Relationships by Type:
  Type                Count
  ──────────────────  ─────
  DEPENDS_ON          890
  RELATES_TO          456
  ...

--- Postgres Relational Store ---
Tables:
  Table               Rows     Size
  ──────────────────  ──────   ──────
  skills              245      48 kB
  concepts            189      32 kB
  ...
```

**Constraints:**
- Read-only. Never modify any data.
- If a database is unreachable, report the error inline and continue with the other store.
- The MCP tool names are project-prefixed (e.g., `cm_brigid_dev-read_neo4j_cypher`, `cm-brigid-dev-postgres/query`). Use whatever Neo4j read and Postgres query tools are available in the current session.
