# Federal jobs that mention "permitting"

Every federal job announcement posted on USAJOBS from 2017 through March 2026
whose full text contains the word **"permitting"** (~8,800 postings), plus an
expanded search for permitting-work jobs that never use the word, plus a
one-command way to find **currently open** permitting jobs.

## If you just want the data (no coding needed)

**Open `results/permitting_jobs.csv`** — it opens in Excel or Google Sheets.
One row per historical posting:

| Column | What it means |
|---|---|
| year, month | When the job was posted (`2023_04` = April 2023) |
| title | The job title |
| agency, department | Who was hiring |
| series | Occupational series code (e.g. 0401 = biologist) |
| mention_type | `real mention` = permitting looks like part of the job. `probably incidental` = every mention was a stock phrase ("weather permitting") or verb use ("a waiver permitting you to…") |
| link | Opens the announcement on USAJOBS (older ones have expired) |

**Or double-click `index.html`** to browse the same data in your web browser —
searchable and filterable, no Excel needed.

`results/permitting_by_year.csv` is a small count of postings per year.
`results/expanded_jobs.csv` (after running the expanded scan below) covers
jobs that do permitting work under other names — NEPA reviews, NPDES,
section 404, special use permits — with a `flag` column separating "likely
permitting" from "adjacent mention."

## The rules live in patterns.yaml

Everything judgment-based is configuration, not code:

1. **Incidental filtering** — which uses of the word "permitting" don't count:
   stock phrases ("weather/budget permitting") and verb uses ("permitting you
   to…"), plus `real_overrides` that force specific phrasings to count (TTB's
   Permitting Division, APHIS's movement certificates).
2. **Grab rule** — `expansion.core_phrases` + `expansion.adjacent_phrases`:
   what the expanded scans collect. Matched case-insensitively with word
   boundaries (so "rcra" can't match inside "aircraft" — learned the hard way).
3. **Flag rule** — a grabbed posting is `likely permitting` if it matches ≥1
   core phrase or ≥`adjacent_threshold` distinct adjacent phrases; otherwise
   `adjacent mention`. The word "permitting" only counts as core when rule 1
   didn't classify the posting incidental.

Edit the YAML, then rerun the classifiers (seconds, no re-scan):

```bash
python3 classify.py            # re-classify the word-scan results
python3 classify_expanded.py   # re-flag the expanded-scan results
```

## Finding TODAY'S open permitting jobs

```bash
bash update_current.sh
```

Writes `results/current_permitting_jobs.csv` — currently open positions
matching the grab rule, with a `matched_phrases` column showing why each was
included. Reads the live-jobs mirror maintained by the
[usajobs_historical](https://github.com/abigailhaddad/usajobs_historical)
pipeline, so "current" is as fresh as that pipeline's last run.

## Rebuilding from scratch (coders)

```bash
bash scan_permitting.sh    # ~1 hr: full-text scan of ~2M announcements
                           # (HF dataset loyoladatamining/usajobs) remotely
                           # via DuckDB; nothing downloaded except hits
bash finalize.sh           # joins agency names from R2, runs classify.py
bash scan_expanded.sh      # ~1 hr: second pass with the grab-rule phrases
python3 classify_expanded.py
```

Intermediate files: `results/permitting_hits.csv` (raw word-scan),
`results/permitting_contexts.csv` (±120 chars around every mention — read
this when tuning patterns.yaml), `results/permitting_jobs_base.csv`
(pre-classification), `results/expanded_hits.csv` (raw expanded scan),
`reference/parquet_files.txt` (corpus file list).

## Caveats

- The incidental/real split is pattern-based. It was tuned by reading
  contexts (see `results/permitting_contexts.csv`) but skim before trusting
  it for anything load-bearing.
- Posting volume isn't constant: overall federal hiring collapsed in 2025,
  so raw counts need a denominator for trend claims.
- "Adjacent mention" jobs (one NEPA/environmental-review phrase, nothing
  else) are deliberately not flagged — many are compliance jobs, not
  permitting jobs. Raise or lower `adjacent_threshold` in patterns.yaml to
  taste.
