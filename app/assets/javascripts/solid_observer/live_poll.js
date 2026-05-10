(function () {
  "use strict";

  function init(root) {
    var wrapper = root.querySelector("[data-so-live]");
    if (!wrapper) return;

    var intervalSec = parseInt(wrapper.getAttribute("data-so-live-interval"), 10);
    var frameId = wrapper.getAttribute("data-so-live-frame");
    if (!intervalSec || !frameId || intervalSec <= 0) return;

    var checkbox = wrapper.querySelector("input[type=checkbox][name=live]");
    if (!checkbox) return;

    var timerId = null;
    var inFlight = false;

    function swapFrameContent(frame, html) {
      var doc = new DOMParser().parseFromString(html, "text/html");
      var freshFrame = doc.querySelector("turbo-frame#" + frameId);
      if (!freshFrame) return;

      frame.replaceChildren();
      while (freshFrame.firstChild) {
        frame.appendChild(freshFrame.firstChild);
      }
    }

    function poll() {
      if (inFlight) return;

      var frame = document.getElementById(frameId);
      if (!frame) return;

      var src = frame.getAttribute("src");
      if (!src) return;

      inFlight = true;
      fetch(src, {headers: {Accept: "text/html"}, credentials: "same-origin"})
        .then(function (response) {
          if (!response.ok) return null;
          return response.text();
        })
        .then(function (html) {
          if (!html) return;
          swapFrameContent(frame, html);
        })
        .catch(function () {
        })
        .finally(function () {
          inFlight = false;
        });
    }

    function start() {
      stop();
      timerId = window.setInterval(poll, intervalSec * 1000);
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
      if (checkbox.checked) {
        start();
      } else {
        stop();
      }
    });

    if (checkbox.checked) start();

    window.addEventListener("beforeunload", stop);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      init(document);
    });
  } else {
    init(document);
  }
})();
