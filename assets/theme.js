/* Theme: FOUC prevention (runs sync in <head> before stylesheet) */
(() => {
  try {
    if (window.localStorage?.getItem('ns-theme') === 'light') {
      document.documentElement.setAttribute('data-theme', 'light');
    }
  } catch (_) {}
})();

/* Theme: toggle initialisation (waits for DOM) */
document.addEventListener('DOMContentLoaded', () => {
  const btn = document.getElementById('theme-toggle');
  const root = document.documentElement;
  if (btn) {
    const setButtonContent = (currentTheme, nextTheme) => {
      const kicker = document.createElement('span');
      kicker.className = 'theme-toggle__kicker';
      kicker.textContent = 'Reading mode';
      const value = document.createElement('span');
      value.className = 'theme-toggle__value';
      value.textContent = currentTheme === 'light' ? 'Day desk' : 'Night desk';
      btn.replaceChildren(kicker, value);
      btn.setAttribute('aria-label', 'Current theme ' + currentTheme + '. Switch to ' + nextTheme + ' theme');
      btn.setAttribute('title', 'Switch to ' + nextTheme + ' theme');
    };

    const applyTheme = (t) => {
      if (t === 'light') {
        root.setAttribute('data-theme', 'light');
        setButtonContent('light', 'dark');
      } else {
        root.removeAttribute('data-theme');
        setButtonContent('dark', 'light');
      }
    };
    let savedTheme = 'dark';
    try {
      savedTheme = window.localStorage?.getItem('ns-theme') || 'dark';
    } catch (_) {}
    applyTheme(savedTheme);
    btn.addEventListener('click', () => {
      const next = root.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
      try {
        window.localStorage?.setItem('ns-theme', next);
      } catch (_) {}
      applyTheme(next);
    });
  }

  /* Reveal animation: fade/lift elements into view using IntersectionObserver */
  const revealEls = document.querySelectorAll('.reveal');
  if (!revealEls.length) return;
  if (!('IntersectionObserver' in window)) {
    revealEls.forEach((el) => { el.classList.add('is-visible'); });
    return;
  }
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.04, rootMargin: '0px 0px 80px 0px' });
  revealEls.forEach((el) => { observer.observe(el); });
});
