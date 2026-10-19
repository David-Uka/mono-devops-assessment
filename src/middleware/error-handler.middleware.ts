import type { NextFunction, Request, Response } from "express";
import { ExpressErrorMiddlewareInterface, HttpError, Middleware } from "routing-controllers";
import { Service } from "typedi";

@Service()
@Middleware({ type: "after" })
export class ErrorHandlerMiddleware implements ExpressErrorMiddlewareInterface {
  error(error: unknown, _req: Request, res: Response, next: NextFunction): void {
    if (res.headersSent) {
      next();
      return;
    }

    const status = error instanceof HttpError ? error.httpCode : 500;
    const message =
      error instanceof Error && error.message ? error.message : "Internal server error";
    res.status(status).json({ error: message });
  }
}
