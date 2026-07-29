#!/bin/bash
# Scan every USAJOBS announcement (HF dataset loyoladatamining/usajobs) for the
# word "permitting"; save one row per posting plus context windows around each
# mention. Per-file with retries (HF range reads occasionally fail).
cd "$(dirname "$0")"
OUT=results/permitting_hits.csv
CTX=results/permitting_contexts.csv
mkdir -p results
echo "month,usajobsControlNumber,title" > "$OUT"
echo "month,usajobsControlNumber,ctx" > "$CTX"
FAILED=()
i=0
total=$(wc -l < reference/parquet_files.txt | tr -d ' ')
while IFS= read -r f; do
  i=$((i+1))
  month=$(echo "$f" | sed -E 's|postings/([0-9]{4}_[0-9]{2}).*|\1|')
  ok=0
  for attempt in 1 2 3; do
    if duckdb -c "
      LOAD httpfs;
      SET http_retries=5;
      CREATE TABLE src AS SELECT usajobsControlNumber, title, lower(text) AS t
        FROM read_parquet('hf://datasets/loyoladatamining/usajobs/$f')
        WHERE regexp_matches(text, '(?i)\bpermitting\b');
      COPY (SELECT '$month' AS month, usajobsControlNumber, title FROM src)
        TO 'tmp_hit.csv' (HEADER false);
      COPY (SELECT '$month' AS month, usajobsControlNumber,
                   unnest(regexp_extract_all(t, '.{0,120}permitting.{0,120}')) AS ctx
            FROM src)
        TO 'tmp_ctx.csv' (HEADER false);
    " > /dev/null 2> err.txt; then
      cat tmp_hit.csv >> "$OUT" 2>/dev/null
      cat tmp_ctx.csv >> "$CTX" 2>/dev/null
      ok=1
      break
    fi
    sleep $((attempt * 5))
  done
  if [ $ok -eq 0 ]; then
    FAILED+=("$f")
    echo "FAILED after retries: $f  ($(head -1 err.txt))"
  fi
  if [ $((i % 20)) -eq 0 ]; then
    echo "progress: $i/$total files, $(($(wc -l < "$OUT") - 1)) hits so far"
  fi
done < reference/parquet_files.txt
echo "DONE: scanned $i files, $(($(wc -l < "$OUT") - 1)) total hits"
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "Files that never succeeded:"
  printf '%s\n' "${FAILED[@]}"
fi
