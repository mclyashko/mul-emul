defmodule Emulator do
  defstruct memory: %{}, registers: %{a: 0, b: 0, c: 0, d: 0, e: 0, ifreg: 0}, ir: 0, pc: 0

  def new(memory_size) do
    %Emulator{
      memory: Enum.into(0..(memory_size - 1), %{}, fn i -> {i, 0} end),
      registers: %{a: 0, b: 0, c: 0, d: 0, e: 0, ifreg: 0},
      ir: 0,
      pc: 0
    }
  end

  def load_program(emulator, program) do
    encoded_program = encode_program(program)
    indexed_program = Enum.zip(0..(length(program) - 1), encoded_program)
    memory = Enum.into(indexed_program, emulator.memory, fn {i, instr} -> {i, instr} end)
    %Emulator{emulator | memory: memory}
  end

  def run(%Emulator{memory: memory, registers: _registers, ir: _ir, pc: pc} = emulator)
      when pc >= 0 do
    next_ir = memory[pc]
    parsed_next_ir = parse_instruction(next_ir)

    next_emulator =
      case parsed_next_ir do
        {opcode, operand1, operand2} ->
          case opcode do
            :store_init -> store_init(emulator, next_ir, operand1, operand2)
            :store_from_reg -> store_from_reg(emulator, next_ir, operand1, operand2)
            :load_init -> load_init(emulator, next_ir, operand1, operand2)
            :load_from_reg -> load_from_reg(emulator, next_ir, operand1, operand2)
            :add -> add(emulator, next_ir, operand1, operand2)
            :sub -> sub(emulator, next_ir, operand1, operand2)
            :if -> if(emulator, next_ir, operand1, operand2)
            _ -> raise "Unknown opcode"
          end

        {opcode, operand1} ->
          case opcode do
            :goto -> goto(emulator, next_ir, operand1)
            _ -> raise "Unknown opcode"
          end

        {opcode} ->
          case opcode do
            :halt -> halt(emulator, next_ir)
            _ -> raise "Unknown opcode"
          end
      end

    next_emulator
    |> with_log()
    |> run()
  end

  def run(%Emulator{} = _emulator), do: :ok

  defp with_log(emulator) do
    sorted_parsed_memory =
      emulator.memory
      |> Map.to_list()
      |> Enum.sort()
      |> Enum.map(fn {ind, command} ->
        {ind,
         "encoded: #{command}; parsed: #{inspect(try do
           parse_instruction(command)
         rescue
           _ -> command
         end)}"}
      end)

    sorted_registers =
      emulator.registers
      |> Map.to_list()
      |> Enum.sort()

    parsed_ir =
      try do
        parse_instruction(emulator.ir)
      rescue
        _ -> emulator.ir
      end

    IO.inspect(
      %{
        memory: sorted_parsed_memory,
        registers: sorted_registers,
        ir: "encoded: #{emulator.ir}; parsed: #{inspect(parsed_ir)}",
        pc: emulator.pc
      },
      limit: :infinity
    )

    emulator
  end

  defp encode_program(program) do
    program
    |> Enum.map(&encode_command/1)
  end

  defp encode_command(command) do
    case command do
      {:if, addr1, addr2} ->
        <<1::16-little, addr1::8-little, addr2::8-little>>

      {:store_init, addr1, addr2} ->
        <<2::16-little, addr1::8-little, addr2::8-little>>

      {:store_from_reg, reg1, reg2} ->
        <<3::16-little, encode_reg(reg1)::8-little, encode_reg(reg2)::8-little>>

      {:load_init, reg1, addr1} ->
        <<4::16-little, encode_reg(reg1)::8-little, addr1::8-little>>

      {:load_from_reg, reg1, reg2} ->
        <<5::16-little, encode_reg(reg1)::8-little, encode_reg(reg2)::8-little>>

      {:add, reg1, reg2} ->
        <<6::16-little, encode_reg(reg1)::8-little, encode_reg(reg2)::8-little>>

      {:sub, reg1, reg2} ->
        <<7::16-little, encode_reg(reg1)::8-little, encode_reg(reg2)::8-little>>

      {:goto, addr1} ->
        <<8::16-little, addr1::16-little>>

      {:halt} ->
        <<9::16-little, 1::16-little>>
    end
    |> :binary.decode_unsigned()
  end

  defp encode_reg(reg) do
    case reg do
      :a -> 1
      :b -> 2
      :c -> 3
      :d -> 4
      :e -> 5
      :ifreg -> 6
      :ir -> 7
      :pc -> 8
    end
  end

  defp parse_instruction(encoded_command) do
    encoded_command
    |> :binary.encode_unsigned()
    |> case do
      <<1::16-little, addr1::8-little, addr2::8-little>> ->
        {:if, addr1, addr2}

      <<2::16-little, addr1::8-little, addr2::8-little>> ->
        {:store_init, addr1, addr2}

      <<3::16-little, reg1_no::8-little, reg2_no::8-little>> ->
        {:store_from_reg, parse_reg(reg1_no), parse_reg(reg2_no)}

      <<4::16-little, reg1_no::8-little, addr1::8-little>> ->
        {:load_init, parse_reg(reg1_no), addr1}

      <<5::16-little, reg1_no::8-little, reg2_no::8-little>> ->
        {:load_from_reg, parse_reg(reg1_no), parse_reg(reg2_no)}

      <<6::16-little, reg1_no::8-little, reg2_no::8-little>> ->
        {:add, parse_reg(reg1_no), parse_reg(reg2_no)}

      <<7::16-little, reg1_no::8-little, reg2_no::8-little>> ->
        {:sub, parse_reg(reg1_no), parse_reg(reg2_no)}

      <<8::16-little, addr1::16-little>> ->
        {:goto, addr1}

      <<9::16-little, 1::16-little>> ->
        {:halt}
    end
  end

  defp parse_reg(reg_no) do
    case reg_no do
      1 -> :a
      2 -> :b
      3 -> :c
      4 -> :d
      5 -> :e
      6 -> :ifreg
      7 -> :ir
      8 -> :pc
    end
  end

  defp if(emulator, ir, addr1, addr2) do
    if emulator.registers[:ifreg] != 0 do
      %Emulator{emulator | ir: ir, pc: addr1}
    else
      %Emulator{emulator | ir: ir, pc: addr2}
    end
  end

  defp store_init(emulator, ir, addr, value) do
    new_memory = Map.put(emulator.memory, addr, value)
    %Emulator{emulator | memory: new_memory, ir: ir, pc: emulator.pc + 1}
  end

  defp store_from_reg(emulator, ir, memory_to_reg, memory_from_reg) do
    new_memory =
      Map.put(
        emulator.memory,
        emulator.registers[memory_to_reg],
        emulator.registers[memory_from_reg]
      )

    %Emulator{emulator | memory: new_memory, ir: ir, pc: emulator.pc + 1}
  end

  defp load_init(emulator, ir, dest_reg, addr) do
    new_registers = Map.put(emulator.registers, dest_reg, emulator.memory[addr])
    %Emulator{emulator | registers: new_registers, ir: ir, pc: emulator.pc + 1}
  end

  defp load_from_reg(emulator, ir, dest_reg, from_reg) do
    new_registers =
      Map.put(emulator.registers, dest_reg, emulator.memory[emulator.registers[from_reg]])

    %Emulator{emulator | registers: new_registers, ir: ir, pc: emulator.pc + 1}
  end

  defp add(emulator, ir, reg1, reg2) do
    result = emulator.registers[reg1] + emulator.registers[reg2]
    new_registers = Map.put(emulator.registers, reg1, result)
    %Emulator{emulator | registers: new_registers, ir: ir, pc: emulator.pc + 1}
  end

  defp sub(emulator, ir, reg1, reg2) do
    result = emulator.registers[reg1] - emulator.registers[reg2]
    new_registers = Map.put(emulator.registers, reg1, result)
    %Emulator{emulator | registers: new_registers, ir: ir, pc: emulator.pc + 1}
  end

  defp goto(emulator, ir, to) do
    %Emulator{emulator | ir: ir, pc: to}
  end

  defp halt(emulator, ir) do
    %Emulator{emulator | ir: ir, pc: -1}
  end
end
