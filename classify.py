#!/usr/bin/env python3
"""
Classify each permitting posting as 'real mention' or 'probably incidental'
using the rules in patterns.yaml, then rebuild the outputs a person actually
opens: results/permitting_jobs.csv, data.js (for index.html),
results/permitting_by_year.csv, reference/permitting_agency_series.csv.

Fast and local: edit patterns.yaml, rerun this, done. No re-scanning.
Requires results/permitting_jobs_base.csv (from finalize.sh) and
results/permitting_contexts.csv (from scan_permitting.sh).
"""

import csv
import json
import re
from collections import Counter, defaultdict

import yaml

P = yaml.safe_load(open('patterns.yaml'))

stock = re.compile(
    r'(?:' + '|'.join(re.escape(w) for w in P['incidental']['stock_phrases']) + r')\s+permitting')
verb = re.compile(
    r'permitting\s+(?:' + '|'.join(re.escape(w) for w in P['incidental']['verb_following_words']) + r')\b')
overrides = [o.lower() for o in P['real_overrides']]


def classify_contexts(contexts):
    if any(o in c for c in contexts for o in overrides):
        return 'real mention'
    if all(stock.search(c) or verb.search(c) for c in contexts):
        return 'probably incidental'
    return 'real mention'


ctx_by_job = defaultdict(list)
for row in csv.DictReader(open('results/permitting_contexts.csv')):
    ctx_by_job[row['usajobsControlNumber']].append(row['ctx'].lower())

rows = []
for row in csv.DictReader(open('results/permitting_jobs_base.csv')):
    contexts = ctx_by_job.get(row['usajobsControlNumber'], [])
    row['mention_type'] = classify_contexts(contexts) if contexts else 'real mention'
    rows.append(row)

cols = ['year', 'month', 'title', 'agency', 'department', 'series', 'mention_type', 'link', 'usajobsControlNumber']
with open('results/permitting_jobs.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=cols)
    w.writeheader()
    w.writerows(rows)

with open('data.js', 'w') as f:
    f.write('const JOBS = ')
    json.dump(rows, f)
    f.write(';')

by_year = Counter(r['year'] for r in rows)
with open('results/permitting_by_year.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['year', 'postings', 'real_mentions'])
    real = Counter(r['year'] for r in rows if r['mention_type'] == 'real mention')
    for y in sorted(by_year):
        w.writerow([y, by_year[y], real.get(y, 0)])

combos = Counter((r['agency'], r['department'], r.get('series', ''))
                 for r in rows if r['mention_type'] == 'real mention' and r['agency'])
with open('reference/permitting_agency_series.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['agency', 'department', 'series', 'historical_postings'])
    for (a, d, s), n in combos.most_common():
        if n >= 3:
            w.writerow([a, d, s, n])

n_real = sum(1 for r in rows if r['mention_type'] == 'real mention')
print(f"{len(rows)} postings: {n_real} real, {len(rows) - n_real} probably incidental")
