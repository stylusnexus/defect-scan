import { z } from "zod";

const User = z.object({ name: z.object({ first: z.string() }) });

export function loadUser(raw: string): string {
  // NEAR-MISS: looks like the unvalidated-JSON bug, but validates at the boundary
  // before dereferencing, so the access is safe.
  const user = User.parse(JSON.parse(raw));
  return user.name.first;
}
