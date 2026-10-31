/* WalkInCovenant service worker — the thing that replaces Covenant's
   single-file offline html.
   
   First load: normal network fetch, everything gets cached.
   Every load after: cache-first, so the game opens on a bus with no signal.
   This is how a hosted Godot build gives players the "works offline, no
   install" property the old Covenant-offline.html gave them, without needing
   the (impossible-for-WASM) single-file trick.

   Bump CACHE on every deploy so players never run stale .pck against new code.
   CI stamps it from the git sha. */

const CACHE = "walkincovenant-v1";

/* The Godot web export's fixed file set. The .pck holds every game asset, so
   caching it is what makes offline play real. */
const CORE = [
  "./",
  "./index.html",
  "./index.js",
  "./index.wasm",
  "./index.pck",
  "./index.audio.worklet.js",
  "./index.audio.position.worklet.js",
  "./index.png",
  "./manifest.webmanifest",
];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) =>
      // Tolerate a missing optional file; a failed core file must not kill install.
      Promise.allSettled(CORE.map((u) => c.add(u)))
    ).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET" || !req.url.startsWith(self.location.origin)) return;

  e.respondWith(
    caches.match(req, { ignoreSearch: true }).then((hit) => {
      if (hit) return hit;
      return fetch(req).then((res) => {
        // Cache same-origin successes so the *next* visit is offline-complete.
        if (res && res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      }).catch(() => caches.match("./index.html"));
    })
  );
});
