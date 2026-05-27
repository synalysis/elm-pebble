export function errMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}
