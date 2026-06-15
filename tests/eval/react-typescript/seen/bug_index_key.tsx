export function List({ items }: { items: string[] }) {
  return (
    <ul>
      {items.map((item, i) => (
        <li key={i}>{item}</li>  // cat#5: index key corrupts identity on reorder/insert
      ))}
    </ul>
  );
}
