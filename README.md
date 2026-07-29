# permitting

Every USAJOBS announcement (2017–March 2026) whose full text contains the word
"permitting", from the HuggingFace dataset
[`loyoladatamining/usajobs`](https://huggingface.co/datasets/loyoladatamining/usajobs),
scanned remotely with DuckDB over `hf://` parquet.

## Run

```bash
bash scan_permitting.sh
```

Outputs:
- `results/permitting_hits.csv` — month, usajobsControlNumber, title
- `results/permitting_contexts.csv` — ±120 chars around each mention, for
  separating real permitting work (environmental/land use/construction) from
  incidental uses ("weather permitting", "time permitting", "permitting the
  use of...")

Announcement URLs are `https://www.usajobs.gov/job/<usajobsControlNumber>`.
Agency names can be joined from the
[usajobs_historical](https://github.com/abigailhaddad/usajobs_historical)
R2 parquet mirror on `usajobsControlNumber`.
