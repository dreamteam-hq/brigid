# Brigid 🔥

Godot 4.6 MMO game dev agent for the DreamTeams ecosystem.

Celtic triple goddess of craft, smithwork, and inspiration. Brigid forges game systems — scene trees, entity architectures, multiplayer netcode, render pipelines.

## Install

```bash
cd ~/gh/me/dev-cm
bash ~/gh/dreamteam-hq/brigid/scripts/install.sh
```

Or use `deploy.sh` with a `deploy.yaml` for full project loadout (Brigid + Iris + Docent + skills).

## Agent

```bash
claude --agent dt-brigid:brigid --project ~/gh/me/dev-cm
```

## Brain

Brigid uses a `gamedev` brain domain with Godot 4.6 API surface, game design patterns, and learning corpus references. Brain provisioned automatically via `dt-brain` on first session.
