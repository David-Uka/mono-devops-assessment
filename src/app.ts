import "reflect-metadata";
import { createExpressServer, useContainer } from "routing-controllers";
import { Container } from "typedi";
import { AccountController } from "./controllers/account.controller.js";
import { HealthController } from "./controllers/health.controller.js";
import { MetricsController } from "./controllers/metrics.controller.js";
import { ErrorHandlerMiddleware } from "./middleware/error-handler.middleware.js";
import { NotFoundMiddleware } from "./middleware/not-found.middleware.js";
import { RequestMetricsMiddleware } from "./middleware/request-metrics.middleware.js";

useContainer(Container);

export const app = createExpressServer({
  controllers: [HealthController, AccountController, MetricsController],
  middlewares: [RequestMetricsMiddleware, NotFoundMiddleware, ErrorHandlerMiddleware],
  defaultErrorHandler: false,
});
