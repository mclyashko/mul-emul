defmodule Loader do
  defstruct memory_size: 0, program: [%{}]

  @memory_size 64

  def load(file_path) do
    %Loader{
      memory_size: @memory_size,
      program: load_program_from_file(file_path)
    }
  end

  def execute(loader) do
    Emulator.new(loader.memory_size)
    |> Emulator.load_program(loader.program)
    |> Emulator.run()
  end

  defp load_program_from_file(file_path) do
    case File.read(file_path) do
      {:ok, file_contents} ->
        instructions_with_labels =
          file_contents
          |> String.split("\n")
          |> Enum.map(&parse_instruction/1)
          |> Enum.with_index()

        labels =
          instructions_with_labels
          |> Enum.reduce(%{}, fn {instruction, index}, labels ->
            case instruction do
              {:label, label} ->
                Map.put(labels, label, index)

              _ ->
                labels
            end
          end)

        instructions_without_labels =
          instructions_with_labels
          |> Enum.map(fn {instruction, index} ->
            replace_labels(instruction, index, labels)
          end)

        instructions_without_labels

      {:error, reason} ->
        raise "Error loading program from file #{file_path}: #{reason}"
    end
  end

  defp parse_instruction(line) do
    case String.split(line) do
      ["!" <> label] ->
        {:label, label}

      ["IF", addr1, addr2] ->
        case {addr1, addr2} do
          {"!" <> label1, "!" <> label2} -> {:if, label1, label2}
          _ -> {:if, String.to_integer(addr1), String.to_integer(addr2)}
        end

      ["SI", addr1, addr2] ->
        {:store_init, String.to_integer(addr1), String.to_integer(addr2)}

      ["SFR", reg1, reg2] ->
        {:store_from_reg, parse_reg(reg1), parse_reg(reg2)}

      ["LI", reg1, addr1] ->
        {:load_init, parse_reg(reg1), String.to_integer(addr1)}

      ["LFR", reg1, reg2] ->
        {:load_from_reg, parse_reg(reg1), parse_reg(reg2)}

      ["ADD", reg1, reg2] ->
        {:add, parse_reg(reg1), parse_reg(reg2)}

      ["SUB", reg1, reg2] ->
        {:sub, parse_reg(reg1), parse_reg(reg2)}

      ["GOTO", addr1] ->
        case addr1 do
          "!" <> label ->
            {:goto, label}

          _ ->
            {addr1_as_integer, ""} = Integer.parse(addr1)
            {:goto, addr1_as_integer}
        end

      ["HALT"] ->
        {:halt}

      _ ->
        raise "Unknown instruction: #{line}}"
    end
  end

  defp parse_reg(line) do
    case line do
      "A" -> :a
      "B" -> :b
      "C" -> :c
      "D" -> :d
      "E" -> :e
      "IFR" -> :ifreg
      "IR" -> :ir
      "PC" -> :pc
    end
  end

  def replace_labels(instruction, index, labels) do
    case instruction do
      {:if, label1, label2} when is_binary(label1) and is_binary(label2) ->
        {:if, Map.get(labels, label1), Map.get(labels, label2)}

      {:goto, label} when is_binary(label) ->
        {:goto, Map.get(labels, label)}

      {:label, label} when is_binary(label) ->
        {:goto, index + 1}

      _ ->
        instruction
    end
  end
end

Loader.load("program.em")
|> Loader.execute()
