#!/bin/bash
# After scan_permitting.sh: join agency names + occupational series from the
# usajobs_historical R2 mirror, write results/permitting_jobs_base.csv, then
# run classify.py (patterns.yaml) to build the final outputs.
cd "$(dirname "$0")"
duckdb -c "
LOAD httpfs;
CREATE TABLE hits AS SELECT * FROM read_csv('results/permitting_hits.csv', header=true, all_varchar=true);
CREATE TABLE ag AS
SELECT usajobsControlNumber::varchar AS control, hiringAgencyName, hiringDepartmentName,
       array_to_string(regexp_extract_all(coalesce(JobCategories, jobcategories_1, ''), '[0-9]{4}'), ' | ') AS series
FROM read_parquet($(python3 -c "print('[' + ', '.join(chr(39) + u.strip() + chr(39) for u in open('reference/r2_historical_urls.txt')) + ']')"),
  union_by_name=true);
COPY (
  SELECT substr(h.month,1,4) AS year,
         h.month,
         h.title,
         coalesce(a.hiringAgencyName, '') AS agency,
         coalesce(a.hiringDepartmentName, '') AS department,
         coalesce(a.series, '') AS series,
         'https://www.usajobs.gov/job/' || h.usajobsControlNumber AS link,
         h.usajobsControlNumber
  FROM hits h
  LEFT JOIN ag a ON h.usajobsControlNumber = a.control
  ORDER BY h.month, h.title
) TO 'results/permitting_jobs_base.csv' (HEADER);
"
python3 classify.py
