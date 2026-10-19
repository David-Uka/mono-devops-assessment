import client from "prom-client";
import { Service } from "typedi";

/**
 * Routes we are willing to use as a metric label. Anything else is bucketed
 * as "unmatched" so a scanner hitting random paths cannot blow up label
 * cardinality in Prometheus.
 */
const KNOWN_ROUTES = new Set(["/health", "/metrics", "/getAccount"]);

export function normalizeRoute(path: string): string {
  return KNOWN_ROUTES.has(path) ? path : "unmatched";
}

@Service()
export class MetricsService {
  readonly register = new client.Registry();

  private readonly httpRequestsTotal = new client.Counter({
    name: "http_requests_total",
    help: "Total number of HTTP requests received",
    labelNames: ["method", "route", "status_code"],
    registers: [this.register],
  });

  private readonly httpRequestDuration = new client.Histogram({
    name: "http_request_duration_seconds",
    help: "HTTP request latency in seconds",
    labelNames: ["method", "route", "status_code"],
    // Buckets tuned for a sub-second API: 5ms .. 5s
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
    registers: [this.register],
  });

  private readonly httpRequestsInFlight = new client.Gauge({
    name: "http_requests_in_flight",
    help: "Number of HTTP requests currently being handled",
    registers: [this.register],
  });

  constructor() {
    client.collectDefaultMetrics({ register: this.register });
  }

  get contentType(): string {
    return this.register.contentType;
  }

  requestStarted(): void {
    this.httpRequestsInFlight.inc();
  }

  requestFinished(method: string, path: string, statusCode: number, durationSeconds: number): void {
    const route = normalizeRoute(path);
    const status = String(statusCode);
    this.httpRequestsInFlight.dec();
    this.httpRequestsTotal.labels(method, route, status).inc();
    this.httpRequestDuration.labels(method, route, status).observe(durationSeconds);
  }

  async render(): Promise<string> {
    return this.register.metrics();
  }
}
