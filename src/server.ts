import { app } from "./app.js";

const PORT = Number(process.env.PORT) || 3000;
// Give in-flight requests this long to finish before the process exits.
const SHUTDOWN_TIMEOUT_MS = Number(process.env.SHUTDOWN_TIMEOUT_MS) || 10_000;

const server = app.listen(PORT, () => {
  console.log(`API listening on port ${PORT}`);
});

// Keep-alive connections must not outlive the pod; cap idle sockets so the
// load balancer can recycle them cleanly (AWS ALB idle timeout is 60s).
server.keepAliveTimeout = 65_000;
server.headersTimeout = 66_000;

function shutdown(signal: NodeJS.Signals): void {
  console.log(`${signal} received, draining connections`);
  server.close((err?: Error) => {
    if (err) {
      console.error("error while closing server", err);
      process.exit(1);
    }
    console.log("server closed, exiting");
    process.exit(0);
  });
  // Force exit if clients hold connections open past the grace period.
  setTimeout(() => {
    console.error("shutdown timeout reached, forcing exit");
    process.exit(1);
  }, SHUTDOWN_TIMEOUT_MS).unref();
}

// Kubernetes sends SIGTERM on pod termination; Ctrl-C sends SIGINT locally.
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
