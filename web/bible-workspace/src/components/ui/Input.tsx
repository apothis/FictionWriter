import { forwardRef } from "react";
import type { InputHTMLAttributes } from "react";
import { cn } from "../../lib/cn";

// shadcn-style primitive. Copy-pasted-into-repo pattern — modify
// the styling here directly rather than overriding via props.
// Pairs with the Liquid Glass CSS variables in styles.css.
export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(
  function Input({ className, ...props }, ref) {
    return (
      <input
        ref={ref}
        className={cn(
          "flex h-9 w-full rounded-md border border-loom-border bg-loom-bg-input px-3 py-1 text-sm text-loom-fg shadow-sm transition-colors",
          "placeholder:text-loom-fg-tertiary",
          "focus:outline-none focus:ring-1 focus:ring-loom-accent",
          "disabled:cursor-not-allowed disabled:opacity-50",
          className,
        )}
        {...props}
      />
    );
  },
);
