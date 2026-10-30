'use strict';

// RootSphere offline support for the web app.
//
// After one visit online, the app shell (HTML, JS, renderer, fonts, images)
// is kept in the browser so rootsphere.ink opens with no connection. Data
// offline is handled inside the app (cached family tree + sync queue); this
// worker only deals with files.
//
// Strategy:
//  * This site's files: network first, so a new deploy is picked up on the
//    next online visit; the cached copy is used only when the network fails.
//    Page navigations fall back to index.html (the app does its own routing).
//  * Flutter's renderer and Google Fonts files: cache first. Their URLs
//    include a version/hash, so a cached copy never goes stale.
//  * Uploaded photos (Supabase Storage): shown from cache straight away and
//    refreshed in the background.
//  * Everything else (Supabase API, maps, videos): not touched.
//
// Bump VERSION to throw away everything cached by older versions.

const VERSION = 'v2';
const SITE_CACHE = `rootsphere-site-${VERSION}`;
const CDN_CACHE = `rootsphere-cdn-${VERSION}`;
const PHOTO_CACHE = `rootsphere-photos-${VERSION}`;

// Fetched on install so the app can start offline even if the first visit
// was cut short. Failures are ignored (e.g. a file renamed by a Flutter
// upgrade) — the runtime cache fills in the rest.
const SHELL = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
  'assets/fonts/MaterialIcons-Regular.otf',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(SITE_CACHE);
      await Promise.allSettled(
        SHELL.map((path) => cache.add(new Request(path, { cache: 'reload' }))),
      );
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keep = [SITE_CACHE, CDN_CACHE, PHOTO_CACHE];
      for (const key of await caches.keys()) {
        if (!keep.includes(key)) await caches.delete(key);
      }
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || request.headers.has('range')) return;
  const url = new URL(request.url);

  if (url.origin === self.location.origin) {
    // Videos are large and streamed in ranges; leave them to the browser
    // (their poster images are still cached).
    if (url.pathname.startsWith('/videos/') && url.pathname.endsWith('.mp4')) {
      return;
    }
    if (request.mode === 'navigate') {
      event.respondWith(networkFirst(request, SITE_CACHE, 'index.html'));
    } else {
      event.respondWith(networkFirst(request, SITE_CACHE));
    }
    return;
  }

  if (
    (url.hostname === 'www.gstatic.com' &&
      url.pathname.startsWith('/flutter-canvaskit/')) ||
    url.hostname === 'fonts.gstatic.com'
  ) {
    event.respondWith(cacheFirst(request, CDN_CACHE));
    return;
  }

  if (url.hostname === 'fonts.googleapis.com') {
    event.respondWith(networkFirst(request, CDN_CACHE));
    return;
  }

  if (
    url.hostname.endsWith('.supabase.co') &&
    url.pathname.includes('/storage/v1/object/public/')
  ) {
    event.respondWith(staleWhileRevalidate(event, request, PHOTO_CACHE));
  }
});

function cacheable(response) {
  return response && (response.ok || response.type === 'opaque');
}

async function networkFirst(request, cacheName, fallbackPath) {
  const cache = await caches.open(cacheName);
  try {
    const response = await fetch(request);
    if (cacheable(response)) await cache.put(request, response.clone());
    return response;
  } catch (error) {
    const cached =
      (await cache.match(request)) ||
      (fallbackPath && (await cache.match(fallbackPath)));
    if (cached) return cached;
    throw error;
  }
}

async function cacheFirst(request, cacheName) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (cacheable(response)) await cache.put(request, response.clone());
  return response;
}

async function staleWhileRevalidate(event, request, cacheName) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request);
  const refresh = fetch(request)
    .then(async (response) => {
      if (cacheable(response)) await cache.put(request, response.clone());
      return response;
    })
    .catch(() => undefined);
  if (cached) {
    event.waitUntil(refresh);
    return cached;
  }
  return (await refresh) || Response.error();
}
