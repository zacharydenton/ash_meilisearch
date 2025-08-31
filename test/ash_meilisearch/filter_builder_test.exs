defmodule AshMeilisearch.FilterBuilderTest do
  use ExUnit.Case, async: true

  alias AshMeilisearch.FilterBuilder

  require Ash.Query

  describe "build_filter/1" do
    test "returns nil for nil input" do
      assert FilterBuilder.build_filter(nil) == nil
    end

    test "handles Ash.Filter struct with relationship field in expression" do
      # Test how the actual filter gets passed to the FilterBuilder from manual reads
      # The filter comes from query options like query: [filter: filter_expr]
      values = ["Value A", "Value B", "Value C"]

      # Build query using a generic resource
      import Ash.Expr

      # Create a mock query structure that mimics Ash.Query.filter behavior
      query = Ash.Query.filter(AshMeilisearch.Test.Post, expr(title in ^values))
      result = FilterBuilder.build_filter(query.filter)

      # Should convert to OR conditions for Meilisearch
      assert result
      assert String.contains?(result, "title")
      assert String.contains?(result, "Value A")
      assert String.contains?(result, "Value B")
      assert String.contains?(result, "Value C")

      # Should be in OR format
      assert String.contains?(result, " OR ")
      assert String.starts_with?(result, "(")
      assert String.ends_with?(result, ")")
    end

    test "handles single value filter" do
      values = ["Single Value"]

      import Ash.Expr

      query = Ash.Query.filter(AshMeilisearch.Test.Post, expr(title in ^values))
      result = FilterBuilder.build_filter(query.filter)

      # Single value should not have OR conditions or parentheses
      assert result
      assert result == ~s(title = "Single Value")
    end

    test "escapes quotes in values" do
      values = [~s(Value with "quotes")]

      import Ash.Expr

      query = Ash.Query.filter(AshMeilisearch.Test.Post, expr(title in ^values))
      result = FilterBuilder.build_filter(query.filter)

      assert result
      assert String.contains?(result, ~s(Value with \\"quotes\\"))
    end

    test "handles equality operator" do
      import Ash.Expr

      query = Ash.Query.filter(AshMeilisearch.Test.Post, expr(title == "Test Title"))
      result = FilterBuilder.build_filter(query.filter)

      assert result == ~s(title = "Test Title")
    end

    test "handles not equal operator" do
      import Ash.Expr

      query = Ash.Query.filter(AshMeilisearch.Test.Post, expr(title != "Test Title"))
      result = FilterBuilder.build_filter(query.filter)

      assert result == ~s(title != "Test Title")
    end

    test "handles greater than operator" do
      import Ash.Expr

      query = Ash.Query.filter(AshMeilisearch.Test.Album, expr(year > 2020))
      result = FilterBuilder.build_filter(query.filter)

      assert result == "year > 2020"
    end

    test "handles greater than or equal operator" do
      import Ash.Expr

      query = Ash.Query.filter(AshMeilisearch.Test.Album, expr(year >= 2020))
      result = FilterBuilder.build_filter(query.filter)

      assert result == "year >= 2020"
    end

    test "handles less than operator" do
      import Ash.Expr

      query = Ash.Query.filter(AshMeilisearch.Test.Album, expr(year < 2020))
      result = FilterBuilder.build_filter(query.filter)

      assert result == "year < 2020"
    end

    test "handles less than or equal operator" do
      import Ash.Expr

      query = Ash.Query.filter(AshMeilisearch.Test.Album, expr(year <= 2020))
      result = FilterBuilder.build_filter(query.filter)

      assert result == "year <= 2020"
    end

    test "handles is_nil operator for null values" do
      import Ash.Expr

      query = Ash.Query.filter(AshMeilisearch.Test.Post, expr(is_nil(content)))
      result = FilterBuilder.build_filter(query.filter)

      assert result == "content IS NULL"
    end

    test "handles is_nil operator for non-null values" do
      import Ash.Expr

      query = Ash.Query.filter(AshMeilisearch.Test.Post, expr(not is_nil(content)))
      result = FilterBuilder.build_filter(query.filter)

      # This should result in IS NOT NULL check for non-null values
      assert result == "content IS NOT NULL"
    end

    test "handles number values" do
      import Ash.Expr

      query = Ash.Query.filter(AshMeilisearch.Test.Album, expr(year == 2021))
      result = FilterBuilder.build_filter(query.filter)

      assert result == "year = 2021"
    end

    test "handles mixed operators with AND" do
      import Ash.Expr

      # Multiple conditions should be joined with AND
      query =
        Ash.Query.filter(
          AshMeilisearch.Test.Album,
          expr(year > 2020 and title == "Test Album")
        )

      result = FilterBuilder.build_filter(query.filter)

      assert result == ~s(year > 2020 AND title = "Test Album")
    end

    test "handles mixed AND/OR" do
      import Ash.Expr

      # Ash reorders this expression, putting the OR part first
      query =
        Ash.Query.filter(
          AshMeilisearch.Test.Album,
          expr(not is_nil(description) and (year > 2020 or title == "Test Album"))
        )

      result = FilterBuilder.build_filter(query.filter)

      # Ash puts the OR expression first, then the NOT condition
      assert result ==
               ~s{(year > 2020 OR title = "Test Album") AND description IS NOT NULL}
    end

    test "handles OR with nested AND" do
      import Ash.Expr

      # Test A or (B and C) to ensure proper parentheses
      query =
        Ash.Query.filter(
          AshMeilisearch.Test.Album,
          expr(is_nil(description) or (year > 2020 and title == "Test Album"))
        )

      result = FilterBuilder.build_filter(query.filter)

      # Should have parentheses around the AND part
      assert result == ~s{(year > 2020 AND title = "Test Album") OR description IS NULL}
    end

    test "handles complex multi-level nested expressions" do
      import Ash.Expr

      # Test deeply nested expression: ((A and B) or (C and D)) and (E or (F and not G))
      query =
        Ash.Query.filter(
          AshMeilisearch.Test.Album,
          expr(
            ((year > 2020 and title == "Album A") or
               (year < 2000 and title == "Album B")) and
              (is_nil(description) or (year >= 2015 and not is_nil(genre)))
          )
        )

      result = FilterBuilder.build_filter(query.filter)

      assert result ==
               ~s{((year > 2020 AND title = "Album A") OR (year < 2000 AND title = "Album B")) AND ((year >= 2015 AND genre IS NOT NULL) OR description IS NULL)}
    end
  end
end
