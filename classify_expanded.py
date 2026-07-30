#!/usr/bin/env python3
"""
Flag each posting from the expanded scan as 'likely permitting' or
'adjacent mention', using the expansion rules in patterns.yaml:

  likely permitting  = matches >= 1 core phrase,
                       OR matches >= adjacent_threshold DISTINCT adjacent phrases
  adjacent mention   = grabbed by the scan but neither condition holds

The word "permitting" only counts as a core match when the posting is not
classified 'probably incidental' by classify.py (results/permitting_jobs.csv).

Input:  results/expanded_hits.csv  (from scan_expanded.sh)
Output: results/expanded_jobs.csv  (adds flag, core/adjacent match columns)
"""

import csv
import re

import yaml

P = yaml.safe_load(open('patterns.yaml'))['expansion']
core = set(p.lower() for p in P['core_phrases'])
adjacent = set(p.lower() for p in P['adjacent_phrases'])
threshold = int(P['adjacent_threshold'])

incidental = set()
try:
    for row in csv.DictReader(open('results/permitting_jobs.csv')):
        if row['mention_type'] == 'probably incidental':
            incidental.add(row['usajobsControlNumber'])
except FileNotFoundError:
    pass

PHRASE_RE = re.compile(r"[a-z0-9][a-z0-9 .&'/-]*[a-z0-9]")


def parse_phrases(cell):
    return set(m.group(0) for m in PHRASE_RE.finditer(cell.lower()))


n_likely = n_adjacent = 0
with open('results/expanded_hits.csv') as fin, \
     open('results/expanded_jobs.csv', 'w', newline='') as fout:
    w = csv.writer(fout)
    w.writerow(['month', 'usajobsControlNumber', 'title', 'flag',
                'core_matches', 'adjacent_matches', 'link'])
    for row in csv.DictReader(fin):
        found = parse_phrases(row['matched_phrases'])
        c = found & core
        if 'permitting' in c and row['usajobsControlNumber'] in incidental:
            c.discard('permitting')
        a = found & adjacent
        if c or len(a) >= threshold:
            flag = 'likely permitting'
            n_likely += 1
        else:
            flag = 'adjacent mention'
            n_adjacent += 1
        w.writerow([row['month'], row['usajobsControlNumber'], row['title'],
                    flag, '; '.join(sorted(c)), '; '.join(sorted(a)),
                    f"https://www.usajobs.gov/job/{row['usajobsControlNumber']}"])

print(f"likely permitting: {n_likely}, adjacent mention: {n_adjacent}")
