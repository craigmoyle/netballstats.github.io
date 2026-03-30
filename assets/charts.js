(function attachNetballCharts(global) {
  const { formatNumber } = global.NetballStatsUI || {};

  function clearChart(container, message) {
    container.replaceChildren();
    container.dataset.state = "empty";
    const empty = document.createElement("p");
    empty.className = "chart-empty";
    empty.textContent = message;
    container.appendChild(empty);
  }

  function createSvgElement(tagName, attributes = {}, textContent = "") {
    const element = document.createElementNS("http://www.w3.org/2000/svg", tagName);
    Object.entries(attributes).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        element.setAttribute(key, `${value}`);
      }
    });
    if (textContent) {
      element.textContent = textContent;
    }
    return element;
  }

  function truncateLabel(value, maxLength = 18) {
    if (!value || value.length <= maxLength) {
      return value || "-";
    }
    return `${value.slice(0, maxLength - 1)}…`;
  }

  function renderHorizontalBarChart(container, rows, {
    ariaLabel,
    emptyMessage,
    labelAccessor,
    valueAccessor,
    colourAccessor
  }) {
    if (!rows.length) {
      clearChart(container, emptyMessage);
      return;
    }

    const chartRows = rows.map((row, index) => ({
      label: labelAccessor(row, index),
      value: Number(valueAccessor(row, index)) || 0,
      colour: colourAccessor(row, index)
    }));

    const maxValue = Math.max(...chartRows.map((row) => row.value), 1);
    const width = 760;
    const left = 196;
    const right = 84;
    const top = 26;
    const bottom = 20;
    const barHeight = 24;
    const gap = 16;
    const innerWidth = width - left - right;
    const height = top + bottom + (chartRows.length * (barHeight + gap)) - gap;
    const svg = createSvgElement("svg", {
      viewBox: `0 0 ${width} ${height}`,
      class: "chart-svg",
      preserveAspectRatio: "xMidYMid meet"
    });

    [0, 0.25, 0.5, 0.75, 1].forEach((ratio) => {
      const x = left + (innerWidth * ratio);
      svg.appendChild(createSvgElement("line", {
        x1: x,
        x2: x,
        y1: top - 8,
        y2: height - bottom + 4,
        class: "chart-grid-line"
      }));
      svg.appendChild(createSvgElement("text", {
        x,
        y: top - 12,
        "text-anchor": ratio === 0 ? "start" : ratio === 1 ? "end" : "middle",
        class: "chart-grid-label"
      }, formatNumber(maxValue * ratio)));
    });

    chartRows.forEach((row, index) => {
      const y = top + (index * (barHeight + gap));
      const barWidth = maxValue > 0 ? (innerWidth * row.value) / maxValue : 0;

      svg.appendChild(createSvgElement("text", {
        x: left - 12,
        y: y + (barHeight / 2) + 5,
        "text-anchor": "end",
        class: "chart-label"
      }, truncateLabel(row.label, 19)));

      svg.appendChild(createSvgElement("rect", {
        x: left,
        y,
        width: innerWidth,
        height: barHeight,
        rx: 12,
        class: "chart-track"
      }));

      const bar = createSvgElement("rect", {
        x: left,
        y,
        width: Math.max(barWidth, 2),
        height: barHeight,
        rx: 12,
        fill: row.colour,
        class: "chart-bar"
      });
      bar.appendChild(createSvgElement("title", {}, `${row.label}: ${formatNumber(row.value)}`));
      svg.appendChild(bar);

      svg.appendChild(createSvgElement("text", {
        x: width - 8,
        y: y + (barHeight / 2) + 5,
        "text-anchor": "end",
        class: "chart-value"
      }, formatNumber(row.value)));
    });

    container.replaceChildren(svg);
    container.removeAttribute("data-state");
    container.setAttribute("aria-label", ariaLabel);
  }

  function renderTrendChart(container, rows, {
    ariaLabel,
    emptyMessage,
    singleSeasonMessage,
    idAccessor,
    labelAccessor,
    valueAccessor,
    colourAccessor
  }) {
    if (!rows.length) {
      clearChart(container, emptyMessage);
      return;
    }

    const seasons = [...new Set(
      rows
        .map((row) => Number(row.season))
        .filter((value) => Number.isFinite(value))
    )].sort((left, right) => left - right);

    if (seasons.length < 2) {
      clearChart(container, singleSeasonMessage);
      return;
    }

    const grouped = new Map();
    rows.forEach((row) => {
      const id = `${idAccessor(row)}`;
      if (!grouped.has(id)) {
        grouped.set(id, {
          id,
          label: labelAccessor(row),
          colour: colourAccessor(row, grouped.size),
          points: new Map()
        });
      }
      grouped.get(id).points.set(Number(row.season), Number(valueAccessor(row)) || 0);
    });

    const series = [...grouped.values()];
    const maxValue = Math.max(
      ...series.flatMap((entry) => [...entry.points.values()]),
      1
    );

    const width = 760;
    const height = 360;
    const left = 56;
    const right = 20;
    const top = 20;
    const bottom = 54;
    const innerWidth = width - left - right;
    const innerHeight = height - top - bottom;
    const svg = createSvgElement("svg", {
      viewBox: `0 0 ${width} ${height}`,
      class: "chart-svg",
      preserveAspectRatio: "xMidYMid meet"
    });

    const xForSeason = (season) => {
      const index = seasons.indexOf(season);
      const span = Math.max(seasons.length - 1, 1);
      return left + (innerWidth * index) / span;
    };
    const yForValue = (value) => top + innerHeight - ((innerHeight * value) / maxValue);

    [0, 0.25, 0.5, 0.75, 1].forEach((ratio) => {
      const y = top + innerHeight - (innerHeight * ratio);
      svg.appendChild(createSvgElement("line", {
        x1: left,
        x2: width - right,
        y1: y,
        y2: y,
        class: "chart-grid-line"
      }));
      svg.appendChild(createSvgElement("text", {
        x: left - 8,
        y: y + 4,
        "text-anchor": "end",
        class: "chart-grid-label"
      }, formatNumber(maxValue * ratio)));
    });

    svg.appendChild(createSvgElement("line", {
      x1: left,
      x2: left,
      y1: top,
      y2: height - bottom,
      class: "chart-axis-line"
    }));

    seasons.forEach((season) => {
      const x = xForSeason(season);
      svg.appendChild(createSvgElement("line", {
        x1: x,
        x2: x,
        y1: height - bottom,
        y2: height - bottom + 6,
        class: "chart-axis-line"
      }));
      svg.appendChild(createSvgElement("text", {
        x,
        y: height - bottom + 22,
        "text-anchor": "middle",
        class: "chart-axis"
      }, `${season}`));
    });

    series.forEach((entry) => {
      const definedPoints = seasons
        .filter((season) => entry.points.has(season))
        .map((season) => ({
          season,
          value: entry.points.get(season),
          x: xForSeason(season),
          y: yForValue(entry.points.get(season))
        }));

      if (!definedPoints.length) {
        return;
      }

      const path = definedPoints
        .map((point, index) => `${index === 0 ? "M" : "L"} ${point.x} ${point.y}`)
        .join(" ");

      const line = createSvgElement("path", {
        d: path,
        stroke: entry.colour,
        class: "chart-series-line"
      });
      line.appendChild(createSvgElement("title", {}, `${entry.label}`));
      svg.appendChild(line);

      definedPoints.forEach((point) => {
        const dot = createSvgElement("circle", {
          cx: point.x,
          cy: point.y,
          r: 5,
          fill: entry.colour,
          class: "chart-dot"
        });
        dot.appendChild(createSvgElement("title", {}, `${entry.label} • ${point.season}: ${formatNumber(point.value)}`));
        svg.appendChild(dot);
      });
    });

    const legend = document.createElement("div");
    legend.className = "chart-legend";
    series.forEach((entry) => {
      const latestSeason = [...entry.points.keys()].sort((left, right) => right - left)[0];
      const latestValue = latestSeason ? entry.points.get(latestSeason) : null;

      const item = document.createElement("div");
      item.className = "chart-legend__item";

      const swatch = document.createElement("span");
      swatch.className = "chart-legend__swatch";
      swatch.style.background = entry.colour;

      const label = document.createElement("span");
      label.textContent = latestValue === null
        ? entry.label
        : `${truncateLabel(entry.label, 24)} · ${formatNumber(latestValue)}`;

      item.append(swatch, label);
      legend.appendChild(item);
    });

    container.replaceChildren(svg, legend);
    container.removeAttribute("data-state");
    container.setAttribute("aria-label", ariaLabel);
  }

  function renderSeasonColumnChart(container, rows, {
    ariaLabel,
    emptyMessage,
    labelAccessor,
    valueAccessor,
    colourAccessor
  }) {
    if (!rows.length) {
      clearChart(container, emptyMessage);
      return;
    }

    const chartRows = rows.map((row, index) => ({
      label: `${labelAccessor(row, index)}`,
      value: Number(valueAccessor(row, index)) || 0,
      colour: colourAccessor(row, index)
    }));

    const maxValue = Math.max(...chartRows.map((row) => row.value), 1);
    const width = 760;
    const height = 360;
    const left = 56;
    const right = 20;
    const top = 20;
    const bottom = 62;
    const innerWidth = width - left - right;
    const innerHeight = height - top - bottom;
    const slotWidth = innerWidth / chartRows.length;
    const barWidth = Math.min(62, Math.max(24, slotWidth * 0.62));
    const svg = createSvgElement("svg", {
      viewBox: `0 0 ${width} ${height}`,
      class: "chart-svg",
      preserveAspectRatio: "xMidYMid meet"
    });

    [0, 0.25, 0.5, 0.75, 1].forEach((ratio) => {
      const y = top + innerHeight - (innerHeight * ratio);
      svg.appendChild(createSvgElement("line", {
        x1: left,
        x2: width - right,
        y1: y,
        y2: y,
        class: "chart-grid-line"
      }));
      svg.appendChild(createSvgElement("text", {
        x: left - 8,
        y: y + 4,
        "text-anchor": "end",
        class: "chart-grid-label"
      }, formatNumber(maxValue * ratio)));
    });

    svg.appendChild(createSvgElement("line", {
      x1: left,
      x2: width - right,
      y1: height - bottom,
      y2: height - bottom,
      class: "chart-axis-line"
    }));

    chartRows.forEach((row, index) => {
      const xCenter = left + (slotWidth * index) + (slotWidth / 2);
      const barHeight = maxValue > 0 ? (innerHeight * row.value) / maxValue : 0;
      const y = top + innerHeight - barHeight;
      const bar = createSvgElement("rect", {
        x: xCenter - (barWidth / 2),
        y,
        width: barWidth,
        height: Math.max(barHeight, 2),
        rx: 14,
        fill: row.colour,
        class: "chart-bar"
      });
      bar.appendChild(createSvgElement("title", {}, `${row.label}: ${formatNumber(row.value)}`));
      svg.appendChild(bar);

      svg.appendChild(createSvgElement("text", {
        x: xCenter,
        y: Math.max(y - 10, top + 12),
        "text-anchor": "middle",
        class: "chart-value"
      }, formatNumber(row.value)));

      svg.appendChild(createSvgElement("text", {
        x: xCenter,
        y: height - bottom + 24,
        "text-anchor": "middle",
        class: "chart-axis"
      }, row.label));
    });

    container.replaceChildren(svg);
    container.removeAttribute("data-state");
    container.setAttribute("aria-label", ariaLabel);
  }

  global.NetballCharts = {
    clearChart,
    formatNumber,
    renderHorizontalBarChart,
    renderTrendChart,
    renderSeasonColumnChart
  };
}(window));
