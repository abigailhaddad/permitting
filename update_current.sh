#!/bin/bash
# Find CURRENTLY OPEN permitting jobs. Run any time; no coding needed.
#
# Reads the live current_jobs_*.parquet mirror on R2 (refreshed by the
# usajobs_historical pipeline) and matches each open job's raw record against
# the expansion_phrases list in patterns.yaml. Edit the YAML to change what
# counts; the matched_phrases column shows why each job was included.
# Output: results/current_permitting_jobs.csv (open in Excel/Google Sheets)
cd "$(dirname "$0")"
# The current_jobs files are ~1GB with huge JSON columns; DuckDB's remote
# range reads fail reproducibly on them (local reads are fine). So: cache
# locally first. curl -z only re-downloads when R2 has a newer version.
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
LOAD httpfs;
SET http_retries=5;
COPY (
  SELECT positionTitle AS title,
         hiringAgencyName AS agency,
         hiringDepartmentName AS department,
         array_to_string(regexp_extract_all(JobCategories::varchar, '[0-9]{4}'), ' | ') AS series,
         positionOpenDate AS opens,
         positionCloseDate AS closes,
         list_distinct(regexp_extract_all(lower(CAST(MatchedObjectDescriptor AS VARCHAR)), '$RX')) AS matched_phrases,
         'https://www.usajobs.gov/job/' || usajobsControlNumber AS link
  FROM read_parquet($(python3 -c "import os; print('[' + ', '.join(chr(39) + 'cache/' + os.path.basename(u.strip()) + chr(39) for u in open('reference/r2_current_urls.txt')) + ']')"), union_by_name=true)
  WHERE regexp_matches(lower(CAST(MatchedObjectDescriptor AS VARCHAR)), '$RX')
  ORDER BY agency, title
) TO 'results/current_permitting_jobs.csv' (HEADER);
"; then
    ok=1
    break
  fi
  echo "attempt $attempt failed (transient R2 read error is common), retrying..."
  sleep $((attempt * 10))
done
if [ $ok -eq 0 ]; then
  echo "ERROR: all attempts failed; results/current_permitting_jobs.csv NOT updated" >&2
  exit 1
fi
echo "Wrote results/current_permitting_jobs.csv ($(($(wc -l < results/current_permitting_jobs.csv) - 1)) currently-listed jobs)"
