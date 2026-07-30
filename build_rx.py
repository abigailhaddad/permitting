#!/usr/bin/env python3
"""
Print the grab-rule regex (core + adjacent phrases from patterns.yaml) with
word boundaries, SQL-escaped for embedding in a duckdb -c string.
Single source for scan_expanded.sh and update_current.sh:  RX=$(python3 build_rx.py)
"""

import re

import yaml

p = yaml.safe_load(open('patterns.yaml'))['expansion']
phrases = p['core_phrases'] + p['adjacent_phrases']


def bounded(phrase):
    escaped = re.escape(phrase.lower())
    start = r'\b' if escaped[0].isalnum() else ''
    end = r'\b' if escaped[-1].isalnum() else ''
    return start + escaped + end


rx = '|'.join(bounded(x) for x in phrases)
print(rx.replace("'", "''"))
