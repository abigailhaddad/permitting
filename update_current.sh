#!/bin/bash
# Extend the dataset past the HF corpus cutoff (March 2026) using the
# current-jobs mirror — a running archive of every job the live USAJOBS API
# has seen this year. Run any time.
#
# 1. Sync the archive parquet files locally (they're ~1GB with huge JSON
#    columns; DuckDB's remote range reads fail on them, local reads work.
#    curl -z only re-downloads when R2 has a newer version).
# 2. Take archive jobs that mention "permitting", opened AFTER the corpus
#    cutoff, and not already in our scraped data -> same shape as the
#    word-scan pipeline (a base file + context snippets). classify.py then
#    folds them into permitting_jobs.csv and the website.
# 3. Also write results/current_permitting_jobs.csv: jobs matching the
#    expanded vocabulary (patterns.yaml) whose close date hasn't passed.
cd "$(dirname "$0")"
CORPUS_CUTOFF='2026-03-31'

mkdir -p cache
while IFS= read -r url; do
  f="cache/$(basename "$url")"
  echo "syncing $f ..."
  curl -sS $([ -f "$f" ] && echo -z "$f") -o "$f" "$url" || { echo "download failed: $url" >&2; exit 1; }
done < reference/r2_current_urls.txt

RX=$(python3 build_rx.py)
ok=0
for attempt in 1 2 3; do
  if duckdb -c "
CREATE TABLE already AS SELECT usajobsControlNumber FROM read_csv('results/permitting_jobs_base.csv', header=true, all_varchar=true);
CREATE TABLE archive AS
SELECT usajobsControlNumber::varchar AS control,
       positionTitle AS title,
       hiringAgencyName AS agency,
       hiringDepartmentName AS department,
       array_to_string(regexp_extract_all(JobCategories::varchar, '[0-9]{4}'), ' | ') AS series,
       substr(positionOpenDate, 1, 10) AS open_date,
       positionCloseDate,
       lower(CAST(MatchedObjectDescriptor AS VARCHAR)) AS t
FROM read_parquet($(python3 -c "import os; print('[' + ', '.join(chr(39) + 'cache/' + os.path.basename(u.strip()) + chr(39) for u in open('reference/r2_current_urls.txt')) + ']')"), union_by_name=true);

-- New word-mention postings for the main dataset
CREATE TABLE new_hits AS
SELECT * FROM archive
WHERE regexp_matches(t, '(?i)\bpermitting\b')
  AND open_date > '$CORPUS_CUTOFF'
  AND control NOT IN (SELECT usajobsControlNumber FROM already);
COPY (
  SELECT substr(open_date, 1, 4) AS year,
         replace(substr(open_date, 1, 7), '-', '_') AS month,
         title, coalesce(agency, '') AS agency, coalesce(department, '') AS department,
         series,
         'https://www.usajobs.gov/job/' || control AS link,
         control AS usajobsControlNumber
  FROM new_hits ORDER BY month, title
) TO 'results/permitting_jobs_archive_base.csv' (HEADER);
COPY (
  SELECT replace(substr(open_date, 1, 7), '-', '_') AS month, control AS usajobsControlNumber,
         unnest(regexp_extract_all(t, '.{0,120}permitting.{0,120}')) AS ctx
  FROM new_hits
) TO 'results/permitting_contexts_archive.csv' (HEADER);

-- Currently open jobs matching the expanded vocabulary
COPY (
  SELECT title, agency, department, series,
         open_date AS opens, positionCloseDate AS closes,
         list_distinct(regexp_extract_all(t, '$RX')) AS matched_phrases,
         'https://www.usajobs.gov/job/' || control AS link
  FROM archive
  WHERE regexp_matches(t, '$RX')
    AND (positionCloseDate IS NULL OR positionCloseDate = '' OR substr(positionCloseDate, 1, 10) >= strftime(current_date, '%Y-%m-%d'))
  ORDER BY agency, title
) TO 'results/current_permitting_jobs.csv' (HEADER);
"; then
    ok=1
    break
  fi
  echo "attempt $attempt failed, retrying..."
  sleep $((attempt * 10))
done
if [ $ok -eq 0 ]; then
  echo "ERROR: all attempts failed; outputs NOT updated" >&2
  exit 1
fi
echo "new archive postings: $(($(wc -l < results/permitting_jobs_archive_base.csv) - 1))"
echo "currently open (expanded vocab): $(($(wc -l < results/current_permitting_jobs.csv) - 1))"
python3 classify.py
