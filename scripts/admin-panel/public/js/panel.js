(function () {
  "use strict";

  var doc = document;
  var root = doc.documentElement;
  var body = doc.body;
  var themeBtn = doc.getElementById("apThemeBtn");
  var sidebarToggle = doc.getElementById("apSidebarToggle");
  var overlay = doc.getElementById("apOverlay");
  var themeKey = "admin_panel_theme";
  var charts = [];

  function cssVar(name, fallback) {
    var value = getComputedStyle(root).getPropertyValue(name).trim();
    return value || fallback;
  }

  function clearCharts() {
    charts.forEach(function (ch) {
      if (ch && typeof ch.destroy === "function") {
        ch.destroy();
      }
    });
    charts = [];
  }

  function renderCharts() {
    if (typeof window.Chart === "undefined") {
      return;
    }

    clearCharts();

    var textColor = cssVar("--ap-text", "#0f172a");
    var mutedColor = cssVar("--ap-muted", "#64748b");
    var borderColor = cssVar("--ap-border", "#e2e8f0");
    var primary = cssVar("--ap-primary", "#465fff");
    var success = cssVar("--ap-success", "#059669");
    var warn = cssVar("--ap-warn", "#d97706");
    var danger = cssVar("--ap-danger", "#dc2626");

    var revenueEl = doc.getElementById("apRevenueChart");
    if (revenueEl) {
      charts.push(new window.Chart(revenueEl, {
        type: "line",
        data: {
          labels: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
          datasets: [
            {
              label: "Revenue",
              data: [8, 9, 10, 13, 14, 16, 19, 22, 21, 25, 27, 30],
              borderColor: primary,
              backgroundColor: "rgba(70, 95, 255, 0.12)",
              fill: true,
              tension: 0.36,
              pointRadius: 0,
              borderWidth: 2
            },
            {
              label: "Subscriptions",
              data: [3, 4, 4.5, 5, 5.5, 6.2, 6.8, 7.4, 8, 8.3, 9, 9.7],
              borderColor: success,
              fill: false,
              tension: 0.36,
              pointRadius: 0,
              borderWidth: 2
            }
          ]
        },
        options: {
          maintainAspectRatio: false,
          plugins: {
            legend: {
              position: "top",
              align: "end",
              labels: {
                usePointStyle: true,
                boxWidth: 8,
                color: mutedColor,
                font: { size: 11, weight: "600" }
              }
            }
          },
          scales: {
            x: {
              grid: { display: false },
              ticks: { color: mutedColor, font: { size: 11 } }
            },
            y: {
              border: { display: false },
              grid: { color: borderColor },
              ticks: { color: mutedColor, font: { size: 11 } }
            }
          }
        }
      }));
    }

    var channelEl = doc.getElementById("apChannelChart");
    if (channelEl) {
      charts.push(new window.Chart(channelEl, {
        type: "doughnut",
        data: {
          labels: ["Organic", "Direct", "Paid", "Referral"],
          datasets: [{
            data: [38, 24, 20, 18],
            backgroundColor: [primary, success, warn, danger],
            borderWidth: 0
          }]
        },
        options: {
          cutout: "70%",
          plugins: {
            legend: {
              position: "bottom",
              labels: {
                color: textColor,
                boxWidth: 10,
                padding: 14,
                font: { size: 11, weight: "600" }
              }
            }
          }
        }
      }));
    }

    var deviceEl = doc.getElementById("apDeviceChart");
    if (deviceEl) {
      charts.push(new window.Chart(deviceEl, {
        type: "doughnut",
        data: {
          labels: ["Desktop", "Mobile", "Tablet"],
          datasets: [{
            data: [52, 40, 8],
            backgroundColor: [primary, success, warn],
            borderWidth: 0
          }]
        },
        options: {
          cutout: "68%",
          plugins: {
            legend: {
              position: "bottom",
              labels: {
                color: textColor,
                boxWidth: 10,
                padding: 14,
                font: { size: 11, weight: "600" }
              }
            }
          }
        }
      }));
    }
  }

  function setTheme(mode) {
    var next = mode === "dark" ? "dark" : "light";
    root.setAttribute("data-bs-theme", next);
    try {
      localStorage.setItem(themeKey, next);
    } catch (e) {
      // ignore
    }
    if (themeBtn) {
      themeBtn.innerHTML = next === "dark"
        ? '<i class="bi bi-sun"></i>'
        : '<i class="bi bi-moon-stars"></i>';
    }
    renderCharts();
  }

  function initTheme() {
    var saved = "light";
    try {
      saved = localStorage.getItem(themeKey) || "light";
    } catch (e) {
      saved = "light";
    }
    setTheme(saved);
  }

  function openSidebar() {
    body.classList.add("ap-sidebar-open");
  }

  function closeSidebar() {
    body.classList.remove("ap-sidebar-open");
  }

  function initSidebar() {
    if (sidebarToggle) {
      sidebarToggle.addEventListener("click", function () {
        if (body.classList.contains("ap-sidebar-open")) {
          closeSidebar();
        } else {
          openSidebar();
        }
      });
    }

    if (overlay) {
      overlay.addEventListener("click", closeSidebar);
    }

    doc.addEventListener("keydown", function (ev) {
      if (ev.key === "Escape") {
        closeSidebar();
      }
    });
  }

  if (themeBtn) {
    themeBtn.addEventListener("click", function () {
      var now = root.getAttribute("data-bs-theme") || "light";
      setTheme(now === "dark" ? "light" : "dark");
    });
  }

  initTheme();
  initSidebar();
  renderCharts();
})();

