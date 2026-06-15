interface User { name: { first: string } }

export function loadUser(raw: string): string {
  const user = JSON.parse(raw) as User;  // cat#1: types erased at runtime; unvalidated
  return user.name.first;                // unguarded deref of untrusted input
}
