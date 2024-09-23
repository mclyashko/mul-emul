defmodule Loader do
  defstruct memory_size: 0, program: [%{}]

  @memory_size 36

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
        instructions =
          file_contents
          |> String.split("\n")
          |> Enum.map(&parse_instruction/1)

        instructions

      {:error, reason} ->
        raise "Error loading program from file #{file_path}: #{reason}"
    end
  end

  defp parse_instruction(line) do
    case String.split(line) do
      ["IF", addr1, addr2] -> {:if, String.to_integer(addr1), String.to_integer(addr2)}
      ["SI", addr1, addr2] -> {:store_init, String.to_integer(addr1), String.to_integer(addr2)}
      ["SFR", reg1, reg2] -> {:store_from_reg, parse_reg(reg1), parse_reg(reg2)}
      ["LI", reg1, addr1] -> {:load_init, parse_reg(reg1), String.to_integer(addr1)}
      ["LFR", reg1, reg2] -> {:load_from_reg, parse_reg(reg1), parse_reg(reg2)}
      ["ADD", reg1, reg2] -> {:add, parse_reg(reg1), parse_reg(reg2)}
      ["SUB", reg1, reg2] -> {:sub, parse_reg(reg1), parse_reg(reg2)}
      ["GOTO", addr1] -> {:goto, String.to_integer(addr1)}
      ["HALT"] -> {:halt}
      _ -> raise "Unknown instruction: #{line}}"
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
end

Loader.load("program.em")
|> Loader.execute()
