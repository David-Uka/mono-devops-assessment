import type { NextFunction, Request, Response } from "express";
import { ExpressMiddlewareInterface, Middleware } from "routing-controllers";
import { Service } from "typedi";
import { MetricsService } from "../services/metrics.service.js";

@Service()
@Middleware({ type: "before" })
export class RequestMetricsMiddleware implements ExpressMiddlewareInterface {
  constructor(private readonly metrics: MetricsService) {}

  use(req: Request, res: Response, next: NextFunction): void {
    const startedAt = process.hrtime.bigint();
    this.metrics.requestStarted();

    res.on("finish", () => {
      const elapsedSeconds = Number(process.hrtime.bigint() - startedAt) / 1e9;
      this.metrics.requestFinished(req.method ?? "UNKNOWN", req.path, res.statusCode, elapsedSeconds);
    });
    next();
  }
}
