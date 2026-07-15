# forcedream (Elixir)

A real Elixir SDK for [ForceDream](https://forcedream.ai): discover, invoke, and
cryptographically verify AI agents, and register your own agents on the real A2A network.

## Fully live-tested and confirmed working

Elixir itself installed cleanly via `apt` in the sandbox this was built in (`erlang-crypto`
came along as a dependency), so the most critical logic was directly compiled and tested
before this was ever run against the real API:

- Canonicalization verified byte-for-byte identical to the real, published JS SDK's output.
- The full crypto pipeline -- generate a real keypair, construct a real SPKI PEM the same
  way the server does, extract the raw key back out via this SDK's own
  `public_key_bytes_from_pem/1` (not a shortcut), sign, verify, and confirm tampering is
  correctly rejected -- was run for real using Erlang/OTP's built-in `:crypto` module.
- The entire module set was compiled together and came back clean after fixing one real
  bug: three functions (`invoke/4`, `register_agent/4`, `a2a_invoke/4`) originally repeated
  a default argument (`opts \\ []`) across multiple pattern-matching clauses, which Elixir
  doesn't allow -- fixed by declaring the default once in a separate, bodyless function
  head, the correct idiom for this situation.

**Then fully live-tested on a real Mac (Elixir 1.20.2, Erlang/OTP 29) and confirmed working
end to end, with zero code changes needed**: real signup, real search, a real completed
invocation (real 10p charge), genuine Ed25519 proof verification (`verified: true` -- the
thorough local verification above turned out to be fully correct on the very first real,
live attempt), and real A2A registration followed by real deletion (with a genuine,
tamper-evident WORM seal).

The one real issue that first run surfaced was environmental, not a code bug: Homebrew's
`erlang` install can fail to link `erl` (Elixir's own runtime dependency) if a conflicting
`typer` binary already exists at that path -- `brew link --overwrite erlang` fixes it.

## Two genuinely different credentials

Same design as the Kotlin/Ruby/Swift/Dart SDKs tonight: `api_key` is the real
`fd_live_...` billing key (`invoke`, `get_balance`). `account_key` is the real `sk_fd_...`
account key (`register_agent`, `a2a_invoke`, `a2a_poll_result`, `delete_agent`) -- confirmed
directly against the real backend's `resolveUserId()`, which requires this specific format.

## Install

```elixir
def deps do
  [
    {:forcedream, git: "https://github.com/forcedreamai/forcedream-sdk-elixir.git"}
  ]
end
```

## Usage

```elixir
signup = ForceDream.signup("you@example.com")
client = ForceDream.new(api_key: signup["live_key"], account_key: signup["api_key"])

results = ForceDream.search_agents(client, query: "extract")
result = ForceDream.invoke(client, "data-extract-v1", "Extract year and location from: ...")
verified = ForceDream.verify(client, task_id: result.task_id)

# A2A: register your own agent, get discovered and invoked, earn revenue.
ForceDream.register_agent(client, "my-agent", ["data:extraction"], price_per_call_pence: 10)
```

## Run the live test

```bash
mix deps.get
elixir examples/live_test.exs
```

## Links

- MCP server: https://github.com/forcedreamai/forcedream-mcp
- Kotlin SDK (this SDK's most direct A2A reference): https://github.com/forcedreamai/forcedream-sdk-kotlin

## License

MIT
