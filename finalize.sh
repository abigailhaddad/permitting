#!/bin/bash
# After scan_permitting.sh finishes: build the one file non-coders need
# (permitting_jobs.csv with agency + link + incidental-mention flag) and the
# browsable web page (data.js consumed by index.html).
cd "$(dirname "$0")"
duckdb -c "
LOAD httpfs;
CREATE TABLE hits AS SELECT * FROM read_csv('results/permitting_hits.csv', header=true, all_varchar=true);
CREATE TABLE ctx AS SELECT * FROM read_csv('results/permitting_contexts.csv', header=true, all_varchar=true);

-- A posting is 'likely incidental' when every mention looks like stock
-- phrases ('weather permitting', 'time permitting', ...) rather than
-- permitting as a job subject.
CREATE TABLE flags AS
SELECT usajobsControlNumber,
       bool_and(regexp_matches(ctx,
         '(weather|time|schedule|workload|funding|funds|resources|space|conditions|circumstances|staffing|census|mission|operations|duties)\s+permitting'))
         AS all_incidental
FROM ctx GROUP BY 1;

CREATE TABLE ag AS
SELECT usajobsControlNumber::varchar AS control, hiringAgencyName, hiringDepartmentName,
       regexp_extract(JobCategories, '[0-9]{4}') AS series
FROM read_parquet(['https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2013.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2014.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2015.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2016.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2017.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2018.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2019.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2020.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2021.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2022.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2023.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2024.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2025.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2026.parquet'],
  union_by_name=true);

CREATE TABLE final AS
SELECT substr(h.month,1,4) AS year,
       h.month,
       h.title,
       coalesce(a.hiringAgencyName, '') AS agency,
       coalesce(a.hiringDepartmentName, '') AS department,
       CASE WHEN coalesce(f.all_incidental, false) THEN 'probably incidental' ELSE 'real mention' END AS mention_type,
       'https://www.usajobs.gov/job/' || h.usajobsControlNumber AS link,
       h.usajobsControlNumber
FROM hits h
LEFT JOIN flags f USING (usajobsControlNumber)
LEFT JOIN ag a ON h.usajobsControlNumber = a.control
ORDER BY h.month, h.title;

COPY final TO 'results/permitting_jobs.csv' (HEADER);
COPY (SELECT year, count(*) AS postings FROM final GROUP BY 1 ORDER BY 1) TO 'results/permitting_by_year.csv' (HEADER);

-- The agency + occupational-series combos that actually post real permitting
-- jobs; update_current.sh uses this as the profile for finding new ones.
COPY (
  SELECT a.hiringAgencyName AS agency, a.hiringDepartmentName AS department,
         a.series, count(*) AS historical_postings
  FROM final fi JOIN ag a ON fi.usajobsControlNumber = a.control
  WHERE fi.mention_type = 'real mention' AND a.series IS NOT NULL AND a.series != ''
  GROUP BY 1, 2, 3 HAVING count(*) >= 3 ORDER BY 4 DESC
) TO 'reference/permitting_agency_series.csv' (HEADER);
"
python3 - << 'EOF'
import csv, json
rows = list(csv.DictReader(open('results/permitting_jobs.csv')))
with open('data.js', 'w') as f:
    f.write('const JOBS = ')
    json.dump(rows, f)
    f.write(';')
print(f"data.js written with {len(rows)} rows")
EOF
echo "Finalize done."
