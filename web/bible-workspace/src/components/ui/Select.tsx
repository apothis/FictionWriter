import { forwardRef } from "react";
import type { SelectHTMLAttributes } from "react";
import { cn } from "../../lib/cn";

// Native <select> styled to match the Input primitive. Native is
// fine for the small enums in the Character schema (role,
// injectionMode, customField.kind) — we'll swap to a richer
// shadcn-style Select only if/when we hit a use case it can't
// cover (>20 options, search, multi-select, etc.).
export const Select = forwardRef<
  HTMLSelectElement,
  SelectHTMLAttributes<HTMLSelectElement>
>(function Select({ className, children, ...props }, ref) {
  return (
    <select
      ref={ref}
      className={cn(
        "flex h-9 w-full rounded-md border border-loom-border bg-loom-bg-input px-3 py-1 text-sm text-loom-fg shadow-sm transition-colors",
        "focus:outline-none focus:ring-1 focus:ring-loom-accent",
        "disabled:cursor-not-allowed disabled:opacity-50",
        // Native arrow indicator stays — we don't try to recreate
        // it via background-image since WKWebView renders the
        // system one correctly.
        className,
      )}
      {...props}
    >
      {children}
    </select>
  );
});
