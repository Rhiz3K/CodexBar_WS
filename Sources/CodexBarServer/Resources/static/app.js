const chartInstances = {};
let use24HourFormat = localStorage.getItem('timeFormat') === '24h';

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
        hour: 'numeric',
        minute: '2-digit',
        hour12: !use24HourFormat,
    };
    return date.toLocaleString(undefined, options);
}

function formatTimestamp(date) {
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const minutes = Math.floor(diff / 60000);

    if (minutes < 1) return 'just now';
    if (minutes < 60) return `${minutes}m ago`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    return `${days}d ago`;
}

function getUsageColor(percent) {
    if (percent === null || percent === undefined) return '#6e7681';
    if (percent < 25) return '#58a6ff';
    if (percent < 50) return '#3fb950';
    if (percent < 75) return '#d29922';
    if (percent < 90) return '#db6d28';
    return '#f85149';
}

function createUsageChart(canvasId, data) {
    if (!window.Chart) return;

    const ctx = document.getElementById(canvasId);
    if (!ctx) return;

    if (chartInstances[canvasId]) {
        chartInstances[canvasId].destroy();
    }

    const sessionData = data.map(d => ({ x: new Date(d.timestamp), y: d.primaryUsage }));
    const weeklyData = data.map(d => ({ x: new Date(d.timestamp), y: d.secondaryUsage }));

    const latestWeekly = weeklyData.length > 0 ? weeklyData[weeklyData.length - 1].y : null;
    const weeklyColor = getUsageColor(latestWeekly);

    chartInstances[canvasId] = new Chart(ctx, {
        type: 'line',
        data: {
            datasets: [
                {
                    label: 'Session',
                    data: sessionData,
                    borderColor: '#6e7681',
                    backgroundColor: 'transparent',
                    borderWidth: 2,
                    borderDash: [5, 5],
                    pointRadius: 0,
                    tension: 0.2,
                },
                {
                    label: 'Weekly',
                    data: weeklyData,
                    borderColor: weeklyColor,
                    backgroundColor: 'transparent',
                    borderWidth: 2,
                    pointRadius: 0,
                    tension: 0.2,
                },
            ],
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: { display: false },
                tooltip: {
                    callbacks: {
                        label: function (context) {
                            const value = context.parsed.y;
                            if (value === null || value === undefined) return '';
                            return `${context.dataset.label}: ${value.toFixed(1)}%`;
                        },
                    },
                },
            },
            scales: {
                x: {
                    type: 'time',
                    time: { unit: 'hour' },
                    grid: { color: '#30363d' },
                    ticks: { color: '#6e7681', maxTicksLimit: 4 },
                },
                y: {
                    min: 0,
                    max: 100,
                    grid: { color: '#30363d' },
                    ticks: {
                        color: '#6e7681',
                        callback: value => `${value}%`,
                        maxTicksLimit: 5,
                    },
                },
            },
        },
    });
}

async function fetchStatus() {
    const response = await fetch('/api/status');
    return response.json();
}

async function fetchHistory(provider) {
    const response = await fetch(`/api/history/${provider}?hours=24&limit=200`);
    return response.json();
}

async function refreshDashboard() {
    try {
        const status = await fetchStatus();
        const providers = status.providers;

        // Update last update timestamp
        const lastUpdate = document.getElementById('last-update');
        if (lastUpdate) {
            const timestamp = new Date();
            lastUpdate.dataset.timestamp = timestamp.toISOString();
            lastUpdate.textContent = formatTimestamp(timestamp);
        }

        // Update each provider card
        for (const providerName in providers) {
            const card = document.querySelector(`[data-provider="${providerName}"]`);
            if (!card) continue;

            const provider = providers[providerName];

            // Update status indicator
            const indicator = card.querySelector('.status-indicator');
            if (indicator) {
                indicator.className = `status-indicator ${provider.prediction?.status || 'healthy'}`;
                if (provider.prediction?.estimatedLimitDate && provider.primaryResetAt) {
                    const limitDate = new Date(provider.prediction.estimatedLimitDate);
                    const resetDate = new Date(provider.primaryResetAt);
                    if (limitDate < resetDate) {
                        indicator.className = 'status-indicator critical';
                        indicator.title = 'Limit before reset!';
                    }
                }
            }

            // Update usage values
            const sessionValue = card.querySelector('.session-usage');
            if (sessionValue) sessionValue.textContent = provider.primaryUsage !== null ? `${provider.primaryUsage.toFixed(1)}%` : '—';

            const weeklyValue = card.querySelector('.weekly-usage');
            if (weeklyValue) weeklyValue.textContent = provider.secondaryUsage !== null ? `${provider.secondaryUsage.toFixed(1)}%` : '—';

            // Update reset times
            const sessionReset = card.querySelector('.session-reset');
            if (sessionReset && provider.primaryResetAt) {
                sessionReset.textContent = formatRelativeTime(new Date(provider.primaryResetAt));
            }

            const weeklyReset = card.querySelector('.weekly-reset');
            if (weeklyReset && provider.secondaryResetAt) {
                weeklyReset.textContent = formatRelativeTime(new Date(provider.secondaryResetAt));
            }

            // Update prediction
            const prediction = card.querySelector('.prediction');
            if (prediction) {
                const timeToLimit = provider.prediction?.timeToLimit;
                prediction.textContent = timeToLimit || '—';
            }

            // Refresh chart data
            const history = await fetchHistory(providerName);
            createUsageChart(`chart-${providerName}`, history.data);
        }
    } catch (error) {
        console.error('Refresh failed:', error);
    }
}

