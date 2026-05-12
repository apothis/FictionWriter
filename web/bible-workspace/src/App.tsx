import { useEffect, useState } from "react";
import type { BibleWorkspaceSnapshot } from "./types";
import { subscribeToSnapshots } from "./bridge";
import { EntityList } from "./views/EntityList";

export function App() {
  const [snapshot, setSnapshot] = useState<BibleWorkspaceSnapshot | null>(null);

  useEffect(() => {
    return subscribeToSnapshots(setSnapshot);
  }, []);

  if (!snapshot) {
    return (
      <div className="flex h-full items-center justify-center text-sm text-loom-fg-tertiary">
        Awaiting first snapshot from Loom…
      </div>
    );
  }

  return <EntityList snapshot={snapshot} />;
}
