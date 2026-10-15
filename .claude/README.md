Agent documentation map:

The shared coding instructions are in ../AGENTS.md. Root ../CLAUDE.md imports
that file explicitly. Deeper design/workflow files are read by task, not all
imported at startup; ordinary references do not add the entire guide to context.

Structure (repository-relative paths):

  AGENTS.md                    Shared coding rules and task-reading map.
  CLAUDE.md                    Thin Claude router with one @AGENTS.md import.
  .claude/README.md             This document index and discovery notes.
  .claude/architecture.md       Functional features, components, Firebase/infra
                               flows, ASCII sequence diagrams and versions.
  .claude/technical-lld.md      Implementation and field-level contracts migrated
                               from the earlier detailed CLAUDE.md.
  .claude/tdd/README.md         Project-specific RED-GREEN-REFACTOR workflow.
  .claude/review/README.md      Evidence-based reviewer workflow and checklist.
  .claude/plan.md               Historical decisions; obsolete behavior labeled.
  .claude/skill.md              Legacy index pointer, not an executable skill.
  BUILD.md                     Local builds versus environment/infra changes.

Read by task:

  Orientation/features: architecture, relevant LLD sections, source and tests.
  Bug fixes: source/tests and TDD; reviewer workflow before final handoff.
  Firestore/auth/backend work: LLD, source and separate backend rules/tests when
  available. Missing backend code or deployment access is an explicit limitation.
  Native/build/dependencies: BUILD.md and architecture's version inventory; check
  the actual SDK/manifests/lock and exercise the affected native build.
  Historical UX rationale: plan.md, but current source establishes behavior.

Compatibility and limits:

  Codex discovers AGENTS.md along the repository-to-working-directory chain.
  AGENTS.override.md and configured global instructions can take priority.
  Cursor supports root and nested AGENTS.md, combining more specific guidance.
  Hermes supports AGENTS.md; .hermes.md/HERMES.md or AGENTS.override.md may take
  priority. Current docs describe directory-chain and progressive discovery.
  Start the tool in the intended checkout and inspect its loaded context if unsure.
  Claude loads root CLAUDE.md, whose @AGENTS.md import is relative to that file.
  Current docs also support AGENTS.md directly; the explicit router avoids version
  and precedence ambiguity when CLAUDE.md is present.

  Path references are instructions to read, not a guaranteed automatic loader.
  Organization/global/local instructions and actual tool permissions still apply.
  Official documentation verifies supported formats, not live startup behavior
  of every installed client version. Check a client's context UI/logs if needed;
  do not bypass permissions or invoke paid model calls just to claim compatibility.

  Arbitrary .claude/review/, .claude/tdd/ and skill.md files are documentation.
  No .claude/rules, agents, commands, skills or hooks are installed by this layout.
  Those mechanisms have specific formats/discovery and need explicit implementation;
  a folder name does not register a named agent. Existing settings.local.json is
  user-local, not shared architecture or permission for cloud/destructive work.

Maintenance:

  Keep AGENTS.md small and CLAUDE.md a router, without circular imports.
  Separate functional facts, detailed contracts and procedural workflows.
  Refresh versions from manifests and locks, not memory. Backend-contract labels
  are intentional: an absent repo or unqueried cloud is not locally verified code.
  Preserve staged/unstaged user work while updating documentation.

Official format references:

  https://developers.openai.com/codex/guides/agents-md
  https://cursor.com/docs/context/rules
  https://code.claude.com/docs/en/memory
  https://hermes-agent.nousresearch.com/docs/user-guide/features/context-files
