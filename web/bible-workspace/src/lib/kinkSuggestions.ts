// Curated autocomplete suggestions for the per-character kink field.
//
// Drawn from common AO3 freeform/additional kink tags and the
// conventional BDSM "yes/no/maybe" negotiation checklists. This is a
// SUGGESTION list only — the field accepts free text, so the list
// never needs to be exhaustive (the research warned against a rigid
// taxonomy). Grouped by area for maintenance; exported flat for the
// <datalist>.

const POWER_DYNAMIC = [
  "dominance", "submission", "power exchange", "service submission",
  "brat taming", "ownership", "collaring", "protocol", "obedience",
  "pet play", "primal play", "caregiving",
];

const RESTRAINT = [
  "bondage", "rope / shibari", "restraints", "handcuffs", "blindfolds",
  "gags", "sensory deprivation", "suspension", "immobilisation",
];

const SENSATION = [
  "impact play", "spanking", "flogging", "sensation play",
  "temperature play", "wax play", "electrostimulation", "tickling",
  "nipple play", "hair pulling",
];

const INTENSITY = [
  "pain", "rough sex", "breath play", "choking", "marking", "biting",
  "scratching", "knife play", "degradation", "humiliation", "overstimulation",
];

const PSYCHOLOGICAL = [
  "praise", "dirty talk", "teasing", "begging", "orgasm control",
  "edging", "orgasm denial", "worship", "body worship", "exhibitionism",
  "voyeurism", "being watched",
];

const ROLEPLAY = [
  "roleplay", "uniforms", "costumes", "lingerie", "size difference",
  "oral fixation", "aftercare",
];

const CONSENT_FRAMING = [
  "consensual non-consent", "dubious consent", "somnophilia",
];

const SPECULATIVE = [
  "omegaverse", "alpha/beta/omega", "knotting", "heat / rut",
  "sex pollen", "soulmate bond",
];

export const KINK_SUGGESTIONS: string[] = [
  ...POWER_DYNAMIC,
  ...RESTRAINT,
  ...SENSATION,
  ...INTENSITY,
  ...PSYCHOLOGICAL,
  ...ROLEPLAY,
  ...CONSENT_FRAMING,
  ...SPECULATIVE,
];
