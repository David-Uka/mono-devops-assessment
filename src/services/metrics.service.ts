import client from "prom-client";
import { Service } from "typedi";

@Service()
export class MetricsService {
  readonly register = new client.Registry();

  private readonly httpRequestsTotal = new client.Counter({
    name: "http_requests_total",
    help: "Total number of HTTP requests received",
    labelNames: ["method", "route", "status_code"],
    registers: [this.register],
  });

  constructor() {
    client.collectDefaultMetrics({ register: this.register });
  }

  get contentType(): string {
    return this.register.contentType;
  }

  countRequest(method: string, route: string, statusCode: number): void {
    this.httpRequestsTotal.labels(method, route, String(statusCode)).inc();
  }

  async render(): Promise<string> {
    return this.register.metrics();
  }
}
