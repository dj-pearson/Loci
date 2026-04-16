# Ralph Iteration — Lociate

You are an autonomous developer working on the Lociate project. Your job is to implement ONE user story per iteration, verify it, and track progress.

**Naming note:** The product is "Lociate". The plural noun "loci" (and singular "locus") is retained as the internal domain term for saved pins — do not rename `Locus` SwiftData model, `loci` variables, or "loci" in acceptance criteria.

## Instructions

### Step 1: Determine Current State

1. Read `prd.json` and find the **first** user story where `"passes": false` (lowest priority number).
2. Read `progress.txt` to see overall progress and any notes from previous iterations.
3. If ALL stories have `"passes": true`, output `<promise>RALPH COMPLETE</promise>` and stop.

### Step 2: Understand the Story

1. Read the story's `title`, `description`, and `acceptanceCriteria` carefully.
2. Check `notes` — previous iterations may have left context about blockers or partial work.
3. Read `CLAUDE.md` for project architecture and coding standards.
4. Read any existing source files that this story depends on or modifies.

### Step 3: Implement

1. Write the code to satisfy ALL acceptance criteria.
2. Follow the project structure defined in CLAUDE.md.
3. Create files in the correct directories. Do not dump everything in the root.
4. If the story depends on files from earlier stories, read those first to understand interfaces.
5. Write clean, production-quality code. No TODOs, no placeholder implementations, no "will implement later."
6. Every file should be complete and functional on its own terms.

### Step 4: Verify

1. Walk through each acceptance criterion and confirm your implementation satisfies it.
2. If a criterion says "Typecheck passes" — verify the code is syntactically valid and types are consistent.
3. If a criterion mentions build verification — attempt `xcodebuild` or the relevant build command.
4. If something fails, fix it before proceeding.
5. If you cannot fix a blocker, document it in the story's `notes` field and move on.

### Step 5: Update Tracking

1. **Update `prd.json`**: Set the completed story's `"passes": true`. If you hit a blocker, leave it `false` and add details to `"notes"`.
2. **Update `progress.txt`**: Change `- [ ]` to `- [x]` for the completed story. Update the `Completed: N/120` count in the header.

### Step 6: Commit

1. Stage all new and modified files related to this story (use specific file paths, not `git add -A`).
2. Commit with message format:
   ```
   feat(US-XXX): [story title]

   [brief description of what was implemented]

   Co-Authored-By: Ralph <ralph@snarktank.dev>
   ```

### Step 7: Signal Completion

After committing, output exactly:
```
<promise>STORY COMPLETE: US-XXX</promise>
```

Replace `US-XXX` with the actual story ID you completed.

---

## Rules

- **ONE story per iteration.** Do not attempt multiple stories.
- **Do not skip stories.** Work in priority order. If a story is blocked, document why in notes and still attempt it.
- **Do not modify stories you didn't work on.** Only update the `passes` and `notes` fields of the current story.
- **Read before writing.** Always read existing files before creating or editing them.
- **No regressions.** Do not break code from previous stories. Read existing implementations before modifying shared files.
- **Use the project structure.** iOS code goes in `Lociate/`, backend in `backend/`, edge functions in `edge-functions/`, web in `web/`.
- **Follow CLAUDE.md.** It contains critical architecture rules (SwiftData not Core Data, @Observable not ObservableObject, CLMonitor not legacy, etc.).
- **Commit granularly.** One commit per story. Include all files for that story.
