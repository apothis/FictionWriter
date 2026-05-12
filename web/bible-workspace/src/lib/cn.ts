import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

// Standard Tailwind class-name helper. Used throughout the views;
// follows shadcn/ui convention so future shadcn components drop in
// without rewriting their cn() imports.
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}
