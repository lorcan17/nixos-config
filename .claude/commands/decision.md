---
description: Capture a decision to DECISIONS.md in ADR-lite format, and add a pointer row to PROJECT_STATUS.md
---

Record a decision made during this conversation.

**Title (from arguments, or infer from recent context if empty):** $ARGUMENTS

## What to do

1. Open `DECISIONS.md` at the repo root.
2. Insert a new entry **after the intro block and before the first existing entry** (most recent at top). Use exactly this structure:

   - `## <today's date, YYYY-MM-DD> — <Title>`
   - `**Context:**` — 1–2 sentences on what prompted this decision.
   - `**Decision:**` — what was chosen.
   - `**Rationale:**` — the key reasons, including the tradeoffs weighed against alternatives. Bullet points are fine if there are multiple distinct reasons.
   - `**Consequences:**` — what follows from this choice: files/modules affected, new constraints, costs, new secrets required.
   - `**Revisit if:**` — the conditions under which this should be reconsidered.
   - A horizontal rule (`---`) after the entry.

3. Open `PROJECT_STATUS.md` and add a new row at the top of the Decision Log index table (below the header, above existing rows):

   `| <today's date, YYYY-MM-DD> | <Title> |`

## Rules

- Fill every field from the preceding conversation context. **Do not** leave placeholders or write "N/A".
- If a field genuinely has no meaningful content, omit the whole line rather than writing filler.
- Use today's date from the environment's `currentDate`, not a guessed date.
- Keep the title short and declarative (e.g. "Docker accepted as required"), not phrased as a question.
- If the conversation hasn't actually produced a real decision yet, stop and ask the user to clarify what the decision is rather than fabricating one.
