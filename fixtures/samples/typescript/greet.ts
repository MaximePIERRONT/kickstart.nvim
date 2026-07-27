export function greet(name: string): string {
  const safe = name.trim() || 'world'
  return `Hello, ${safe}!`
}

export const answer = 41 + 1
