defmodule OK do
  @moduledoc """
  The `OK` module enables clean and expressive error handling when coding with
  idiomatic `:ok`/`:error` tuples. We've included many examples in the function
  docs here, but you can also check out the
  [README](https://github.com/CrowdHailer/OK/blob/master/README.md) for more
  details and usage.

  Feel free to [open an issue](https://github.com/CrowdHailer/OK/issues) for
  any questions that you have.
  """

  @doc """
  Takes a result tuple and a next function.
  If the result tuple is tagged as a success then its value will be passed to the next function.
  If the tag is failure then the next function is skipped.

  ## Examples

      iex> OK.bind({:ok, 2}, fn (x) -> {:ok, 2 * x} end)
      {:ok, 4}

      iex> OK.bind({:error, :some_reason}, fn (x) -> {:ok, 2 * x} end)
      {:error, :some_reason}
  """
  def bind({:ok, value}, func) when is_function(func, 1), do: func.(value)
  def bind(failure = {:error, _reason}, _func), do: failure

  @doc """
  Wraps a value as a successful result tuple.

  ## Examples

      iex> OK.success(:value)
      {:ok, :value}
  """
  defmacro success(value) do
    quote do
      {:ok, unquote(value)}
    end
  end
  @doc """
  Creates a failed result tuple with the given reason.

  ## Examples

      iex> OK.failure("reason")
      {:error, "reason"}
  """
  defmacro failure(reason) do
    quote do
      {:error, unquote(reason)}
    end
  end

  @doc """
  Require a variable not to be nil.

  Optionally provide a reason why variable is required.

  ## Example

      iex> OK.required(:some)
      {:ok, :some}

      iex> OK.required(nil)
      {:error, :value_required}

      iex> OK.required(Map.get(%{}, :port), :port_number_required)
      {:error, :port_number_required}
  """
  def required(value, reason \\ :value_required)
  def required(nil, reason), do: {:error, reason}
  def required(value, _reason), do: {:ok, value}

  @doc """
  The OK result pipe operator `~>>`, or result monad bind operator, is similar
  to Elixir's native `|>` except it is used within happy path. It takes the
  value out of an `{:ok, value}` tuple and passes it as the first argument to
  the function call on the right.

  It can be used in several ways.

  Pipe to a local call.<br />
  _(This is equivalent to calling `double(5)`)_

      iex> {:ok, 5} ~>> double()
      {:ok, 10}

  Pipe to a remote call.<br />
  _(This is equivalent to calling `OKTest.double(5)`)_

      iex> {:ok, 5} ~>> OKTest.double()
      {:ok, 10}

      iex> {:ok, 5} ~>> __MODULE__.double()
      {:ok, 10}

  Pipe with extra arguments.<br />
  _(This is equivalent to calling `safe_div(6, 2)`)_

      iex> {:ok, 6} ~>> safe_div(2)
      {:ok, 3.0}

      iex> {:ok, 6} ~>> safe_div(0)
      {:error, :zero_division}

  It also works with anonymous functions.

      iex> {:ok, 3} ~>> (fn (x) -> {:ok, x + 1} end).()
      {:ok, 4}

      iex> {:ok, 6} ~>> decrement().(2)
      {:ok, 4}

  When an error is returned anywhere in the pipeline, it will be returned.

      iex> {:ok, 6} ~>> safe_div(0) ~>> double()
      {:error, :zero_division}

      iex> {:error, :previous_bad} ~>> safe_div(0) ~>> double()
      {:error, :previous_bad}
  """
  defmacro lhs ~>> rhs do
    {call, line, args} = case rhs do
      {call, line, nil} ->
        {call, line, []}
      {call, line, args} when is_list(args) ->
        {call, line, args}
    end
    quote do
      case unquote(lhs) do
        {:ok, value} ->
          unquote({call, line, [{:value, [], OK} | args]})
        {:error, reason} -> {:error, reason}
          # unquote(lhs)
      end
    end
  end

  @doc """
  Macro which converts a truthy result to {:ok, result} and a falsy result
  to {:error, :not_found}
    request
    ~>> name_not_blank
    ~>> (found name_trim)
  """
  defmacro found(args, func) do
    quote do
      (fn ->
        result = unquote(args) |> unquote(func)
        if result do
          {:ok, result}
        else
          {:error, :not_found}
        end
      end).()
    end
  end

  def found(result) do
    if result do
      {:ok, result}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Macro that will change the error output aplying the list of tags from `tag_list`.
  An input in the form [:tag, :sub_tag] will change {:error, reason} to
  {:error, {:tag, :sub_tag, reason}}.

  Usage
    request
    ~>> validate
    ~>> (tag_error Repo.insert, [:changeset, :user])
  """
  defmacro tag_error(args, func, tag_list) when is_list(tag_list) do
  # defmacro error_tag(args, func) do
    quote do
      (fn ->
        result = unquote(args) |> unquote(func)
        tag_error(result, unquote(tag_list))
      end).()
    end
  end
  defmacro tag_error(args, func, tag) do
    quote do
      (fn ->
        result = unquote(args) |> unquote(func)
        tag_error(result, [unquote(tag)])
      end).()
    end
  end
  defmacro tag_error(args, func, tag, sub_tag) do
    quote do
      (fn ->
        result = unquote(args) |> unquote(func)
        tag_error(result, [unquote(tag), unquote(sub_tag)])
      end).()
    end
  end

  @doc """
  Function that will change the error output aplying the list of tags from `tag_list`.
  An input in the form [:tag, :sub_tag] will change {:error, reason} to
  {:error, :tag, :sub_tag, reason}.

  Usage
    request
    ~>> validate
    ~>> Repo.insert
    |> tag_error(:changeset, :user)
  """
  def tag_error(result, tag_list) when is_list(tag_list) do
    case result do
      {:error, reason} -> {:error, List.to_tuple(tag_list ++ [reason])}
      ok -> ok
    end
  end


  @doc """
  Macro that will change the error output aplying the list of tags from `tag_list`.
  An input in the form [:tag, :sub_tag] will change {:error, reason} to
  {:error, {:tag, :sub_tag, reason}}.

  Usage
    request
    ~>> validate
    ~>> (tag_ok Repo.insert, [:tag01, :tag02])
  """
  defmacro tag_ok(args, func, tag_list) when is_list(tag_list) do
    quote do
      (fn ->
        result = unquote(args) |> unquote(func)
        tag_ok(result, unquote(tag_list))
      end).()
    end
  end
  defmacro tag_ok(args, func, tag) do
    quote do
      (fn ->
        result = unquote(args) |> unquote(func)
        tag_ok(result, [unquote(tag)])
      end).()
    end
  end
  defmacro tag_ok(args, func, tag, sub_tag) do
    quote do
      (fn ->
        result = unquote(args) |> unquote(func)
        tag_ok(result, [unquote(tag), unquote(sub_tag)])
      end).()
    end
  end

  @doc """
  Function that will change the ok output aplying the list of tags from `tag_list`.
  An input in the form [:tag, :sub_tag] will change {:ok, result} to
  {:ok, {:tag, :sub_tag, result}}.

  Usage
    request
    ~>> validate
    ~>> Repo.insert
    |>  tag_ok([:tag01, :tag02])
  """
  def tag_ok(result, tag_list) when is_list(tag_list) do
    case result do
      {:ok, result} -> {:ok, List.to_tuple(tag_list ++ [result])}
      error -> error
    end
  end


  @doc """
  Macro that will change the error output aplying the list of tags from `tag_list`.
  An input in the form [:tag, :sub_tag] will change {:error, reason} to
  {:error, {:tag, :sub_tag, reason}}.

  Usage
    request
    ~>> validate
    ~>> (tag_ok Repo.insert, [:tag01, :tag02])
  """
  defmacro tag(args, func, tag_list) do
    quote do
      (fn ->
        result = unquote(args) |> unquote(func)
        tag(result, unquote(tag_list))
      end).()
    end
  end


  @doc """
  Function that will change the ok output aplying the list of tags from `tag_list`.
  An input in the form [:tag, :sub_tag] will change {:ok, result} to
  {:ok, {:tag, :sub_tag, result}}.

  Usage
    request
    ~>> validate
    ~>> Repo.insert
    |>  tag_ok([:tag01, :tag02])
  """
  def tag(result, [{:ok, ok_list}, {:error, error_list}]) when is_list(ok_list) and is_list(error_list) do
    case result do
      {:ok, result} -> {:ok, List.to_tuple(ok_list ++ [result])}
      {:error, result} -> {:error, List.to_tuple(error_list ++ [result])}
    end
  end
  def tag(result, [{:ok, ok_tag}, {:error, error_list}]) when is_list(error_list), 
    do: tag(result, [{:ok, [ok_tag]}, {:error, error_list}])
  def tag(result, [{:ok, ok_list}, {:error, error_tag}]), 
    do: tag(result, [{:ok, ok_list}, {:error, [error_tag]}])
  
  @doc """
  Macro which always changes the output from functions that do not return
  {:ok/:error, } tagged tuples to a success two-track function output.
  Usage along side ~>> operator can be as follows:
    request
    ~>> name_not_blank
    ~>> (map name_trim)
  """
  defmacro map(args, func) do
    quote do
      (fn ->
        result = unquote(args) |> unquote(func)
        {:ok, result}
      end).()
    end
  end

  @doc """
  Macro which will call dead-end functions and then return the input back
  as output.
  Usage along side ~>> operator can be as follows:
    request
    ~>> validate
    ~>> (tee update_db)
    ~>> send_email
  """
  defmacro tee(args, func) do
    quote do
      (fn ->
        unquote(args) |> unquote(func)
        {:ok, unquote(args)}
      end).()
    end
  end

  @doc """
  Macro which will change a function which can throw exceptions to a
  two-track output.
  Usage along side ~>> operator can be as follows:
    request
    ~>> validate
    ~>> (tee update_db)
    ~>> (try_catch send_email)
  """
  defmacro try_catch(args, func) do
    quote do
      (fn ->
        try do
          {:ok, unquote(args) |> unquote(func)}
        rescue
          e -> {:error, {:try_catch, e}}
        end
      end).()
    end
  end

  @doc """
  Composes multiple functions similar to Elixir's native `with` construct.

  `OK.ok_with/1` enables more terse and readable expressions however, eliminating
  noise and regaining precious horizontal real estate. This makes `OK.ok_with`
  statements simpler, more readable, and ultimately more maintainable.

  It does this by extracting result tuples when using the `<-` operator.

      iex> OK.ok_with do
      ...>   a <- safe_div(8, 2)
      ...>   b <- safe_div(a, 2)
      ...>   OK.success b
      ...> end
      {:ok, 2.0}

  In above example, the result of each call to `safe_div/2` is an `:ok` tuple
  from which the `<-` extract operator pulls the value and assigns to the
  variable `a`. We then do the same for `b`, and to indicate our return value
  we use the `OK.success/1` macro.

  We could have also written this with a raw `:ok` tuple:

      iex> OK.ok_with do
      ...>   a <- safe_div(8, 2)
      ...>   b <- safe_div(a, 2)
      ...>   {:ok, b}
      ...> end
      {:ok, 2.0}

  Or even this:

      iex> OK.ok_with do
      ...>   a <- safe_div(8, 2)
      ...>   _ <- safe_div(a, 2)
      ...> end
      {:ok, 2.0}

  In addition to this, regular matching using the `=` operator is also available:

      iex> OK.ok_with do
      ...>   a <- safe_div(8, 2)
      ...>   b = 2.0
      ...>   OK.success a + b
      ...> end
      {:ok, 6.0}

  Error tuples are returned from the expression:

      iex> OK.ok_with do
      ...>   a <- safe_div(8, 2)
      ...>   b <- safe_div(a, 0) # error here
      ...>   {:ok, a + b}        # does not execute this line
      ...> end
      {:error, :zero_division}

  `OK.ok_with` also provides `else` blocks where you can pattern match on the _extracted_ error values, which is useful for wrapping or correcting errors:

      iex> OK.ok_with do
      ...>   a <- safe_div(8, 2)
      ...>   b <- safe_div(a, 0) # returns {:error, :zero_division}
      ...>   {:ok, a + b}
      ...> else
      ...>   :zero_division -> OK.failure "You cannot divide by 0."
      ...> end
      {:error, "You cannot divide by 0."}

  ## Combining OK.ok_with and ~>>

  Because the OK.pipe operator (`~>>`) also uses result monads, you can now pipe
  _safely_ within an `OK.ok_with` block:

      iex> OK.ok_with do
      ...>   a <- {:ok, 100}
      ...>        ~>> safe_div(10)
      ...>        ~>> safe_div(5)
      ...>   b <- safe_div(64, 32)
      ...>        ~>> double()
      ...>   OK.success a + b
      ...> end
      {:ok, 6.0}

      iex> OK.ok_with do
      ...>   a <- {:ok, 100}
      ...>        ~>> safe_div(10)
      ...>        ~>> safe_div(0)   # error here
      ...>   b <- safe_div(64, 32)
      ...>        ~>> double()
      ...>   OK.success a + b
      ...> end
      {:error, :zero_division}

  ## Remarks

  Notice that in all of these examples, we know this is a happy path operation
  because we are inside of the `OK.ok_with` block. But it is much more elegant,
  readable and DRY, as it eliminates large numbers of superfluous `:ok` tags
  that would normally be found in native `with` blocks.

  Also, `OK.ok_with` does not have trailing commas on each line. This avoids
  compilation errors when you accidentally forget to add/remove a comma when
  coding.

  Be sure to check out [`ok_test.exs` tests](https://github.com/CrowdHailer/OK/blob/master/test/ok_test.exs)
  for more examples.
  """
  defmacro ok_with(do: {:__block__, _env, lines}) do
    return = bind_match(lines)
    quote do
      case unquote(return) do
        result = {tag, _} when tag in [:ok, :error] -> 
          result
      end
    end
  end
  defmacro ok_with(do: {:__block__, _, normal}, else: exceptional) do
    exceptional_clauses = exceptional ++ (quote do
      reason ->
        {:error, reason}
    end)
    quote do
      unquote(bind_match(normal))
      |> case do
        {:ok, value} -> {:ok, value}
        {:error, reason} ->
          case reason do
            unquote(exceptional_clauses)
          end
          |> case do
            result = {tag, _} when tag in [:ok, :error] ->
              result
          end
      end
    end
  end

  require Logger

  # @doc """
  # DEPRECATED: `OK.try` has been replaced with `OK.ok_with`
  # """
  # defmacro try(do: {:__block__, _env, lines}) do
  #   Logger.warn("DEPRECATED: `OK.try` has been replaced with `OK.ok_with`")
  #   bind_match(lines)
  # end

  defmodule BindError do
    defexception [:return, :lhs, :rhs]

    def message(%{return: return, lhs: lhs, rhs: rhs}) do
      """
      no binding to right hand side value: '#{inspect(return)}'

          Code
            #{lhs} <- #{rhs}

          Expected signature
            #{rhs} :: {:ok, #{lhs}} | {:error, reason}

          Actual values
            #{rhs} :: #{inspect(return)}
      """
    end
  end

  defp bind_match([]) do
    quote do: nil
  end
  defp bind_match([{:<-, env, [left, right]} | rest]) do
    line = Keyword.get(env, :line)
    lhs_string = Macro.to_string(left)
    rhs_string = Macro.to_string(right)
    tmp = quote do: tmp
    
    case lhs_string do
      t when t in ["_", ":ok"] ->
        quote line: line do
          case unquote(tmp) = unquote(right) do
            {:ok, unquote(left)} ->
              unquote(bind_match(rest) || tmp)

            :ok ->
              unquote(bind_match(rest) || {:ok, tmp})

            result = {:error, _} ->
              result
            result = {:error, r1, r2} ->
              {:error, {r1, r2}}
            result = {:error, r1, r2, r3} ->
              {:error, {r1, r2, r3}}
            return ->
              raise %BindError{
                return: return,
                lhs: unquote(lhs_string),
                rhs: unquote(rhs_string)}
          end
        end
      # :ok only case not necessary here
      _ ->
        quote line: line do
          case unquote(tmp) = unquote(right) do
            {:ok, unquote(left)} ->
              unquote(bind_match(rest) || tmp)
            result = {:error, _} ->
              result
            result = {:error, r1, r2} ->
              {:error, {r1, r2}}
            result = {:error, r1, r2, r3} ->
              {:error, {r1, r2, r3}}
            return ->
              raise %BindError{
                return: return,
                lhs: unquote(lhs_string),
                rhs: unquote(rhs_string)}
          end
        end
    end
  end
  defp bind_match([normal | rest]) do
    tmp = quote do: tmp
    quote do
      unquote(tmp) = unquote(normal)
      unquote(bind_match(rest) || tmp)
    end
  end
end
