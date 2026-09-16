// Chart.js configuration for dark-themed dashboards

const chartColors = {
  green: 'rgba(16, 185, 129, 1)',
  greenFade: 'rgba(16, 185, 129, 0.15)',
  blue: 'rgba(59, 130, 246, 1)',
  blueFade: 'rgba(59, 130, 246, 0.15)',
  purple: 'rgba(139, 92, 246, 1)',
  purpleFade: 'rgba(139, 92, 246, 0.15)',
  orange: 'rgba(245, 158, 11, 1)',
  orangeFade: 'rgba(245, 158, 11, 0.15)',
  pink: 'rgba(236, 72, 153, 1)',
  red: 'rgba(239, 68, 68, 1)',
  yellow: 'rgba(234, 179, 8, 1)',
  cyan: 'rgba(6, 182, 212, 1)',
  grid: 'rgba(255, 255, 255, 0.06)',
  text: 'rgba(148, 163, 184, 1)',
};

const chartPalette = [
  chartColors.green, chartColors.blue, chartColors.purple,
  chartColors.orange, chartColors.pink, chartColors.red,
  chartColors.yellow, chartColors.cyan
];

// Global Chart.js defaults
Chart.defaults.color = chartColors.text;
Chart.defaults.font.family = "'Inter', sans-serif";
Chart.defaults.plugins.legend.labels.usePointStyle = true;
Chart.defaults.plugins.legend.labels.padding = 16;

function createForecastChart(canvasId, history, predictions) {
  const ctx = document.getElementById(canvasId);
  if (!ctx) return null;

  const histDates = history.map(h => h.date);
  const histValues = history.map(h => h.total);
  const predDates = predictions.map(p => p.date);
  const predValues = predictions.map(p => {
    const vals = Object.values(p.predictions);
    return vals.reduce((a, b) => a + b, 0);
  });

  // Combine for continuous line
  const allDates = [...histDates, ...predDates];
  const actualData = [...histValues, ...Array(predDates.length).fill(null)];
  const forecastData = [...Array(histDates.length - 1).fill(null), histValues[histValues.length - 1], ...predValues];

  return new Chart(ctx, {
    type: 'line',
    data: {
      labels: allDates.map(d => {
        const date = new Date(d);
        return date.toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
      }),
      datasets: [
        {
          label: 'Actual Waste (kg)',
          data: actualData,
          borderColor: chartColors.green,
          backgroundColor: chartColors.greenFade,
          fill: true,
          tension: 0.4,
          pointRadius: 3,
          pointHoverRadius: 6,
          borderWidth: 2.5,
        },
        {
          label: 'AI Forecast (kg)',
          data: forecastData,
          borderColor: chartColors.purple,
          backgroundColor: chartColors.purpleFade,
          fill: true,
          tension: 0.4,
          borderDash: [6, 4],
          pointRadius: 3,
          pointHoverRadius: 6,
          borderWidth: 2.5,
        }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        tooltip: {
          backgroundColor: 'rgba(17, 24, 39, 0.95)',
          borderColor: 'rgba(255,255,255,0.1)',
          borderWidth: 1,
          padding: 12,
          titleFont: { weight: '600' },
        }
      },
      scales: {
        x: {
          grid: { color: chartColors.grid },
          ticks: { maxTicksLimit: 10 }
        },
        y: {
          grid: { color: chartColors.grid },
          title: { display: true, text: 'Quantity (kg)' },
          beginAtZero: true
        }
      }
    }
  });
}

function createWasteByTypeChart(canvasId, data) {
  const ctx = document.getElementById(canvasId);
  if (!ctx) return null;

  const labels = data.map(d => d.foodType.charAt(0).toUpperCase() + d.foodType.slice(1));
  const values = data.map(d => parseFloat(d.total));
  const bgColors = data.map((_, i) => chartPalette[i % chartPalette.length]);

  return new Chart(ctx, {
    type: 'doughnut',
    data: {
      labels,
      datasets: [{
        data: values,
        backgroundColor: bgColors,
        borderColor: 'rgba(10, 14, 26, 0.8)',
        borderWidth: 3,
        hoverOffset: 8,
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      cutout: '65%',
      plugins: {
        legend: { position: 'bottom' },
        tooltip: {
          backgroundColor: 'rgba(17, 24, 39, 0.95)',
          callbacks: {
            label: (ctx) => ` ${ctx.label}: ${ctx.parsed} kg`
          }
        }
      }
    }
  });
}

function createWeeklyTrendChart(canvasId, history) {
  const ctx = document.getElementById(canvasId);
  if (!ctx) return null;

  // Aggregate last 4 weeks
  const weeks = {};
  history.slice(-28).forEach(h => {
    const date = new Date(h.date);
    const weekNum = Math.floor((Date.now() - date.getTime()) / (7 * 86400000));
    const label = weekNum === 0 ? 'This Week' : weekNum === 1 ? 'Last Week' : `${weekNum} Weeks Ago`;
    if (!weeks[label]) weeks[label] = 0;
    weeks[label] += h.total;
  });

  const labels = Object.keys(weeks).reverse();
  const values = labels.map(l => Math.round(weeks[l] * 10) / 10);

  return new Chart(ctx, {
    type: 'bar',
    data: {
      labels,
      datasets: [{
        label: 'Total Waste (kg)',
        data: values,
        backgroundColor: labels.map((_, i) => chartPalette[i % chartPalette.length]),
        borderRadius: 8,
        borderSkipped: false,
        barPercentage: 0.6,
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: {
          backgroundColor: 'rgba(17, 24, 39, 0.95)',
        }
      },
      scales: {
        x: { grid: { display: false } },
        y: {
          grid: { color: chartColors.grid },
          beginAtZero: true,
          title: { display: true, text: 'kg' }
        }
      }
    }
  });
}
