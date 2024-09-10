defmodule Emulator do
  defstruct memory: %{}, registers: %{a: 0, b: 0, c: 0, d: 0, e: 0, ifreg: 0}, ir: 0, pc: 0

  def with_log(emulator) do
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

  defp encode_program(program) do
    program
    |> Enum.map(fn command -> command |> :erlang.term_to_binary() |> :binary.decode_unsigned() end)
  end

  defp parse_instruction(encoded_command) do
    encoded_command |> :binary.encode_unsigned() |> :erlang.binary_to_term()
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

program = [
  # mem[0] = 25
  {:store_init, 0, 25},
  # mem[1] = 8
  {:store_init, 1, 8},
  # mem[2] = 1
  {:store_init, 2, 1},
  # reg[:a] = 25
  {:load_init, :a, 0},
  # reg[:b] = 1
  {:load_init, :b, 2},
  # reg[:ifreg] = 8
  {:load_init, :ifreg, 1},
  # reg[:ifreg] != 0 ? goto 7 : goto 11
  {:if, 7, 11},
  # mem[reg[:a]] = reg[:ifreg]
  {:store_from_reg, :a, :ifreg},
  # reg[:a] += reg[:b]
  {:add, :a, :b},
  # reg[:ifreg] -= reg[:b]
  {:sub, :ifreg, :b},
  # goto if
  {:goto, 6},
  # mem[3] = 0
  {:store_init, 3, 0},
  # reg[:a] = 25
  {:load_init, :a, 0},
  # reg[:c] = 0
  {:load_init, :c, 3},
  # reg[:ifreg] = 8
  {:load_init, :ifreg, 1},
  # reg[:ifreg] != 0 ? goto 16 : goto 21
  {:if, 16, 21},
  # reg[:d] = mem[reg[:a]]
  {:load_from_reg, :d, :a},
  # reg[:c] += reg[:d]
  {:add, :c, :d},
  # reg[:c] += reg[:b]
  {:add, :a, :b},
  # reg[:ifreg] -= reg[:b]
  {:sub, :ifreg, :b},
  # goto if
  {:goto, 15},
  # mem[0] = 0
  {:store_init, 0, 0},
  # reg[:a] = 0
  {:load_init, :a, 0},
  # mem[reg[:a]] = reg[:c]
  {:store_from_reg, :a, :c},
  # end program
  {:halt}
]

emulator =
  Emulator.new(36)
  |> Emulator.with_log()
  |> Emulator.load_program(program)
  |> Emulator.with_log()

result = Emulator.run(emulator)

IO.inspect(result)
