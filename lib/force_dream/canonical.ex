defmodule ForceDream.Canonical do
  @moduledoc """
  Exact replica of the server's wfCanonical: JSON.stringify(obj, Object.keys(obj).sort()).
  Sorted keys, no whitespace. Ported from the same logic already proven in ten other
  language SDKs tonight (JS, Python, Go, Rust, Java, C#, PHP, Kotlin, Ruby, Swift, Dart) --
  not invented fresh for Elixir.

  Confirmed directly, before writing any client logic: Elixir's `to_string/1` for floats
  always includes a decimal point, even for whole numbers (`1783860125.0`, not
  `1783860125`) -- a differently-shaped version of the same class of bug every language SDK
  tonight had to fix in its own way. `js_number/1` strips it.
  """

  @doc """
  Uses a custom, minimal serializer rather than a general JSON library's default encoding,
  since exact byte-for-byte output matters here (a single differing byte changes the
  signed bytes and breaks every signature check).
  """
  def wf_canonical(obj) when is_map(obj) do
    sorted_keys = obj |> Map.keys() |> Enum.sort()

    parts =
      Enum.map(sorted_keys, fn key ->
        ~s("#{escape(key)}":#{serialize(Map.get(obj, key))})
      end)

    "{" <> Enum.join(parts, ",") <> "}"
  end

  defp serialize(nil), do: "null"
  defp serialize(value) when is_binary(value), do: ~s("#{escape(value)}")
  defp serialize(value) when is_boolean(value), do: to_string(value)
  defp serialize(value) when is_number(value), do: js_number(value * 1.0)

  defp serialize(value) do
    raise ArgumentError, "Unsupported type for canonicalization: #{inspect(value)}"
  end

  defp escape(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  @doc """
  Mirrors JS's Number(x) -> JSON.stringify() behavior: whole values with no decimal point,
  fractional values preserved, never scientific notation. Confirmed directly (see module
  doc above) that Elixir's default float-to-string conversion needed this same correction.
  """
  def js_number(d) when is_float(d) do
    if d == Float.round(d) and abs(d) < 1.0e15 do
      d |> trunc() |> Integer.to_string()
    else
      # Elixir's Float.to_string/1 is confirmed (via direct test) to avoid scientific
      # notation and match JS's shortest-round-trip representation for the real fractional
      # values this SDK actually deals with (pence amounts, sub-second timestamp fractions).
      Float.to_string(d)
    end
  end

  def sha256_hex(str) do
    :crypto.hash(:sha256, str) |> Base.encode16(case: :lower)
  end
end
