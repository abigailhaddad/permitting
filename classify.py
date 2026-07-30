#!/usr/bin/env python3
"""
Build the unified dataset from the rules in patterns.yaml.

Sources (all already have agency/series joined by join_agencies.sh, plus any
archive rows from update_current.sh):
  results/permitting_jobs_base.csv          word-scan postings (HF corpus)
  results/permitting_jobs_archive_base.csv  word postings after the corpus cutoff
  results/expanded_base.csv                 postings matching the expansion vocabulary

Every posting gets one mention_type:
  real mention          says "permitting", and not merely incidentally
  probably incidental   says "permitting", but every mention is a stock phrase
                        or verb use
  likely permitting     doesn't say the word; matches >=1 core term or
                        >= adjacent_threshold distinct adjacent terms
  adjacent mention      doesn't say the word; one adjacent term only

Outputs: results/permitting_jobs.csv (word postings), results/expanded_jobs.csv
(vocabulary postings), results/permitting_by_year.csv, and the website data
(data.js with all rows + series names, contexts.js for the mentions modal).
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
core = set(p.lower() for p in P['expansion']['core_phrases']) - {'permitting'}
adjacent = set(p.lower() for p in P['expansion']['adjacent_phrases'])
threshold = int(P['expansion']['adjacent_threshold'])


def classify_word_contexts(contexts):
    """(mention_type, why) for a posting that contains the word."""
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


TERM_RE = re.compile(r"[a-z0-9][a-z0-9 .&'/-]*[a-z0-9]")


def classify_expanded_terms(matched_cell):
    """(mention_type, why) for a posting found only via the expansion vocabulary."""
    found = set(m.group(0) for m in TERM_RE.finditer(matched_cell.lower()))
    c = sorted(found & core)
    a = sorted(found & adjacent)
    if c or len(a) >= threshold:
        return 'likely permitting', 'matched: ' + '; '.join(c + a)
    return 'adjacent mention', ('matched: ' + '; '.join(a)) if a else 'no term parsed'


def read_csv_rows(path):
    try:
        f = open(path)
    except FileNotFoundError:
        return []
    return list(csv.DictReader(f))


ctx_by_job = defaultdict(list)
for path in ['results/permitting_contexts.csv', 'results/permitting_contexts_archive.csv']:
    for row in read_csv_rows(path):
        ctx_by_job[row['usajobsControlNumber']].append(row['ctx'].lower())

# Word postings (corpus + archive), then vocabulary-only postings
rows, seen = [], set()
for path in ['results/permitting_jobs_base.csv', 'results/permitting_jobs_archive_base.csv']:
    for row in read_csv_rows(path):
        if row['usajobsControlNumber'] in seen:
            continue
        seen.add(row['usajobsControlNumber'])
        contexts = ctx_by_job.get(row['usajobsControlNumber'], [])
        if contexts:
            row['mention_type'], row['why'] = classify_word_contexts(contexts)
        else:
            row['mention_type'], row['why'] = 'real mention', 'no context captured'
        rows.append(row)
n_word = len(rows)

for row in read_csv_rows('results/expanded_base.csv'):
    if row['usajobsControlNumber'] in seen:
        continue
    seen.add(row['usajobsControlNumber'])
    row['mention_type'], row['why'] = classify_expanded_terms(row.get('matched_phrases', ''))
    rows.append(row)

cols = ['year', 'month', 'title', 'agency', 'department', 'series', 'mention_type', 'link', 'usajobsControlNumber']
word_types = {'real mention', 'probably incidental'}
with open('results/permitting_jobs.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=cols, extrasaction='ignore')
    w.writeheader()
    w.writerows(r for r in rows if r['mention_type'] in word_types)
with open('results/expanded_jobs.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=cols + ['why'], extrasaction='ignore')
    w.writeheader()
    w.writerows(r for r in rows if r['mention_type'] not in word_types)

expansion = P['expansion']
series_names = json.load(open('reference/series_names.json'))
# Website: the three meaningful tiers (adjacent mentions stay CSV-only), and
# year/link are derived client-side from month/control to keep the file small.
site_rows = [{k: r[k] for k in ('month', 'title', 'agency', 'department', 'series', 'mention_type', 'why', 'usajobsControlNumber')}
             for r in rows if r['mention_type'] != 'adjacent mention']
with open('data.js', 'w') as f:
    f.write('const JOBS = ')
    json.dump(site_rows, f)
    f.write(';\nvar EXPANSION = ')
    json.dump({'core': expansion['core_phrases'],
               'adjacent': expansion['adjacent_phrases'],
               'threshold': expansion['adjacent_threshold']}, f)
    f.write(';\nvar SERIES_NAMES = ')
    json.dump(series_names, f)
    f.write(';')

with open('contexts.js', 'w') as f:
    f.write('var CONTEXTS = ')
    json.dump({k: v for k, v in ctx_by_job.items()}, f)
    f.write(';')

by_year = Counter(r['year'] for r in rows)
with open('results/permitting_by_year.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['year', 'postings', 'real_mentions', 'likely_permitting'])
    real = Counter(r['year'] for r in rows if r['mention_type'] == 'real mention')
    likely = Counter(r['year'] for r in rows if r['mention_type'] == 'likely permitting')
    for y in sorted(by_year):
        w.writerow([y, by_year[y], real.get(y, 0), likely.get(y, 0)])

counts = Counter(r['mention_type'] for r in rows)
print(f"{len(rows)} postings ({n_word} word, {len(rows) - n_word} vocabulary-only): "
      + ', '.join(f"{k}: {v}" for k, v in counts.most_common()))
