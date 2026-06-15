async function save(data: string): Promise<void> {
  await fetch("/api/save", { method: "POST", body: data });
}

export async function onSubmit(data: string): Promise<void> {
  await save(data);  // correct: awaited, rejection propagates
}
