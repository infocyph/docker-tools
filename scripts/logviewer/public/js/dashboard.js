(() => {
  const $ = (id) => document.getElementById(id);

  $('btnSearch')?.addEventListener('click', () => {
    const q = ($('q')?.value || '').trim();
    const u = new URL(location.origin + '/');
    u.searchParams.set('p', 'logs');
    if (q) u.searchParams.set('q', q);
    location.href = u.toString();
  });

  $('q')?.addEventListener('keydown', e => {
    if (e.key === 'Enter') {
      $('btnSearch')?.click();
    }
  });
})();