async function save(data: string): Promise<void> {
  await fetch("/api/save", { method: "POST", body: data });
}

export function onSubmit(data: string): void {
  save(data);  // cat#2: floating promise — rejection is lost, no await/catch/void
}
