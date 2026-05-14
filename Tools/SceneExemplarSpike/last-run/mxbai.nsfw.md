### `mxbai-embed-large (Ollama)` — retrieval baseline — topical-cosine reference

**register** — Same: 0.885 | Cross: 0.778 | Separation: +0.108 (n=5 same / 40 cross)

**style_axis** — Same: 0.885 | Cross: 0.778 | Separation: +0.108 (n=5 same / 40 cross)

<details><summary>Full 10×10 cosine matrix</summary>

|  | nsfw_01_explicit_direct | nsfw_02_explicit_direct | nsfw_03_clinical | nsfw_04_clinical | nsfw_05_euphemistic | nsfw_06_euphemistic | nsfw_07_explicit_poetic | nsfw_08_explicit_poetic | nsfw_09_explicit_mundane | nsfw_10_explicit_mundane |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nsfw_01_explicit_direct | 1.000 | 0.910 | 0.773 | 0.733 | 0.751 | 0.789 | 0.871 | 0.839 | 0.864 | 0.850 |
| nsfw_02_explicit_direct | 0.910 | 1.000 | 0.740 | 0.698 | 0.735 | 0.798 | 0.826 | 0.826 | 0.870 | 0.839 |
| nsfw_03_clinical | 0.773 | 0.740 | 1.000 | 0.849 | 0.677 | 0.709 | 0.762 | 0.734 | 0.725 | 0.702 |
| nsfw_04_clinical | 0.733 | 0.698 | 0.849 | 1.000 | 0.692 | 0.717 | 0.694 | 0.682 | 0.719 | 0.706 |
| nsfw_05_euphemistic | 0.751 | 0.735 | 0.677 | 0.692 | 1.000 | 0.881 | 0.843 | 0.818 | 0.799 | 0.766 |
| nsfw_06_euphemistic | 0.789 | 0.798 | 0.709 | 0.717 | 0.881 | 1.000 | 0.825 | 0.809 | 0.825 | 0.815 |
| nsfw_07_explicit_poetic | 0.871 | 0.826 | 0.762 | 0.694 | 0.843 | 0.825 | 1.000 | 0.901 | 0.849 | 0.775 |
| nsfw_08_explicit_poetic | 0.839 | 0.826 | 0.734 | 0.682 | 0.818 | 0.809 | 0.901 | 1.000 | 0.860 | 0.794 |
| nsfw_09_explicit_mundane | 0.864 | 0.870 | 0.725 | 0.719 | 0.799 | 0.825 | 0.849 | 0.860 | 1.000 | 0.885 |
| nsfw_10_explicit_mundane | 0.850 | 0.839 | 0.702 | 0.706 | 0.766 | 0.815 | 0.775 | 0.794 | 0.885 | 1.000 |

</details>