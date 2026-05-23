(function () {
  "use strict";

  var MAX_POINTS = 60;
  var SVG_W = 120,
    SVG_H = 32;
  var INTERVAL_SEC = 5;

  function init() {
    var wrapper = document.querySelector("[data-so-live]");
    if (!wrapper) return;

    var checkbox = wrapper.querySelector("input[type=checkbox][name=live]");
    if (!checkbox) return;

    var sparks = collectSparks();
    var url = "/solid_observer/poll_data";
    var inFlight = false,
      timerId = null;

    function tick() {
      if (inFlight) return;
      inFlight = true;
      var rangeParam = readRangeFromUrl();
      fetch(
        url + (rangeParam ? "?range=" + encodeURIComponent(rangeParam) : ""),
        { headers: { Accept: "application/json" }, credentials: "same-origin" },
      )
        .then(function (r) {
          return r.ok ? r.json() : null;
        })
        .then(function (data) {
          if (data) applyUpdate(data);
        })
        .catch(function () {
          /* drop tick silently */
        })
        .finally(function () {
          inFlight = false;
        });
    }

    function applyUpdate(data) {
      var snapshot = data.snapshot || {};
      Object.keys(snapshot).forEach(function (key) {
        var el = document.querySelector('[data-so-card-value="' + key + '"]');
        if (el) el.textContent = formatValue(snapshot[key]);
      });
      var chart = data.chart || {};
      Object.keys(sparks).forEach(function (key) {
        var series = chart[key];
        if (Array.isArray(series)) sparks[key].render(series);
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

    function syncUrl() {
      var url = new URL(window.location.href);
      if (checkbox.checked) {
        url.searchParams.set("live", "on");
      } else {
        url.searchParams.delete("live");
      }
      window.history.replaceState({}, "", url.toString());
    }

    checkbox.addEventListener("change", function () {
      syncUrl();
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
    this.valueEl = figureEl.querySelector("[data-so-spark-value]");
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
    if (this.valueEl) {
      this.valueEl.textContent = formatValue(series[series.length - 1].v);
    }
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