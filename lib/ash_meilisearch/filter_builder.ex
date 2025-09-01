defmodule AshMeilisearch.FilterBuilder do
  @moduledoc """
  Builds Meilisearch filter strings from Ash.Filter structs.

  Converts Ash filter expressions into Meilisearch-compatible filter strings.

  ## Supported Operators

  ### Comparison Operators
  - `==` → `=` (equality)
  - `!=` → `!=` (inequality) 
  - `>` → `>` (greater than)
  - `>=` → `>=` (greater than or equal)
  - `<` → `<` (less than)
  - `<=` → `<=` (less than or equal)

  ### List Operators
  - `in` → multiple OR conditions (e.g., `field = "a" OR field = "b"`)

  ### Existence Operators
  - `is_nil` → `IS NULL`
  - `not is_nil` → `IS NOT NULL`

  ### Logical Operators
  - `and` → `AND` (combines conditions)
  - `or` → `OR` (combines conditions)
  - `not` → negates inner expressions (limited support)

  ## Value Handling
  - Strings are quoted and escaped: `"value"`
  - Numbers are unquoted: `42`
  - Booleans are unquoted: `true`, `false`
  - Null values: `null`
  """

  require Logger

  @doc """
  Converts an Ash.Filter struct to a Meilisearch filter string.

  ## Examples

      # IN operator
      iex> build_filter(ash_filter)
      "(tag.name = \"Comedy\" OR tag.name = \"Horror\")"

      # Equality
      iex> build_filter(ash_filter) 
      "studio.name = \"Universal Studios\""

      # Comparison
      iex> build_filter(ash_filter)
      "duration > 3600"

      # Existence check
      iex> build_filter(ash_filter)
      "director IS NULL"
  """
  def build_filter(nil), do: nil

  def build_filter(%Ash.Filter{} = ash_filter) do
    # Handle Ash.Filter structs by converting to Meilisearch filter string
    ash_filter_to_meilisearch(ash_filter)
  end

  # Format values for Meilisearch filters
  defp format_value(value) when is_binary(value), do: ~s("#{escape_quotes(value)}")
  defp format_value(value) when is_number(value), do: to_string(value)
  defp format_value(value) when is_boolean(value), do: to_string(value)
  defp format_value(nil), do: "null"
  defp format_value(value), do: ~s("#{escape_quotes(to_string(value))}")

  # Escape quotes in string values for Meilisearch
  defp escape_quotes(value) when is_binary(value), do: String.replace(value, "\"", "\\\"")
  defp escape_quotes(value), do: to_string(value)

  # Convert Ash.Filter struct to Meilisearch filter string
  defp ash_filter_to_meilisearch(%Ash.Filter{expression: expression}) do
    # Convert the expression directly rather than using list_predicates
    # which may not preserve NOT wrappers
    convert_expression_to_meilisearch(expression)
  end

  # Convert expression to Meilisearch filter string
  defp convert_expression_to_meilisearch(expression) do
    case expression do
      %Ash.Query.BooleanExpression{op: :and, left: left, right: right} ->
        left_result = convert_expression_to_meilisearch(left)
        right_result = convert_expression_to_meilisearch(right)

        # Add parentheses around OR expressions when they're part of an AND
        left_formatted = if is_or_expression?(left), do: "(#{left_result})", else: left_result
        right_formatted = if is_or_expression?(right), do: "(#{right_result})", else: right_result

        combine_conditions([left_formatted, right_formatted], " AND ")

      %Ash.Query.BooleanExpression{op: :or, left: left, right: right} ->
        left_result = convert_expression_to_meilisearch(left)
        right_result = convert_expression_to_meilisearch(right)

        # Add parentheses around AND expressions when they're part of an OR
        left_formatted = if is_and_expression?(left), do: "(#{left_result})", else: left_result

        right_formatted =
          if is_and_expression?(right), do: "(#{right_result})", else: right_result

        combine_conditions([left_formatted, right_formatted], " OR ")

      # Handle NOT wrapper
      %Ash.Query.Not{expression: inner_expression} ->
        handle_not_operator(inner_expression)

      # Handle direct operators
      predicate when is_struct(predicate) ->
        convert_predicate_to_meilisearch(predicate)

      unknown ->
        Logger.debug("AshMeilisearch.FilterBuilder: Unknown expression type: #{inspect(unknown)}")

        nil
    end
  end

  # Check if an expression is an OR operation that needs parentheses
  defp is_or_expression?(%Ash.Query.BooleanExpression{op: :or}), do: true
  defp is_or_expression?(_), do: false

  # Check if an expression is an AND operation that needs parentheses
  defp is_and_expression?(%Ash.Query.BooleanExpression{op: :and}), do: true
  defp is_and_expression?(_), do: false

  # Helper to combine conditions with proper handling
  defp combine_conditions(conditions, joiner) do
    valid_conditions = Enum.reject(conditions, &is_nil/1)

    case valid_conditions do
      [] -> nil
      [single] -> single
      multiple -> Enum.join(multiple, joiner)
    end
  end

  # Convert individual predicate to Meilisearch condition  
  defp convert_predicate_to_meilisearch(predicate) do
    case predicate do
      %Ash.Query.Operator.In{left: left, right: right} ->
        handle_in_operator(left, right)

      %Ash.Query.Operator.Eq{left: left, right: right} ->
        handle_equality_operator(left, right, "=")

      %Ash.Query.Operator.NotEq{left: left, right: right} ->
        handle_equality_operator(left, right, "!=")

      %Ash.Query.Operator.GreaterThan{left: left, right: right} ->
        handle_comparison_operator(left, right, ">")

      %Ash.Query.Operator.GreaterThanOrEqual{left: left, right: right} ->
        handle_comparison_operator(left, right, ">=")

      %Ash.Query.Operator.LessThan{left: left, right: right} ->
        handle_comparison_operator(left, right, "<")

      %Ash.Query.Operator.LessThanOrEqual{left: left, right: right} ->
        handle_comparison_operator(left, right, "<=")

      %Ash.Query.Operator.IsNil{left: left, right: true} ->
        handle_is_nil_operator(left, true)

      %Ash.Query.Operator.IsNil{left: left, right: false} ->
        handle_is_nil_operator(left, false)

      unsupported ->
        Logger.debug(
          "AshMeilisearch.FilterBuilder: Unsupported predicate type: #{inspect(unsupported.__struct__)}"
        )

        nil
    end
  end

  # Handle NOT operator wrapper
  defp handle_not_operator(inner_expression) do
    case inner_expression do
      %Ash.Query.Operator.IsNil{left: left, right: true} ->
        # NOT is_nil means the field is not null
        handle_is_nil_operator(left, false)

      unsupported ->
        # Log unsupported NOT operations for debugging
        Logger.debug(
          "AshMeilisearch.FilterBuilder: Unsupported NOT operation for: #{inspect(unsupported.__struct__)}"
        )

        nil
    end
  end

  # Handle the In operator
  defp handle_in_operator(left, right) do
    field_name = extract_field_name(left)
    values = extract_values(right)

    case values do
      [] ->
        nil

      [single] ->
        ~s(#{field_name} = "#{escape_quotes(single)}")

      multiple ->
        conditions =
          Enum.map(multiple, fn value -> ~s(#{field_name} = "#{escape_quotes(value)}") end)

        "(#{Enum.join(conditions, " OR ")})"
    end
  end

  # Handle equality and inequality operators  
  defp handle_equality_operator(left, right, operator) do
    field_name = extract_field_name(left)
    value = format_value(right)
    ~s(#{field_name} #{operator} #{value})
  end

  # Handle comparison operators (>, <, >=, <=)
  defp handle_comparison_operator(left, right, operator) do
    field_name = extract_field_name(left)
    value = format_value(right)
    ~s(#{field_name} #{operator} #{value})
  end

  # Handle IsNil operator
  defp handle_is_nil_operator(left, is_nil?) do
    field_name = extract_field_name(left)

    if is_nil? do
      ~s(#{field_name} IS NULL)
    else
      ~s(#{field_name} IS NOT NULL)
    end
  end

  # Extract field name from field reference
  defp extract_field_name(%Ash.Query.Ref{
         relationship_path: relationship_path,
         attribute: attribute
       }) do
    case {relationship_path, attribute} do
      {[], %{name: name}} ->
        to_string(name)

      {[rel], %{name: name}} ->
        "#{rel}.#{name}"

      _ ->
        "unknown_field"
    end
  end

  defp extract_field_name(_other) do
    "unknown_field"
  end

  # Extract values from values reference
  defp extract_values(%MapSet{} = mapset) do
    MapSet.to_list(mapset)
  end

  defp extract_values(values) when is_list(values) do
    values
  end

  defp extract_values(_other) do
    []
  end
end
