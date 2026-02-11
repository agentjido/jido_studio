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

  document.addEventListener("DOMContentLoaded", syncAllComposerInputs);
  window.addEventListener("pageshow", syncAllComposerInputs);
  window.addEventListener("phx:page-loading-stop", syncAllComposerInputs);
  setTimeout(syncAllComposerInputs, 0);
})();
