import { useEffect, useState } from "react";
import type { InputHTMLAttributes } from "react";
import { Input } from "./Input";

// Numeric input that lets the user transiently empty the field
// while typing. The naive pattern
//   `value={n} onChange={e => set(parseInt(e.target.value) || 0)}`
// re-anchors a 0 the moment the user clears the field (parseInt("")
// is NaN, NaN || 0 → 0, render shows "0" again — so typing "1" over
// a "0" produces "01" rather than "1"). Local string state breaks
// that round-trip: we hold the raw text the user typed and only
// emit numbers when the parse succeeds.
type Props = Omit<InputHTMLAttributes<HTMLInputElement>, "value" | "onChange" | "type"> & {
  value: number;
  onChange: (next: number) => void;
};

export function NumericField({ value, onChange, ...rest }: Props) {
  const [text, setText] = useState(String(value));

  // Sync when the external value changes — e.g., snapshot push for
  // a different entity, or a programmatic reset. Comparing against
  // the current parse avoids clobbering in-flight typing when the
  // emitted value comes back round-trip.
  useEffect(() => {
    const parsed = parseInt(text, 10);
    if (parsed !== value) {
      setText(String(value));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value]);

  return (
    <Input
      type="number"
      value={text}
      onChange={(e) => {
        const raw = e.target.value;
        setText(raw);
        const parsed = parseInt(raw, 10);
        if (!Number.isNaN(parsed)) {
          onChange(parsed);
        }
      }}
      {...rest}
    />
  );
}
