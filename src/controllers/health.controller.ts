import { Get, JsonController } from "routing-controllers";
import { Service } from "typedi";

const startedAt = Date.now();

@Service()
@JsonController("/health")
export class HealthController {
  @Get()
  health(): { status: string; uptimeSeconds: number } {
    return {
      status: "ok",
      uptimeSeconds: Math.floor((Date.now() - startedAt) / 1000),
    };
  }
}
