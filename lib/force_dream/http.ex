defmodule ForceDream.Http do
  @moduledoc """
  Thin wrapper over Erlang/OTP's built-in `:httpc` (via `:inets`) -- no external HTTP Hex
  package needed. Uses `Jason` (the real, standard Elixir JSON library -- Elixir's own
  standard library has no built-in JSON encoder/decoder) for encoding/decoding.

  Calls `Application.ensure_all_started/1` for `:inets` and `:ssl` defensively on first use
  (idempotent -- safe to call repeatedly) rather than relying on the caller to have started
  them via a supervision tree, since this SDK may be invoked from a plain script or IEx
  session as well as a full Mix application.
  """

  defmodule Result do
    @moduledoc false
    defstruct [:status, :json]
  end

  defp ensure_started do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)
    :ok
  end

  def get(url, bearer \\ nil) do
    ensure_started()
    headers = auth_headers(bearer)
    {:ok, {{_, status, _}, _resp_headers, body}} =
      :httpc.request(:get, {String.to_charlist(url), headers}, [], body_format: :binary)

    json = safe_decode(body)

    if status < 200 or status >= 300 do
      raise "GET #{url} -> HTTP #{status}: #{body}"
    end

    json
  end

  def post(url, body, bearer \\ nil) do
    ensure_started()
    headers = auth_headers(bearer)
    encoded = Jason.encode!(body)

    {:ok, {{_, status, _}, _resp_headers, resp_body}} =
      :httpc.request(
        :post,
        {String.to_charlist(url), headers, ~c"application/json", encoded},
        [],
        body_format: :binary
      )

    json = safe_decode(resp_body)

    if status < 200 or status >= 300 do
      raise "POST #{url} -> HTTP #{status}: #{resp_body}"
    end

    json
  end

  @doc """
  Returns the real status alongside the body without raising on a non-2xx status -- used
  where the caller needs to inspect the real status itself (invoke's 401 handling,
  delete-agent's real 404/403/200), matching the {status, json} pattern already used in
  several other SDKs tonight.
  """
  def get_result(url, bearer \\ nil) do
    ensure_started()
    headers = auth_headers(bearer)
    {:ok, {{_, status, _}, _resp_headers, body}} =
      :httpc.request(:get, {String.to_charlist(url), headers}, [], body_format: :binary)

    %Result{status: status, json: safe_decode(body)}
  end

  def post_result(url, body, bearer \\ nil) do
    ensure_started()
    headers = auth_headers(bearer)
    encoded = Jason.encode!(body)

    {:ok, {{_, status, _}, _resp_headers, resp_body}} =
      :httpc.request(
        :post,
        {String.to_charlist(url), headers, ~c"application/json", encoded},
        [],
        body_format: :binary
      )

    %Result{status: status, json: safe_decode(resp_body)}
  end

  defp auth_headers(nil), do: []
  defp auth_headers(bearer), do: [{~c"Authorization", String.to_charlist("Bearer #{bearer}")}]

  defp safe_decode(body) when byte_size(body) == 0, do: %{}

  defp safe_decode(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{}
    end
  end
end
