defmodule OKTest do
  use ExUnit.Case
  import OK, only: [
    ~>>: 2, success: 1, failure: 1, 
    map: 2, tee: 2, try_catch: 2, found: 2, 
    tag_error: 2, tag_error: 3, tag_error: 4,
    tag: 2, tag: 3
  ]
  doctest OK

  test "try a chain of operations" do
    result = OK.ok_with do
      a <- safe_div(8, 2)
      _ <- safe_div(a, 2)
    end
    assert result == {:ok, 2}
  end

  test "modify an error" do
    result = OK.ok_with do
      a <- safe_div(8, 2)
      _ <- safe_div(a, 0)
    else
      :other ->
        {:ok, :bob}
      :zero_division ->
        failure(:inf)
    end
    assert result == {:error, :inf}
  end

  test "pass through an error with else block present" do
    result = OK.ok_with do
      a <- safe_div(8, 2)
      _ <- safe_div(a, 0)
    else
      :other ->
        {:ok, :bob}
    end
    assert result == {:error, :zero_division}
  end

  test "try last operation failure" do
    result = OK.ok_with do
      a <- safe_div(8, 2)
      _ <- safe_div(a, 0)
    end
    assert result == {:error, :zero_division}
  end

  test "try first operation failure" do
    result = OK.ok_with do
      a <- safe_div(8, 0)
      _ <- safe_div(a, 2)
    end
    assert result == {:error, :zero_division}
  end

  test "try normal code within block" do
    result = OK.ok_with do
      a <- safe_div(6, 2)
      b = a + 1
      safe_div(b, 2)
    end
    assert result == {:ok, 2}
  end

  test "primitives as final operation - ok literal" do
    result = OK.ok_with do
      a <- safe_div(8, 2)
      b <- safe_div(a, 2)
      {:ok, b}
    end
    assert result == {:ok, 2}
  end

  test "primitives as final operation - ok literal func" do
    result = OK.ok_with do
      a <- safe_div(8, 2)
      b <- safe_div(a, 2)
      {:ok, a + b}
    end
    assert result == {:ok, 6}
  end

  test "primitives as final operation - OK.success literal" do
    result = OK.ok_with do
      a <- safe_div(8, 2)
      b <- safe_div(a, 2)
      # {:ok, a + b}
      # OK.success a + b
      OK.success b
    end
    assert result == {:ok, 2}
  end

  test "primitives as final operation - OK.success func" do
    result = OK.ok_with do
      a <- safe_div(8, 2)
      b <- safe_div(a, 2)
      OK.success a + b
    end
    assert result == {:ok, 6}
  end

  test "function as final operation - pass" do
    result = OK.ok_with do
      a <- safe_div(8, 2)
      b <- safe_div(a, 2)
      pass_func(b)
    end
    assert result == {:ok, 2.0}
  end

  test "function as final operation - fail" do
    result = OK.ok_with do
      a <- safe_div(8, 2)
      b <- safe_div(a, 2)
      fail_func(b)
    end
    assert result == {:error, 2.0}
  end

  test "test function returning :ok tag instead of tuple - success" do
    ok_only = fn :ok -> :ok; _ -> {:error, :failure} end
    result = OK.ok_with do
      :ok <- ok_only.(:ok)
      a <- safe_div(8, 2)
      _ <- safe_div(a, 2)
    end
    assert result == {:ok, 2.0}
  end

  test "test function returning :ok tag instead of tuple - failure" do
    ok_only = fn :ok -> :ok; _ -> {:error, :failure} end
    result = OK.ok_with do
      :ok <- ok_only.(:error)
      a <- safe_div(8, 2)
      _ <- safe_div(a, 2)
    end
    assert result == {:error, :failure}
  end

  test "test function with flattened error clause - tuple 3" do
    three_tuple_error_func = fn () -> {:error, :type, :failure} end
    result = OK.ok_with do
      a <- safe_div(8, 2)
      _ <- three_tuple_error_func.()
      _ <- safe_div(a, 2)
    end
    assert result == {:error, {:type, :failure}}
  end
  
  test "test function with flattened error clause - tuple 4" do
    four_tuple_error_func = fn () ->  {:error, :type, :sub_type, :failure} end
    result = OK.ok_with do
      a <- safe_div(8, 2)
      _ <- four_tuple_error_func.()
      _ <- safe_div(a, 2)
    end
    assert result == {:error, {:type, :sub_type, :failure}}
  end

  test "will fail to match if the return value is not a result" do
    assert_raise CaseClauseError, fn() ->
      OK.ok_with do
        a <- safe_div(8, 2)
        (fn() -> {:x, a} end).()
      end
    end
  end

  test "will fail to match if the return value of exceptional block is not a result" do
    assert_raise CaseClauseError, fn() ->
      OK.ok_with do
        a <- safe_div(8, 2)
        _ <- safe_div(a, 0)
      else
        :zero_division ->
          :not_a_result
      end
    end
  end

  test "matching on a success case" do
    success(value) = {:ok, :value}
    assert :value == value
  end

  test "matching on a failure case" do
    failure(reason) = {:error, :reason}
    assert :reason == reason
  end

  test "bind passes success value to function" do
    report_func = fn (arg) -> send(self(), arg) end

    OK.bind({:ok, :test_value}, report_func)
    assert_receive :test_value
  end

  test "bind returns replied value" do
    reply_func = fn (_arg) -> {:ok, :reply_ok} end

    result = OK.bind({:ok, :test_value}, reply_func)
    assert {:ok, :reply_ok} == result
  end

  test "bind does not execute function for failure tuple" do
    fail_func = fn (_arg) -> flunk("Should not be called") end

    OK.bind({:error, :error_reason}, fail_func)
  end

  test "bind returns original error" do
    error_func = fn (_arg) -> {:error, :new_error} end

    result = OK.bind({:error, :original_error}, error_func)
    assert {:error, :original_error} == result
  end

  test "bind must only take a function in success case" do
    assert_raise FunctionClauseError, fn ->
      OK.bind({:ok, :test_value}, :no_func)
    end
  end

  test "bind with found function" do
    two_track_sum = fn(a, b) -> {:ok, a + b} end
    search_with_nil_result = fn(_x) -> nil end
    search_with_result = fn(x) -> x end

    result =
      two_track_sum.(20, 40)
      ~>> two_track_sum.(40)
      ~>> (found search_with_nil_result.())
      ~>> two_track_sum.(40)

    assert result == {:error, :not_found}

    result =
      two_track_sum.(20, 40)
      ~>> two_track_sum.(40)
      ~>> (found search_with_result.())
      ~>> two_track_sum.(40)

    assert result == {:ok, 140}
  end

  test "bind with one_track function" do
    two_track_sum = fn(a, b) -> {:ok, a + b} end
    one_track_sum = fn(a, b) -> a + b end

    result =
      20
      |> two_track_sum.(40)
      ~>> two_track_sum.(40)
      ~>> (map one_track_sum.(40))
    assert result == {:ok, 140}
  end

  test "bind with dead_end function" do
    two_track_sum = fn(a, b) -> {:ok, a + b} end
    dead_end_operation = fn(x) -> IO.puts(x) end

    result =
      20
      |> two_track_sum.(40)
      ~>> two_track_sum.(40)
      ~>> (tee dead_end_operation.())
      ~>> two_track_sum.(40)

    assert result == {:ok, 140}
  end

  test "bind with try_catch function" do
    two_track_sum = fn(a, b) -> {:ok, a + b} end
    try_catch_division = fn(a) -> a/0 end

    result =
      20
      |> two_track_sum.(40)
      ~>> two_track_sum.(40)
      ~>> (try_catch try_catch_division.())
      ~>> two_track_sum.(40)

    assert elem(result, 0) == :error
  end

  test "1-tag error macro test" do
    two_track_sum = fn(a, b) -> {:ok, a + b} end
    error_func = fn(a) -> {:error, a} end

    result =
      20
      |> two_track_sum.(40)
      ~>> two_track_sum.(40)
      ~>> (tag_error error_func.(), :tag)
      ~>> two_track_sum.(40)

    assert result == {:error, {:tag, 100}}
  end

  test "2-tag error macro test" do
    two_track_sum = fn(a, b) -> {:ok, a + b} end
    error_func = fn(a) -> {:error, a} end

    result =
      20
      |> two_track_sum.(40)
      ~>> two_track_sum.(40)
      ~>> (tag_error error_func.(), :tag, :sub_tag)
      ~>> two_track_sum.(40)

    assert result == {:error, {:tag, :sub_tag, 100}}
  end

  test "list-tag error macro test" do
    two_track_sum = fn(a, b) -> {:ok, a + b} end
    error_func = fn(a) -> {:error, a} end

    result =
      20
      |> two_track_sum.(40)
      ~>> two_track_sum.(40)
      ~>> (tag_error error_func.(), [:tag1, :tag2, :tag3])
      ~>> two_track_sum.(40)

    assert result == {:error, {:tag1, :tag2, :tag3, 100}}
  end

  test "list-tag macro test" do
    two_track_sum = 
      fn
        ({a, b}, c) -> {:ok, a + b + c} 
        (a, b) -> {:ok, a + b} 
      end
    error_func = fn(a) -> {:error, a} end

    result =
      20
      |>  two_track_sum.(40)
      ~>> two_track_sum.(40)
      ~>> (tag error_func.(), [ok: 10, error: :tag1])
      ~>> two_track_sum.(40)

    assert result == {:error, {:tag1, 100}}

    any = %{"whatever" => %{}}
    result =
      20
      |>  two_track_sum.(40)
      ~>> two_track_sum.(40)
      ~>> (tag two_track_sum.(40), [ok: 10, error: :tag1])
      ~>> (tag two_track_sum.(40), [ok: [any, "ok_tag"], error: :not_used])

    assert result == {:ok, {any, "ok_tag", 190}}
  end

  # These are all used in doc tests
  def double(a) do
    {:ok, 2 * a}
  end

  def x do
    {:ok, 7}
  end

  def decrement() do
    fn (a, b) -> {:ok, a - b} end
  end

  def safe_div(_, 0) do
    {:error, :zero_division}
  end
  def safe_div(a, b) do
    {:ok, a / b}
  end

  def pass_func(x) do
    {:ok, x}
  end

  def fail_func(x) do
    {:error, x}
  end
end
