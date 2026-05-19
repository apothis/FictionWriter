# ContinuityAuditSpike — eval harness

- **Mode**: engine · **Runs**: 3
- **Manuscripts**: lighthouse, long_watch, ash_court, tuesday_account
- **Extraction**: Goetia @ http://192.168.1.201:5001

## Engine end-to-end — 3 runs per manuscript

| manuscript | finding precision | recall | F1 |
|---|---|---|---|
| lighthouse | 89% ±22 | 33% ±33 | 0.41 |
| long_watch | 67% ±33 | 11% ±5 | 0.19 |
| ash_court | 100% ±0 | 6% ±5 | 0.10 |
| tuesday_account | 100% ±0 | 19% ±5 | 0.32 |
| **all** | **89% ±12** | **17% ±10** | **0.26** |

### Reliability — pass@k vs pass^k

- **pass@k** (caught in ≥1 run): 9/40
- **pass^k** (caught in every run): 2/40
- the gap of 7 is the stochasticity tax — contradictions a single audit will sometimes miss.

### Detection rate by class

| class | mean detection rate | pass^k |
|---|---|---|
| attribute_drift | 10% | 1/16 |
| knowledge_violation | 17% | 0/4 |
| timeline_conflict | 13% | 1/10 |
| spatial_conflict | 20% | 0/10 |

### Detection rate by scene distance

| distance | mean detection rate | n |
|---|---|---|
| adjacent (1-2) | 28% | 6 |
| mid (3-5) | 12% | 16 |
| far (6+) | 11% | 18 |

### Per-contradiction detection

| manuscript:id | kind | dist | detection rate |
|---|---|---|---|
| lighthouse:c1 | attribute_drift | 2 | 67% |
| lighthouse:c2 | knowledge_violation | 1 | 67% |
| lighthouse:c3 | timeline_conflict | 2 | 0% |
| lighthouse:c4 | spatial_conflict | 5 | 0% |
| long_watch:c1 | attribute_drift | 5 | 0% |
| long_watch:c2 | attribute_drift | 3 | 0% |
| long_watch:c3 | spatial_conflict | 4 | 33% |
| long_watch:c4 | spatial_conflict | 5 | 0% |
| long_watch:c5 | timeline_conflict | 3 | 0% |
| long_watch:c6 | timeline_conflict | 2 | 33% |
| long_watch:c7 | knowledge_violation | 1 | 0% |
| long_watch:c8 | attribute_drift | 4 | 0% |
| long_watch:c9 | attribute_drift | 5 | 0% |
| long_watch:c10 | timeline_conflict | 4 | 0% |
| long_watch:c11 | spatial_conflict | 5 | 67% |
| long_watch:c12 | attribute_drift | 4 | 0% |
| ash_court:c1 | attribute_drift | 9 | 0% |
| ash_court:c2 | attribute_drift | 8 | 0% |
| ash_court:c3 | attribute_drift | 6 | 0% |
| ash_court:c4 | attribute_drift | 9 | 0% |
| ash_court:c5 | spatial_conflict | 9 | 67% |
| ash_court:c6 | spatial_conflict | 7 | 0% |
| ash_court:c7 | spatial_conflict | 7 | 0% |
| ash_court:c8 | timeline_conflict | 7 | 0% |
| ash_court:c9 | timeline_conflict | 6 | 0% |
| ash_court:c10 | timeline_conflict | 6 | 0% |
| ash_court:c11 | knowledge_violation | 3 | 0% |
| ash_court:c12 | attribute_drift | 4 | 0% |
| tuesday_account:c1 | attribute_drift | 7 | 0% |
| tuesday_account:c2 | attribute_drift | 8 | 0% |
| tuesday_account:c3 | attribute_drift | 7 | 100% |
| tuesday_account:c4 | attribute_drift | 7 | 0% |
| tuesday_account:c5 | spatial_conflict | 8 | 33% |
| tuesday_account:c6 | spatial_conflict | 8 | 0% |
| tuesday_account:c7 | spatial_conflict | 4 | 0% |
| tuesday_account:c8 | timeline_conflict | 5 | 100% |
| tuesday_account:c9 | timeline_conflict | 5 | 0% |
| tuesday_account:c10 | timeline_conflict | 6 | 0% |
| tuesday_account:c11 | knowledge_violation | 2 | 0% |
| tuesday_account:c12 | attribute_drift | 7 | 0% |

