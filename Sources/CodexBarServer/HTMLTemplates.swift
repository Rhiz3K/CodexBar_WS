// HTMLTemplates.swift
// Server-side HTML rendering for CodexBar Dashboard
// Cross-platform: macOS and Linux

import CodexBarCore
import Foundation

// MARK: - Static Files

enum StaticFiles {
    static func get(_ path: String) -> String? {
        switch path {
        case "style.css":
            return Self.css
        case "app.js":
            return Self.javascript
        default:
            return nil
        }
    }

    static func contentType(for path: String) -> String {
        if path.hasSuffix(".css") { return "text/css" }
        if path.hasSuffix(".js") { return "application/javascript" }
        if path.hasSuffix(".json") { return "application/json" }
        return "text/plain"
    }

    static let css = """
        :root {
            --bg-primary: #0d1117;
            --bg-secondary: #161b22;
            --bg-tertiary: #21262d;
            --bg-card: #1c2128;
            --text-primary: #e6edf3;
            --text-secondary: #8b949e;
            --text-muted: #6e7681;
            --border-color: #30363d;
            --accent-blue: #58a6ff;
            --accent-green: #3fb950;
            --accent-yellow: #d29922;
            --accent-orange: #db6d28;
            --accent-red: #f85149;
            --accent-purple: #a371f7;
        }

        * { box-sizing: border-box; margin: 0; padding: 0; }

        html, body {
            height: 100%;
            overflow-x: hidden;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.5;
            padding: 16px;
            display: flex;
            flex-direction: column;
        }

        .container {
            max-width: 100%;
            margin: 0 auto;
            flex: 1;
            display: flex;
            flex-direction: column;
            min-height: 0;
        }

        header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 16px;
            padding-bottom: 12px;
            border-bottom: 1px solid var(--border-color);
            flex-shrink: 0;
        }

        .header-left { display: flex; align-items: center; gap: 16px; }
        .header-left h1 { font-size: 20px; font-weight: 600; }
        .header-left .subtitle { color: var(--text-secondary); font-size: 14px; }

        .refresh-btn {
            background: var(--bg-tertiary);
            border: 1px solid var(--border-color);
            color: var(--text-primary);
            padding: 8px 16px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            display: flex;
            align-items: center;
            gap: 8px;
            transition: background 0.15s;
        }
        .refresh-btn:hover { background: var(--border-color); }
        .refresh-btn:disabled { opacity: 0.5; cursor: not-allowed; }

        .grid {
            display: grid;
            gap: 16px;
            flex: 1;
            min-height: 0;
            align-content: start;
        }

        /* Responsive grid: 1-3 cols, 1-2 rows to fit on page */
        .grid { grid-template-columns: repeat(3, 1fr); }
        .grid.providers-1 { grid-template-columns: 1fr; max-width: 800px; margin: 0 auto; }
        .grid.providers-2 { grid-template-columns: repeat(2, 1fr); }
        .grid.providers-3 { grid-template-columns: repeat(3, 1fr); }
        .grid.providers-4 { grid-template-columns: repeat(2, 1fr); }
        .grid.providers-5 { grid-template-columns: repeat(3, 1fr); }
        .grid.providers-6 { grid-template-columns: repeat(3, 1fr); }

        .card {
            background: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            overflow: hidden;
            display: flex;
            flex-direction: column;
            min-height: 280px;
        }

        .card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 16px;
            border-bottom: 1px solid var(--border-color);
            background: var(--bg-secondary);
            flex-shrink: 0;
        }

        .provider-info { display: flex; align-items: center; gap: 10px; }
        .provider-name { font-size: 16px; font-weight: 600; text-transform: capitalize; }
        .provider-version { font-size: 11px; color: var(--text-muted); font-family: monospace; }

        .plan-badge {
            padding: 3px 10px;
            border-radius: 12px;
            font-size: 11px;
            font-weight: 500;
            text-transform: uppercase;
        }
        .plan-badge.pro, .plan-badge.plus { background: rgba(88, 166, 255, 0.15); color: var(--accent-blue); }
        .plan-badge.paid, .plan-badge.premium { background: rgba(63, 185, 80, 0.15); color: var(--accent-green); }
        .plan-badge.free, .plan-badge.basic { background: var(--bg-tertiary); color: var(--text-secondary); }
        .plan-badge.max { background: rgba(163, 113, 247, 0.15); color: var(--accent-purple); }

        .card-body {
            padding: 12px 16px;
            flex: 1;
            display: flex;
            flex-direction: column;
            min-height: 0;
        }

        .usage-row {
            display: flex;
            gap: 16px;
            margin-bottom: 12px;
        }

        .usage-item {
            flex: 1;
        }

        .usage-item-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 6px;
        }

        .usage-label { font-size: 12px; color: var(--text-secondary); font-weight: 500; }
        .usage-percent { font-size: 18px; font-weight: 600; font-family: monospace; }
        .usage-percent.low { color: var(--accent-green); }
        .usage-percent.medium { color: var(--accent-yellow); }
        .usage-percent.high { color: var(--accent-orange); }
        .usage-percent.critical { color: var(--accent-red); }

        .usage-bar {
            height: 8px;
            background: var(--bg-tertiary);
            border-radius: 4px;
            overflow: hidden;
            margin-bottom: 6px;
        }

        .usage-fill {
            height: 100%;
            border-radius: 3px;
            transition: width 0.3s ease;
        }
        .usage-fill.low { background: var(--accent-green); }
        .usage-fill.medium { background: var(--accent-yellow); }
        .usage-fill.high { background: var(--accent-orange); }
        .usage-fill.critical { background: var(--accent-red); }

        .usage-meta {
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 10px;
        }

        .reset-time {
            color: var(--text-muted);
            display: flex;
            align-items: center;
            gap: 3px;
        }

        .prediction-inline { font-weight: 500; }
        .prediction-inline.healthy { color: var(--accent-green); }
        .prediction-inline.warning { color: var(--accent-yellow); }
        .prediction-inline.critical { color: var(--accent-red); }
        .prediction-inline.decreasing { color: var(--text-muted); }
        .prediction-inline.atLimit { color: var(--accent-red); }

        .stats-row {
            display: flex;
            gap: 10px;
            padding: 10px 0;
            border-top: 1px solid var(--border-color);
            margin-top: 10px;
        }

        .stat-item {
            flex: 1;
            text-align: center;
            padding: 6px 4px;
            background: var(--bg-tertiary);
            border-radius: 6px;
        }

        .stat-value { font-size: 14px; font-weight: 600; color: var(--text-primary); }
        .stat-label { font-size: 10px; color: var(--text-muted); text-transform: uppercase; }

        .models-row {
            display: flex;
            flex-wrap: wrap;
            gap: 6px;
            margin-top: 8px;
        }

        .model-tag {
            font-size: 10px;
            padding: 3px 8px;
            background: var(--bg-secondary);
            border: 1px solid var(--border-color);
            border-radius: 4px;
            color: var(--text-secondary);
        }

        .credits-row {
            display: flex;
            gap: 8px;
            padding-top: 8px;
            border-top: 1px solid var(--border-color);
        }

        .chart-section {
            padding: 10px 0 0 0;
            border-top: 1px solid var(--border-color);
            margin-top: 10px;
            flex: 1;
            display: flex;
            flex-direction: column;
            min-height: 120px;
        }
        .chart-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 8px;
            flex-shrink: 0;
        }
        .chart-container {
            flex: 1;
            position: relative;
            min-height: 100px;
        }
        .chart-label { font-size: 11px; color: var(--text-muted); }
        .chart-period-btns {
            display: flex;
            gap: 4px;
        }
        .chart-period-btn {
            background: none;
            border: 1px solid var(--border-color);
            color: var(--text-muted);
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 10px;
            cursor: pointer;
            transition: all 0.15s;
        }
        .chart-period-btn:hover { border-color: var(--text-secondary); color: var(--text-secondary); }
        .chart-period-btn.active { background: var(--accent-blue); border-color: var(--accent-blue); color: #fff; }

        .card-footer {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px 16px;
            background: var(--bg-secondary);
            border-top: 1px solid var(--border-color);
            font-size: 11px;
            color: var(--text-muted);
            flex-shrink: 0;
        }
        .source-label { font-family: monospace; font-size: 10px; }

        .no-data {
            grid-column: 1 / -1;
            text-align: center;
            padding: 60px 20px;
            color: var(--text-secondary);
        }
        .no-data h2 { font-size: 18px; margin-bottom: 8px; color: var(--text-primary); }
        .no-data p { font-size: 14px; }

        .footer {
            margin-top: 16px;
            padding-top: 12px;
            border-top: 1px solid var(--border-color);
            display: flex;
            justify-content: space-between;
            align-items: center;
            color: var(--text-muted);
            font-size: 12px;
            flex-shrink: 0;
        }
        .footer-center { flex: 1; text-align: center; }
        .footer-controls { display: flex; align-items: center; gap: 12px; }

        .footer-control {
            background: none;
            border: 1px solid var(--border-color);
            color: var(--text-muted);
            padding: 6px 10px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 12px;
            display: flex;
            align-items: center;
            gap: 6px;
            transition: all 0.15s;
        }
        .footer-control:hover { border-color: var(--text-secondary); color: var(--text-secondary); }
        .footer-control.active { color: var(--accent-blue); border-color: var(--accent-blue); }

        .header-controls { display: flex; align-items: center; gap: 8px; }

        .refresh-select {
            background: var(--bg-tertiary);
            border: 1px solid var(--border-color);
            color: var(--text-primary);
            padding: 8px 12px;
            border-radius: 6px;
            font-size: 14px;
            cursor: pointer;
            transition: background 0.15s;
        }
        .refresh-select:hover { background: var(--border-color); }
        .refresh-select:focus { outline: none; border-color: var(--accent-blue); }

        body.emails-hidden .account-email { 
            filter: blur(5px);
            user-select: none;
        }
        body.emails-hidden .account-email:hover { filter: blur(3px); }

        .reset-time {
            position: relative;
            cursor: help;
        }
        .reset-time[data-tooltip]:hover::after {
            content: attr(data-tooltip);
            position: absolute;
            bottom: 100%;
            left: 50%;
            transform: translateX(-50%);
            background: var(--bg-tertiary);
            border: 1px solid var(--border-color);
            color: var(--text-primary);
            padding: 6px 10px;
            border-radius: 6px;
            font-size: 12px;
            white-space: nowrap;
            z-index: 100;
            margin-bottom: 4px;
        }

        /* Responsive breakpoints */
        @media (max-width: 1400px) {
            .grid.providers-5, .grid.providers-6 { grid-template-columns: repeat(3, 1fr); }
        }

        @media (max-width: 1200px) {
            .grid.providers-3, .grid.providers-4, .grid.providers-5, .grid.providers-6 {
                grid-template-columns: repeat(2, 1fr);
            }
        }

        @media (max-width: 900px) {
            .grid, .grid.providers-1, .grid.providers-2, .grid.providers-3,
            .grid.providers-4, .grid.providers-5, .grid.providers-6 {
                grid-template-columns: 1fr;
            }
            .card { min-height: 320px; }
        }

        @media (max-width: 600px) {
            body { padding: 12px; }
            header { flex-direction: column; gap: 12px; align-items: flex-start; }
            .header-controls { width: 100%; justify-content: space-between; }
            .card-header, .card-body, .card-footer { padding: 10px 12px; }
            .provider-name { font-size: 14px; }
        }

        /* Tall screens: allow more space for charts */
        @media (min-height: 900px) {
            .card { min-height: 340px; }
            .chart-section { min-height: 150px; }
        }

        @media (min-height: 1100px) {
            .card { min-height: 400px; }
            .chart-section { min-height: 180px; }
        }
        """

