import { forwardRef } from "react";
import type { TextareaHTMLAttributes } from "react";
import { cn } from "../../lib/cn";

export const Textarea = forwardRef<
  HTMLTextAreaElement,
  TextareaHTMLAttributes<HTMLTextAreaElement>
>(function Textarea({ className, ...props }, ref) {
  return (
    <textarea
      ref={ref}
      className={cn(
        "flex min-h-[64px] w-full rounded-md border border-loom-border bg-loom-bg-input px-3 py-2 text-sm text-loom-fg shadow-sm transition-colors resize-y",
        "placeholder:text-loom-fg-tertiary",
        "focus:outline-none focus:ring-1 focus:ring-loom-accent",
        "disabled:cursor-not-allowed disabled:opacity-50",
        className,
      )}
      {...props}
    />
  );
});
