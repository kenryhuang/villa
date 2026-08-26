# Villa Agent Service

This local TypeScript service calls a configured real OpenAI-compatible Provider. It has no runtime mock Provider.

Required environment variables:

- `AGENT_PROVIDER_BASE_URL`
- `AGENT_PROVIDER_API_KEY`
- `AGENT_PROVIDER_MODEL`

Optional variables include `AGENT_SERVICE_HOST`, `AGENT_SERVICE_PORT`, `AGENT_MEMORY_DB`, `AGENT_PROVIDER_TIMEOUT_MS`, `AGENT_PROVIDER_MAX_OUTPUT_TOKENS`, and `AGENT_PROVIDER_TEMPERATURE`.

Run tests with `npm test`. Tests use local fake HTTP endpoints and never use public network or real credentials. Start with `npm start` after setting the required environment variables.
