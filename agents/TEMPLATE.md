# <Name> Agent

Template for every file in `agents/`. Copy it, fill it in, delete this
paragraph and the notes in `<...>`.

Multica provides **no markdown format for agents**. An agent is an API record
created by `multica agent create` / `POST /api/agents`; `instructions` is a
free-form string with no validation, and `name` plus `runtime_id` are the only
required fields. This file layout is a repository convention, not a platform
one — it exists so the instructions the platform stores as an opaque blob get
version control, diffs, and review.

## Purpose

<One line. What this agent is for.>

## Multica Settings

- Name: `<the agent's name in Multica>`
- Runtime: `<runtime type>`. Record the actual `runtime_id` you bound.
- Model: `<tier, e.g. high reasoning model>`
- Max concurrent tasks: `<n>`
- Visibility: `workspace`
- Instruction version: `<YYYY-MM-DD.n>`

## Matt Skills

- `<skill>` — from `matt-skills/`, bound by name in Multica.

## Workspace Skills

- `<skill>` (path `skills/<name>`, not `matt-skills/`)

## Instructions

````md
<Everything inside this fence is the literal `--instructions` payload, byte for
byte. It must be self-contained: an agent must be able to paste it into
`multica agent create --instructions` with no surrounding context. Do not refer
to "the file above", to sibling `agents/*.md` files, or to this template.>
````

---

## Field notes

Contract details that bite when you load one of these into a workspace:

- **`description` never reaches the runtime.** It is catalogue metadata, capped
  at 255 code points. Only `instructions` is passed to the provider at claim
  time. A rich description with empty instructions produces a named shell with
  no operating contract. The convention here is to store the
  `Instruction version` in it, which fits.
- **`agent create` does not bind skills.** The HTTP body accepts `skill_ids`,
  but the CLI create path binds nothing — bind explicitly afterward.
  `multica agent copy` does bind in the same transaction.
- **`skill set` replaces all bindings.** Use `skill add` when you mean add.
- **`conversation_starters` has no CLI flag** on create or update; only
  `agent copy` carries an existing value forward. Setting it means calling the
  API directly or using the web UI.
- **`max_concurrent_tasks`** is 1-50 and defaults to 6. Every agent here
  specifies `1`. That is deliberate serialisation — keep it.
- **Squad `instructions` are leader briefing content**, injected into the leader
  only. They never reach members. See `agents/squad.md`.

## Deployment sync rule

`agents/*.md` is the design source; the Multica server's stored `instructions`
is the runtime copy. Editing this file changes nothing on the server. Every
edit requires:

1. Sync the agent's `## Instructions` block to Multica.
2. Record the same `Instruction version` in the agent's Multica description.
3. Verify the agent name, bound skills, and `max_concurrent_tasks`.
4. Run one side-effect-free smoke issue to verify status transitions, PR
   evidence reads, and the handoff.
