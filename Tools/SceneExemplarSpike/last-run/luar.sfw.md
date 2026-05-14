### `gabrielloiseau/LUAR-MUD-sentence-transformers` — predicted negative control — authorship embedder; expected to fail register discrimination per Wegmann TACL + StyleDistance paper

**register** — Same: 0.674 | Cross: 0.000 | Separation: +0.674 (n=45 same / 0 cross)

**style_axis** — Same: 0.851 | Cross: 0.652 | Separation: +0.199 (n=5 same / 40 cross)

<details><summary>Full 10×10 cosine matrix</summary>

|  | sfw_01_clipped_hemingway | sfw_02_clipped_hemingway | sfw_03_lyrical_mccarthy | sfw_04_lyrical_mccarthy | sfw_05_clinical_procedural | sfw_06_clinical_procedural | sfw_07_baroque_victorian | sfw_08_baroque_victorian | sfw_09_mundane_workmanlike | sfw_10_mundane_workmanlike |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| sfw_01_clipped_hemingway | 1.000 | 0.895 | 0.754 | 0.757 | 0.567 | 0.536 | 0.669 | 0.718 | 0.802 | 0.871 |
| sfw_02_clipped_hemingway | 0.895 | 1.000 | 0.785 | 0.794 | 0.577 | 0.544 | 0.710 | 0.749 | 0.737 | 0.814 |
| sfw_03_lyrical_mccarthy | 0.754 | 0.785 | 1.000 | 0.907 | 0.571 | 0.558 | 0.626 | 0.672 | 0.679 | 0.679 |
| sfw_04_lyrical_mccarthy | 0.757 | 0.794 | 0.907 | 1.000 | 0.531 | 0.541 | 0.641 | 0.705 | 0.626 | 0.702 |
| sfw_05_clinical_procedural | 0.567 | 0.577 | 0.571 | 0.531 | 1.000 | 0.782 | 0.693 | 0.711 | 0.504 | 0.501 |
| sfw_06_clinical_procedural | 0.536 | 0.544 | 0.558 | 0.541 | 0.782 | 1.000 | 0.644 | 0.655 | 0.467 | 0.459 |
| sfw_07_baroque_victorian | 0.669 | 0.710 | 0.626 | 0.641 | 0.693 | 0.644 | 1.000 | 0.925 | 0.578 | 0.669 |
| sfw_08_baroque_victorian | 0.718 | 0.749 | 0.672 | 0.705 | 0.711 | 0.655 | 0.925 | 1.000 | 0.618 | 0.674 |
| sfw_09_mundane_workmanlike | 0.802 | 0.737 | 0.679 | 0.626 | 0.504 | 0.467 | 0.578 | 0.618 | 1.000 | 0.747 |
| sfw_10_mundane_workmanlike | 0.871 | 0.814 | 0.679 | 0.702 | 0.501 | 0.459 | 0.669 | 0.674 | 0.747 | 1.000 |

</details>