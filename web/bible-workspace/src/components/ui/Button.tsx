import { forwardRef } from "react";
import type { ButtonHTMLAttributes } from "react";
import { cn } from "../../lib/cn";

type Variant = "default" | "ghost" | "destructive";

export const Button = forwardRef<
  HTMLButtonElement,
  ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant }
>(function Button({ className, variant = "default", ...props }, ref) {
  return (
    <button
      ref={ref}
      className={cn(
        "inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors",
        "focus:outline-none focus:ring-1 focus:ring-loom-accent",
        "disabled:pointer-events-none disabled:opacity-50",
        "h-8 px-3",
        {
          default:
            "bg-loom-bg-elevated text-loom-fg hover:bg-loom-bg-input border border-loom-border",
          ghost: "text-loom-fg-secondary hover:bg-loom-bg-elevated hover:text-loom-fg",
          destructive:
            "bg-red-500/20 text-red-400 hover:bg-red-500/30 border border-red-500/30",
        }[variant],
        className,
      )}
      {...props}
    />
  );
});