async function triggerFetch() {
    const button = document.querySelector('.refresh-btn');
    if (button) button.disabled = true;

    try {
        await fetch('/api/fetch', { method: 'POST' });
        // Give the server a moment then refresh
        setTimeout(refreshDashboard, 1000);
    } finally {
        if (button) button.disabled = false;
    }
}

function initAutoRefresh() {
    const select = document.getElementById('autorefresh-select');
    let intervalId = null;

    function updateInterval() {
        if (intervalId) clearInterval(intervalId);
        const value = parseInt(select.value, 10);
        if (value > 0) {
            intervalId = setInterval(refreshDashboard, value);
        }
    }

    if (select) {
        select.value = localStorage.getItem('autoRefreshInterval') || '60000';
        select.addEventListener('change', () => {
            localStorage.setItem('autoRefreshInterval', select.value);
            updateInterval();
        });
        updateInterval();
    }
}

const eyeIcon = '<svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M16 8s-3-5.5-8-5.5S0 8 0 8s3 5.5 8 5.5S16 8 16 8zM1.173 8a13.133 13.133 0 0 1 1.66-2.043C4.12 4.668 5.88 3.5 8 3.5c2.12 0 3.879 1.168 5.168 2.457A13.133 13.133 0 0 1 14.828 8c-.058.087-.122.183-.195.288-.335.48-.83 1.12-1.465 1.755C11.879 11.332 10.119 12.5 8 12.5c-2.12 0-3.879-1.168-5.168-2.457A13.134 13.134 0 0 1 1.172 8z"/><path d="M8 5.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM4.5 8a3.5 3.5 0 1 1 7 0 3.5 3.5 0 0 1-7 0z"/></svg>';
const eyeSlashIcon = '<svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="m10.79 12.912-1.614-1.615a3.5 3.5 0 0 1-4.474-4.474l-1.615-1.615A13.134 13.134 0 0 0 1.173 8c.058.087.122.183.195.288.335.48.83 1.12 1.465 1.755C4.121 11.332 5.881 12.5 8 12.5c.716 0 1.39-.133 2.02-.368z"/><path d="M14.828 8c-.058-.087-.122-.183-.195-.288-.335-.48-.83-1.12-1.465-1.755C11.879 4.668 10.119 3.5 8 3.5c-.716 0-1.39.133-2.02.368l1.614 1.615a3.5 3.5 0 0 1 4.474 4.474l1.615 1.615A13.134 13.134 0 0 0 14.828 8z"/><path d="M8 5.5a2.5 2.5 0 0 0-2.5 2.5c0 .637.237 1.22.626 1.665l3.539 3.539A2.5 2.5 0 0 0 8 5.5z"/><path d="m13.646 14.354-12-12 .708-.708 12 12-.708.708z"/></svg>';

function initTimeToggle() {
    const toggle = document.getElementById('timeformat-toggle');

    function updateButton() {
        if (toggle) {
            toggle.textContent = use24HourFormat ? '24H' : '12H';
            toggle.classList.toggle('active', use24HourFormat);
        }
    }

    if (toggle) {
        updateButton();
        toggle.addEventListener('click', () => {
            use24HourFormat = !use24HourFormat;
            localStorage.setItem('timeFormat', use24HourFormat ? '24h' : '12h');
            updateButton();
            refreshDashboard();
        });
    }
}

function initPrivacyToggle() {
    const toggle = document.getElementById('privacy-toggle');

    function updatePrivacyState(hidden) {
        if (!toggle) return;
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

    if (toggle) {
        const hideEmails = localStorage.getItem('hideEmails') === 'true';
        updatePrivacyState(hideEmails);

        toggle.addEventListener('click', () => {
            const newState = !document.body.classList.contains('emails-hidden');
            localStorage.setItem('hideEmails', newState);
            updatePrivacyState(newState);
        });
    }
}

document.addEventListener('DOMContentLoaded', () => {
    initAutoRefresh();
    initTimeToggle();
    initPrivacyToggle();

    const refreshButton = document.querySelector('.refresh-btn');
    if (refreshButton) {
        refreshButton.addEventListener('click', triggerFetch);
    }

    // Initial load
    refreshDashboard();

    // Update timestamp every minute
    setInterval(() => {
        const lastUpdate = document.getElementById('last-update');
        if (lastUpdate?.dataset.timestamp) {
            const timestamp = new Date(lastUpdate.dataset.timestamp);
            lastUpdate.textContent = formatTimestamp(timestamp);
        }
    }, 60000);
});
