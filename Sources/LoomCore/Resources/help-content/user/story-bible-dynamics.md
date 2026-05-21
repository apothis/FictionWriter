# Story Bible — Dynamics

A **Dynamic** is a structured relationship sheet for a pair (or group) of characters — roles, wants, soft and hard limits, a safeword, the intended arc. It's the kink-aware community's "negotiated scene sheet" turned into Loom data: at once the author's planning artefact and a generation constraint that gets fed to the model whenever the dynamic's participants are in scene.

Dynamics complement Characters. A character entry says *who someone is*; a dynamic says *what's between them and someone else.* The same pair can have multiple dynamics (a public-facing rapport, a private one); the same character can appear in multiple dynamics.

Edit in the **Bible Workspace** (**⌘⇧B**), Dynamics tab.

## What a Dynamic carries

| Field | What goes in it |
|---|---|
| **Name** | Your label. Not sent to the model; used internally for organisation and for matching against recent prose. |
| **Participants** | The characters in this dynamic, picked from your existing Characters. At least one is required for keyed activation to work. |
| **Roles** | Who plays what in this dynamic. "She leads; he follows" / "Older sister to younger brother" / "Master and apprentice, with the apprentice quietly outgrowing the master." Plain prose. |
| **Wants** | What each participant wants from this dynamic. Real motivations, not surface ones. Drives the model toward scenes where the dynamic *moves*, not just exists. |
| **Soft limits** | What's negotiable, conditional, approached with care. The model treats these as terrain to enter only with reason. |
| **Hard limits** | What never happens in this dynamic. The model treats these as off the page. |
| **Safeword** | The word or signal that stops a scene. Phrased as you'd phrase it in your prose. |
| **Arc** | Where the dynamic is going. "It starts loving and curdles into bitterness" / "She thinks she's in control; she isn't." Gives the model a vector, not just a snapshot. |
| **Always-on** | When true, the dynamic is injected on every generation. When false (default), it's injected only when a participant is in the recent prose. |
| **Enabled** | Master toggle. Disabled dynamics never activate. |

Every field except the participants is plain prose — there's no enforced taxonomy. The kink-negotiation framing in the field names ("soft limits," "safeword") is the source of the convention, but it generalises: a sibling dynamic uses the same fields and benefits from filling them out. "Wants" and "Arc" are doing most of the work in any dynamic, kink-coded or not.

## When a Dynamic is injected

The activation rule mirrors keyed lorebook entries:

- **Always-on dynamics** inject on every generation, regardless of recent prose.
- **Off-by-default dynamics** inject only when a participant character (by their canonical name or any alias) — or the dynamic's own name — appears as a whole word in the recent prose.

That means: write a scene with two characters present, and any dynamic they're in lights up. Walk one of them out of the scene, and the dynamic stops being injected on the next generation. The activator doesn't try to reason about *which* dynamic is foregrounded in a multi-dynamic scene — every relevant sheet gets included, and the model decides which is salient.

If you want a dynamic to keep biasing the writing even when no participant has been named in a while (e.g. an aftermath sequence), flip **always-on** for the duration.

## How it lands in the prompt

Each activated sheet is rendered into a labelled block — only fields you've filled appear:

```
[ Relationship dynamic — Eleanor & Tom:
  Roles: She leads; he follows.
  Wants: Eleanor wants to be needed; Tom wants someone to trust without questioning.
  Soft limits: Tom doesn't talk about the army.
  Hard limits: No reconciliation with her father.
  Arc: The trust is real, and it's a problem. ]
```

Multiple activated sheets are joined with blank lines and land in the prompt's `dynamicSheet` layer, above-cache. You can audit exactly what was rendered for any past generation in **▸ History** at the bottom of the tray.

For where the layer sits in the full prompt assembly, see **Generation pipeline** in the Technical Reference book.

## When to use a Dynamic vs a Character.relationships entry

Both exist. They're not redundant.

- A **`Character.relationships`** entry is a directional edge — character A has a relationship of kind X to character B. Lightweight; surfaced in entity discovery and the relationship-map view. Use for *every* connection you want recorded: "Tom is Eleanor's husband," "Eleanor is the sister of Sarah."
- A **Dynamic** is a full sheet *about* that relationship — the texture of the connection. Use when you want to direct the writing. Not every relationship needs a dynamic; the ones that drive your scenes do.

A typical setup: every named character has a few Relationship edges; a handful of the most-driving pairs have Dynamics on top.

## When to use a Dynamic vs a Lorebook entry

A Lorebook entry could in principle hold the same content as a Dynamic ("when Eleanor and Tom are both in scene, lean into the…"). The difference is shape and tooling:

- Dynamics give you participant-driven activation (it picks up automatically when both names appear), structured fields the model reads consistently, and a relationship-shaped slot in the data model that future features (relationship discovery, relationship-map visualisation) build on.
- Lorebook entries give you key-driven activation (which can be broader or narrower than "participant name in prose") and a free-form content body.

Default to Dynamics for between-characters content. Use a Lorebook entry when the activation pattern isn't "these participants are in scene" — for example, a "sex scenes in this project should foreground tenderness over performance" steer that applies regardless of which pair is on the page.
