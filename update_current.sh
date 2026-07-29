#!/bin/bash
# Find CURRENTLY OPEN permitting jobs. Run this any time; no coding needed.
#
# Sources: the live current_jobs_*.parquet files on R2 (refreshed by the
# usajobs_historical pipeline). Two ways a job qualifies:
#   1. "text match"             — the announcement's raw API record contains
#                                 the word "permitting"
#   2. "agency+series profile"  — its agency + occupational series combo
#                                 historically posts real permitting jobs
#                                 (reference/permitting_agency_series.csv,
#                                 built by finalize.sh)
# Output: results/current_permitting_jobs.csv (open in Excel/Google Sheets)
cd "$(dirname "$0")"
duckdb -c "
LOAD httpfs;
CREATE TABLE profile AS SELECT * FROM read_csv('reference/permitting_agency_series.csv', header=true, all_varchar=true);
CREATE TABLE cur AS
SELECT usajobsControlNumber,
       positionTitle,
       hiringAgencyName,
       hiringDepartmentName,
       regexp_extract(JobCategories::varchar, '[0-9]{4}') AS series,
       positionOpenDate,
       positionCloseDate,
       (CAST(MatchedObjectDescriptor AS VARCHAR) ILIKE '%permitting%') AS text_match
FROM read_parquet(['https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/current_jobs_2025.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/current_jobs_2026.parquet'], union_by_name=true);
COPY (
  SELECT DISTINCT c.positionTitle AS title,
         c.hiringAgencyName AS agency,
         c.hiringDepartmentName AS department,
         c.series,
         c.positionOpenDate AS opens,
         c.positionCloseDate AS closes,
         CASE WHEN c.text_match THEN 'text match' ELSE 'agency+series profile' END AS how_found,
         'https://www.usajobs.gov/job/' || c.usajobsControlNumber AS link
  FROM cur c
  LEFT JOIN profile p ON c.hiringAgencyName = p.agency AND c.series = p.series
  WHERE c.text_match OR p.agency IS NOT NULL
  ORDER BY how_found, agency, title
) TO 'results/current_permitting_jobs.csv' (HEADER);
"
echo "Wrote results/current_permitting_jobs.csv:"
head -1 results/current_permitting_jobs.csv
echo "$(($(wc -l < results/current_permitting_jobs.csv) - 1)) currently-listed jobs"
