/* Theme: FOUC prevention (runs sync in <head> before stylesheet) */
(function () {
  var t = localStorage.getItem('ns-theme');
  if (t === 'light') document.documentElement.setAttribute('data-theme', 'light');
}());

/* Theme: toggle initialisation (waits for DOM) */
document.addEventListener('DOMContentLoaded', function () {
  var btn = document.getElementById('theme-toggle');
  var root = document.documentElement;
  if (!btn) return;
  function applyTheme(t) {
    if (t === 'light') {
      root.setAttribute('data-theme', 'light');
      btn.textContent = '\u25d7';
      btn.setAttribute('aria-label', 'Switch to dark theme');
    } else {
      root.removeAttribute('data-theme');
      btn.textContent = '\u2600';
      btn.setAttribute('aria-label', 'Switch to light theme');
    }
  }
  applyTheme(localStorage.getItem('ns-theme') || 'dark');
  btn.addEventListener('click', function () {
    var next = root.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
    localStorage.setItem('ns-theme', next);
    applyTheme(next);
  });
});
