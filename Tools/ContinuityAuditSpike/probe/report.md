# ContinuityAuditSpike — same-fact probe (lighthouse)

- **Manuscript**: lighthouse · 6 scenes · 4 gold contradictions
- **Extraction**: koboldcpp/Huihui-gemma-4-31B-it-abliterated-v2.i1-Q4_K_M1 [gemma4] @ http://192.168.1.201:5001 · runs=3
- **Adjudication**: koboldcpp/Huihui-gemma-4-31B-it-abliterated-v2.i1-Q4_K_M1 [gemma4] @ http://192.168.1.201:5001
- **Pairs**: 58 (same_fact=25, different_fact=33)

## Confusion (rows = label, cols = predicted)

| label \ pred | same_fact | different_fact | ERROR |
|---|---|---|---|
| same_fact | 19 | 6 | 0 |
| different_fact | 0 | 33 | 0 |

## Headline

- **same_fact agreement**: 19/25 = 76%
- **different_fact agreement**: 33/33 = 100%
- **separation**: -0.24 (1.0 = perfect, 0.0 = no signal)

