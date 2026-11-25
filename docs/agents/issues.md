# Issue storage

- Backend: csv
- Location: docs/roadmaps/jido-studio-v3.csv
- CLI: none
- Authority: local
- Guidance: Use one writer. Read the full file before a write. Use a CSV
  parser to create or update records. Keep decision IDs stable and enter
  prerequisite IDs in `blocked_by`. A decision is ready when its status is open
  and all its prerequisites are resolved. To claim a decision, set its owner
  and status to `in_progress`. To resolve it, record its answer and evidence.
  Increment the row revision and set the update timestamp for each change.
  The roadmap can cite existing GitHub issues.
- Last checked: 2026-11-24
