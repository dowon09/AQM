import { useEffect, useRef, useState } from "react";
import {
  Activity,
  Cloud,
  Droplets,
  Thermometer,
  Wind,
  type LucideIcon,
} from "lucide-react";
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

interface Reading {
  id: number;
  aqi: number | null;
  tvoc: number | null;
  eco2: number | null;
  temperature: number | null;
  humidity: number | null;
  timestamp: string;
}

const API_ROOT = (import.meta.env.VITE_API_URL || "http://localhost:8000/api").replace(/\/$/, "");
const ranges = [
  { label: "24 hours", days: 1 },
  { label: "7 days", days: 7 },
  { label: "30 days", days: 30 },
] as const;
const chartMetrics = [
  { key: "aqi", label: "AQI", unit: "" },
  { key: "tvoc", label: "TVOC", unit: "ppb" },
  { key: "eco2", label: "eCO₂", unit: "ppm" },
  { key: "temperature", label: "Temperature", unit: "°C" },
  { key: "humidity", label: "Humidity", unit: "%" },
] as const;
type ChartMetric = typeof chartMetrics[number]["key"];

function aqiStatus(value: number | null) {
  if (value === null) return { label: "No reading", tone: "neutral" };
  if (value == 1) return { label: "Excellent", tone: "good" };
  if (value == 2) return { label: "Good", tone: "good" };
  if (value == 3) return { label: "Moderate", tone: "sensitive" };
  if (value == 4) return { label: "Poor", tone: "unhealthy" };
  if (value == 5) return { label: "Very Poor", tone: "very-unhealthy" };
  return { label: "No reading", tone: "neutral" };
}

function formatTimestamp(timestamp: string) {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(parseTimestamp(timestamp));
}

function parseTimestamp(timestamp: string) {
  const hasTimezone = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(timestamp);
  return new Date(hasTimezone ? timestamp : `${timestamp}Z`);
}

function mergeLatestReading(history: Reading[], latest: Reading | null) {
  if (!latest) {
    return history;
  }

  const readingsById = new Map(history.map((reading) => [reading.id, reading]));
  readingsById.set(latest.id, latest);
  return [...readingsById.values()].sort(
    (first, second) => parseTimestamp(first.timestamp).getTime() - parseTimestamp(second.timestamp).getTime(),
  );
}

function MetricCard({
  icon: Icon,
  label,
  value,
  unit,
  tone,
}: {
  icon: LucideIcon;
  label: string;
  value: string;
  unit: string;
  tone: string;
}) {
  return (
    <article className={`metric-card ${tone}`}>
      <div className="metric-heading">
        <span className="metric-icon"><Icon size={17} strokeWidth={1.8} /></span>
        <span>{label}</span>
      </div>
      <div className="metric-reading">
        <strong>{value}</strong>
        {unit && <span>{unit}</span>}
      </div>
    </article>
  );
}

