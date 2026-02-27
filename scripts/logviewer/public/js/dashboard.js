(() => {
  const $ = (id) => document.getElementById(id);

  const THEME_KEY = "lv_theme_mode"; // "auto" | "light" | "dark"

  function prefersDark() {
    return !!(window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches);
  }

  function applyTheme(mode) {
    let actual = mode;
    if (mode === "auto") actual = prefersDark() ? "dark" : "light";
    document.documentElement.setAttribute("data-bs-theme", actual);
  }

  function getMode() {
    return localStorage.getItem(THEME_KEY) || "auto";
  }

  function setMode(mode) {
    localStorage.setItem(THEME_KEY, mode);
    syncThemeUI();
  }

  function syncThemeUI() {
    const mode = getMode();
    applyTheme(mode);

    const t = $("themeToggle");
    const l = $("themeLabel");
    if (!t || !l) return;

    if (mode === "auto") {
      t.checked = prefersDark();
      l.textContent = "Auto";
    } else if (mode === "dark") {
      t.checked = true;
      l.textContent = "Dark";
    } else {
      t.checked = false;
      l.textContent = "Light";
    }
  }

  syncThemeUI();

  if (window.matchMedia) {
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
      if (getMode() === "auto") syncThemeUI();
    });
  }

  $("themeToggle")?.addEventListener("change", (e) => {
    const checked = !!e.target.checked;
    setMode(checked ? "dark" : "light");
  });

  $("themeLabel")?.addEventListener("dblclick", () => setMode("auto"));

  $("btnSearch")?.addEventListener("click", () => {
    const q = ($("q")?.value || "").trim();
    const u = new URL(location.origin + "/");
    u.searchParams.set("p", "logs");
    if (q) u.searchParams.set("q", q);
    location.href = u.toString();
  });

  $("q")?.addEventListener("keydown", (e) => {
    if (e.key === "Enter") $("btnSearch")?.click();
  });
})();