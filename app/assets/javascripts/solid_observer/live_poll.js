(function () {
  "use strict";

  var MAX_POINTS = 60;
  var SVG_W = 120,
    SVG_H = 32;
  var INTERVAL_SEC = 5;

  // Shared state — IIFE-level so all functions can access them
  var checkbox, rangeSelect, refreshBtn, helpBtn, helpPanel, helpWrapper, freshnessEl;
  var hoverActive = false;
  var sparks = {};
  var url;
  var inFlight = false;
  var timerId = null;
  var lastFullSnapshot = null;
  var lastFullChart = null;
  var lastRange = null;

  function init() {
    var wrapper = document.querySelector("[data-so-live]");
    if (!wrapper) return;

    url = wrapper.getAttribute("data-so-poll-url") || "/solid_observer/poll_data";

    checkbox = wrapper.querySelector('[data-so-live-toggle]');
    if (!checkbox) return;

    rangeSelect = wrapper.querySelector("[data-so-range-select]");
    refreshBtn = wrapper.querySelector("[data-so-refresh]");
    helpBtn = wrapper.querySelector("[data-so-help-btn]");
    helpPanel = wrapper.querySelector("[data-so-help-panel]");
    helpWrapper = wrapper.querySelector("[data-so-help-wrapper]");
    freshnessEl = wrapper.querySelector("[data-so-freshness]");

    sparks = collectSparks();
    lastRange = readRangeFromUrl() || "15m";

    // --- Range change (full fetch) ---
    if (rangeSelect) {
      rangeSelect.addEventListener("change", function () {
        lastRange = rangeSelect.value;
        updateUrlRange(lastRange);
        updateUrlLive(checkbox.checked);
        fullFetch();
      });
    }

    // --- Refresh button (full fetch) ---
    if (refreshBtn) {
      refreshBtn.addEventListener("click", function () {
        fullFetch();
      });
    }

    // --- Help disclosure ---
    if (helpBtn && helpPanel) {
      helpBtn.addEventListener("click", function () {
        var expanded = helpBtn.getAttribute("aria-expanded") === "true";
        // Don't close on click if hover is active — mouseleave will handle closing
        if (expanded && hoverActive) {
          return;
        }
        helpBtn.setAttribute("aria-expanded", String(!expanded));
        helpPanel.hidden = expanded;
      });
      helpBtn.addEventListener("keydown", function (e) {
        if (e.key === "Escape") {
          helpBtn.setAttribute("aria-expanded", "false");
          helpPanel.hidden = true;
          helpBtn.focus();
        }
      });
      helpBtn.addEventListener("focusout", function (e) {
        var related = e.relatedTarget;
        if (!related || !helpPanel.contains(related)) {
          helpBtn.setAttribute("aria-expanded", "false");
          helpPanel.hidden = true;
        }
      });
      document.addEventListener("click", function (e) {
        if (helpPanel && !helpPanel.contains(e.target) && e.target !== helpBtn) {
          helpBtn.setAttribute("aria-expanded", "false");
          helpPanel.hidden = true;
        }
      });
      // Focusout/blur close behavior
      helpPanel.addEventListener("focusout", function (e) {
        if (!helpPanel.contains(e.relatedTarget) && e.relatedTarget !== helpBtn) {
          helpBtn.setAttribute("aria-expanded", "false");
          helpPanel.hidden = true;
        }
      });
      // Hover show/hide for mouse users
      if (helpWrapper) {
        helpWrapper.addEventListener("mouseenter", function () {
          hoverActive = true;
          helpBtn.setAttribute("aria-expanded", "true");
          helpPanel.hidden = false;
        });
        helpWrapper.addEventListener("mouseleave", function () {
          hoverActive = false;
          helpBtn.setAttribute("aria-expanded", "false");
          helpPanel.hidden = true;
        });
      }
    }

    // --- Live toggle ---
    checkbox.addEventListener("change", function () {
      updateUrlLive(checkbox.checked);
      var label = checkbox.closest("label");
      label.classList.toggle("so-toggle--on", checkbox.checked);
      label.querySelector(".so-toggle__cadence").textContent = checkbox.checked
        ? "5s"
        : "off";
      if (checkbox.checked) {
        start();
      } else {
        stop();
      }
    });

    document.addEventListener("visibilitychange", function () {
      if (document.hidden) {
        stop();
      } else if (checkbox.checked) {
        tick();
        start();
      }
    });

    if (checkbox.checked) start();
    checkbox
      .closest("label")
      .classList.toggle("so-toggle--on", checkbox.checked);
  }

  function fullFetch() {
    if (inFlight) return;
    inFlight = true;

    if (refreshBtn) {
      refreshBtn.textContent = "Refreshing\u2026";
      refreshBtn.setAttribute("aria-busy", "true");
      refreshBtn.disabled = true;
    }

    // Add loading class to range-bound zones
    addLoadingClass(true);

    var rangeParam = lastRange || readRangeFromUrl() || "15m";
    fetch(
      url + "?range=" + encodeURIComponent(rangeParam),
      { headers: { Accept: "application/json" }, credentials: "same-origin" }
    )
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (data) {
        if (data) {
          lastFullSnapshot = data.snapshot || {};
          lastFullChart = data.chart || {};
          applyFullUpdate(data);
          updateFreshness("Updated just now");
        }
      })
      .catch(function () { /* drop silently */ })
      .finally(function () {
        inFlight = false;
        addLoadingClass(false);
        if (refreshBtn) {
          refreshBtn.textContent = "Refresh data";
          refreshBtn.setAttribute("aria-busy", "false");
          refreshBtn.disabled = false;
          refreshBtn.focus();
        }
      });
  }

  function tick() {
    if (inFlight) return;
    inFlight = true;
    var rangeParam = lastRange || readRangeFromUrl() || "15m";
    fetch(
      url + "?range=" + encodeURIComponent(rangeParam) + "&tick=true",
      { headers: { Accept: "application/json" }, credentials: "same-origin" }
    )
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (data) {
        if (data) applyTickUpdate(data);
      })
      .catch(function () { /* drop tick silently */ })
      .finally(function () { inFlight = false; });
  }

  function applyFullUpdate(data) {
    var snapshot = data.snapshot || {};
    // Patch live-state values (Zone B)
    patchZoneValues("live-state", snapshot);
    // Patch throughput values (Zone C) — value nodes only, preserve suffix/range-copy
    patchZoneValues("throughput", snapshot);
    // Patch chart indicator values (Zone D) — range totals, not latest bucket
    patchZoneValues("chart", snapshot);
    // Patch queue table (Zone E)
    patchQueueTable(snapshot);
    // Patch stability (Zone F)
    patchStability(snapshot);
    // Update chart sparklines (Zone D)
    var chart = data.chart || {};
    Object.keys(sparks).forEach(function (key) {
      var series = chart[key];
      if (Array.isArray(series)) sparks[key].render(series);
    });
    // Update range-copy nodes from server-provided label
    if (data.range_label) {
      updateRangeCopyFromLabel(data.range_label);
    }
  }

  function applyTickUpdate(data) {
    var snapshot = data.snapshot || {};
    // Tick only patches live-state values (Zone B)
    patchZoneValues("live-state", snapshot);
    // chart is nil on tick — preserve last full-fetch chart/range state
  }

  function patchZoneValues(zone, snapshot) {
    var zoneEl = document.querySelector('[data-so-zone="' + zone + '"]');
    if (!zoneEl) return;
    var valueEls = zoneEl.querySelectorAll("[data-so-card-value]");
    valueEls.forEach(function (el) {
      var key = el.getAttribute("data-so-card-value");
      if (snapshot.hasOwnProperty(key)) {
        var val = snapshot[key];
        // Duration values arrive in seconds; display as milliseconds
        if (key === "avg_duration_in_range" && val !== null && val !== undefined) {
          var ms = Math.round(val * 1000);
          el.textContent = formatValue(ms);
          var suffixEl = el.parentElement.querySelector("[data-so-card-suffix]");
          if (suffixEl) suffixEl.textContent = "ms";
        } else {
          el.textContent = formatValue(val);
        }
      }
    });
  }

  function patchQueueTable(snapshot) {
    var tableEl = document.querySelector('[data-so-zone="queue-table"]');
    if (!tableEl) return;
    var queues = snapshot.queues || {};
    var performedByQueue = snapshot.performed_by_queue || {};
    var failedByQueue = snapshot.failed_by_queue || {};

    // Update live depth values
    Object.keys(queues).forEach(function (qName) {
      var el = tableEl.querySelector('[data-so-table-value="queue-depth-' + qName + '"]');
      if (el) el.textContent = formatValue(queues[qName]);
    });

    // Update performed/failed in range
    Object.keys(performedByQueue).forEach(function (qName) {
      var el = tableEl.querySelector('[data-so-table-value="queue-performed-' + qName + '"]');
      if (el) el.textContent = formatValue(performedByQueue[qName]);
    });
    Object.keys(failedByQueue).forEach(function (qName) {
      var el = tableEl.querySelector('[data-so-table-value="queue-failed-' + qName + '"]');
      if (el) el.textContent = formatValue(failedByQueue[qName]);
    });
  }

  function patchStability(snapshot) {
    // Stability is rendered server-side; tick does not update it.
    // Full fetch re-renders via page or could patch, but we keep it simple.
  }

  function updateRangeCopyFromLabel(label) {
    var els = document.querySelectorAll("[data-so-range-copy]");
    els.forEach(function (el) { el.textContent = label; });
  }

  function updateFreshness(text) {
    if (freshnessEl) freshnessEl.textContent = text;
  }

  function addLoadingClass(on) {
    var zones = document.querySelectorAll(
      '[data-so-zone="throughput"], [data-so-zone="chart"], [data-so-zone="queue-table"]'
    );
    zones.forEach(function (el) {
      var section = el.closest(".so-dashboard-section") || el;
      if (on) {
        section.classList.add("is-loading");
      } else {
        section.classList.remove("is-loading");
      }
    });
  }

  function start() {
    stop();
    timerId = window.setInterval(tick, INTERVAL_SEC * 1000);
  }

  function stop() {
    if (timerId !== null) {
      window.clearInterval(timerId);
      timerId = null;
    }
    inFlight = false;
  }

  function updateUrlRange(range) {
    var urlObj = new URL(window.location.href);
    urlObj.searchParams.set("range", range);
    window.history.replaceState({}, "", urlObj.toString());
  }

  function updateUrlLive(isLive) {
    var urlObj = new URL(window.location.href);
    if (isLive) {
      urlObj.searchParams.set("live", "on");
    } else {
      urlObj.searchParams.delete("live");
    }
    window.history.replaceState({}, "", urlObj.toString());
  }

  function collectSparks() {
    var sparks = {};
    var figures = document.querySelectorAll("[data-so-spark]");
    for (var i = 0; i < figures.length; i++) {
      var key = figures[i].getAttribute("data-so-spark");
      sparks[key] = new Sparkline(figures[i]);
    }
    return sparks;
  }

  function Sparkline(figureEl) {
    this.line = figureEl.querySelector(".so-spark__line");
  }

  Sparkline.prototype.render = function (series) {
    if (!this.line || !series.length) return;
    var tMin = series[0].t,
      tMax = series[series.length - 1].t;
    var vMax = 1;
    for (var i = 0; i < series.length; i++) {
      if (series[i].v > vMax) vMax = series[i].v;
    }
    var points = [];
    for (var i = 0; i < series.length; i++) {
      var x =
        tMin === tMax
          ? SVG_W / 2
          : ((series[i].t - tMin) / (tMax - tMin)) * (SVG_W - 2) + 1;
      var y = SVG_H - 1 - (series[i].v / vMax) * (SVG_H - 2);
      points.push(x.toFixed(1) + "," + y.toFixed(1));
    }
    this.line.setAttribute("points", points.join(" "));
  };

  function formatValue(v) {
    if (v === null || v === undefined) return "\u2014";
    if (Number.isInteger(v))
      return v.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return parseFloat(v).toFixed(1);
  }

  function readRangeFromUrl() {
    return new URL(window.location.href).searchParams.get("range");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();