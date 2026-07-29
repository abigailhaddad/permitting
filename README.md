# Federal jobs that mention "permitting"

This folder contains every federal job announcement posted on USAJOBS from
2017 through March 2026 whose full text contains the word **"permitting"**,
plus a one-command way to find **currently open** permitting jobs.

## If you just want the data (no coding needed)

**Open `results/permitting_jobs.csv`** — it opens in Excel or Google Sheets.
One row per historical job posting:

| Column | What it means |
|---|---|
| year, month | When the job was posted (`2023_04` = April 2023) |
| title | The job title |
| agency, department | Who was hiring |
| mention_type | `real mention` = permitting looks like part of the job. `probably incidental` = every mention was a stock phrase like "weather permitting" |
| link | Click to open the announcement on USAJOBS (older ones have expired) |

**Or double-click `index.html`** to browse the same data in your web browser —
searchable and filterable, no Excel needed.

`results/permitting_by_year.csv` is a small count of postings per year.

## Finding TODAY'S open permitting jobs

```bash
bash update_current.sh
```

That writes `results/current_permitting_jobs.csv` — currently open positions
whose records match any phrase in the `expansion_phrases` list in
**`patterns.yaml`** (the word "permitting" itself, plus phrases like
"environmental review" and "special use permit" that permitting jobs use even
when they skip the word). The `matched_phrases` column shows why each job was
included. It reads the live-jobs mirror maintained by the
[usajobs_historical](https://github.com/abigailhaddad/usajobs_historical)
pipeline, so "current" is as fresh as that pipeline's last run.

## Tuning the rules (no re-scan needed)

All judgment calls live in **`patterns.yaml`**:

- which "permitting" mentions are incidental (stock phrases like "weather
  permitting", verb uses like OCC's "waiver determination permitting you to
  retain bank securities" that appears in every OCC announcement)
- overrides that force specific phrasings to count as real (TTB's "permitting
  and taxation" division, APHIS's "certificates permitting the movement")
- the `expansion_phrases` used to find permitting jobs that never say
  "permitting"

Edit the YAML, then run `python3 classify.py` — it re-classifies everything
and rebuilds the spreadsheet, web page, and per-year counts in seconds.

To apply the expansion phrases to the whole historical corpus (find jobs that
never say "permitting" at all), run `bash scan_expanded.sh` (~1 hour) —
results land in `results/expanded_hits.csv` with a `matched_phrases` column.
Review `expansion_phrases` in the YAML first; the current list is a starting
point and the environmental-review phrases will also catch
permitting-adjacent jobs.

## How the historical data was built (coders)

```bash
bash scan_permitting.sh   # ~1 hour: full-text scans ~2M announcements
                          # (HF dataset loyoladatamining/usajobs) remotely
                          # with DuckDB; nothing downloaded except hits
bash finalize.sh          # joins agency names, builds permitting_jobs.csv,
                          # the web page data (data.js), and the
                          # agency/series profile
```

Other files:
- `results/permitting_hits.csv` — raw scan output (month, control number, title)
- `results/permitting_contexts.csv` — the sentence fragment around every
  "permitting" mention; read this to see how the word is used, or to build a
  better real-vs-incidental classifier
- `reference/parquet_files.txt` — the corpus file list

## Caveats

- The `mention_type` flag is a simple pattern check ("weather/time/funding
  permitting" etc.). It's conservative — one non-stock mention makes a
  posting a `real mention`. Skim the contexts file before trusting it for
  anything load-bearing.
- Jobs that describe permitting work without the word (only "NEPA review",
  "licenses and authorizations") won't appear in the historical text scan;
  the agency+series profile in `update_current.sh` partially compensates.
- The agency+series profile requires ≥3 historical real-mention postings for
  a combo, to keep one-off flukes out.
