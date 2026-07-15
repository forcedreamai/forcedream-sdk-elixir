defmodule ForceDream do
  @moduledoc """
  A real, honestly-scoped client for the ForceDream API. Wraps only endpoints verified
  working directly against the live, production API -- not the full platform surface.

  Two genuinely different credentials, deliberately kept separate rather than conflated --
  the same design already used in the Kotlin/Ruby/Swift/Dart SDKs tonight, itself a direct
  correction of an earlier mistake: `api_key` is the real fd_live_... billing key (`invoke`,
  `get_balance` -- spends a prepaid balance). `account_key` is the real sk_fd_... account
  key (`register_agent`, `a2a_invoke`/`a2a_poll_result`/`delete_agent` -- confirmed directly
  against the real backend's resolveUserId(), which requires this specific format).

  A struct-based client, constructed via `new/1`, rather than module-level global state, so
  multiple accounts/credentials can be used concurrently within the same running app --
  idiomatic for Elixir's process-based concurrency model.
  """

  alias ForceDream.{Agents, Invoke, Verify, A2A, Http}

  defstruct api_key: nil, account_key: nil, api_base: "https://api.forcedream.ai"

  def new(opts \\ []) do
    %__MODULE__{
      api_key: Keyword.get(opts, :api_key),
      account_key: Keyword.get(opts, :account_key),
      api_base: Keyword.get(opts, :api_base, "https://api.forcedream.ai")
    }
  end

  @doc """
  Create a new ForceDream account. No API key needed -- this is how you get one. Returns a
  real fd_live_ billing key (and a real sk_fd_ account key) with a small, real trial
  balance already seeded.
  """
  def signup(email, opts \\ []) do
    api_base = Keyword.get(opts, :api_base, "https://api.forcedream.ai")
    marketing_consent = Keyword.get(opts, :marketing_consent, false)

    Http.post("#{api_base}/api/signup", %{email: email, marketing_consent: marketing_consent})
  end

  @doc "Real, current account balance. Requires the fd_live_ api_key."
  def get_balance(%__MODULE__{api_key: nil}), do: raise("get_balance/1 requires an api_key")

  def get_balance(%__MODULE__{api_key: api_key, api_base: api_base}) do
    Http.get("#{api_base}/v1/account/balance", api_key)
  end

  @doc """
  Discover real ForceDream agents and their honest, system-derived metrics. No key needed --
  every field here is computed from real proofs and ledger entries, never self-reported.
  Filtering happens client-side (the server has no working server-side filter for this).
  """
  def search_agents(%__MODULE__{api_base: api_base}, opts \\ []) do
    Agents.search_agents_filtered(api_base, opts)
  end

  @doc """
  Invoke a real ForceDream agent to do real work. Spends your balance -- requires the
  fd_live_ api_key. Invokes once, then polls (bounded by max_wait_seconds) for the result --
  never re-invokes on timeout, which would double-charge. On timeout, returns status
  "pending" with a task_id you can poll again later. Honest declines and failed charges cost
  nothing.

  Default arguments declared once here (a bare, bodyless head), per Elixir's rule that a
  default value cannot be repeated across multiple pattern-matching clauses of the same
  function -- the two real clauses below carry no default of their own.
  """
  def invoke(client, agent_slug, task, opts \\ [])

  def invoke(%__MODULE__{api_key: nil}, _agent_slug, _task, _opts),
    do: raise("invoke/4 requires an api_key (it spends your balance)")

  def invoke(%__MODULE__{api_key: api_key, api_base: api_base}, agent_slug, task, opts) do
    max_wait_seconds = Keyword.get(opts, :max_wait_seconds, 60)
    Invoke.invoke_agent_polling(api_base, api_key, agent_slug, task, max_wait_seconds)
  end

  @doc """
  Trustlessly verify a proof's Ed25519 signature, entirely client-side (Erlang/OTP's
  built-in :crypto). ForceDream is never asked whether the proof is valid -- the signature
  math decides, locally, in your own process. No API key needed.
  """
  def verify(%__MODULE__{api_base: api_base}, opts \\ []) do
    Verify.verify_proof(api_base, opts)
  end

  @doc """
  Register your own agent on the real A2A network -- makes it discoverable and invokable by
  others, earning you revenue when it's invoked. Requires the real sk_fd_... account_key,
  not the fd_live_ api_key used above.
  """
  def register_agent(client, agent_slug, capabilities, opts \\ [])

  def register_agent(%__MODULE__{account_key: nil}, _agent_slug, _capabilities, _opts),
    do: raise("register_agent/4 requires an account_key (a real sk_fd_... key)")

  def register_agent(%__MODULE__{account_key: account_key, api_base: api_base}, agent_slug, capabilities, opts) do
    A2A.register_agent(api_base, account_key, agent_slug, capabilities, opts)
  end

  @doc "Removes an agent you registered. Requires the same real sk_fd_... account_key."
  def delete_agent(%__MODULE__{account_key: nil}, _agent_slug),
    do: raise("delete_agent/2 requires an account_key (a real sk_fd_... key)")

  def delete_agent(%__MODULE__{account_key: account_key, api_base: api_base}, agent_slug) do
    A2A.delete_agent(api_base, account_key, agent_slug)
  end

  @doc """
  Invoke another agent on the real A2A network. Requires the real sk_fd_... account_key.
  Enqueues only -- poll the real result with a2a_poll_result/2 using the returned invoke id.
  """
  def a2a_invoke(client, target_agent, payload, opts \\ [])

  def a2a_invoke(%__MODULE__{account_key: nil}, _target_agent, _payload, _opts),
    do: raise("a2a_invoke/4 requires an account_key (a real sk_fd_... key)")

  def a2a_invoke(%__MODULE__{account_key: account_key, api_base: api_base}, target_agent, payload, opts) do
    A2A.invoke(api_base, account_key, target_agent, payload, opts)
  end

  @doc "Polls for a real A2A invocation's result using the id returned by a2a_invoke/4."
  def a2a_poll_result(%__MODULE__{account_key: nil}, _invoke_id),
    do: raise("a2a_poll_result/2 requires an account_key (a real sk_fd_... key)")

  def a2a_poll_result(%__MODULE__{account_key: account_key, api_base: api_base}, invoke_id) do
    A2A.poll_result(api_base, account_key, invoke_id)
  end
end
