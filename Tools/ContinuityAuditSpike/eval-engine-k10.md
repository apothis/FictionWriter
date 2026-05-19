# ContinuityAuditSpike — eval harness

- **Mode**: engine · **Runs**: 10
- **Manuscripts**: lighthouse, long_watch, ash_court, tuesday_account
- **Extraction**: Goetia @ http://192.168.1.201:5001

## Engine end-to-end — 10 runs per manuscript

| manuscript | finding precision | recall | F1 |
|---|---|---|---|
| lighthouse | 92% ±11 | 40% ±13 | 0.51 |
| long_watch | 76% ±10 | 33% ±4 | 0.46 |
| ash_court | 87% ±10 | 35% ±7 | 0.49 |
| tuesday_account | 44% ±5 | 32% ±5 | 0.37 |
| **all** | **75% ±7** | **35% ±4** | **0.46** |

### Reliability — pass@k vs pass^k

- **pass@k** (caught in ≥1 run): 26/40
- **pass^k** (caught in every run): 3/40
- the gap of 23 is the stochasticity tax — contradictions a single audit will sometimes miss.

### Detection rate by class

| class | mean detection rate | pass^k |
|---|---|---|
| attribute_drift | 41% | 2/16 |
| knowledge_violation | 8% | 0/4 |
| timeline_conflict | 29% | 0/10 |
| spatial_conflict | 39% | 1/10 |

### Detection rate by scene distance

| distance | mean detection rate | n |
|---|---|---|
| adjacent (1-2) | 33% | 6 |
| mid (3-5) | 28% | 16 |
| far (6+) | 41% | 18 |

### Per-contradiction detection

| manuscript:id | kind | dist | detection rate |
|---|---|---|---|
| lighthouse:c1 | attribute_drift | 2 | 70% |
| lighthouse:c2 | knowledge_violation | 1 | 10% |
| lighthouse:c3 | timeline_conflict | 2 | 80% |
| lighthouse:c4 | spatial_conflict | 5 | 0% |
| long_watch:c1 | attribute_drift | 5 | 70% |
| long_watch:c2 | attribute_drift | 3 | 0% |
| long_watch:c3 | spatial_conflict | 4 | 70% |
| long_watch:c4 | spatial_conflict | 5 | 10% |
| long_watch:c5 | timeline_conflict | 3 | 10% |
| long_watch:c6 | timeline_conflict | 2 | 40% |
| long_watch:c7 | knowledge_violation | 1 | 0% |
| long_watch:c8 | attribute_drift | 4 | 0% |
| long_watch:c9 | attribute_drift | 5 | 100% |
| long_watch:c10 | timeline_conflict | 4 | 0% |
| long_watch:c11 | spatial_conflict | 5 | 100% |
| long_watch:c12 | attribute_drift | 4 | 0% |
| ash_court:c1 | attribute_drift | 9 | 10% |
| ash_court:c2 | attribute_drift | 8 | 60% |
| ash_court:c3 | attribute_drift | 6 | 80% |
| ash_court:c4 | attribute_drift | 9 | 60% |
| ash_court:c5 | spatial_conflict | 9 | 30% |
| ash_court:c6 | spatial_conflict | 7 | 30% |
| ash_court:c7 | spatial_conflict | 7 | 60% |
| ash_court:c8 | timeline_conflict | 7 | 70% |
| ash_court:c9 | timeline_conflict | 6 | 0% |
| ash_court:c10 | timeline_conflict | 6 | 0% |
| ash_court:c11 | knowledge_violation | 3 | 20% |
| ash_court:c12 | attribute_drift | 4 | 0% |
| tuesday_account:c1 | attribute_drift | 7 | 20% |
| tuesday_account:c2 | attribute_drift | 8 | 80% |
| tuesday_account:c3 | attribute_drift | 7 | 100% |
| tuesday_account:c4 | attribute_drift | 7 | 0% |
| tuesday_account:c5 | spatial_conflict | 8 | 90% |
| tuesday_account:c6 | spatial_conflict | 8 | 0% |
| tuesday_account:c7 | spatial_conflict | 4 | 0% |
| tuesday_account:c8 | timeline_conflict | 5 | 60% |
| tuesday_account:c9 | timeline_conflict | 5 | 0% |
| tuesday_account:c10 | timeline_conflict | 6 | 30% |
| tuesday_account:c11 | knowledge_violation | 2 | 0% |
| tuesday_account:c12 | attribute_drift | 7 | 10% |

