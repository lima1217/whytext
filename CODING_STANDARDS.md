# Coding standards

Judgement rules for reviewing a diff. Mechanical rules live in the checks instead: `scripts/ux-audit.py` (font sizes, colors, contrast, materials, italic/monospaced/uppercase reasons, number formatting) and `WhyTextCoreSmokeTests` (translation coverage and placeholders). Apply every rule below to every changed line of UI code and copy; section numbers refer to `docs/design/guidelines.md`.

## Copy

- **Native**: each language reads as if written by a native speaker, using the macOS term for system concepts (§1 term table). A new system term gets a row in that table.
- **One verb per action**: an action label uses the verb already assigned to that action (§1 verb table); a new kind of action gets a row there first. Labels describe, never urge.
- **Earned text**: every explanatory line passes the §2 test — without it the user would get stuck. A line the control already says is removed.
- **Longest language fits**: labels and buttons wrap or are reworded; nothing is truncated or shrunk to fit (§2).

## Behaviour

- **Confirmation only for loss**: a dialog appears only before an action that destroys something the user made and can't get back (§7). Everything else acts at once.
- **States**: a new screen or flow handles empty, loading, error and missing-permission states, or the diff says why one can't occur.

## Docs

- A change to a control, its copy, or a flow updates the lines of `docs/manual-checklist.md` that name it.
- A design decision that settles a §8 conflict is recorded in that table with its date.