    static let javascript = """
        const chartInstances = {};
        let use24HourFormat = localStorage.getItem('timeFormat') === '24h';

        // Time formatting functions
        function formatRelativeTime(date) {
            if (!date) return '';
            const now = new Date();
            const diff = date.getTime() - now.getTime();
            if (diff <= 0) return 'now';
            
            const minutes = Math.floor(diff / 60000);
            const hours = Math.floor(minutes / 60);
            const days = Math.floor(hours / 24);
            
            if (days > 0) {
                const remHours = hours % 24;
                return remHours > 0 ? `in ${days}d ${remHours}h` : `in ${days}d`;
            }
            if (hours > 0) {
                const remMins = minutes % 60;
                return remMins > 0 ? `in ${hours}h ${remMins}m` : `in ${hours}h`;
            }
            return `in ${minutes}m`;
        }

        function formatAbsoluteTime(date) {
            if (!date) return '';
            const options = {
                month: 'short',
                day: 'numeric',
                hour: '2-digit',
                minute: '2-digit',
                hour12: !use24HourFormat
            };
            return date.toLocaleString(undefined, options);
        }

        function updateAllResetTimes() {
            document.querySelectorAll('.reset-time[data-reset-at]').forEach(el => {
                const resetAt = new Date(el.dataset.resetAt);
                if (isNaN(resetAt.getTime())) return;
                
                const relativeText = formatRelativeTime(resetAt);
                const absoluteText = formatAbsoluteTime(resetAt);
                
                el.innerHTML = `<svg width="12" height="12" viewBox="0 0 16 16" fill="currentColor"><path d="M8 3.5a.5.5 0 0 0-1 0V9a.5.5 0 0 0 .252.434l3.5 2a.5.5 0 0 0 .496-.868L8 8.71V3.5z"/><path d="M8 16A8 8 0 1 0 8 0a8 8 0 0 0 0 16zm7-8A7 7 0 1 1 1 8a7 7 0 0 1 14 0z"/></svg> ${relativeText}`;
                el.setAttribute('data-tooltip', absoluteText);
            });
            
            // Update last update time
            const lastUpdate = document.getElementById('last-update');
            if (lastUpdate && lastUpdate.dataset.timestamp) {
                const date = new Date(lastUpdate.dataset.timestamp);
                lastUpdate.textContent = formatAbsoluteTime(date);
            }
        }

        async function refreshData() {
            try {
                const response = await fetch('/api/status');
                const data = await response.json();
                updateDashboard(data.providers);
            } catch (error) {
                console.error('Failed to refresh data:', error);
            }
        }

        function updateDashboard(providers) {
            providers.forEach(provider => {
                const card = document.querySelector(`[data-provider="${provider.provider}"]`);
                if (!card) return;

                // Update primary usage
                const primaryPct = provider.primaryUsage || 0;
                updateUsageSection(card, 'primary', primaryPct, provider.primaryResetAt);

                // Update secondary usage
                if (provider.secondaryUsage !== undefined && provider.secondaryUsage !== null) {
                    updateUsageSection(card, 'secondary', provider.secondaryUsage, provider.secondaryResetAt);
                }

                // Update prediction
                if (provider.prediction) {
                    const ttl = card.querySelector('.prediction-ttl');
                    if (ttl) {
                        ttl.textContent = provider.prediction.timeToLimit || 'N/A';
                        ttl.className = 'prediction-ttl ' + provider.prediction.status;
                    }

                    const rate = card.querySelector('.prediction-rate .value');
                    if (rate) {
                        const rateVal = provider.prediction.ratePerHour;
                        rate.textContent = rateVal > 0 ? `+${rateVal.toFixed(1)}%/hr` : `${rateVal.toFixed(1)}%/hr`;
                    }
                }
            });
            
            updateAllResetTimes();
        }

        function updateUsageSection(card, type, percent, resetAt) {
            const section = card.querySelector(`.usage-section.${type}`);
            if (!section) return;

            const pctEl = section.querySelector('.usage-percent');
            if (pctEl) {
                pctEl.textContent = `${percent.toFixed(0)}%`;
                pctEl.className = 'usage-percent ' + getUsageClass(percent);
            }

            const fill = section.querySelector('.usage-fill');
            if (fill) {
                fill.style.width = `${Math.min(100, percent)}%`;
                fill.className = 'usage-fill ' + getUsageClass(percent);
            }

            const reset = section.querySelector('.reset-time');
            if (reset && resetAt) {
                reset.dataset.resetAt = resetAt;
            }
        }

        function getUsageClass(usage) {
            if (usage < 50) return 'low';
            if (usage < 75) return 'medium';
            if (usage < 90) return 'high';
            return 'critical';
        }

        // Get color based on usage percentage
        function getUsageColor(percent) {
            if (percent >= 90) return '#f85149';      // red
            if (percent >= 75) return '#db6d28';      // orange
            if (percent >= 50) return '#d29922';      // yellow
            if (percent >= 25) return '#3fb950';      // green
            return '#58a6ff';                          // blue
        }

        async function loadChart(provider, canvasId, hours = 24) {
            try {
                const limit = hours <= 24 ? 200 : hours <= 168 ? 500 : hours <= 720 ? 1000 : 2000;
                const response = await fetch(`/api/history/${provider}?hours=${hours}&limit=${limit}`);
                const data = await response.json();

                const ctx = document.getElementById(canvasId);
                if (!ctx || !data.data || data.data.length < 2) {
                    const container = ctx?.closest('.chart-section');
                    if (container) container.style.display = 'none';
                    return;
                }

                // Destroy existing chart if any
                if (chartInstances[canvasId]) {
                    chartInstances[canvasId].destroy();
                }

                // Prepare session (primary) data - dashed gray
                const sessionData = data.data
                    .map(d => ({ x: new Date(d.timestamp), y: d.primaryUsage }))
                    .filter(d => d.y !== null)
                    .reverse();

                // Prepare weekly (secondary) data - colored by percentage
                const weeklyData = data.data
                    .map(d => ({ x: new Date(d.timestamp), y: d.secondaryUsage }))
                    .filter(d => d.y !== null)
                    .reverse();

                // Get latest weekly value for color
                const latestWeekly = weeklyData.length > 0 ? weeklyData[weeklyData.length - 1].y : 0;
                const weeklyColor = getUsageColor(latestWeekly);

                // Determine time unit based on period
                let timeUnit = 'hour';
                let displayFormat = 'HH:mm';
                if (hours > 24 && hours <= 168) {
                    timeUnit = 'day';
                    displayFormat = 'EEE';
                } else if (hours > 168 && hours <= 720) {
                    timeUnit = 'day';
                    displayFormat = 'MMM d';
                } else if (hours > 720) {
                    timeUnit = 'month';
                    displayFormat = 'MMM';
                }

                const datasets = [];

                // Weekly dataset (solid colored line) - show first so it's behind
                if (weeklyData.length >= 2) {
                    datasets.push({
                        label: 'Weekly',
                        data: weeklyData,
                        borderColor: weeklyColor,
                        backgroundColor: weeklyColor + '20',
                        fill: true,
                        tension: 0.3,
                        borderWidth: 2,
                        pointRadius: 0,
                        pointHoverRadius: 4,
                        order: 2
                    });
                }

                // Session dataset (dashed gray line) - show on top
                if (sessionData.length >= 2) {
                    datasets.push({
                        label: 'Session',
                        data: sessionData,
                        borderColor: '#6e7681',
                        backgroundColor: 'transparent',
                        fill: false,
                        tension: 0.3,
                        borderWidth: 2,
                        borderDash: [5, 5],
                        pointRadius: 0,
                        pointHoverRadius: 4,
                        order: 1
                    });
                }

                if (datasets.length === 0) {
                    const container = ctx?.closest('.chart-section');
                    if (container) container.style.display = 'none';
                    return;
                }

                chartInstances[canvasId] = new Chart(ctx, {
                    type: 'line',
                    data: { datasets },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        interaction: { intersect: false, mode: 'index' },
                        plugins: {
                            legend: { 
                                display: true,
                                position: 'top',
                                align: 'end',
                                labels: {
                                    boxWidth: 12,
                                    boxHeight: 2,
                                    padding: 8,
                                    font: { size: 9 },
                                    color: '#6e7681'
                                }
                            },
                            tooltip: {
                                backgroundColor: '#21262d',
                                titleColor: '#e6edf3',
                                bodyColor: '#8b949e',
                                borderColor: '#30363d',
                                borderWidth: 1,
                                callbacks: {
                                    label: ctx => `${ctx.dataset.label}: ${ctx.parsed.y.toFixed(1)}%`
                                }
                            }
                        },
                        scales: {
                            x: {
                                type: 'time',
                                time: { 
                                    unit: timeUnit, 
                                    displayFormats: { 
                                        hour: 'HH:mm',
                                        day: displayFormat,
                                        month: 'MMM'
                                    } 
                                },
                                ticks: { color: '#6e7681', maxTicksLimit: 6 },
                                grid: { display: false }
                            },
                            y: {
                                min: 0,
                                max: 100,
                                ticks: { color: '#6e7681', stepSize: 25 },
                                grid: { color: '#21262d' }
                            }
                        }
                    }
                });
            } catch (error) {
                console.error(`Failed to load chart for ${provider}:`, error);
            }
        }

        // Chart period button handlers
        function initChartPeriodButtons() {
            document.querySelectorAll('.chart-period-btns').forEach(btnGroup => {
                const chartId = btnGroup.dataset.chart;
                const provider = chartId.replace('chart-', '');
                
                btnGroup.querySelectorAll('.chart-period-btn').forEach(btn => {
                    btn.addEventListener('click', () => {
                        // Update active state
                        btnGroup.querySelectorAll('.chart-period-btn').forEach(b => b.classList.remove('active'));
                        btn.classList.add('active');
                        
                        // Reload chart with new period
                        const hours = parseInt(btn.dataset.hours);
                        loadChart(provider, chartId, hours);
                    });
                });
            });
        }

        document.querySelector('.refresh-btn')?.addEventListener('click', async () => {
            const btn = document.querySelector('.refresh-btn');
            const originalText = btn.innerHTML;
            btn.innerHTML = '<svg class="spin" width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M8 3a5 5 0 1 0 4.546 2.914.5.5 0 0 1 .908-.417A6 6 0 1 1 8 2v1z"/><path d="M8 4.466V.534a.25.25 0 0 1 .41-.192l2.36 1.966c.12.1.12.284 0 .384L8.41 4.658A.25.25 0 0 1 8 4.466z"/></svg> Fetching...';
            btn.disabled = true;

            try {
                await fetch('/api/fetch', { method: 'POST' });
                await new Promise(r => setTimeout(r, 3000));
                await refreshData();
                // Reload charts
                document.querySelectorAll('[data-provider]').forEach(card => {
                    const provider = card.dataset.provider;
                    loadChart(provider, `chart-${provider}`);
                });
            } finally {
                btn.innerHTML = originalText;
                btn.disabled = false;
            }
        });

        // Auto-refresh handling
        let autoRefreshInterval = null;

        function initAutoRefresh() {
            const select = document.getElementById('autorefresh-select');
            if (!select) return;

            // Restore saved value
            const saved = localStorage.getItem('autoRefreshInterval') || '0';
            select.value = saved;
            setAutoRefreshInterval(parseInt(saved));

            select.addEventListener('change', (e) => {
                const interval = parseInt(e.target.value);
                localStorage.setItem('autoRefreshInterval', interval);
                setAutoRefreshInterval(interval);
            });
        }

        function setAutoRefreshInterval(ms) {
            if (autoRefreshInterval) {
                clearInterval(autoRefreshInterval);
                autoRefreshInterval = null;
            }
            if (ms > 0) {
                autoRefreshInterval = setInterval(async () => {
                    await refreshData();
                    updateLastUpdateTime();
                }, ms);
            }
        }

        function updateLastUpdateTime() {
            const el = document.getElementById('last-update');
            if (el) {
                const now = new Date();
                el.dataset.timestamp = now.toISOString();
                el.textContent = formatAbsoluteTime(now);
            }
        }

        // Time format toggle (12H/24H)
        function initTimeFormatToggle() {
            const toggle = document.getElementById('timeformat-toggle');
            if (!toggle) return;

            updateTimeFormatButton();

            toggle.addEventListener('click', () => {
                use24HourFormat = !use24HourFormat;
                localStorage.setItem('timeFormat', use24HourFormat ? '24h' : '12h');
                updateTimeFormatButton();
                updateAllResetTimes();
            });
        }

        function updateTimeFormatButton() {
            const toggle = document.getElementById('timeformat-toggle');
            if (!toggle) return;
            toggle.textContent = use24HourFormat ? '24H' : '12H';
            toggle.classList.toggle('active', use24HourFormat);
        }

        document.addEventListener('DOMContentLoaded', () => {
            document.querySelectorAll('[data-provider]').forEach(card => {
                const provider = card.dataset.provider;
                loadChart(provider, `chart-${provider}`, 24);
            });
            initChartPeriodButtons();
            initAutoRefresh();
            initTimeFormatToggle();
            updateAllResetTimes();
            
            // Update relative times every minute
            setInterval(updateAllResetTimes, 60000);
        });

        // Add spin animation
        const style = document.createElement('style');
        style.textContent = '@keyframes spin { to { transform: rotate(360deg); } } .spin { animation: spin 1s linear infinite; }';
        document.head.appendChild(style);

        // Privacy toggle for emails
        const eyeIcon = `<svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M16 8s-3-5.5-8-5.5S0 8 0 8s3 5.5 8 5.5S16 8 16 8zM1.173 8a13.133 13.133 0 0 1 1.66-2.043C4.12 4.668 5.88 3.5 8 3.5c2.12 0 3.879 1.168 5.168 2.457A13.133 13.133 0 0 1 14.828 8c-.058.087-.122.183-.195.288-.335.48-.83 1.12-1.465 1.755C11.879 11.332 10.119 12.5 8 12.5c-2.12 0-3.879-1.168-5.168-2.457A13.134 13.134 0 0 1 1.172 8z"/><path d="M8 5.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM4.5 8a3.5 3.5 0 1 1 7 0 3.5 3.5 0 0 1-7 0z"/></svg>`;
        const eyeSlashIcon = `<svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M13.359 11.238C15.06 9.72 16 8 16 8s-3-5.5-8-5.5a7.028 7.028 0 0 0-2.79.588l.77.771A5.944 5.944 0 0 1 8 3.5c2.12 0 3.879 1.168 5.168 2.457A13.134 13.134 0 0 1 14.828 8c-.058.087-.122.183-.195.288-.335.48-.83 1.12-1.465 1.755-.165.165-.337.328-.517.486l.708.709z"/><path d="M11.297 9.176a3.5 3.5 0 0 0-4.474-4.474l.823.823a2.5 2.5 0 0 1 2.829 2.829l.822.822zm-2.943 1.299.822.822a3.5 3.5 0 0 1-4.474-4.474l.823.823a2.5 2.5 0 0 0 2.829 2.829z"/><path d="M3.35 5.47c-.18.16-.353.322-.518.487A13.134 13.134 0 0 0 1.172 8l.195.288c.335.48.83 1.12 1.465 1.755C4.121 11.332 5.881 12.5 8 12.5c.716 0 1.39-.133 2.02-.36l.77.772A7.029 7.029 0 0 1 8 13.5C3 13.5 0 8 0 8s.939-1.721 2.641-3.238l.708.709zm10.296 8.884-12-12 .708-.708 12 12-.708.708z"/></svg>`;

        function initPrivacyToggle() {
            const toggle = document.getElementById('privacy-toggle');
            if (!toggle) return;

            const isHidden = localStorage.getItem('hideEmails') === 'true';
            updatePrivacyState(isHidden);

            toggle.addEventListener('click', () => {
                const newState = !document.body.classList.contains('emails-hidden');
                localStorage.setItem('hideEmails', newState);
                updatePrivacyState(newState);
            });
        }

        function updatePrivacyState(hidden) {
            const toggle = document.getElementById('privacy-toggle');
            if (hidden) {
                document.body.classList.add('emails-hidden');
                toggle.innerHTML = eyeSlashIcon + ' Hidden';
                toggle.classList.add('active');
            } else {
                document.body.classList.remove('emails-hidden');
                toggle.innerHTML = eyeIcon + ' Visible';
                toggle.classList.remove('active');
            }
        }

        document.addEventListener('DOMContentLoaded', initPrivacyToggle);
        """
}

