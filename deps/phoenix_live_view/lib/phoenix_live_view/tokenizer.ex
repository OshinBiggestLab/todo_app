defmodule Phoenix.LiveView.Tokenizer do
  @moduledoc false
  @space_chars ~c"\s\t\f"
  @quote_chars ~c"\"'"
  @stop_chars ~c">/=\r\n" ++ @quote_chars ++ @space_chars

  defmodule ParseError do
    @moduledoc false
    defexception [:file, :line, :column, :description]

    @impl true
    def message(exception) do
      location =
        exception.file
        |> Path.relative_to_cwd()
        |> Exception.format_file_line_column(exception.line, exception.column)

      "#{location} #{exception.description}"
    end

    def code_snippet(source, meta, indentation \\ 0) do
      line_start = max(meta.line - 3, 1)
      line_end = meta.line
      digits = line_end |> Integer.to_string() |> byte_size()
      number_padding = String.duplicate(" ", digits)
      indentation = String.duplicate(" ", indentation)

      source
      |> String.split(["\r\n", "\n"])
      |> Enum.slice((line_start - 1)..(line_end - 1))
      |> Enum.map_reduce(line_start, fn
        expr, line_number when line_number == line_end ->
          arrow = String.duplicate(" ", meta.column - 1) <> "^"
          acc = "#{line_number} | #{indentation}#{expr}\n #{number_padding}| #{arrow}"
          {acc, line_number + 1}

        expr, line_number ->
          line_number_padding = String.pad_leading("#{line_number}", digits)
          {"#{line_number_padding} | #{indentation}#{expr}", line_number + 1}
      end)
      |> case do
        {[], _} ->
          ""

        {snippet, _} ->
          Enum.join(["\n #{number_padding}|" | snippet], "\n")
      end
    end
  end

  def finalize(_tokens, file, {:comment, line, column}, source) do
    message = "expected closing `-->` for comment"
    meta = %{line: line, column: column}
    raise_syntax_error!(message, meta, %{source: source, file: file, indentation: 0})
  end

  def finalize(tokens, _file, _cont, _source) do
    tokens
    |> strip_text_token_fully()
    |> Enum.reverse()
    |> strip_text_token_fully()
  end

  @doc """
  Initiate the Tokenizer state.

  ### Params

  * `indentation` - An integer that indicates the current indentation.
  * `file` - Can be either a file or a string "nofile".
  * `source` - The contents of the file as binary used to be tokenized.
  * `tag_handler` - Tag handler to classify the tags. See `Phoenix.LiveView.TagEngine`
    behaviour.
  """
  def init(indentation, file, source, tag_handler) do
    %{
      file: file,
      column_offset: indentation + 1,
      braces: :enabled,
      context: [],
      source: source,
      indentation: indentation,
      tag_handler: tag_handler
    }
  end

  @doc """
  Tokenize the given text according to the given params.

  ### Params

  * `text` - The content to be tokenized.
  * `meta` - A keyword list with `:line` and `:column`. Both must be integers.
  * `tokens` - A list of tokens.
  * `cont` - An atom that is `:text`, `:style`, or `:script`, or a tuple
    {:comment, line, column}.
  * `state` - The tokenizer state that must be initiated by `Tokenizer.init/4`

  ### Examples

      iex> alias Phoenix.LiveView.Tokenizer

      iex> state =
        Tokenizer.init(indent, file, [text: "<section><div/></section>"], HTMLEngine)

      iex> Tokenizer.tokenize(state)
      {[
         {:close, :tag, "section", %{column: 16, line: 1}},
         {:tag, "div", [], %{column: 10, line: 1, closing: :self}},
         {:tag, "section", [], %{column: 1, line: 1}}
       ], {:text, :enabled}}
  """
  def tokenize(text, meta, tokens, cont, state) do
    line = Keyword.get(meta, :line, 1)
    column = Keyword.get(meta, :column, 1)

    case cont do
      {:text, braces} -> handle_text(text, line, column, [], tokens, %{state | braces: braces})
      :style -> handle_style(text, line, column, [], tokens, state)
      :script -> handle_script(text, line, column, [], tokens, state)
      {:comment, _, _} -> handle_comment(text, line, column, [], tokens, state)
    end
  end

  ## handle_text

  defp handle_text("\r\n" <> rest, line, _column, buffer, acc, state) do
    handle_text(rest, line + 1, state.column_offset, ["\r\n" | buffer], acc, state)
  end

  defp handle_text("\n" <> rest, line, _column, buffer, acc, state) do
    handle_text(rest, line + 1, state.column_offset, ["\n" | buffer], acc, state)
  end

  defp handle_text("<!doctype" <> rest, line, column, buffer, acc, state) do
    handle_doctype(rest, line, column + 9, ["<!doctype" | buffer], acc, state)
  end

  defp handle_text("<!DOCTYPE" <> rest, line, column, buffer, acc, state) do
    handle_doctype(rest, line, column + 9, ["<!DOCTYPE" | buffer], acc, state)
  end

  defp handle_text("<!--" <> rest, line, column, buffer, acc, state) do
    state = update_in(state.context, &[:comment_start | &1])
    handle_comment(rest, line, column + 4, ["<!--" | buffer], acc, state)
  end

  defp handle_text("</" <> rest, line, column, buffer, acc, state) do
    text_to_acc = text_to_acc(buffer, acc, line, column, state.context)
    handle_tag_close(rest, line, column + 2, text_to_acc, %{state | context: []})
  end

  defp handle_text("<" <> rest, line, column, buffer, acc, state) do
    text_to_acc = text_to_acc(buffer, acc, line, column, state.context)
    handle_tag_open(rest, line, column + 1, text_to_acc, %{state | context: []})
  end

  defp handle_text("{" <> rest, line, column, buffer, acc, %{braces: :enabled} = state) do
    text_to_acc = text_to_acc(buffer, acc, line, column, state.context)
    state = put_in(state.context, [])

    case handle_interpolation(rest, line, column + 1, [], 0, state) do
      {:ok, value, new_line, new_column, rest} ->
        acc = [{:body_expr, value, %{line: line, column: column}} | text_to_acc]
        handle_text(rest, new_line, new_column, [], acc, state)

      {:error, message} ->
        meta = %{line: line, column: column}
        raise_syntax_error!(message, meta, state)
    end
  end

  defp handle_text(<<c::utf8, rest::binary>>, line, column, buffer, acc, state) do
    handle_text(rest, line, column + 1, [char_or_bin(c) | buffer], acc, state)
  end

  defp handle_text(<<>>, line, column, buffer, acc, state) do
    ok(text_to_acc(buffer, acc, line, column, state.context), {:text, state.braces})
  end

  ## handle_doctype

  defp handle_doctype(<<?>, rest::binary>>, line, column, buffer, acc, state) do
    handle_text(rest, line, column + 1, [?> | buffer], acc, state)
  end

  defp handle_doctype("\r\n" <> rest, line, _column, buffer, acc, state) do
    handle_doctype(rest, line + 1, state.column_offset, ["\r\n" | buffer], acc, state)
  end

  defp handle_doctype("\n" <> rest, line, _column, buffer, acc, state) do
    handle_doctype(rest, line + 1, state.column_offset, ["\n" | buffer], acc, state)
  end

  defp handle_doctype(<<c::utf8, rest::binary>>, line, column, buffer, acc, state) do
    handle_doctype(rest, line, column + 1, [char_or_bin(c) | buffer], acc, state)
  end

  defp handle_doctype(<<>>, line, column, _buffer, _acc, state) do
    raise_syntax_error!(
      "unexpected end of string inside tag",
      %{line: line, column: column},
      state
    )
  end

  ## handle_script

  defp handle_script("</script>" <> rest, line, column, buffer, acc, state) do
    acc = [
      {:close, :tag, "script", %{line: line, column: column, inner_location: {line, column}}}
      | text_to_acc(buffer, acc, line, column, [])
    ]

    handle_text(rest, line, column + 9, [], acc, state)
  end

  defp handle_script("\r\n" <> rest, line, _column, buffer, acc, state) do
    handle_script(rest, line + 1, state.column_offset, ["\r\n" | buffer], acc, state)
  end

  defp handle_script("\n" <> rest, line, _column, buffer, acc, state) do
    handle_script(rest, line + 1, state.column_offset, ["\n" | buffer], acc, state)
  end

  defp handle_script(<<c::utf8, rest::binary>>, line, column, buffer, acc, state) do
    handle_script(rest, line, column + 1, [char_or_bin(c) | buffer], acc, state)
  end

  defp handle_script(<<>>, line, column, buffer, acc, _state) do
    ok(text_to_acc(buffer, acc, line, column, []), :script)
  end

  ## handle_style

  defp handle_style("</style>" <> rest, line, column, buffer, acc, state) do
    acc = [
      {:close, :tag, "style", %{line: line, column: column, inner_location: {line, column}}}
      | text_to_acc(buffer, acc, line, column, [])
    ]

    handle_text(rest, line, column + 9, [], acc, state)
  end

  defp handle_style("\r\n" <> rest, line, _column, buffer, acc, state) do
    handle_style(rest, line + 1, state.column_offset, ["\r\n" | buffer], acc, state)
  end

  defp handle_style("\n" <> rest, line, _column, buffer, acc, state) do
    handle_style(rest, line + 1, state.column_offset, ["\n" | buffer], acc, state)
  end

  defp handle_style(<<c::utf8, rest::binary>>, line, column, buffer, acc, state) do
    handle_style(rest, line, column + 1, [char_or_bin(c) | buffer], acc, state)
  end

  defp handle_style(<<>>, line, column, buffer, acc, _state) do
    ok(text_to_acc(buffer, acc, line, column, []), :style)
  end

  ## handle_comment

  defp handle_comment(rest, line, column, buffer, acc, state) do
    case handle_comment(rest, line, column, buffer, state) do
      {:text, rest, line, column, buffer} ->
        state = update_in(state.context, &[:comment_end | &1])
        handle_text(rest, line, column, buffer, acc, state)

      {:ok, line_end, column_end, buffer} ->
        acc = text_to_acc(buffer, acc, line_end, column_end, state.context)
        # We do column - 4 to point to the opening <!--
        ok(acc, {:comment, line, column - 4})
    end
  end

  defp handle_comment("\r\n" <> rest, line, _column, buffer, state) do
    handle_comment(rest, line + 1, state.column_offset, ["\r\n" | buffer], state)
  end

  defp handle_comment("\n" <> rest, line, _column, buffer, state) do
    handle_comment(rest, line + 1, state.column_offset, ["\n" | buffer], state)
  end

  defp handle_comment("-->" <> rest, line, column, buffer, _state) do
    {:text, rest, line, column + 3, ["-->" | buffer]}
  end

  defp handle_comment(<<c::utf8, rest::binary>>, line, column, buffer, state) do
    handle_comment(rest, line, column + 1, [char_or_bin(c) | buffer], state)
  end

  defp handle_comment(<<>>, line, column, buffer, _state) do
    {:ok, line, column, buffer}
  end

  ## handle_tag_open

  defp handle_tag_open(text, line, column, acc, state) do
    case handle_tag_name(text, column, []) do
      {:ok, name, new_column, rest} ->
        meta = %{line: line, column: column - 1, inner_location: nil, tag_name: name}

        case state.tag_handler.classify_type(name) do
          {:error, message} ->
            raise_syntax_error!(message, %{line: line, column: column}, state)

          {type, name} ->
            acc = [{type, name, [], meta} | acc]
            handle_maybe_tag_open_end(rest, line, new_column, acc, state)
        end

      :error ->
        message =
          "expected tag name after <. If you meant to use < as part of a text, use &lt; instead"

        meta = %{line: line, column: column}

        raise_syntax_error!(message, meta, state)
    end
  end

  ## handle_tag_close

  defp handle_tag_close(text, line, column, acc, state) do
    case handle_tag_name(text, column, []) do
      {:ok, name, new_column, ">" <> rest} ->
        meta = %{
          line: line,
          column: column - 2,
          inner_location: {line, column - 2},
          tag_name: name
        }

        case state.tag_handler.classify_type(name) do
          {:error, message} ->
            raise_syntax_error!(message, meta, state)

          {type, name} ->
            acc = [{:close, type, name, meta} | acc]
            handle_text(rest, line, new_column + 1, [], acc, pop_braces(state))
        end

      {:ok, _, new_column, _} ->
        message = "expected closing `>`"
        meta = %{line: line, column: new_column}
        raise_syntax_error!(message, meta, state)

      :error ->
        message = "expected tag name after </"
        meta = %{line: line, column: column}
        raise_syntax_error!(message, meta, state)
    end
  end

  ## handle_tag_name

  defp handle_tag_name(<<c::utf8, _rest::binary>> = text, column, buffer)
       when c in @stop_chars do
    done_tag_name(text, column, buffer)
  end

  defp handle_tag_name(<<c::utf8, rest::binary>>, column, buffer) do
    handle_tag_name(rest, column + 1, [char_or_bin(c) | buffer])
  end

  defp handle_tag_name(<<>>, column, buffer) do
    done_tag_name(<<>>, column, buffer)
  end

  defp done_tag_name(_text, _column, []) do
    :error
  end

  defp done_tag_name(text, column, buffer) do
    {:ok, buffer_to_string(buffer), column, text}
  end

  ## handle_maybe_tag_open_end

  defp handle_maybe_tag_open_end("\r\n" <> rest, line, _column, acc, state) do
    handle_maybe_tag_open_end(rest, line + 1, state.column_offset, acc, state)
  end

  defp handle_maybe_tag_open_end("\n" <> rest, line, _column, acc, state) do
    handle_maybe_tag_open_end(rest, line + 1, state.column_offset, acc, state)
  end

  defp handle_maybe_tag_open_end(<<c::utf8, rest::binary>>, line, column, acc, state)
       when c in @space_chars do
    handle_maybe_tag_open_end(rest, line, column + 1, acc, state)
  end

  defp handle_maybe_tag_open_end("/>" <> rest, line, column, acc, state) do
    acc = normalize_tag(acc, line, column + 2, true, state)
    handle_text(rest, line, column + 2, [], acc, state)
  end

  defp handle_maybe_tag_open_end(">" <> rest, line, column, acc, state) do
    case normalize_tag(acc, line, column + 1, false, state) do
      [{:tag, "script", _, _} | _] = acc ->
        handle_script(rest, line, column + 1, [], acc, state)

      [{:tag, "style", _, _} | _] = acc ->
        handle_style(rest, line, column + 1, [], acc, state)

      acc ->
        handle_text(rest, line, column + 1, [], acc, push_braces(state))
    end
  end

  defp handle_maybe_tag_open_end("{" <> rest, line, column, acc, state) do
    handle_root_attribute(rest, line, column + 1, acc, state)
  end

  defp handle_maybe_tag_open_end(<<>>, line, column, _acc, state) do
    message = ~S"""
    expected closing `>` or `/>`

    Make sure the tag is properly closed. This may happen if there
    is an EEx interpolation inside a tag, which is not supported.
    For instance, instead of

        <div id="<%= @id %>">Content</div>

    do

        <div id={@id}>Content</div>

    If @id is nil or false, then no attribute is sent at all.

    Inside {...} you can place any Elixir expression. If you want
    to interpolate in the middle of an attribute value, instead of

        <a class="foo bar <%= @class %>">Text</a>

    you can pass an Elixir string with interpolation:

        <a class={"foo bar #{@class}"}>Text</a>
    """

    raise_syntax_error!(message, %{line: line, column: column}, state)
  end

  defp handle_maybe_tag_open_end(text, line, column, acc, state) do
    handle_attribute(text, line, column, acc, state)
  end

  ## handle_attribute

  defp handle_attribute(text, line, column, acc, state) do
    case handle_attr_name(text, column, []) do
      {:ok, name, new_column, rest} ->
        attr_meta = %{line: line, column: column}
        {text, line, column, value} = handle_maybe_attr_value(rest, line, new_column, state)
        acc = put_attr(acc, name, attr_meta, value)

        state =
          if name == "phx-no-curly-interpolation" and state.braces == :enabled and
               not script_or_style?(acc) do
            %{state | braces: 0}
          else
            state
          end

        handle_maybe_tag_open_end(text, line, column, acc, state)

      {:error, message, column} ->
        meta = %{line: line, column: column}
        raise_syntax_error!(message, meta, state)
    end
  end

  defp script_or_style?([{:tag, name, _, _} | _]) when name in ~w(script style), do: true
  defp script_or_style?(_), do: false

  ## handle_root_attribute

  defp handle_root_attribute(text, line, column, acc, state) do
    case handle_interpolation(text, line, column, [], 0, state) do
      {:ok, value, new_line, new_column, rest} ->
        meta = %{line: line, column: column}
        acc = put_attr(acc, :root, meta, {:expr, value, meta})
        handle_maybe_tag_open_end(rest, new_line, new_column, acc, state)

      {:error, message} ->
        # We do column - 1 to point to the opening {
        meta = %{line: line, column: column - 1}
        raise_syntax_error!(message, meta, state)
    end
  end

  ## handle_attr_name

  defp handle_attr_name(<<c::utf8, _rest::binary>>, column, _buffer)
       when c in @quote_chars do
    {:error, "invalid character in attribute name: #{<<c>>}", column}
  end

  defp handle_attr_name(<<c::utf8, _rest::binary>>, column, [])
       when c in @stop_chars do
    {:error, "expected attribute name", column}
  end

  defp handle_attr_name(<<c::utf8, _rest::binary>> = text, column, buffer)
       when c in @stop_chars do
    {:ok, buffer_to_string(buffer), column, text}
  end

  defp handle_attr_name(<<c::utf8, rest::binary>>, column, buffer) do
    handle_attr_name(rest, column + 1, [char_or_bin(c) | buffer])
  end

  defp handle_attr_name(<<>>, column, _buffer) do
    {:error, "unexpected end of string inside tag", column}
  end

  ## handle_maybe_attr_value

  defp handle_maybe_attr_value("\r\n" <> rest, line, _column, state) do
    handle_maybe_attr_value(rest, line + 1, state.column_offset, state)
  end

  defp handle_maybe_attr_value("\n" <> rest, line, _column, state) do
    handle_maybe_attr_value(rest, line + 1, state.column_offset, state)
  end

  defp handle_maybe_attr_value(<<c::utf8, rest::binary>>, line, column, state)
       when c in @space_chars do
    handle_maybe_attr_value(rest, line, column + 1, state)
  end

  defp handle_maybe_attr_value("=" <> rest, line, column, state) do
    handle_attr_value_begin(rest, line, column + 1, state)
  end

  defp handle_maybe_attr_value(text, line, column, _state) do
    {text, line, column, nil}
  end

  ## handle_attr_value_begin

  defp handle_attr_value_begin("\r\n" <> rest, line, _column, state) do
    handle_attr_value_begin(rest, line + 1, state.column_offset, state)
  end

  defp handle_attr_value_begin("\n" <> rest, line, _column, state) do
    handle_attr_value_begin(rest, line + 1, state.column_offset, state)
  end

  defp handle_attr_value_begin(<<c::utf8, rest::binary>>, line, column, state)
       when c in @space_chars do
    handle_attr_value_begin(rest, line, column + 1, state)
  end

  defp handle_attr_value_begin("\"" <> rest, line, column, state) do
    handle_attr_value_quote(rest, ?", line, column + 1, [], state)
  end

  defp handle_attr_value_begin("'" <> rest, line, column, state) do
    handle_attr_value_quote(rest, ?', line, column + 1, [], state)
  end

  defp handle_attr_value_begin("{" <> rest, line, column, state) do
    handle_attr_value_as_expr(rest, line, column + 1, state)
  end

  defp handle_attr_value_begin(_text, line, column, state) do
    message =
      "invalid attribute value after `=`. Expected either a value between quotes " <>
        "(such as \"value\" or \'value\') or an Elixir expression between curly braces (such as `{expr}`)"

    meta = %{line: line, column: column}
    raise_syntax_error!(message, meta, state)
  end

  ## handle_attr_value_quote

  defp handle_attr_value_quote("\r\n" <> rest, delim, line, _column, buffer, state) do
    column = state.column_offset
    handle_attr_value_quote(rest, delim, line + 1, column, ["\r\n" | buffer], state)
  end

  defp handle_attr_value_quote("\n" <> rest, delim, line, _column, buffer, state) do
    column = state.column_offset
    handle_attr_value_quote(rest, delim, line + 1, column, ["\n" | buffer], state)
  end

  defp handle_attr_value_quote(<<delim, rest::binary>>, delim, line, column, buffer, _state) do
    value = buffer_to_string(buffer)
    {rest, line, column + 1, {:string, value, %{delimiter: delim}}}
  end

  defp handle_attr_value_quote(<<c::utf8, rest::binary>>, delim, line, column, buffer, state) do
    handle_attr_value_quote(rest, delim, line, column + 1, [char_or_bin(c) | buffer], state)
  end

  defp handle_attr_value_quote(<<>>, delim, line, column, _buffer, state) do
    message = """
    expected closing `#{<<delim>>}` for attribute value

    Make sure the attribute is properly closed. This may also happen if
    there is an EEx interpolation inside a tag, which is not supported.
    Instead of

        <div <%= @some_attributes %>>
        </div>

    do

        <div {@some_attributes}>
        </div>

    Where @some_attributes must be a keyword list or a map.
    """

    meta = %{line: line, column: column}
    raise_syntax_error!(message, meta, state)
  end

  ## handle_attr_value_as_expr

  defp handle_attr_value_as_expr(text, line, column, state) do
    case handle_interpolation(text, line, column, [], 0, state) do
      {:ok, value, new_line, new_column, rest} ->
        {rest, new_line, new_column, {:expr, value, %{line: line, column: column}}}

      {:error, message} ->
        # We do column - 1 to point to the opening {
        meta = %{line: line, column: column - 1}
        raise_syntax_error!(message, meta, state)
    end
  end

  ## handle_interpolation

  defp handle_interpolation("\r\n" <> rest, line, _column, buffer, braces, state) do
    handle_interpolation(rest, line + 1, state.column_offset, ["\r\n" | buffer], braces, state)
  end

  defp handle_interpolation("\n" <> rest, line, _column, buffer, braces, state) do
    handle_interpolation(rest, line + 1, state.column_offset, ["\n" | buffer], braces, state)
  end

  defp handle_interpolation("}" <> rest, line, column, buffer, 0, _state) do
    value = buffer_to_string(buffer)
    {:ok, value, line, column + 1, rest}
  end

  defp handle_interpolation(~S(\}) <> rest, line, column, buffer, braces, state) do
    handle_interpolation(rest, line, column + 2, [~S(\}) | buffer], braces, state)
  end

  defp handle_interpolation(~S(\{) <> rest, line, column, buffer, braces, state) do
    handle_interpolation(rest, line, column + 2, [~S(\{) | buffer], braces, state)
  end

  defp handle_interpolation("}" <> rest, line, column, buffer, braces, state) do
    handle_interpolation(rest, line, column + 1, ["}" | buffer], braces - 1, state)
  end

  defp handle_interpolation("{" <> rest, line, column, buffer, braces, state) do
    handle_interpolation(rest, line, column + 1, ["{" | buffer], braces + 1, state)
  end

  defp handle_interpolation(<<c::utf8, rest::binary>>, line, column, buffer, braces, state) do
    handle_interpolation(rest, line, column + 1, [char_or_bin(c) | buffer], braces, state)
  end

  defp handle_interpolation(<<>>, _line, _column, _buffer, _braces, _state) do
    {:error,
     """
     expected closing `}` for expression

     In case you don't want `{` to begin a new interpolation, \
     you may write it using `&lbrace;` or using `<%= "{" %>`\
     """}
  end

  ## helpers

  @compile {:inline, ok: 2, char_or_bin: 1}
  defp ok(acc, cont), do: {acc, cont}

  defp char_or_bin(c) when c <= 127, do: c
  defp char_or_bin(c), do: <<c::utf8>>

  defp buffer_to_string(buffer) do
    IO.iodata_to_binary(Enum.reverse(buffer))
  end

  defp text_to_acc(buffer, acc, line, column, context)

  defp text_to_acc([], acc, _line, _column, _context),
    do: acc

  defp text_to_acc(buffer, acc, line, column, context) do
    meta = %{line_end: line, column_end: column}

    meta =
      if context == [] do
        meta
      else
        Map.put(meta, :context, trim_context(context))
      end

    [{:text, buffer_to_string(buffer), meta} | acc]
  end

  defp trim_context([:comment_end, :comment_start | [_ | _] = rest]), do: trim_context(rest)
  defp trim_context(rest), do: Enum.reverse(rest)

  defp push_braces(%{braces: :enabled} = state), do: state
  defp push_braces(%{braces: braces} = state), do: %{state | braces: braces + 1}

  defp pop_braces(%{braces: :enabled} = state), do: state
  defp pop_braces(%{braces: 1} = state), do: %{state | braces: :enabled}
  defp pop_braces(%{braces: braces} = state), do: %{state | braces: braces - 1}

  defp put_attr([{type, name, attrs, meta} | acc], attr, attr_meta, value) do
    attrs = [{attr, value, attr_meta} | attrs]
    [{type, name, attrs, meta} | acc]
  end

  defp normalize_tag([{type, name, attrs, meta} | acc], line, column, self_close?, state) do
    attrs = Enum.reverse(attrs)
    meta = %{meta | inner_location: {line, column}}

    meta =
      cond do
        type == :tag and state.tag_handler.void?(name) -> Map.put(meta, :closing, :void)
        self_close? -> Map.put(meta, :closing, :self)
        true -> meta
      end

    [{type, name, attrs, meta} | acc]
  end

  defp strip_text_token_fully(tokens) do
    with [{:text, text, _} | rest] <- tokens,
         "" <- String.trim_leading(text) do
      strip_text_token_fully(rest)
    else
      _ -> tokens
    end
  end

  defp raise_syntax_error!(message, meta, state) do
    raise ParseError,
      file: state.file,
      line: meta.line,
      column: meta.column,
      description: message <> ParseError.code_snippet(state.source, meta, state.indentation)
  end
end
