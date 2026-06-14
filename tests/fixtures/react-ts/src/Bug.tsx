import { useEffect, useState } from "react";

export function Timer({ ms }: { ms: number }) {
  const [n, setN] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setN(n + 1), ms);  // cat#5: stale closure on n
    // cat#4: no cleanup — interval leaks on unmount
  }, []);                                            // cat#5: missing dep `ms`, `n`
  return <span>{n}</span>;
}