// MARK: - Dashboard Page

enum DashboardPage {
    static func render(state: AppState, costData: [String: ProviderCostData]) throws -> String {
        let latest = try state.store.fetchLatestForAllProviders()
        let predictions = try state.predictionEngine.predictAllBoth(from: state.store)

        var providerCards = ""

        // Only show providers that have data
        for (providerName, record) in latest.sorted(by: { $0.key < $1.key }) {
            let providerPredictions = predictions[providerName]
            let providerCost = costData[providerName]
            providerCards += Self.renderProviderCard(
                providerName: providerName,
                record: record,
                predictions: providerPredictions,
                cost: providerCost
            )
        }

        if providerCards.isEmpty {
            providerCards = """
                <div class="no-data">
                    <h2>No usage data yet</h2>
                    <p>The scheduler is collecting data from CodexBarCLI. Check back in a minute.</p>
                </div>
                """
        }

        let recordCount = (try? state.store.recordCount()) ?? 0
        let providerCount = latest.count

        return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>CodexBar Dashboard</title>
                <link rel="stylesheet" href="/static/style.css">
                <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js" integrity="sha384-9nhczxUqK87bcKHh20fSQcTGD4qq5GhayNYSYWqwBkINBhOfQLg/P5HG5lF1urn4" crossorigin="anonymous"></script>
                <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns@3.0.0/dist/chartjs-adapter-date-fns.bundle.min.js" integrity="sha384-cVMg8E3QFwTvGCDuK+ET4PD341jF3W8nO1auiXfuZNQkzbUUiBGLsIQUE+b1mxws" crossorigin="anonymous"></script>
            </head>
            <body>
                <div class="container">
                    <header>
                        <div class="header-left">
                            <h1>CodexBar</h1>
                            <span class="subtitle">\(providerCount) provider\(providerCount == 1 ? "" : "s") · \(recordCount) records</span>
                        </div>
                        <div class="header-controls">
                            <select id="autorefresh-select" class="refresh-select" title="Auto-refresh interval">
                                <option value="0">Auto: Off</option>
                                <option value="60000">1 min</option>
                                <option value="300000">5 min</option>
                                <option value="900000">15 min</option>
                                <option value="1800000">30 min</option>
                                <option value="3600000">60 min</option>
                            </select>
                            <button class="refresh-btn">
                                <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M8 3a5 5 0 1 0 4.546 2.914.5.5 0 0 1 .908-.417A6 6 0 1 1 8 2v1z"/><path d="M8 4.466V.534a.25.25 0 0 1 .41-.192l2.36 1.966c.12.1.12.284 0 .384L8.41 4.658A.25.25 0 0 1 8 4.466z"/></svg>
                                Refresh
                            </button>
                        </div>
                    </header>

                    <div class="grid providers-\(min(providerCount, 6))">
                        \(providerCards)
                    </div>

                    <footer class="footer">
                        <div></div>
                        <div class="footer-center">CodexBar Server v\(CodexBarServer.version) · Last update: <span id="last-update" data-timestamp="\(ISO8601DateFormatter().string(from: Date()))">\(Self.formatDate(Date()))</span></div>
                        <div class="footer-controls">
                            <button id="timeformat-toggle" class="footer-control" title="Toggle 12H/24H time format">12H</button>
                            <button id="privacy-toggle" class="footer-control" title="Toggle email visibility">
                                <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M16 8s-3-5.5-8-5.5S0 8 0 8s3 5.5 8 5.5S16 8 16 8zM1.173 8a13.133 13.133 0 0 1 1.66-2.043C4.12 4.668 5.88 3.5 8 3.5c2.12 0 3.879 1.168 5.168 2.457A13.133 13.133 0 0 1 14.828 8c-.058.087-.122.183-.195.288-.335.48-.83 1.12-1.465 1.755C11.879 11.332 10.119 12.5 8 12.5c-2.12 0-3.879-1.168-5.168-2.457A13.134 13.134 0 0 1 1.172 8z"/><path d="M8 5.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM4.5 8a3.5 3.5 0 1 1 7 0 3.5 3.5 0 0 1-7 0z"/></svg>
                                Visible
                            </button>
                        </div>
                    </footer>
                </div>
                <script src="/static/app.js"></script>
            </body>
            </html>
            """
    }

    private static func renderProviderCard(
        providerName: String,
        record: UsageHistoryRecord,
        predictions: ProviderPredictions?,
        cost: ProviderCostData?
    ) -> String {
        let primaryUsage = record.primaryUsedPercent ?? 0
        let secondaryUsage = record.secondaryUsedPercent
        let primaryClass = Self.usageClass(primaryUsage)

        let version = record.version ?? ""
        let versionHTML = version.isEmpty ? "" : "<span class=\"provider-version\">\(version)</span>"

        let plan = record.accountPlan ?? ""
        let planClass = Self.planClass(plan)
        let planHTML = plan.isEmpty ? "" : "<span class=\"plan-badge \(planClass)\">\(plan)</span>"

        let primaryResetAt = record.primaryResetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
        let secondaryResetAt = record.secondaryResetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""

        let primaryPredHTML = Self.renderPredictionInline(predictions?.primary, resetAt: record.primaryResetsAt)

        // Build secondary usage item (if exists)
        let secondaryItemHTML: String
        if let sec = secondaryUsage {
            let secClass = Self.usageClass(sec)
            let secPredHTML = Self.renderPredictionInline(predictions?.secondary, resetAt: record.secondaryResetsAt)
            secondaryItemHTML = """
                <div class="usage-item">
                    <div class="usage-item-header">
                        <span class="usage-label">Weekly</span>
                        <span class="usage-percent \(secClass)">\(Int(sec))%</span>
                    </div>
                    <div class="usage-bar"><div class="usage-fill \(secClass)" style="width: \(min(100, sec))%"></div></div>
                    <div class="usage-meta">
                        <span class="reset-time" data-reset-at="\(secondaryResetAt)"></span>
                        \(secPredHTML)
                    </div>
                </div>
                """
        } else {
            secondaryItemHTML = ""
        }

        let email = record.accountEmail ?? ""
        let source = record.sourceLabel ?? "unknown"

        // Build cost stats section - always show, use dashes if no data
        let todayTokens: String
        let todayCost: String
        let monthTokens: String
        let monthCost: String
        let modelsHTML: String

        if let cost = cost {
            todayTokens = Self.formatTokenCount(cost.sessionTokens)
            todayCost = Self.formatUSD(cost.sessionCostUSD)
            monthTokens = Self.formatTokenCount(cost.last30DaysTokens)
            monthCost = Self.formatUSD(cost.last30DaysCostUSD)

            if !cost.modelsUsed.isEmpty {
                let modelTags = cost.modelsUsed.map { "<span class=\"model-tag\">\($0)</span>" }.joined()
                modelsHTML = "<div class=\"models-row\">\(modelTags)</div>"
            } else {
                modelsHTML = "<div class=\"models-row\"><span class=\"model-tag\">—</span></div>"
            }
        } else {
            todayTokens = "—"
            todayCost = "—"
            monthTokens = "—"
            monthCost = "—"
            modelsHTML = "<div class=\"models-row\"><span class=\"model-tag\">—</span></div>"
        }

        let costHTML = """
            <div class="stats-row">
                <div class="stat-item">
                    <div class="stat-value">\(todayTokens)</div>
                    <div class="stat-label">Today</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value">\(todayCost)</div>
                    <div class="stat-label">Cost</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value">\(monthTokens)</div>
                    <div class="stat-label">30d</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value">\(monthCost)</div>
                    <div class="stat-label">Cost</div>
                </div>
            </div>
            \(modelsHTML)
            """

        return """
            <div class="card" data-provider="\(providerName)">
                <div class="card-header">
                    <div class="provider-info">
                        <span class="provider-name">\(providerName)</span>
                        \(versionHTML)
                    </div>
                    \(planHTML)
                </div>
                <div class="card-body">
                    <div class="usage-row">
                        <div class="usage-item">
                            <div class="usage-item-header">
                                <span class="usage-label">Session</span>
                                <span class="usage-percent \(primaryClass)">\(Int(primaryUsage))%</span>
                            </div>
                            <div class="usage-bar"><div class="usage-fill \(primaryClass)" style="width: \(min(100, primaryUsage))%"></div></div>
                            <div class="usage-meta">
                                <span class="reset-time" data-reset-at="\(primaryResetAt)"></span>
                                \(primaryPredHTML)
                            </div>
                        </div>
                        \(secondaryItemHTML)
                    </div>
                    \(costHTML)
                    <div class="chart-section">
                        <div class="chart-header">
                            <span class="chart-label">History</span>
                            <div class="chart-period-btns" data-chart="chart-\(providerName)">
                                <button class="chart-period-btn active" data-hours="24">24h</button>
                                <button class="chart-period-btn" data-hours="168">W</button>
                                <button class="chart-period-btn" data-hours="720">M</button>
                                <button class="chart-period-btn" data-hours="8760">Y</button>
                            </div>
                        </div>
                        <div class="chart-container">
                            <canvas id="chart-\(providerName)"></canvas>
                        </div>
                    </div>
                </div>
                <div class="card-footer">
                    <span class="account-email">\(email)</span>
                    <span class="source-label">\(source)</span>
                </div>
            </div>
            """
    }

    private static func renderPredictionInline(_ prediction: UsagePrediction?, resetAt: Date?) -> String {
        guard let pred = prediction else { return "" }
        guard let ttlStr = pred.timeToLimitDescription else { return "" }

        // Determine status: if we'll hit limit BEFORE reset, it's critical (red)
        let statusClass: String
        var tooltip: String? = nil

        if let limitDate = pred.estimatedLimitDate, let reset = resetAt {
            if limitDate < reset {
                // Will hit limit before reset - critical!
                statusClass = "critical"
                tooltip = "Limit before reset!"
            } else {
                // Will last until reset - use normal status
                statusClass = pred.status.rawValue
            }
        } else {
            statusClass = pred.status.rawValue
        }

        let tooltipAttr = tooltip.map { " title=\"\($0)\"" } ?? ""
        return "<span class=\"prediction-inline \(statusClass)\"\(tooltipAttr)>→ \(ttlStr)</span>"
    }

    private static func usageClass(_ usage: Double) -> String {
        if usage < 50 { return "low" }
        if usage < 75 { return "medium" }
        if usage < 90 { return "high" }
        return "critical"
    }

    private static func planClass(_ plan: String) -> String {
        let lower = plan.lowercased()
        if lower.contains("pro") { return "pro" }
        if lower.contains("plus") { return "plus" }
        if lower.contains("max") { return "max" }
        if lower.contains("paid") || lower.contains("premium") { return "paid" }
        return "free"
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private static func formatResetTime(_ date: Date?) -> String {
        guard let date = date else { return "" }

        let now = Date()
        let diff = date.timeIntervalSince(now)

        if diff <= 0 { return "Resetting..." }

        let hours = Int(diff / 3600)
        let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 24 {
            let days = hours / 24
            return "Resets in \(days)d \(hours % 24)h"
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }

    private static func formatTokenCount(_ count: Int?) -> String {
        guard let count = count else { return "—" }
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1000 {
            return String(format: "%.0fK", Double(count) / 1000)
        }
        return "\(count)"
    }

    private static func formatUSD(_ amount: Double?) -> String {
        guard let amount = amount else { return "—" }
        if amount >= 100 {
            return String(format: "$%.0f", amount)
        } else if amount >= 10 {
            return String(format: "$%.1f", amount)
        }
        return String(format: "$%.2f", amount)
    }
}

// MARK: - Provider Detail Page

enum ProviderPage {
    static func render(provider: UsageProvider, state: AppState) throws -> String {
        let records = try state.store.fetchHistory(provider: provider, limit: 200)
        let prediction = try state.predictionEngine.predict(from: state.store, provider: provider)
        let stats = try state.store.calculateStatistics(
            provider: provider,
            from: Date().addingTimeInterval(-24 * 3600),
            to: Date()
        )

        let latestRecord = records.first
        let usage = latestRecord?.primaryUsedPercent ?? 0
        let usageClass = Self.usageClass(usage)

        return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>\(provider.rawValue.capitalized) - CodexBar</title>
                <link rel="stylesheet" href="/static/style.css">
                <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js" integrity="sha384-9nhczxUqK87bcKHh20fSQcTGD4qq5GhayNYSYWqwBkINBhOfQLg/P5HG5lF1urn4" crossorigin="anonymous"></script>
                <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns@3.0.0/dist/chartjs-adapter-date-fns.bundle.min.js" integrity="sha384-cVMg8E3QFwTvGCDuK+ET4PD341jF3W8nO1auiXfuZNQkzbUUiBGLsIQUE+b1mxws" crossorigin="anonymous"></script>
                <style>
                    .back-link { color: var(--accent-blue); text-decoration: none; font-size: 14px; }
                    .back-link:hover { text-decoration: underline; }
                    .large-chart { height: 300px; margin: 20px 0; }
                    .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 16px; margin: 20px 0; }
                    .stat-card { background: var(--bg-card); border: 1px solid var(--border-color); border-radius: 8px; padding: 16px; }
                    .stat-card h3 { font-size: 14px; color: var(--text-secondary); margin-bottom: 12px; }
                    .stat-row { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid var(--border-color); }
                    .stat-row:last-child { border-bottom: none; }
                    .stat-label { color: var(--text-secondary); font-size: 13px; }
                    .stat-value { font-weight: 500; font-size: 14px; }
                </style>
            </head>
            <body>
                <div class="container">
                    <header>
                        <div class="header-left">
                            <a href="/" class="back-link">← Back</a>
                            <h1>\(provider.rawValue.capitalized)</h1>
                        </div>
                    </header>

                    <div class="card">
                        <div class="card-body">
                            <div class="usage-section">
                                <div class="usage-header">
                                    <span class="usage-label">Current Session Usage</span>
                                    <span class="usage-percent \(usageClass)">\(Int(usage))%</span>
                                </div>
                                <div class="usage-bar" style="height: 12px">
                                    <div class="usage-fill \(usageClass)" style="width: \(min(100, usage))%"></div>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div class="stats-grid">
                        <div class="stat-card">
                            <h3>24h Statistics</h3>
                            <div class="stat-row">
                                <span class="stat-label">Average</span>
                                <span class="stat-value">\(stats.avgPrimaryUsage.map { String(format: "%.1f%%", $0) } ?? "N/A")</span>
                            </div>
                            <div class="stat-row">
                                <span class="stat-label">Maximum</span>
                                <span class="stat-value">\(stats.maxPrimaryUsage.map { String(format: "%.1f%%", $0) } ?? "N/A")</span>
                            </div>
                            <div class="stat-row">
                                <span class="stat-label">Minimum</span>
                                <span class="stat-value">\(stats.minPrimaryUsage.map { String(format: "%.1f%%", $0) } ?? "N/A")</span>
                            </div>
                            <div class="stat-row">
                                <span class="stat-label">Data Points</span>
                                <span class="stat-value">\(stats.recordCount)</span>
                            </div>
                        </div>

                        <div class="stat-card">
                            <h3>Prediction</h3>
                            <div class="stat-row">
                                <span class="stat-label">Rate</span>
                                <span class="stat-value">\(prediction.map { String(format: "%.2f%%/hr", $0.ratePerHour) } ?? "N/A")</span>
                            </div>
                            <div class="stat-row">
                                <span class="stat-label">Time to Limit</span>
                                <span class="stat-value">\(prediction?.timeToLimitDescription ?? "N/A")</span>
                            </div>
                            <div class="stat-row">
                                <span class="stat-label">Status</span>
                                <span class="stat-value">\(prediction?.status.rawValue.capitalized ?? "Unknown")</span>
                            </div>
                            <div class="stat-row">
                                <span class="stat-label">Confidence</span>
                                <span class="stat-value">\(prediction.map { String(format: "%.0f%%", $0.confidence * 100) } ?? "N/A")</span>
                            </div>
                        </div>
                    </div>

                    <div class="card">
                        <div class="card-body">
                            <div class="chart-label" style="margin-bottom: 12px; color: var(--text-secondary);">Usage History (24h)</div>
                            <div class="large-chart">
                                <canvas id="history-chart"></canvas>
                            </div>
                        </div>
                    </div>
                </div>

                <script>
                    fetch('/api/history/\(provider.rawValue)?hours=24&limit=200')
                        .then(r => r.json())
                        .then(data => {
                            const chartData = data.data
                                .map(d => ({ x: new Date(d.timestamp), y: d.primaryUsage }))
                                .filter(d => d.y !== null)
                                .reverse();

                            new Chart(document.getElementById('history-chart'), {
                                type: 'line',
                                data: {
                                    datasets: [{
                                        label: 'Session Usage',
                                        data: chartData,
                                        borderColor: '#58a6ff',
                                        backgroundColor: 'rgba(88, 166, 255, 0.1)',
                                        fill: true,
                                        tension: 0.3
                                    }]
                                },
                                options: {
                                    responsive: true,
                                    maintainAspectRatio: false,
                                    plugins: { legend: { display: false } },
                                    scales: {
                                        x: { type: 'time', time: { unit: 'hour' }, ticks: { color: '#6e7681' }, grid: { color: '#21262d' } },
                                        y: { min: 0, max: 100, ticks: { color: '#6e7681' }, grid: { color: '#21262d' } }
                                    }
                                }
                            });
                        });
                </script>
            </body>
            </html>
            """
    }

    private static func usageClass(_ usage: Double) -> String {
        if usage < 50 { return "low" }
        if usage < 75 { return "medium" }
        if usage < 90 { return "high" }
        return "critical"
    }
}
