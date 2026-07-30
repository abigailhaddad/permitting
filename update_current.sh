#!/bin/bash
# Find CURRENTLY OPEN permitting jobs. Run any time; no coding needed.
#
# Reads the live current_jobs_*.parquet mirror on R2 (refreshed by the
# usajobs_historical pipeline) and matches each open job's raw record against
# the expansion_phrases list in patterns.yaml. Edit the YAML to change what
# counts; the matched_phrases column shows why each job was included.
# Output: results/current_permitting_jobs.csv (open in Excel/Google Sheets)
cd "$(dirname "$0")"
RX=$(python3 -c "
import yaml, re
p = yaml.safe_load(open('patterns.yaml'))['expansion']
phrases = p['core_phrases'] + p['adjacent_phrases']
def b(x):
    x = re.escape(x.lower())
    return ('\\b' if x[0].isalnum() else '') + x + ('\\b' if x[-1].isalnum() else '')
rx = '|'.join(b(x) for x in phrases)
print(rx.replace(chr(39), chr(39)*2))
")
duckdb -c "
LOAD httpfs;
COPY (
  SELECT positionTitle AS title,
         hiringAgencyName AS agency,
         hiringDepartmentName AS department,
         regexp_extract(JobCategories::varchar, '[0-9]{4}') AS series,
         positionOpenDate AS opens,
         positionCloseDate AS closes,
         list_distinct(regexp_extract_all(lower(CAST(MatchedObjectDescriptor AS VARCHAR)), '$RX')) AS matched_phrases,
         'https://www.usajobs.gov/job/' || usajobsControlNumber AS link
  FROM read_parquet(['https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/current_jobs_2025.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/current_jobs_2026.parquet'], union_by_name=true)
  WHERE regexp_matches(lower(CAST(MatchedObjectDescriptor AS VARCHAR)), '$RX')
  ORDER BY agency, title
) TO 'results/current_permitting_jobs.csv' (HEADER);
"
echo "Wrote results/current_permitting_jobs.csv ($(($(wc -l < results/current_permitting_jobs.csv) - 1)) currently-listed jobs)"
