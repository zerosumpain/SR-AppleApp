// Tells /health there is something to pull (spec E2). Carries no data: the
// pull comes back over loopback with the same token. A lost ring loses
// nothing — the next one pulls everything since the cursor.
export function createDoorbell({ url, token, fetchImpl = fetch, log = console }) {
  if (!url || !token) return () => {};
  let inFlight = false, again = false;
  return function ring() {
    if (inFlight) { again = true; return; }
    inFlight = true;
    (async () => {
      try {
        do {
          again = false;
          await fetchImpl(url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(5000) });
        } while (again);
      } catch (error) { log.warn(`[doorbell] ${error.message}`); }
      finally { inFlight = false; }
    })();
  };
}
