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
          const res = await fetchImpl(url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(5000) });
          // Status only — never the token, and never the body, which /health's
          // pull route has no reason to send back anyway.
          if (!res.ok) log.warn(`[doorbell] ${res.status}`);
          // Releasing the body must never itself crash the ring: an errored
          // stream can make `cancel()` reject, and an un-awaited rejection
          // there becomes an unhandled one that kills the process (R8).
          try { await res.body?.cancel?.(); } catch {}
        } while (again);
      } catch (error) { log.warn(`[doorbell] ${error?.message ?? error}`); }
      finally { inFlight = false; }
    })();
  };
}
