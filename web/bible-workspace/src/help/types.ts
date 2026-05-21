// Mirrors the Swift HelpSnapshot / HelpIntent in
// Sources/LoomCore/Models/HelpSnapshot.swift. Keep in sync — wire
// format is discriminated by `kind` for intents and a plain
// object literal for snapshots.

export type HelpBook = "user" | "technical";

export interface HelpSection {
  id: string;
  title: string;
  book: HelpBook;
  order: number;
  group: string | null;
}

export interface HelpSnapshot {
  book: HelpBook;
  toc: HelpSection[];
  selectedSectionId: string | null;
  selectedSectionMarkdown: string | null;
}

export type HelpIntent =
  | { kind: "selectSection"; sectionId: string; book: HelpBook }
  | { kind: "switchBook"; book: HelpBook };
