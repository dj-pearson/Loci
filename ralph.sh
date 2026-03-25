#!/bin/bash
# ============================================================================
# ralph.sh — Autonomous Ralph Loop for Loci
# Runs Claude Code CLI in non-interactive mode, one user story per iteration.
# Usage: bash ralph.sh [--max-iterations N] [--delay SECONDS]
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRD_FILE="$PROJECT_DIR/prd.json"
PROGRESS_FILE="$PROJECT_DIR/progress.txt"
PROMPT_FILE="$PROJECT_DIR/ralph-prompt.md"
LOG_DIR="$PROJECT_DIR/.ralph-logs"

MAX_ITERATIONS=120          # Default: run all stories
MAX_TURNS_PER_STORY=75      # Max Claude turns per story
DELAY_BETWEEN=10            # Seconds between iterations
RESUME_ON_FAILURE=true      # Continue to next story on failure

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
    --delay)          DELAY_BETWEEN="$2"; shift 2 ;;
    --max-turns)      MAX_TURNS_PER_STORY="$2"; shift 2 ;;
    --stop-on-fail)   RESUME_ON_FAILURE=false; shift ;;
    -h|--help)
      echo "Usage: bash ralph.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --max-iterations N   Max iterations to run (default: 120)"
      echo "  --max-turns N        Max Claude turns per story (default: 75)"
      echo "  --delay SECONDS      Pause between iterations (default: 10)"
      echo "  --stop-on-fail       Stop loop if a story fails"
      echo "  -h, --help           Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
echo "============================================"
echo "  RALPH — Loci Autonomous Build Loop"
echo "============================================"
echo ""

# Check Claude CLI is available
if ! command -v claude &>/dev/null; then
  echo "ERROR: 'claude' CLI not found. Install Claude Code first."
  echo "  npm install -g @anthropic-ai/claude-code"
  exit 1
fi

# Check required files exist
for f in "$PRD_FILE" "$PROGRESS_FILE" "$PROMPT_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Required file missing: $f"
    exit 1
  fi
done

# Create log directory
mkdir -p "$LOG_DIR"

# Initialize git if needed
if [[ ! -d "$PROJECT_DIR/.git" ]]; then
  echo "Initializing git repository..."
  cd "$PROJECT_DIR"
  git init
  git add CLAUDE.md prd.json progress.txt ralph-prompt.md ralph.sh
  git commit -m "Initial commit: Ralph project scaffolding

Co-Authored-By: Ralph <ralph@snarktank.dev>"
  echo ""
fi

# ---------------------------------------------------------------------------
# Helper: count remaining stories
# ---------------------------------------------------------------------------
count_remaining() {
  python -c "
import json, sys
with open('$PRD_FILE', 'r', encoding='utf-8') as f:
    data = json.load(f)
remaining = sum(1 for s in data['userStories'] if not s['passes'])
print(remaining)
"
}

# ---------------------------------------------------------------------------
# Helper: get next story ID
# ---------------------------------------------------------------------------
next_story_id() {
  python -c "
import json, sys
with open('$PRD_FILE', 'r', encoding='utf-8') as f:
    data = json.load(f)
for s in sorted(data['userStories'], key=lambda x: x['priority']):
    if not s['passes']:
        print(s['id'])
        sys.exit(0)
print('DONE')
"
}

# ---------------------------------------------------------------------------
# Helper: get story title by ID
# ---------------------------------------------------------------------------
story_title() {
  local sid="$1"
  python -c "
import json, sys
with open('$PRD_FILE', 'r', encoding='utf-8') as f:
    data = json.load(f)
for s in data['userStories']:
    if s['id'] == '$sid':
        print(s['title'])
        sys.exit(0)
print('Unknown')
"
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
cd "$PROJECT_DIR"
ITERATION=0

echo "Max iterations:  $MAX_ITERATIONS"
echo "Max turns/story: $MAX_TURNS_PER_STORY"
echo "Delay between:   ${DELAY_BETWEEN}s"
echo "Stop on fail:    $([ "$RESUME_ON_FAILURE" = true ] && echo 'no' || echo 'yes')"
echo ""

REMAINING=$(count_remaining)
echo "Stories remaining: $REMAINING / $(python -c "import json; d=json.load(open('$PRD_FILE','r',encoding='utf-8')); print(len(d['userStories']))")"
echo ""

if [[ "$REMAINING" -eq 0 ]]; then
  echo "All stories are already complete! Nothing to do."
  exit 0
fi

echo "Starting Ralph loop in 5 seconds... (Ctrl+C to cancel)"
sleep 5
echo ""

while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
  ITERATION=$((ITERATION + 1))
  STORY_ID=$(next_story_id)

  if [[ "$STORY_ID" == "DONE" ]]; then
    echo ""
    echo "============================================"
    echo "  ALL STORIES COMPLETE!"
    echo "  Total iterations: $ITERATION"
    echo "============================================"
    break
  fi

  TITLE=$(story_title "$STORY_ID")
  REMAINING=$(count_remaining)
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  LOG_FILE="$LOG_DIR/${STORY_ID}_$(date '+%Y%m%d_%H%M%S').log"

  echo "--------------------------------------------"
  echo "  Iteration $ITERATION | $STORY_ID: $TITLE"
  echo "  Remaining: $REMAINING | Started: $TIMESTAMP"
  echo "  Log: $LOG_FILE"
  echo "--------------------------------------------"
  echo ""

  # Read the prompt
  PROMPT=$(cat "$PROMPT_FILE")

  # Run Claude Code in non-interactive mode
  # --print: non-interactive, exits after completion
  # --max-turns: limit context usage per story
  # --verbose: log activity
  set +e
  claude -p "$PROMPT" \
    --max-turns "$MAX_TURNS_PER_STORY" \
    --verbose \
    2>&1 | tee "$LOG_FILE"
  EXIT_CODE=$?
  set -e

  # Check result
  if [[ $EXIT_CODE -ne 0 ]]; then
    echo ""
    echo "WARNING: Claude exited with code $EXIT_CODE for $STORY_ID"
    if [[ "$RESUME_ON_FAILURE" = false ]]; then
      echo "Stopping (--stop-on-fail is set)."
      exit 1
    fi
    echo "Continuing to next iteration..."
  fi

  # Check if story was marked complete
  NEW_STORY_ID=$(next_story_id)
  if [[ "$NEW_STORY_ID" == "$STORY_ID" ]]; then
    echo ""
    echo "NOTE: $STORY_ID was NOT marked as complete."
    echo "Claude may have hit a blocker. Check $LOG_FILE for details."
    echo "Re-attempting on next iteration..."
  else
    echo ""
    echo "OK: $STORY_ID completed successfully."
  fi

  # Pause between iterations
  if [[ $ITERATION -lt $MAX_ITERATIONS ]]; then
    NEXT_ID=$(next_story_id)
    if [[ "$NEXT_ID" != "DONE" ]]; then
      echo "Next up: $NEXT_ID — $(story_title "$NEXT_ID")"
      echo "Pausing ${DELAY_BETWEEN}s before next iteration..."
      sleep "$DELAY_BETWEEN"
    fi
  fi

  echo ""
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo "  Ralph Session Complete"
echo "============================================"
REMAINING=$(count_remaining)
TOTAL=$(python -c "import json; d=json.load(open('$PRD_FILE','r',encoding='utf-8')); print(len(d['userStories']))")
COMPLETED=$((TOTAL - REMAINING))
echo "  Completed: $COMPLETED / $TOTAL stories"
echo "  Iterations: $ITERATION"
echo "  Logs: $LOG_DIR/"
echo "============================================"
