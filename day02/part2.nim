import strformat
import sequtils
import strutils

proc run(data:seq[int]):seq[int] =
  var
    mem = data
    pos = 0
  while true:
    let opcode = mem[pos]
    if opcode == 99:
      break
    let
      arg1 = mem[mem[pos+1]]
      arg2 = mem[mem[pos+2]]
      outi = mem[pos+3]
    case opcode
    of 1:
      mem[outi] = arg1 + arg2
    of 2:
      mem[outi] = arg1 * arg2
    else:
      raise newException(CatchableError, "Invalid opcode: " & $opcode)
    pos += 4
  return mem

when defined(test):
  import unittest

  test "all":
    check run(@[1,0,0,0,99]) == @[2,0,0,0,99]
    check run(@[2,3,0,3,99]) == @[2,3,0,6,99]
    check run(@[2,4,4,5,99,0]) == @[2,4,4,5,99,9801]
    check run(@[1,1,1,4,99,5,6,0,99]) == @[30,1,1,4,2,5,6,0,99]

else:
  let inp = "1,0,0,3,1,1,2,3,1,3,4,3,1,5,0,3,2,1,6,19,1,9,19,23,2,23,10,27,1,27,5,31,1,31,6,35,1,6,35,39,2,39,13,43,1,9,43,47,2,9,47,51,1,51,6,55,2,55,10,59,1,59,5,63,2,10,63,67,2,9,67,71,1,71,5,75,2,10,75,79,1,79,6,83,2,10,83,87,1,5,87,91,2,9,91,95,1,95,5,99,1,99,2,103,1,103,13,0,99,2,14,0,0"
  var prog:seq[int]
  for x in inp.split(","):
    prog.add(x.parseInt)
  for noun in 0..99:
    for verb in 0..99:
      prog[1] = noun
      prog[2] = verb
      if run(prog)[0] == 19690720:
        echo "OK: ", 100 * noun + verb
        quit(0)
