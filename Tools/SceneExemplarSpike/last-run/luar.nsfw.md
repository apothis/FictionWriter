### `gabrielloiseau/LUAR-MUD-sentence-transformers` — predicted negative control — authorship embedder; expected to fail register discrimination per Wegmann TACL + StyleDistance paper

**register** — Same: 0.856 | Cross: 0.711 | Separation: +0.144 (n=5 same / 40 cross)

**style_axis** — Same: 0.856 | Cross: 0.711 | Separation: +0.144 (n=5 same / 40 cross)

<details><summary>Full 10×10 cosine matrix</summary>

|  | nsfw_01_explicit_direct | nsfw_02_explicit_direct | nsfw_03_clinical | nsfw_04_clinical | nsfw_05_euphemistic | nsfw_06_euphemistic | nsfw_07_explicit_poetic | nsfw_08_explicit_poetic | nsfw_09_explicit_mundane | nsfw_10_explicit_mundane |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nsfw_01_explicit_direct | 1.000 | 0.908 | 0.513 | 0.535 | 0.781 | 0.804 | 0.783 | 0.789 | 0.815 | 0.876 |
| nsfw_02_explicit_direct | 0.908 | 1.000 | 0.599 | 0.545 | 0.763 | 0.816 | 0.806 | 0.841 | 0.818 | 0.862 |
| nsfw_03_clinical | 0.513 | 0.599 | 1.000 | 0.745 | 0.614 | 0.626 | 0.611 | 0.624 | 0.579 | 0.536 |
| nsfw_04_clinical | 0.535 | 0.545 | 0.745 | 1.000 | 0.604 | 0.588 | 0.536 | 0.506 | 0.556 | 0.588 |
| nsfw_05_euphemistic | 0.781 | 0.763 | 0.614 | 0.604 | 1.000 | 0.860 | 0.807 | 0.821 | 0.793 | 0.780 |
| nsfw_06_euphemistic | 0.804 | 0.816 | 0.626 | 0.588 | 0.860 | 1.000 | 0.821 | 0.840 | 0.810 | 0.831 |
| nsfw_07_explicit_poetic | 0.783 | 0.806 | 0.611 | 0.536 | 0.807 | 0.821 | 1.000 | 0.876 | 0.755 | 0.707 |
| nsfw_08_explicit_poetic | 0.789 | 0.841 | 0.624 | 0.506 | 0.821 | 0.840 | 0.876 | 1.000 | 0.815 | 0.763 |
| nsfw_09_explicit_mundane | 0.815 | 0.818 | 0.579 | 0.556 | 0.793 | 0.810 | 0.755 | 0.815 | 1.000 | 0.888 |
| nsfw_10_explicit_mundane | 0.876 | 0.862 | 0.536 | 0.588 | 0.780 | 0.831 | 0.707 | 0.763 | 0.888 | 1.000 |

</details>