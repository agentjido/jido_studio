(() => {
  const shell = document.currentScript.closest("#studio-shell");
  const sidebar = shell.querySelector("#studio-sidebar-toggle");
  const theme = shell.querySelector("#studio-theme-toggle");
  const narrow = window.matchMedia("(max-width: 44rem)");
  const sidebarKey = "jido-studio-sidebar-state";
  const themeKey = "jido-studio-theme";

  function readPreference(key) {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  function savePreference(key, value) {
    try {
      localStorage.setItem(key, value);
    } catch {
      // The controls also work when the browser blocks storage.
    }
  }

  let sidebarState = readPreference(sidebarKey);

  function syncSidebar() {
    const expanded = sidebarState === "expanded" || (sidebarState !== "collapsed" && !narrow.matches);
    sidebar.setAttribute("aria-expanded", String(expanded));
  }

  sidebar.addEventListener("click", () => {
    sidebarState = sidebar.getAttribute("aria-expanded") === "true" ? "collapsed" : "expanded";
    syncSidebar();
    savePreference(sidebarKey, sidebarState);
  });

  theme.addEventListener("click", () => {
    const light = theme.getAttribute("aria-pressed") !== "true";
    theme.setAttribute("aria-pressed", String(light));
    savePreference(themeKey, light ? "light" : "dark");
  });

  shell.addEventListener("click", (event) => {
    const trigger = event.target.closest("[data-studio-open-dialog]");
    if (!trigger) return;

    const dialog = document.getElementById(trigger.dataset.studioOpenDialog);
    if (dialog instanceof HTMLDialogElement && shell.contains(dialog) && !dialog.open) {
      dialog.showModal();
    }
  });

  narrow.addEventListener("change", syncSidebar);
  syncSidebar();
  theme.setAttribute("aria-pressed", String(readPreference(themeKey) === "light"));
})();
