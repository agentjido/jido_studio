// Jido Studio - embedded JavaScript
(function () {
  if (window.__jidoStudioComposerInit) return;
  window.__jidoStudioComposerInit = true;

  var INPUT_SELECTOR = "[data-js-chat-input]";

  function isChatInput(el) {
    return !!(el && el.matches && el.matches(INPUT_SELECTOR));
  }

  function maxRows(el) {
    var parsed = parseInt(el && el.dataset ? el.dataset.maxRows : "8", 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 8;
  }

  function parsePx(value) {
    var parsed = parseFloat(value || "0");
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function resizeComposerInput(el) {
    if (!isChatInput(el)) return;

    var style = window.getComputedStyle(el);
    var lineHeight = parsePx(style.lineHeight) || 22;
    var padding = parsePx(style.paddingTop) + parsePx(style.paddingBottom);
    var border = parsePx(style.borderTopWidth) + parsePx(style.borderBottomWidth);
    var minHeight = lineHeight + padding + border;
    var maxHeight = lineHeight * maxRows(el) + padding + border;

    el.style.height = "0px";
    var desired = Math.max(el.scrollHeight, minHeight);
    var clamped = Math.min(desired, maxHeight);

    el.style.height = clamped + "px";
    el.style.overflowY = desired > maxHeight ? "auto" : "hidden";
  }

  function submitFromInput(el) {
    if (!el || el.disabled) return;

    var form = el.closest("form");
    if (!form) return;

    if (typeof form.requestSubmit === "function") {
      form.requestSubmit();
    } else {
      form.submit();
    }
  }

  function syncAllComposerInputs() {
    document.querySelectorAll(INPUT_SELECTOR).forEach(function (el) {
      resizeComposerInput(el);
    });
  }

  function detectTimezone() {
    try {
      var timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
      return timezone && timezone.trim() !== "" ? timezone : "UTC";
    } catch (_error) {
      return "UTC";
    }
  }

  function syncTimezoneForms() {
    var timezone = detectTimezone();

    document.querySelectorAll("[data-js-timezone-form]").forEach(function (form) {
      var input = form.querySelector("[data-js-timezone-input]");
      if (!input) return;

      var previous = input.value || "";
      if (previous === timezone) return;

      input.value = timezone;
      input.dispatchEvent(new Event("change", { bubbles: true }));
    });
  }

  function parseMs(value) {
    var parsed = parseInt(value || "", 10);
    return Number.isFinite(parsed) ? parsed : null;
  }

  function formatRelativeTime(milliseconds) {
    var now = Date.now();
    var diffMs = milliseconds - now;
    var absMs = Math.abs(diffMs);
    var rtf = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });

    if (absMs < 60 * 1000) {
      return rtf.format(Math.round(diffMs / 1000), "second");
    }

    if (absMs < 60 * 60 * 1000) {
      return rtf.format(Math.round(diffMs / (60 * 1000)), "minute");
    }

    if (absMs < 24 * 60 * 60 * 1000) {
      return rtf.format(Math.round(diffMs / (60 * 60 * 1000)), "hour");
    }

    return rtf.format(Math.round(diffMs / (24 * 60 * 60 * 1000)), "day");
  }

  function formatLocalTime(milliseconds) {
    try {
      return new Date(milliseconds).toLocaleString();
    } catch (_error) {
      return "";
    }
  }

  function formatUptimeLabel(milliseconds) {
    if (!Number.isFinite(milliseconds) || milliseconds < 0) return "n/a";

    var totalSeconds = Math.floor(milliseconds / 1000);
    var hours = Math.floor(totalSeconds / 3600);
    var minutes = Math.floor((totalSeconds % 3600) / 60);
    var seconds = totalSeconds % 60;

    if (hours > 0) return hours + "h " + minutes + "m";
    if (minutes > 0) return minutes + "m " + seconds + "s";
    return seconds + "s";
  }

  function refreshTimeElements() {
    document.querySelectorAll("[data-js-ts]").forEach(function (el) {
      var ms = parseMs(el.getAttribute("data-js-ts"));
      if (!Number.isFinite(ms)) return;

      var relative = el.getAttribute("data-js-relative") === "true";
      var local = formatLocalTime(ms);
      var text = relative ? formatRelativeTime(ms) : local;

      el.textContent = text || local || "n/a";

      if (local) {
        el.setAttribute("title", local);
      }
    });

    document.querySelectorAll("[data-js-uptime-ms]").forEach(function (el) {
      var ms = parseMs(el.getAttribute("data-js-uptime-ms"));
      if (!Number.isFinite(ms)) return;
      el.textContent = formatUptimeLabel(ms);
    });
  }

  function syncClientTime() {
    syncTimezoneForms();
    refreshTimeElements();
  }

  var HOME_EXAMPLE_STORAGE_KEY = "jido-studio-home-example-hidden";

  function readHomeExampleHidden() {
    try {
      return localStorage.getItem(HOME_EXAMPLE_STORAGE_KEY) === "1";
    } catch (_error) {
      return false;
    }
  }

  function writeHomeExampleHidden(hidden) {
    try {
      if (hidden) {
        localStorage.setItem(HOME_EXAMPLE_STORAGE_KEY, "1");
      } else {
        localStorage.removeItem(HOME_EXAMPLE_STORAGE_KEY);
      }
    } catch (_error) {
      // ignore storage failures
    }
  }

  function syncHomeExampleVisibility() {
    var hidden = readHomeExampleHidden();

    document.querySelectorAll("[data-js-home-example]").forEach(function (root) {
      var card = root.querySelector("[data-js-home-example-card]");
      var show = root.querySelector("[data-js-home-example-show]");

      if (card) card.classList.toggle("hidden", hidden);
      if (show) show.classList.toggle("hidden", !hidden);
    });
  }

  document.addEventListener(
    "input",
    function (event) {
      if (!isChatInput(event.target)) return;
      resizeComposerInput(event.target);
    },
    true
  );

  document.addEventListener(
    "focusin",
    function (event) {
      if (!isChatInput(event.target)) return;
      resizeComposerInput(event.target);
    },
    true
  );

  document.addEventListener(
    "keydown",
    function (event) {
      if (!isChatInput(event.target)) return;
      if (!(event.metaKey || event.ctrlKey) || event.key !== "Enter") return;

      event.preventDefault();
      submitFromInput(event.target);
    },
    true
  );

  document.addEventListener(
    "click",
    function (event) {
      var hideButton =
        event.target && event.target.closest
          ? event.target.closest("[data-js-home-example-hide]")
          : null;

      if (hideButton) {
        writeHomeExampleHidden(true);
        syncHomeExampleVisibility();
        return;
      }

      var showButton =
        event.target && event.target.closest
          ? event.target.closest("[data-js-home-example-show-btn]")
          : null;

      if (showButton) {
        writeHomeExampleHidden(false);
        syncHomeExampleVisibility();
      }
    },
    true
  );

  document.addEventListener("DOMContentLoaded", syncAllComposerInputs);
  window.addEventListener("pageshow", syncAllComposerInputs);
  window.addEventListener("phx:page-loading-stop", syncAllComposerInputs);
  document.addEventListener("DOMContentLoaded", syncClientTime);
  window.addEventListener("pageshow", syncClientTime);
  window.addEventListener("phx:page-loading-stop", syncClientTime);
  document.addEventListener("DOMContentLoaded", syncHomeExampleVisibility);
  window.addEventListener("pageshow", syncHomeExampleVisibility);
  window.addEventListener("phx:page-loading-stop", syncHomeExampleVisibility);
  window.setInterval(refreshTimeElements, 15 * 1000);
  setTimeout(syncAllComposerInputs, 0);
  setTimeout(syncClientTime, 0);
  setTimeout(syncHomeExampleVisibility, 0);
})();
