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
  var HOME_SETUP_STORAGE_KEY = "jido-studio-home-setup-hidden";
  var HOME_SETUP_LAST_COMPLETE_KEY = "jido-studio-home-setup-last-complete";
  var HOME_SETUP_COMPLETE_EMITTED = false;

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

  function readHomeSetupHidden() {
    try {
      return localStorage.getItem(HOME_SETUP_STORAGE_KEY) === "1";
    } catch (_error) {
      return false;
    }
  }

  function writeHomeSetupHidden(hidden) {
    try {
      if (hidden) {
        localStorage.setItem(HOME_SETUP_STORAGE_KEY, "1");
      } else {
        localStorage.removeItem(HOME_SETUP_STORAGE_KEY);
      }
    } catch (_error) {
      // ignore storage failures
    }
  }

  function readHomeSetupLastComplete() {
    try {
      return localStorage.getItem(HOME_SETUP_LAST_COMPLETE_KEY) === "1";
    } catch (_error) {
      return false;
    }
  }

  function writeHomeSetupLastComplete(complete) {
    try {
      if (complete) {
        localStorage.setItem(HOME_SETUP_LAST_COMPLETE_KEY, "1");
      } else {
        localStorage.removeItem(HOME_SETUP_LAST_COMPLETE_KEY);
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

  function syncHomeSetupVisibility() {
    var hidden = readHomeSetupHidden();
    var wasComplete = readHomeSetupLastComplete();

    document.querySelectorAll("[data-js-home-setup]").forEach(function (root) {
      var complete = root.getAttribute("data-js-home-setup-complete") === "true";
      var grid = root.querySelector("[data-js-home-setup-grid]");
      var card = root.querySelector("[data-js-home-setup-card]");
      var show = root.querySelector("[data-js-home-setup-show]");
      var regressed = root.querySelector("[data-js-home-setup-regressed]");
      var shouldHide = hidden && complete;
      var hasRegressed = wasComplete && !complete;

      if (!complete && hidden) {
        writeHomeSetupHidden(false);
        shouldHide = false;
      }

      if (grid) {
        grid.classList.toggle("xl:grid-cols-1", shouldHide);
        grid.classList.toggle("xl:grid-cols-2", !shouldHide);
      }

      if (card) card.classList.toggle("hidden", shouldHide);
      if (show) show.classList.toggle("hidden", !shouldHide);
      if (regressed) regressed.classList.toggle("hidden", !hasRegressed);
      writeHomeSetupLastComplete(complete);

      if (complete && !HOME_SETUP_COMPLETE_EMITTED) {
        HOME_SETUP_COMPLETE_EMITTED = true;
        window.dispatchEvent(new CustomEvent("jido-studio:setup-completed"));
      }

      if (!complete) {
        HOME_SETUP_COMPLETE_EMITTED = false;
      }
    });
  }

  var TOUR_STATE_STORAGE_KEY = "jido-studio-tour-state";
  var TOUR_LAST_RENDERED_TOKEN = null;
  var TOUR_ACTIVE_TARGET = null;
  var TOUR_OVERLAY = null;
  var TOUR_BUBBLE = null;

  function parseTourCatalog() {
    var wrapper = document.getElementById("studio-wrapper");
    if (!wrapper) return {};

    var encoded = wrapper.getAttribute("data-js-tour-catalog");
    if (!encoded) return {};

    try {
      var parsed = JSON.parse(encoded);
      if (!Array.isArray(parsed)) return {};

      return parsed.reduce(function (acc, flow) {
        if (flow && typeof flow.key === "string" && Array.isArray(flow.steps)) {
          acc[flow.key] = flow;
        }

        return acc;
      }, {});
    } catch (_error) {
      return {};
    }
  }

  function normalizeTourState(raw) {
    var state = raw && typeof raw === "object" ? raw : {};

    if (!state.progress || typeof state.progress !== "object") {
      state.progress = {};
    }

    if (typeof state.active_flow !== "string" || state.active_flow === "") {
      state.active_flow = null;
    }

    var stepIndex = parseMs(state.step_index);
    state.step_index = Number.isFinite(stepIndex) && stepIndex >= 0 ? stepIndex : 0;

    return state;
  }

  function readTourState() {
    try {
      var raw = localStorage.getItem(TOUR_STATE_STORAGE_KEY);
      if (!raw) return normalizeTourState({});
      return normalizeTourState(JSON.parse(raw));
    } catch (_error) {
      return normalizeTourState({});
    }
  }

  function writeTourState(state) {
    try {
      localStorage.setItem(TOUR_STATE_STORAGE_KEY, JSON.stringify(normalizeTourState(state)));
    } catch (_error) {
      // ignore storage failures
    }
  }

  function flowProgress(state, flowKey) {
    var progress = state.progress[flowKey];

    if (!progress || typeof progress !== "object") {
      progress = {
        step_index: 0,
        completed_step_keys: [],
        completed_at_ms: null,
        dismissed_at_ms: null
      };

      state.progress[flowKey] = progress;
    }

    if (!Array.isArray(progress.completed_step_keys)) {
      progress.completed_step_keys = [];
    }

    return progress;
  }

  function normalizeStepPath(stepPath) {
    var normalized = typeof stepPath === "string" ? stepPath.trim() : "/";
    if (normalized === "") return "/";
    if (normalized.charAt(0) !== "/") normalized = "/" + normalized;
    return normalized;
  }

  function splitPathAndQuery(pathWithQuery) {
    var normalized = normalizeStepPath(pathWithQuery);
    var qmarkIndex = normalized.indexOf("?");

    if (qmarkIndex < 0) {
      return { path: normalized, query: new URLSearchParams() };
    }

    return {
      path: normalized.slice(0, qmarkIndex) || "/",
      query: new URLSearchParams(normalized.slice(qmarkIndex + 1))
    };
  }

  function wrapperPrefix() {
    var wrapper = document.getElementById("studio-wrapper");
    if (!wrapper) return "";

    var prefix = wrapper.getAttribute("data-prefix") || "";
    if (prefix === "/") return "";
    return prefix.replace(/\/+$/, "");
  }

  function stripPrefix(path, prefix) {
    if (typeof prefix !== "string" || prefix === "") return path;
    if (path.indexOf(prefix) === 0) {
      var stripped = path.slice(prefix.length);
      return stripped === "" ? "/" : stripped;
    }

    return path;
  }

  function matchesCurrentStep(stepPath) {
    var expected = splitPathAndQuery(stepPath);
    var prefix = wrapperPrefix();
    var currentRelative = stripPrefix(window.location.pathname, prefix);
    var currentParams = new URLSearchParams(window.location.search);

    if (normalizeStepPath(currentRelative) !== normalizeStepPath(expected.path)) {
      return false;
    }

    var queryMatches = true;

    expected.query.forEach(function (value, key) {
      if (currentParams.get(key) !== value) queryMatches = false;
    });

    return queryMatches;
  }

  function buildStepUrl(stepPath) {
    var step = splitPathAndQuery(stepPath);
    var prefix = wrapperPrefix();
    var basePath = prefix + (step.path === "/" ? "" : step.path);
    var url = new URL(basePath || "/", window.location.origin);
    var currentParams = new URLSearchParams(window.location.search);

    step.query.forEach(function (value, key) {
      url.searchParams.set(key, value);
    });

    ["runtime", "node"].forEach(function (key) {
      if (!url.searchParams.has(key)) {
        var currentValue = currentParams.get(key);
        if (currentValue && currentValue.trim() !== "") {
          url.searchParams.set(key, currentValue);
        }
      }
    });

    return url.toString();
  }

  function removeActiveTourTarget() {
    if (TOUR_ACTIVE_TARGET) {
      TOUR_ACTIVE_TARGET.classList.remove("js-tour-target-active");
      TOUR_ACTIVE_TARGET = null;
    }
  }

  function ensureTourOverlay() {
    if (TOUR_OVERLAY && TOUR_BUBBLE) return;

    var existing = document.getElementById("js-tour-overlay");
    if (existing) existing.remove();

    TOUR_OVERLAY = document.createElement("div");
    TOUR_OVERLAY.id = "js-tour-overlay";
    TOUR_OVERLAY.className = "js-tour-overlay hidden";
    TOUR_OVERLAY.innerHTML =
      '<div class="js-tour-backdrop"></div><div class="js-tour-bubble" data-js-tour-bubble></div>';

    document.body.appendChild(TOUR_OVERLAY);
    TOUR_BUBBLE = TOUR_OVERLAY.querySelector("[data-js-tour-bubble]");

    TOUR_OVERLAY.addEventListener("click", function (event) {
      var actionTarget =
        event.target && event.target.closest
          ? event.target.closest("[data-js-tour-action]")
          : null;

      if (!actionTarget) return;

      var action = actionTarget.getAttribute("data-js-tour-action");

      if (action === "next") {
        advanceTourStep();
      } else if (action === "back") {
        rewindTourStep();
      } else if (action === "dismiss") {
        dismissTour("dismissed");
      }
    });
  }

  function hideTourOverlay() {
    if (TOUR_OVERLAY) {
      TOUR_OVERLAY.classList.add("hidden");
    }

    if (TOUR_BUBBLE) {
      TOUR_BUBBLE.innerHTML = "";
      TOUR_BUBBLE.removeAttribute("style");
    }

    removeActiveTourTarget();
    TOUR_LAST_RENDERED_TOKEN = null;
  }

  function setBubblePosition(target) {
    if (!TOUR_BUBBLE) return;

    var width = Math.min(360, window.innerWidth - 24);
    var left = 12;
    var top = 12;

    if (target) {
      var rect = target.getBoundingClientRect();
      left = Math.max(12, Math.min(rect.left, window.innerWidth - width - 12));
      top = rect.bottom + 12;
    } else {
      left = Math.max(12, Math.floor((window.innerWidth - width) / 2));
      top = Math.max(24, Math.floor(window.innerHeight * 0.16));
    }

    TOUR_BUBBLE.style.width = width + "px";
    TOUR_BUBBLE.style.left = left + "px";
    TOUR_BUBBLE.style.top = top + "px";

    if (target) {
      var bubbleRect = TOUR_BUBBLE.getBoundingClientRect();
      if (bubbleRect.bottom > window.innerHeight - 12) {
        var targetRect = target.getBoundingClientRect();
        var candidateTop = targetRect.top - bubbleRect.height - 12;
        TOUR_BUBBLE.style.top = Math.max(12, candidateTop) + "px";
      }
    }
  }

  function emitTourMetric(kind, detail) {
    var bridge = document.querySelector("[data-js-tour-metric]");
    if (!bridge || !kind) return;

    Array.prototype.slice.call(bridge.attributes).forEach(function (attribute) {
      if (attribute && /^phx-value-/.test(attribute.name)) {
        bridge.removeAttribute(attribute.name);
      }
    });

    bridge.setAttribute("phx-value-kind", kind);

    Object.keys(detail || {}).forEach(function (key) {
      var value = detail[key];
      if (value === undefined || value === null || value === "") return;
      bridge.setAttribute("phx-value-" + key, String(value));
    });

    bridge.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
  }

  function metricPayload(flow, step, stepIndex, totalSteps, extras) {
    var payload = {
      flow: flow && flow.key,
      step_key: step && step.key,
      step_index: stepIndex + 1,
      total_steps: totalSteps
    };

    Object.keys(extras || {}).forEach(function (key) {
      payload[key] = extras[key];
    });

    return payload;
  }

  function startTourFlow(flowKey, mode) {
    var catalog = parseTourCatalog();
    var flow = catalog[flowKey];
    if (!flow || !Array.isArray(flow.steps) || flow.steps.length === 0) return;

    var state = readTourState();
    var progress = flowProgress(state, flowKey);
    var startAt = 0;

    if (mode === "resume") {
      startAt = parseMs(progress.step_index);
      startAt = Number.isFinite(startAt) && startAt >= 0 ? startAt : 0;
    } else {
      progress.step_index = 0;
      progress.completed_step_keys = [];
      progress.completed_at_ms = null;
      progress.dismissed_at_ms = null;
      startAt = 0;
    }

    state.active_flow = flowKey;
    state.step_index = startAt;
    progress.step_index = startAt;
    writeTourState(state);

    emitTourMetric(
      "started",
      metricPayload(flow, flow.steps[startAt], startAt, flow.steps.length, {
        mode: mode || "start"
      })
    );

    syncGuideFlowCards();
    renderActiveTourStep();
  }

  function dismissTour(status) {
    var catalog = parseTourCatalog();
    var state = readTourState();
    var flow = catalog[state.active_flow];
    if (!flow || !Array.isArray(flow.steps) || flow.steps.length === 0) {
      hideTourOverlay();
      return;
    }

    var stepIndex = Math.max(0, Math.min(state.step_index || 0, flow.steps.length - 1));
    var step = flow.steps[stepIndex];
    var progress = flowProgress(state, flow.key);

    progress.step_index = stepIndex;
    progress.dismissed_at_ms = Date.now();
    state.active_flow = null;
    writeTourState(state);

    emitTourMetric(
      "dismissed",
      metricPayload(flow, step, stepIndex, flow.steps.length, {
        status: status || "dismissed"
      })
    );

    hideTourOverlay();
    syncGuideFlowCards();
  }

  function markStepCompleted(progress, step) {
    if (!progress || !step || !step.key) return;
    if (progress.completed_step_keys.indexOf(step.key) >= 0) return;
    progress.completed_step_keys.push(step.key);
  }

  function advanceTourStep() {
    var catalog = parseTourCatalog();
    var state = readTourState();
    var flow = catalog[state.active_flow];
    if (!flow || !Array.isArray(flow.steps) || flow.steps.length === 0) return;

    var stepIndex = Math.max(0, Math.min(state.step_index || 0, flow.steps.length - 1));
    var step = flow.steps[stepIndex];
    var progress = flowProgress(state, flow.key);

    emitTourMetric("step_completed", metricPayload(flow, step, stepIndex, flow.steps.length));

    markStepCompleted(progress, step);

    if (stepIndex >= flow.steps.length - 1) {
      progress.step_index = stepIndex;
      progress.completed_at_ms = Date.now();
      state.active_flow = null;
      state.step_index = stepIndex;
      writeTourState(state);

      emitTourMetric(
        "completed",
        metricPayload(flow, step, stepIndex, flow.steps.length, { status: "completed" })
      );

      hideTourOverlay();
      syncGuideFlowCards();
      return;
    }

    state.step_index = stepIndex + 1;
    progress.step_index = stepIndex + 1;
    writeTourState(state);
    renderActiveTourStep();
  }

  function rewindTourStep() {
    var catalog = parseTourCatalog();
    var state = readTourState();
    var flow = catalog[state.active_flow];
    if (!flow || !Array.isArray(flow.steps) || flow.steps.length === 0) return;

    var stepIndex = Math.max(0, Math.min(state.step_index || 0, flow.steps.length - 1));
    if (stepIndex === 0) return;

    var progress = flowProgress(state, flow.key);
    state.step_index = stepIndex - 1;
    progress.step_index = stepIndex - 1;
    writeTourState(state);
    renderActiveTourStep();
  }

  function renderActiveTourStep() {
    var catalog = parseTourCatalog();
    var state = readTourState();
    var flow = catalog[state.active_flow];

    if (!flow || !Array.isArray(flow.steps) || flow.steps.length === 0) {
      hideTourOverlay();
      return;
    }

    var stepIndex = Math.max(0, Math.min(state.step_index || 0, flow.steps.length - 1));
    var step = flow.steps[stepIndex];

    if (!matchesCurrentStep(step.path)) {
      window.location.assign(buildStepUrl(step.path));
      return;
    }

    ensureTourOverlay();

    var target = null;

    if (typeof step.selector === "string" && step.selector.trim() !== "") {
      target = document.querySelector(step.selector);
    }

    removeActiveTourTarget();

    if (target) {
      TOUR_ACTIVE_TARGET = target;
      TOUR_ACTIVE_TARGET.classList.add("js-tour-target-active");
    }

    var isLast = stepIndex === flow.steps.length - 1;
    var fallbackVisible = !target && step.fallback;

    TOUR_BUBBLE.innerHTML =
      '<div class="js-tour-kicker">Guided Tour</div>' +
      '<div class="js-tour-title">' +
      (step.title || "Step") +
      "</div>" +
      '<p class="js-tour-body">' +
      (step.body || "") +
      "</p>" +
      (fallbackVisible
        ? '<p class="js-tour-fallback">' + step.fallback + "</p>"
        : "") +
      '<div class="js-tour-progress">Step ' +
      (stepIndex + 1) +
      " of " +
      flow.steps.length +
      "</div>" +
      '<div class="js-tour-actions">' +
      '<button type="button" data-js-tour-action="back" ' +
      (stepIndex === 0 ? "disabled" : "") +
      '>Back</button>' +
      '<button type="button" data-js-tour-action="dismiss">Exit Tour</button>' +
      '<button type="button" data-js-tour-action="next">' +
      (isLast ? "Finish" : "Next") +
      "</button>" +
      "</div>";

    TOUR_OVERLAY.classList.remove("hidden");
    setBubblePosition(target);

    var renderToken = flow.key + ":" + step.key + ":" + stepIndex;
    if (TOUR_LAST_RENDERED_TOKEN !== renderToken) {
      TOUR_LAST_RENDERED_TOKEN = renderToken;
      emitTourMetric("step_viewed", metricPayload(flow, step, stepIndex, flow.steps.length));
    }
  }

  function syncGuideFlowCards() {
    var catalog = parseTourCatalog();
    var state = readTourState();

    document.querySelectorAll("[data-js-tour-flow]").forEach(function (card) {
      var flowKey = card.getAttribute("data-js-tour-flow");
      var flow = catalog[flowKey];
      if (!flow || !Array.isArray(flow.steps)) return;

      var progress = flowProgress(state, flowKey);
      var total = flow.steps.length;
      var completedCount = progress.completed_step_keys.length;
      var active = state.active_flow === flowKey;
      var status = card.querySelector("[data-js-tour-status]");
      var resume = card.querySelector("[data-js-tour-resume]");
      var replay = card.querySelector("[data-js-tour-replay]");

      if (status) {
        if (active) {
          status.textContent = "In progress: step " + (state.step_index + 1) + " of " + total;
        } else if (progress.completed_at_ms) {
          status.textContent = "Completed";
        } else if (completedCount > 0 || progress.step_index > 0) {
          status.textContent =
            "Progress saved: step " + (Math.min(progress.step_index, total - 1) + 1) + " of " + total;
        } else {
          status.textContent = "Not started";
        }
      }

      if (resume) {
        var canResume = !active && !progress.completed_at_ms && (completedCount > 0 || progress.step_index > 0);
        resume.classList.toggle("hidden", !canResume);
      }

      if (replay) {
        var canReplay = !!progress.completed_at_ms || completedCount > 0 || progress.step_index > 0;
        replay.classList.toggle("hidden", !canReplay);
      }
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
      var startTourButton =
        event.target && event.target.closest
          ? event.target.closest("[data-js-tour-start]")
          : null;

      if (startTourButton) {
        startTourFlow(startTourButton.getAttribute("data-js-tour-start"), "start");
        return;
      }

      var resumeTourButton =
        event.target && event.target.closest
          ? event.target.closest("[data-js-tour-resume]")
          : null;

      if (resumeTourButton) {
        startTourFlow(resumeTourButton.getAttribute("data-js-tour-resume"), "resume");
        return;
      }

      var replayTourButton =
        event.target && event.target.closest
          ? event.target.closest("[data-js-tour-replay]")
          : null;

      if (replayTourButton) {
        startTourFlow(replayTourButton.getAttribute("data-js-tour-replay"), "replay");
        return;
      }

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
        return;
      }

      var hideSetupButton =
        event.target && event.target.closest
          ? event.target.closest("[data-js-home-setup-hide]")
          : null;

      if (hideSetupButton) {
        writeHomeSetupHidden(true);
        syncHomeSetupVisibility();
        return;
      }

      var showSetupButton =
        event.target && event.target.closest
          ? event.target.closest("[data-js-home-setup-show-btn]")
          : null;

      if (showSetupButton) {
        writeHomeSetupHidden(false);
        syncHomeSetupVisibility();
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
  document.addEventListener("DOMContentLoaded", syncHomeSetupVisibility);
  window.addEventListener("pageshow", syncHomeSetupVisibility);
  window.addEventListener("phx:page-loading-stop", syncHomeSetupVisibility);
  document.addEventListener("DOMContentLoaded", syncGuideFlowCards);
  window.addEventListener("pageshow", syncGuideFlowCards);
  window.addEventListener("phx:page-loading-stop", syncGuideFlowCards);
  document.addEventListener("DOMContentLoaded", renderActiveTourStep);
  window.addEventListener("pageshow", renderActiveTourStep);
  window.addEventListener("phx:page-loading-stop", renderActiveTourStep);
  window.addEventListener("resize", renderActiveTourStep);
  window.setInterval(refreshTimeElements, 15 * 1000);
  setTimeout(syncAllComposerInputs, 0);
  setTimeout(syncClientTime, 0);
  setTimeout(syncHomeExampleVisibility, 0);
  setTimeout(syncHomeSetupVisibility, 0);
  setTimeout(syncGuideFlowCards, 0);
  setTimeout(renderActiveTourStep, 0);
})();
