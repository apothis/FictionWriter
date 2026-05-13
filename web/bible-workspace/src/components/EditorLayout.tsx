import type { ReactNode } from "react";

// Shared layout primitives for the Bible Workspace editors
// (Character / Lorebook / Reference / TemplateScene). Hoisted from
// per-editor inline copies after the fourth user landed; the four
// inline copies were byte-identical.

export function Section({
  title,
  hint,
  children,
}: {
  title: string;
  hint?: string;
  children: ReactNode;
}) {
  return (
    <section className="mb-8">
      <h2 className="mb-3 text-xs font-medium uppercase tracking-wider text-loom-fg-secondary">
        {title}
      </h2>
      {hint && (
        <p className="mb-3 text-[11px] text-loom-fg-tertiary">{hint}</p>
      )}
      <div className="space-y-3">{children}</div>
    </section>
  );
}

export function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: ReactNode;
}) {
  return (
    <div>
      <div className="mb-1 flex items-baseline justify-between">
        <label className="text-xs font-medium text-loom-fg-secondary">
          {label}
        </label>
        {hint && (
          <span className="ml-2 text-[10px] italic text-loom-fg-tertiary">
            {hint}
          </span>
        )}
      </div>
      {children}
    </div>
  );
}
