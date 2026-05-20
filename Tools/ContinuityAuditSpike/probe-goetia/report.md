# ContinuityAuditSpike — same-fact probe (lighthouse)

- **Manuscript**: lighthouse · 6 scenes · 4 gold contradictions
- **Extraction**: koboldcpp/Goetia-24B-v1.3-absolute-heresy.i1-Q5_K_M [mistralV7] @ http://192.168.1.201:5001 · runs=3
- **Adjudication**: koboldcpp/Goetia-24B-v1.3-absolute-heresy.i1-Q5_K_M [mistralV7] @ http://192.168.1.201:5001
- **Pairs**: 58 (same_fact=25, different_fact=33)

## Confusion (rows = label, cols = predicted)

| label \ pred | same_fact | different_fact | ERROR |
|---|---|---|---|
| same_fact | 20 | 5 | 0 |
| different_fact | 0 | 33 | 0 |

## Headline

- **same_fact agreement**: 20/25 = 80%
- **different_fact agreement**: 33/33 = 100%
- **separation**: -0.20 (1.0 = perfect, 0.0 = no signal)

