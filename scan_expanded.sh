#!/bin/bash
# Second pass over the HISTORICAL corpus: find jobs matching any
# expansion_phrases from patterns.yaml (permitting-work jobs whose text may
# never say "permitting"). ~1 hour. The matched_phrases column shows why each
# posting was included.
# Output: results/expanded_hits.csv
cd "$(dirname "$0")"
RX=$(python3 -c "
import yaml, re
p = yaml.safe_load(open('patterns.yaml'))['expansion']
phrases = p['core_phrases'] + p['adjacent_phrases']
def b(x):
    x = re.escape(x.lower())
    wb = chr(92) + 'b'
    return (wb if x[0].isalnum() else '') + x + (wb if x[-1].isalnum() else '')
rx = '|'.join(b(x) for x in phrases)
print(rx.replace(chr(39), chr(39)*2))
")
OUT=results/expanded_hits.csv
echo "month,usajobsControlNumber,title,matched_phrases" > "$OUT"
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
      COPY (
        SELECT '$month' AS month, usajobsControlNumber, title,
               list_distinct(regexp_extract_all(lower(text), '$RX')) AS matched_phrases
        FROM read_parquet('hf://datasets/loyoladatamining/usajobs/$f')
        WHERE regexp_matches(lower(text), '$RX')
      ) TO 'tmp_exp.csv' (HEADER false);
    " > /dev/null 2> err_exp.txt; then
      cat tmp_exp.csv >> "$OUT" 2>/dev/null
      ok=1
      break
    fi
    sleep $((attempt * 5))
  done
  if [ $ok -eq 0 ]; then
    FAILED+=("$f")
    echo "FAILED after retries: $f  ($(head -1 err_exp.txt))"
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
