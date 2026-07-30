#!/usr/bin/env python3
"""
Classify each permitting posting as 'real mention' or 'probably incidental'
using the rules in patterns.yaml, then rebuild the outputs a person actually
opens: results/permitting_jobs.csv, data.js (for index.html),
results/permitting_by_year.csv, reference/permitting_agency_series.csv.

Fast and local: edit patterns.yaml, rerun this, done. No re-scanning.
Requires results/permitting_jobs_base.csv (from join_agencies.sh) and
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
    """Return (mention_type, why) -- why lists the specific matched words."""
    hit_overrides = sorted(set(o for c in contexts for o in overrides if o in c))
    if hit_overrides:
        return 'real mention', 'matched: ' + '; '.join(hit_overrides)
    incidental_hits = set()
    all_incidental = True
    for c in contexts:
        m = stock.search(c) or verb.search(c)
        if m:
            incidental_hits.add(m.group(0))
        else:
            all_incidental = False
    if contexts and all_incidental:
        return 'probably incidental', 'only matched: ' + '; '.join(sorted(incidental_hits))
    return 'real mention', 'mention(s) not matching any incidental pattern' + (
        '; incidental matches too: ' + '; '.join(sorted(incidental_hits)) if incidental_hits else '')


ctx_by_job = defaultdict(list)
ctx_files = ['results/permitting_contexts.csv', 'results/permitting_contexts_archive.csv']
for path in ctx_files:
    try:
        f = open(path)
    except FileNotFoundError:
        continue
    for row in csv.DictReader(f):
        ctx_by_job[row['usajobsControlNumber']].append(row['ctx'].lower())

# The HF-corpus scan plus any newer postings pulled from the current-jobs
# archive (update_current.sh); the archive file already excludes controls
# present in the corpus base.
base_files = ['results/permitting_jobs_base.csv', 'results/permitting_jobs_archive_base.csv']
rows = []
seen_controls = set()
base_rows = []
for path in base_files:
    try:
        f = open(path)
    except FileNotFoundError:
        continue
    for row in csv.DictReader(f):
        if row['usajobsControlNumber'] in seen_controls:
            continue
        seen_controls.add(row['usajobsControlNumber'])
        base_rows.append(row)

for row in base_rows:
    contexts = ctx_by_job.get(row['usajobsControlNumber'], [])
    if contexts:
        row['mention_type'], row['why'] = classify_contexts(contexts)
    else:
        row['mention_type'], row['why'] = 'real mention', 'no context captured'
    rows.append(row)

cols = ['year', 'month', 'title', 'agency', 'department', 'series', 'mention_type', 'link', 'usajobsControlNumber']
with open('results/permitting_jobs.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=cols, extrasaction='ignore')
    w.writeheader()
    w.writerows(rows)

expansion = yaml.safe_load(open('patterns.yaml'))['expansion']
with open('data.js', 'w') as f:
    f.write('const JOBS = ')
    json.dump(rows, f)
    f.write(';\nvar EXPANSION = ')
    json.dump({'core': expansion['core_phrases'],
               'adjacent': expansion['adjacent_phrases'],
               'threshold': expansion['adjacent_threshold']}, f)
    f.write(';')

# contexts.js: control number -> list of text snippets, lazy-loaded by the
# viewer's "view mentions" modal
with open('contexts.js', 'w') as f:
    f.write('var CONTEXTS = ')
    json.dump({k: v for k, v in ctx_by_job.items()}, f)
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
