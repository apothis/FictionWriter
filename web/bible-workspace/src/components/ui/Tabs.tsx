import { cn } from "../../lib/cn";

// Tiny tab-strip primitive. Renders horizontal segmented buttons;
// state is controlled (parent owns the active tab). When the design
// outgrows this (animated indicator, keyboard nav between tabs,
// nested tab panes, etc.) we can swap to shadcn's `<Tabs>` —
// `value`/`onValueChange` API matches.

export interface TabDef<T extends string> {
  value: T;
  label: string;
  count?: number;
}

interface Props<T extends string> {
  tabs: TabDef<T>[];
  value: T;
  onChange: (next: T) => void;
  className?: string;
}

export function Tabs<T extends string>({ tabs, value, onChange, className }: Props<T>) {
  return (
    <div
      role="tablist"
      className={cn(
        "inline-flex items-center gap-1 rounded-md bg-loom-bg-elevated p-1",
        className,
      )}
    >
      {tabs.map((tab) => {
        const active = tab.value === value;
        return (
          <button
            key={tab.value}
            role="tab"
            aria-selected={active}
            onClick={() => onChange(tab.value)}
            className={cn(
              "rounded px-3 py-1 text-xs font-medium transition-colors",
              "focus:outline-none focus:ring-1 focus:ring-loom-accent",
              active
                ? "bg-loom-bg-input text-loom-fg"
                : "text-loom-fg-secondary hover:text-loom-fg",
            )}
          >
            {tab.label}
            {tab.count !== undefined && (
              <span
                className={cn(
                  "ml-1.5 text-[10px]",
                  active ? "text-loom-fg-tertiary" : "text-loom-fg-tertiary",
                )}
              >
                {tab.count}
              </span>
            )}
          </button>
        );
      })}
    </div>
  );
}
