#!/usr/bin/env bash
./run-sweep.sh \
  --polys    1:5001:500@1000 \
  --steps    1:5001:500@1000 \
  --digits   1:151:5@30 \
  --vars     1:12:1@7 \
  --summands 2:20:2@2 \
  --seed     42       \
  --rounds   1       \
  --overwrite
