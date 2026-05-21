import { useEffect, useMemo, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import type { HelpBook, HelpSection, HelpSnapshot } from "./types";
import { postIntent, subscribeToSnapshot } from "./bridge";

// Top-level component for the in-app Help panel. Three regions:
//   - top: BookSwitcher between "User Help" and "Technical Reference"
//   - left rail: TOC (grouped, sorted by section.order)
//   - main: rendered markdown of the selected section
//
// The Swift host pushes a snapshot whenever the book or selection
// changes; this component just reflects it and posts intents back.

export function HelpApp() {
  const [snapshot, setSnapshot] = useState<HelpSnapshot | null>(null);

  useEffect(() => subscribeToSnapshot(setSnapshot), []);

  if (!snapshot) {
    return (
      <div className="flex h-screen w-screen items-center justify-center text-loom-fg-secondary">
        Loading help…
      </div>
    );
  }

  return (
    <div className="flex h-screen w-screen flex-col">
      <BookSwitcher book={snapshot.book} />
      <div className="flex min-h-0 flex-1">
        <TOC
          toc={snapshot.toc}
          selectedSectionId={snapshot.selectedSectionId}
          book={snapshot.book}
        />
        <ContentArea
          markdown={snapshot.selectedSectionMarkdown}
          hasSelection={snapshot.selectedSectionId != null}
        />
      </div>
    </div>
  );
}

function BookSwitcher({ book }: { book: HelpBook }) {
  return (
    <div className="flex shrink-0 items-center gap-2 border-b border-loom-border bg-loom-bg-elevated px-4 py-2">
      <BookTab label="User Help" book="user" active={book === "user"} />
      <BookTab label="Technical Reference" book="technical" active={book === "technical"} />
    </div>
  );
}

function BookTab({
  label,
  book,
  active,
}: {
  label: string;
  book: HelpBook;
  active: boolean;
}) {
  return (
    <button
      type="button"
      className={
        "rounded-md px-3 py-1 text-sm font-medium transition-colors " +
        (active
          ? "bg-loom-accent text-white"
          : "text-loom-fg-secondary hover:bg-loom-bg-input hover:text-loom-fg")
      }
      onClick={() => {
        if (!active) postIntent({ kind: "switchBook", book });
      }}
    >
      {label}
    </button>
  );
}

function TOC({
  toc,
  selectedSectionId,
  book,
}: {
  toc: HelpSection[];
  selectedSectionId: string | null;
  book: HelpBook;
}) {
  const grouped = useMemo(() => groupSections(toc), [toc]);
  return (
    <nav className="w-72 shrink-0 overflow-y-auto border-r border-loom-border bg-loom-bg-elevated py-3">
      {grouped.map((group) => (
        <div key={group.label ?? "__ungrouped__"} className="mb-4">
          {group.label && (
            <div className="px-4 pb-1 pt-2 text-xs font-semibold uppercase tracking-wide text-loom-fg-secondary">
              {group.label}
            </div>
          )}
          <ul>
            {group.sections.map((section) => (
              <li key={section.id}>
                <button
                  type="button"
                  className={
                    "w-full truncate px-4 py-1.5 text-left text-sm transition-colors " +
                    (section.id === selectedSectionId
                      ? "bg-loom-accent text-white"
                      : "text-loom-fg hover:bg-loom-bg-input")
                  }
                  onClick={() =>
                    postIntent({
                      kind: "selectSection",
                      sectionId: section.id,
                      book,
                    })
                  }
                >
                  {section.title}
                </button>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </nav>
  );
}

function ContentArea({
  markdown,
  hasSelection,
}: {
  markdown: string | null;
  hasSelection: boolean;
}) {
  if (!hasSelection) {
    return (
      <div className="flex flex-1 items-center justify-center text-loom-fg-secondary">
        Pick a section from the left to read it.
      </div>
    );
  }
  if (markdown == null) {
    return (
      <div className="flex flex-1 items-center justify-center text-loom-fg-secondary">
        (No content for this section yet.)
      </div>
    );
  }
  return (
    <main className="flex-1 overflow-y-auto px-10 py-8">
      <article className="prose prose-loom mx-auto max-w-3xl">
        <ReactMarkdown remarkPlugins={[remarkGfm]}>{markdown}</ReactMarkdown>
      </article>
    </main>
  );
}

interface SectionGroup {
  label: string | null;
  sections: HelpSection[];
}

function groupSections(toc: HelpSection[]): SectionGroup[] {
  const groups: SectionGroup[] = [];
  const lookup = new Map<string, SectionGroup>();
  // Preserve insertion order — the TOC is already sorted by `order`,
  // and sections with the same group label appear together because
  // the registry is authored that way.
  for (const section of toc) {
    const key = section.group ?? "__ungrouped__";
    let group = lookup.get(key);
    if (!group) {
      group = { label: section.group, sections: [] };
      lookup.set(key, group);
      groups.push(group);
    }
    group.sections.push(section);
  }
  return groups;
}
