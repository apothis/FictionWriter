import { useCallback, useEffect, useRef } from "react";

// Tiny debounce hook — collapses rapid-fire calls into a single
// delayed invocation. Used by the character editor to avoid
// flooding the bridge with one intent per keystroke.
export function useDebouncedCallback<Args extends unknown[]>(
  fn: (...args: Args) => void,
  delay: number,
): (...args: Args) => void {
  const fnRef = useRef(fn);
  // Always invoke the most recent closure — `fn` may close over
  // state that updates between calls.
  useEffect(() => {
    fnRef.current = fn;
  }, [fn]);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  // Clear any pending timer on unmount so the editor's intent
  // dispatch doesn't fire after the user has navigated away.
  useEffect(() => {
    return () => {
      if (timer.current) {
        clearTimeout(timer.current);
      }
    };
  }, []);
  return useCallback(
    (...args: Args) => {
      if (timer.current) {
        clearTimeout(timer.current);
      }
      timer.current = setTimeout(() => {
        fnRef.current(...args);
      }, delay);
    },
    [delay],
  );
}
