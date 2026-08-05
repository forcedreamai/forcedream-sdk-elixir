defmodule ForceDream.VerifyResult do
  @moduledoc false
  defstruct [:verified, :task_id, :key_id, :algorithm, :fields_signed, :trustless, :message]
end

defmodule ForceDream.Verify do
  @moduledoc """
  Trustlessly verifies a ForceDream proof's Ed25519 signature entirely client-side.
  ForceDream is never asked whether the proof is valid -- the math decides, locally.

  Uses Erlang/OTP's built-in `:crypto` module (via `erlang-crypto`, confirmed available and
  correct via a real, local generate/sign/verify/tamper-detect round trip before writing any
  client logic here) -- no external Hex package needed for the cryptography itself.
  """

  alias ForceDream.{Canonical, Http, VerifyResult}

  defp build_signable(proof) do
    has_ext = Map.get(proof, "external_cost_hash") != nil

    base = %{
      "task_id" => text_or_nil(Map.get(proof, "task_id")),
      "agent_id" => text_or_nil(Map.get(proof, "agent_id")),
      "input_hash" => text_or_nil(Map.get(proof, "input_hash")),
      "output_hash" => text_or_nil(Map.get(proof, "output_hash")),
      "cost_pence" => number_or_zero(Map.get(proof, "cost_pence")),
      "budget_pence" => number_or_zero(Map.get(proof, "budget_pence")),
      "started_at" => number_or_zero(Map.get(proof, "started_at")),
      "completed_at" => string_value(Map.get(proof, "completed_at"))
    }

    if has_ext do
      base =
        base
        |> Map.put("external_cost_hash", string_value(Map.get(proof, "external_cost_hash")))
        |> Map.put("retrieved_count", number_or_zero(Map.get(proof, "retrieved_count", 0)))

      {base, 10}
    else
      {base, 8}
    end
  end

  defp text_or_nil(v) when is_binary(v), do: v
  defp text_or_nil(_), do: nil

  defp number_or_zero(v) when is_number(v), do: v * 1.0

  defp number_or_zero(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp number_or_zero(_), do: 0.0

  defp string_value(v) when is_binary(v), do: v
  defp string_value(v) when is_number(v), do: Canonical.js_number(v * 1.0)
  defp string_value(_), do: ""

  @doc """
  Extracts the raw 32-byte Ed25519 public key from a real SPKI PEM string. Ed25519 SPKI DER
  has a fixed, constant-length prefix (RFC 8410), so the raw key is reliably the final 32
  bytes of the decoded DER -- the same approach already proven working live in the PHP,
  Swift, and Dart SDKs tonight (Erlang's :crypto, like those languages' crypto libraries,
  takes the raw key only -- confirmed via the same real, local round-trip test above), not
  a hardcoded offset from the start (the class of bug caught in the Go SDK earlier).
  """
  def public_key_bytes_from_pem(pem) do
    body =
      pem
      |> String.replace("-----BEGIN PUBLIC KEY-----", "")
      |> String.replace("-----END PUBLIC KEY-----", "")
      |> String.replace(~r/\s+/, "")

    der = Base.decode64!(body)
    byte_size(der) >= 32 || raise "public_key_bytes_from_pem: invalid PEM/DER"
    binary_part(der, byte_size(der) - 32, 32)
  end

  @doc """
  Exact replica of the server's verifyMerkleInclusion. Each sibling carries its own
  position, so ordering is never derived from leaf_index. Hashing is over concatenated
  HEX STRINGS, not raw bytes -- matching the server exactly. An empty sibling list
  means the root is the leaf digest unchanged (the batch_size == 1 case, which is every
  real proof the platform has emitted to date).
  """
  def verify_merkle_inclusion(leaf_hash, siblings, expected_root) when is_list(siblings) do
    computed =
      Enum.reduce_while(siblings, leaf_hash, fn step, current ->
        case step do
          %{"hash" => h} when is_binary(h) ->
            next =
              if Map.get(step, "position") == "right" do
                Canonical.sha256_hex(current <> h)
              else
                Canonical.sha256_hex(h <> current)
              end

            {:cont, next}

          _ ->
            {:halt, :invalid}
        end
      end)

    computed == expected_root
  end

  def verify_merkle_inclusion(_, _, _), do: false

  def verify_proof(api_base, opts \\ []) do
    task_id = Keyword.get(opts, :task_id)
    proof_input = Keyword.get(opts, :proof)

    proof =
      case proof_input do
        nil ->
          if is_nil(task_id), do: raise(ArgumentError, "Provide task_id or proof")
          data = Http.get("#{api_base}/v1/workforce/proof/#{URI.encode(task_id)}/public")
          proof = Map.get(data, "proof")
          if is_nil(proof), do: raise("proof_not_found")
          proof

        p ->
          p
      end

    key_data = Http.get("#{api_base}/v1/workforce/proof/public-key")
    key_id = Map.get(key_data, "key_id")
    pem = Map.get(key_data, "public_key_pem", "")

    {signable, field_count} = build_signable(proof)
    digest_hex = Canonical.sha256_hex(Canonical.wf_canonical(signable))

    verified =
      try do
        signature_b64 = Map.get(proof, "signature")
        algorithm = Map.get(proof, "algorithm")

        cond do
          is_nil(signature_b64) ->
            false

          algorithm == "Ed25519-batched" ->
            # A batched proof is only as strong as this real double-check: the digest
            # must genuinely be a leaf of the claimed root, verified BEFORE the
            # signature is trusted. The signature is over the ROOT, not the digest.
            root = Map.get(proof, "merkle_root")
            inclusion = Map.get(proof, "inclusion_proof")
            siblings = if is_map(inclusion), do: Map.get(inclusion, "siblings"), else: nil

            if is_binary(root) and root != "" and is_list(siblings) and
                 verify_merkle_inclusion(digest_hex, siblings, root) do
              raw_key_bytes = public_key_bytes_from_pem(pem)
              sig_bytes = Base.decode64!(signature_b64)
              root_bytes = Base.decode16!(root, case: :lower)

              :crypto.verify(:eddsa, :none, root_bytes, sig_bytes, [raw_key_bytes, :ed25519])
            else
              false
            end

          is_nil(algorithm) or algorithm == "Ed25519" ->
            raw_key_bytes = public_key_bytes_from_pem(pem)
            sig_bytes = Base.decode64!(signature_b64)
            digest_bytes = Base.decode16!(digest_hex, case: :lower)

            :crypto.verify(:eddsa, :none, digest_bytes, sig_bytes, [raw_key_bytes, :ed25519])

          true ->
            false
        end
      rescue
        _ -> false
      end

    %VerifyResult{
      verified: verified,
      task_id: Map.get(proof, "task_id"),
      key_id: key_id,
      algorithm: Map.get(proof, "algorithm") || "Ed25519",
      fields_signed: field_count,
      trustless: true,
      message:
        if verified do
          "Signature mathematically verified. This proof was signed by ForceDream and has not been altered."
        else
          "Signature verification FAILED. The proof was altered or not signed by ForceDream."
        end
    }
  end
end
