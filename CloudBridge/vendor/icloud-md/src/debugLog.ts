export async function appendDebugLog(..._args: unknown[]): Promise<void> {}
export async function loggedFetch(_label: string, url: string, init?: RequestInit): Promise<Response> { return fetch(url, {...init, signal: AbortSignal.timeout(25000)}); }
