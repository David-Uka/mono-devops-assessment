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

    // "close" fires whether the response finished or the client went away,
    // so the in-flight gauge cannot drift. Aborted requests are labelled 499.
    res.once("close", () => {
      const elapsedSeconds = Number(process.hrtime.bigint() - startedAt) / 1e9;
      const status = res.writableFinished ? res.statusCode : 499;
      this.metrics.requestFinished(req.method ?? "UNKNOWN", req.path, status, elapsedSeconds);
    });
    next();
  }
}
