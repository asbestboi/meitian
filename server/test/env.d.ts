declare namespace Cloudflare {
  interface Env {
    DB: D1Database;
    MATCHMAKER: DurableObjectNamespace;
    ROOMS: DurableObjectNamespace;
    TEST_MIGRATIONS: import("cloudflare:test").D1Migration[];
  }
}
