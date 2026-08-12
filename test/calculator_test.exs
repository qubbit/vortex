defmodule CalculatorTest do
  use ExUnit.Case
  doctest Calculator

  defp eval!(source), do: Calculator.eval!(source)

  describe "literals" do
    test "integers and decimals" do
      assert 42 = eval!("42")
      assert 3.5 = eval!("3.5")
      assert 0 = eval!("0")
    end

    test "surrounding whitespace is ignored" do
      assert 42 = eval!("   42   ")
    end
  end

  describe "operator precedence" do
    test "multiplication binds tighter than addition" do
      assert 7 = eval!("1 + 2 * 3")
      assert 7 = eval!("2 * 3 + 1")
    end

    test "parentheses override precedence" do
      assert 9 = eval!("(1 + 2) * 3")
      assert 1 = eval!("((1))")
    end
  end

  describe "associativity" do
    test "subtraction is left-associative" do
      assert 5 = eval!("10 - 2 - 3")
    end

    test "division is left-associative" do
      assert 5 = eval!("100 / 4 / 5")
    end
  end

  describe "unary minus" do
    test "negates a factor" do
      assert -5 = eval!("-5")
      assert -6 = eval!("2 * -3")
      assert -7 = eval!("-(3 + 4)")
    end
  end

  describe "division" do
    test "stays integral when exact, becomes float otherwise" do
      assert 4 = eval!("12 / 3")
      assert 3.5 = eval!("7 / 2")
    end

    test "division by zero is an error" do
      assert {:error, reason} = Calculator.eval("1 / 0")
      assert reason =~ "division by zero"
    end
  end

  describe "errors" do
    test "a dangling operator fails" do
      assert {:error, _} = Calculator.eval("2 +")
    end

    test "an empty expression fails" do
      assert {:error, _} = Calculator.eval("")
    end

    test "unbalanced parentheses fail" do
      assert {:error, _} = Calculator.eval("(1 + 2")
    end

    test "unexpected trailing input fails" do
      assert {:error, reason} = Calculator.eval("1 2")
      assert reason =~ "line 1"
    end
  end

  describe "larger expressions" do
    test "a mix of everything" do
      assert 5 = eval!("1 + 2 * 3 - 4 / 2")
      assert 5 = eval!("3 * (2 + 1) - 4")
      assert 20 = eval!("(3 + 7) * 4 / 2")
      assert 5.5 = eval!("(3 + 8) / 2")
    end
  end
end