export default function App() {
  const [latest, setLatest] = useState<Reading | null>(null);
  const [readings, setReadings] = useState<Reading[]>([]);
  const [days, setDays] = useState<number>(1);
  const [selectedMetric, setSelectedMetric] = useState<ChartMetric>("tvoc");
  const [historyError, setHistoryError] = useState("");
  const [latestError, setLatestError] = useState("");
  const latestRef = useRef<Reading | null>(null);
  const daysRef = useRef(days);
  daysRef.current = days;
  const error = latestError || historyError;

  useEffect(() => {
    let cancelled = false;

    async function loadHistory() {
      try {
        const response = await fetch(`${API_ROOT}/readings?days=${days}`);
        if (!response.ok) {
          throw new Error("The readings service could not be reached.");
        }
        const historyData = await response.json() as Reading[];
        if (!cancelled) {
          setReadings(mergeLatestReading(historyData, latestRef.current));
          setHistoryError("");
        }
      } catch {
        if (!cancelled) setHistoryError("Unable to load readings. Check the connection and try again.");
      }
    }

    loadHistory();
    return () => {
      cancelled = true;
    };
  }, [days]);

  useEffect(() => {
    let cancelled = false;

    async function pollLatest() {
      try {
        const response = await fetch(`${API_ROOT}/readings/latest`);
        if (!response.ok) {
          throw new Error("The readings service could not be reached.");
        }
        const latestData = await response.json() as Reading | null;
        if (!cancelled) {
          latestRef.current = latestData;
          setLatest(latestData);
          if (latestData) {
            setReadings((current) => mergeLatestReading(current, latestData));
          }
          setLatestError("");
        }
      } catch {
        if (!cancelled) setLatestError("Unable to load readings. Check the connection and try again.");
      }
    }

    pollLatest();
    const interval = window.setInterval(pollLatest, 30_000);
    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, []);

  const status = aqiStatus(latest?.aqi ?? null);
  const lastSeenMs = latest ? Date.now() - parseTimestamp(latest.timestamp).getTime() : null;
  const isLive = lastSeenMs !== null && lastSeenMs < 300_000;
  const chartData = readings.map((reading) => ({
    ...reading,
    chartAqi: reading.aqi === null ? null : 6 - reading.aqi,
    chartTime: parseTimestamp(reading.timestamp).getTime(),
  }));
  const selectedMetricConfig = chartMetrics.find((metric) => metric.key === selectedMetric) ?? chartMetrics[0];
  const metricChartData = chartData.filter((reading) => reading[selectedMetric] !== null);

  return (
    <main className="page-shell">
      <header className="topbar">
        <a className="brand" href="#top" aria-label="Air Quality Monitor home">
          <span className="brand-mark"><Wind size={20} strokeWidth={2} /></span>
          <span>Air Quality Monitor</span>
        </a>
      </header>

      <section className="dashboard" id="top">
        {error && <div className="error-banner" role="alert">{error}</div>}

        <section className="overview-grid" aria-label="Current air quality">
          <article className={`aqi-panel ${status.tone}`}>
            <div className="aqi-topline">
              <div className="panel-kicker"><Activity size={15} /> AIR QUALITY INDEX</div>
              <span className={`connection ${isLive ? "connected" : "disconnected"}`}>
                <span />{latest ? (isLive ? "Live" : "Quiet") : "Sensor not connected"}
              </span>
            </div>
            <div className="aqi-main">
              <div className="aqi-copy">
                <span className="aqi-label">{status.label}</span>
              </div>
            </div>
            <div className="aqi-footer">
              <span>{latest ? `Updated ${formatTimestamp(latest.timestamp)}` : "Waiting for the sensor reading"}</span>
            </div>
            <div className="aqi-scale-bar" aria-hidden="true"><i /></div>
          </article>

          <div className="metrics-grid">
            <MetricCard icon={Thermometer} label="Temperature" value={latest?.temperature == null ? "--" : latest.temperature.toFixed(1)} unit="°C" tone="coral" />
            <MetricCard icon={Droplets} label="Humidity" value={latest?.humidity == null ? "--" : latest.humidity.toFixed(0)} unit="%" tone="gold" />
            <MetricCard icon={Cloud} label="TVOC" value={latest?.tvoc == null ? "--" : latest.tvoc.toFixed(0)} unit="ppb" tone="mint" />
            <MetricCard icon={Wind} label="eCO₂" value={latest?.eco2 == null ? "--" : latest.eco2.toFixed(0)} unit="ppm" tone="blue" />
          </div>
        </section>

        <section className="history-panel" aria-label="Air quality history">
          <div className="history-heading">
            <div>
              <p className="eyebrow">TREND</p>
              <h2>{selectedMetricConfig.label} over time</h2>
            </div>
            <div className="history-controls">
              <div className="range-control" role="group" aria-label="Trend metric">
                {chartMetrics.map((metric) => (
                  <button
                    type="button"
                    key={metric.key}
                    className={selectedMetric === metric.key ? "selected" : ""}
                    onClick={() => setSelectedMetric(metric.key)}
                    aria-pressed={selectedMetric === metric.key}
                  >
                    {metric.label}
                  </button>
                ))}
              </div>
              <div className="range-control" role="group" aria-label="Chart time range">
                {ranges.map((range) => (
                  <button
                    type="button"
                    key={range.days}
                    className={days === range.days ? "selected" : ""}
                    onClick={() => setDays(range.days)}
                    aria-pressed={days === range.days}
                  >
                    {range.label}
                  </button>
                ))}
              </div>
            </div>
          </div>
          <div className="chart-wrap">
            {metricChartData.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={metricChartData} margin={{ top: 16, right: 12, left: -18, bottom: 0 }}>
                  <defs>
                    <linearGradient id="metricFill" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#2f8e73" stopOpacity={0.24} />
                      <stop offset="100%" stopColor="#2f8e73" stopOpacity={0.015} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid vertical={false} stroke="#e8ece7" strokeDasharray="3 5" />
                  <XAxis
                    dataKey="chartTime"
                    type="number"
                    domain={["dataMin", "dataMax"]}
                    tickFormatter={(time: number) => new Intl.DateTimeFormat(undefined, days === 1
                      ? { hour: "numeric" }
                      : { month: "short", day: "numeric" }).format(new Date(time))}
                    axisLine={false}
                    tickLine={false}
                    tick={{ fill: "#8b958d", fontSize: 11 }}
                    minTickGap={36}
                  />
                  <YAxis
                    domain={selectedMetric === "aqi" ? [1, 5] : [0, "auto"]}
                    tickFormatter={(value) => selectedMetric === "aqi" ? 6 - Number(value) : value}
                    axisLine={false}
                    tickLine={false}
                    tick={{ fill: "#8b958d", fontSize: 11 }}
                    width={42}
                  />
                  <Tooltip
                    labelFormatter={(time) => formatTimestamp(new Date(Number(time)).toISOString())}
                    formatter={(value) => {
                      if (selectedMetric === "aqi") {
                        const label = value == null ? "" : aqiStatus(6 - Number(value)).label;
                        return [`${label}`];
                      }
                      const digits = selectedMetric === "temperature" || selectedMetric === "humidity" ? 1 : 0;
                      const formattedValue = value == null ? "--" : Number(value).toFixed(digits);
                      return [`${formattedValue} ${selectedMetricConfig.unit}`.trim(), selectedMetricConfig.label];
                    }}
                    contentStyle={{ border: "1px solid #e4e9e3", borderRadius: 8, fontSize: 12 }}
                  />
                  <Area
                    type="monotone"
                    dataKey={selectedMetric === "aqi" ? "chartAqi" : selectedMetric}
                    baseValue={selectedMetric === "aqi" ? 1 : "dataMin"}
                    stroke="#28795f"
                    strokeWidth={2.5}
                    fill="url(#metricFill)"
                    connectNulls
                    activeDot={{ r: 4, fill: "#28795f", stroke: "#fff", strokeWidth: 2 }}
                  />
                </AreaChart>
              </ResponsiveContainer>
            ) : (
              <div className="chart-empty">
                No {selectedMetricConfig.label} readings in this time range.
              </div>
            )}
          </div>
          <div className="chart-footnote"><span className="legend-dot" /> {selectedMetricConfig.label}{selectedMetricConfig.unit ? ` (${selectedMetricConfig.unit})` : ""} <span className="footnote-separator">·</span> refreshed every 30 seconds</div>
        </section>
      </section>
    </main>
  );
}
