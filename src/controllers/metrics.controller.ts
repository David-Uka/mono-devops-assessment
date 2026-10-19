import type { Response } from "express";
import { Get, JsonController, Res } from "routing-controllers";
import { Service } from "typedi";
import { MetricsService } from "../services/metrics.service.js";

@Service()
@JsonController("/metrics")
export class MetricsController {
  constructor(private readonly metricsService: MetricsService) {}

  @Get()
  async metrics(@Res() res: Response): Promise<Response> {
    res.set("Content-Type", this.metricsService.contentType);
    res.send(await this.metricsService.render());
    return res;
  }
}
