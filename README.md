# Federal permitting jobs

Which federal jobs involve permitting work, 2017 to now.

Browse it: **https://abigailhaddad.github.io/permitting/**

The data combines two sources: the
[`loyoladatamining/usajobs`](https://huggingface.co/datasets/loyoladatamining/usajobs)
scraped corpus (~2M announcements, 2017–March 2026) and the
[usajobs_historical](https://github.com/abigailhaddad/usajobs_historical)
USAJOBS current jobs API archive, which extends coverage from the corpus cutoff to the
present. Postings from both go through the same classification rules.

## What we did

1. **Searched the full text of ~2M USAJOBS announcements** (2017–March 2026,
   the [`loyoladatamining/usajobs`](https://huggingface.co/datasets/loyoladatamining/usajobs)
   dataset) for the word "permitting" — 8,827 postings — and saved the ±120
   characters around every occurrence.

2. **Read the snippets and wrote rules for which mentions are real.** Lots of
   announcements say "permitting" without the job involving permits:
   "weather permitting," "budget permitting," and OCC's ethics clause
   ("a waiver determination **permitting** you to retain bank securities"),
   which appears in every OCC announcement and alone accounted for ~2,400
   postings. A mention is *incidental* if it's "<word> permitting" from a
   known list (weather, budget, time, …) or "permitting <pronoun/article>"
   (verb use). A posting is `probably incidental` only if *every* mention is
   incidental; anything else is a `real mention`. A short override list
   forces phrasings we checked by hand to count (TTB's Permitting Division;
   APHIS "issues certificates permitting the movement of regulated
   articles"). Split: **4,677 real / 4,150 probably incidental**.

3. **Ran a second search for permitting work that skips the word.** From the
   real postings' snippets we collected the vocabulary that co-occurs with
   permitting (NEPA, NPDES, section 404, special use permits, …) and searched
   the corpus again. Postings that don't say "permitting" are flagged
   `likely permitting` (a precise term like "permit applications" or NPDES,
   or 2+ broader ones like NEPA + Clean Water Act) or `adjacent mention` (one
   broad term only — often environmental-review compliance rather than
   permitting work). Everything except adjacent mentions is on the website;
   the CSVs have it all.

4. **Joined agency, department, and occupational series** for every posting
   from the [usajobs_historical](https://github.com/abigailhaddad/usajobs_historical)
   R2 mirror, by control number.

5. **Kept the dataset current.** The corpus ends March 2026, but the
   [usajobs_historical](https://github.com/abigailhaddad/usajobs_historical)
   pipeline maintains a running archive of every job the live API sees.
   `update_current.sh` pulls "permitting" postings opened after the cutoff
   that we don't already have, runs them through the same rules, and adds
   them to the dataset and the website. It also writes a list of jobs
   matching the step-3 vocabulary that are still open right now.

Every list and threshold from steps 2–3 lives in **`patterns.yaml`**. Edit it
and rerun the classifiers (seconds, no re-searching) to change what counts.

## The data

| File | What it is |
|---|---|
| `results/permitting_jobs.csv` | Postings that say "permitting" (~9k): year, month, title, agency, department, series, mention_type, USAJOBS link. **Start here.** |
| `results/expanded_jobs.csv` | Postings matching the wider vocabulary without the word (~41k), same columns plus why |
| `results/current_permitting_jobs.csv` | Currently open jobs matching the vocabulary, with matched terms per job |
| `results/permitting_by_year.csv` | Postings per year |
| `results/permitting_contexts.csv` | The raw text snippets around every "permitting" — the evidence behind mention_type |

All CSVs open in Excel/Google Sheets. Links open the announcement on USAJOBS
(closed jobs still display, marked as closed).

The web viewer (`index.html`, or the link up top) shows
`permitting_jobs.csv` with column filters, shareable filter URLs, and CSV
download. Hover a mention type for the words behind the call; click it to
read the actual snippets.

## Rebuilding

```bash
bash scan_permitting.sh      # ~1 hr: search corpus for "permitting" + save snippets
bash join_agencies.sh        # join agency/series from R2, then classify
bash scan_expanded.sh        # ~1 hr: search corpus for the step-3 vocabulary
bash update_current.sh       # pull post-cutoff postings from the live archive
                             #   into the dataset + refresh the open-jobs list
                             #   (caches ~2GB locally on first run)
python3 classify.py          # rerun after editing patterns.yaml (no re-search)
```

Pipeline: `scan_permitting.sh` → `results/permitting_hits.csv` + contexts →
`join_agencies.sh` → `results/permitting_jobs_base.csv` → `classify.py` →
final CSVs + viewer data (`data.js`, `contexts.js`).

## Caveats

- We wrote the incidental/real rules by reading snippets until the calls
  looked right — nobody has hand-checked a random sample to measure how often
  they're wrong. Skim `permitting_contexts.csv` (or click through mention
  types in the viewer) before leaning on the split for anything important.
- Counts are raw. Federal posting volume collapsed in 2025, so trends need a
  denominator.
- A job can do permitting work without using any term we search for; the
  expanded search narrows that gap but doesn't close it.
