{{flutter_js}}
{{flutter_build_config}}

// No `serviceWorkerSettings`: Flutter's own service worker is now a stub that
// unregisters itself, which would also remove ours (same scope). RootSphere
// registers its own offline worker below instead.
_flutter.loader.load();

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('offline_sw.js').catch((e) => {
      console.warn('Offline support unavailable:', e);
    });
  });
}
