export function List({ items }: { items: { id: string; label: string }[] }) {
  return (
    <ul>
      {items.map((item) => (
        <li key={item.id}>{item.label}</li>  // correct: stable identity key
      ))}
    </ul>
  );
}
