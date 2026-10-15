@AGENTS.md
# Claude Code Project Context

## ⚙️ Execution Boundaries
- You have terminal execution permissions under `backend/` and `frontend/` zones.
- **Pre-Commit Check:** Always invoke the structural validation commands (`uv run ruff check` and `fvm flutter analyze`) prior to presenting a code change for completion.
- Refer to `AGENTS.md` dynamically linked above for code structure, architectural rules, and project-specific environment specifics.