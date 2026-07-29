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
       regexp_extract(JobCategories, '[0-9]{4}') AS series
FROM read_parquet(['https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2013.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2014.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2015.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2016.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2017.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2018.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2019.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2020.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2021.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2022.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2023.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2024.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2025.parquet','https://pub-317c58882ec04f329b63842c1eb65b0c.r2.dev/data/historical_jobs_2026.parquet'],
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
