/* Theme: FOUC prevention (runs sync in <head> before stylesheet) */
(function () {
  var t = localStorage.getItem('ns-theme');
  if (t === 'light') document.documentElement.setAttribute('data-theme', 'light');
}());

/* Theme: toggle initialisation (waits for DOM) */
document.addEventListener('DOMContentLoaded', function () {
  var btn = document.getElementById('theme-toggle');
  var root = document.documentElement;
  if (btn) {
    function applyTheme(t) {
      if (t === 'light') {
        root.setAttribute('data-theme', 'light');
        btn.textContent = 'Dark';
        btn.setAttribute('aria-label', 'Switch to dark theme');
      } else {
        root.removeAttribute('data-theme');
        btn.textContent = 'Light';
        btn.setAttribute('aria-label', 'Switch to light theme');
      }
    }
    applyTheme(localStorage.getItem('ns-theme') || 'dark');
    btn.addEventListener('click', function () {
      var next = root.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
      localStorage.setItem('ns-theme', next);
      applyTheme(next);
    });
  }

  /* Reveal animation: fade/lift elements into view using IntersectionObserver */
  var revealEls = document.querySelectorAll('.reveal');
  if (!revealEls.length) return;
  if (!('IntersectionObserver' in window)) {
    revealEls.forEach(function (el) { el.classList.add('is-visible'); });
    return;
  }
  var observer = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.04, rootMargin: '0px 0px 80px 0px' });
  revealEls.forEach(function (el) { observer.observe(el); });
});
