import strformat
import sequtils
import strutils
import logging

# proc popleft*[T](s: var seq[T]):T =
#   ## INTERNAL: pop from the front of a seq
#   result = s[0]
#   s.delete(0, 0)

proc get_param(mem:seq[int], pos:int, num:int):int =
  ## Get a parameter in either immediate mode or position mode
  ## pos: instruction pointer
  ## num: parameter number (starting at 0)
  let opcode = $mem[pos]
  let opcode_revindex = 3 + num
  if opcode_revindex > opcode.len or opcode[^opcode_revindex] == '0':
    # position mode
    result = mem[mem[pos+num+1]]
  else:
    # immediate mode
    result = mem[pos+num+1]

proc run(data:seq[int], inputs:seq[int] = @[]):seq[int] =
  var
    mem = data
    pos = 0
    ipos = 0
  while true:
    let opcode = mem[pos] mod 100
    # debug "pos: " & $pos & " -> " & $mem[pos] & " = " & $opcode
    if opcode == 99:
      pos += 1
      break

    case opcode
    of 1: # add
      debug $pos & ": " & $mem[pos .. pos+3]
      let
        arg1 = mem.get_param(pos, 0)
        arg2 = mem.get_param(pos, 1)
        outi = mem[pos+3]
      debug &"{arg1} + {arg2} -> &{outi}"
      mem[outi] = arg1 + arg2
      pos += 4
    of 2: # mul
      debug $pos & ": " & $mem[pos .. pos+3]
      let
        arg1 = mem.get_param(pos, 0)
        arg2 = mem.get_param(pos, 1)
        outi = mem[pos+3]
      debug &"{arg1} * {arg2} -> &{outi}"
      mem[outi] = arg1 * arg2
      pos += 4
    of 3: # input/save
      debug $pos & ": " & $mem[pos .. pos+1]
      let arg1 = mem[pos+1]
      let inp = inputs[ipos]
      ipos.inc()
      debug &"{inp} -> &{arg1}"
      mem[arg1] = inp
      pos += 2
    of 4: # output
      debug $pos & ": " & $mem[pos .. pos+1]
      let outp = mem.get_param(pos, 0)
      debug &"echo {outp}"
      echo "OUT: " & $outp
      result.add(outp)
      pos += 2
    of 5: # jump-if-true
      debug $pos & ": " & $mem[pos .. pos+2]
      let
        arg1 = mem.get_param(pos, 0)
        arg2 = mem.get_param(pos, 1)
      if arg1 != 0:
        pos = arg2
        debug &"{arg2} -> IP"
      else:
        pos += 3
        debug "nop"
    of 6: # jump-if-false
      debug $pos & ": " & $mem[pos .. pos+2]
      let
        arg1 = mem.get_param(pos, 0)
        arg2 = mem.get_param(pos, 1)
      if arg1 == 0:
        pos = arg2
        debug &"{arg2} -> IP"
      else:
        pos += 3
        debug "nop"
    of 7: # less-than
      debug $pos & ": " & $mem[pos .. pos+3]
      let
        arg1 = mem.get_param(pos, 0)
        arg2 = mem.get_param(pos, 1)
        outi = mem[pos+3]
        res = if arg1 < arg2: 1 else: 0
      debug &"{arg1} < {arg2} = {res} -> &{outi}"
      mem[outi] = res
      pos += 4
    of 8: # equals
      debug $pos & ": " & $mem[pos .. pos+3]
      let
        arg1 = mem.get_param(pos, 0)
        arg2 = mem.get_param(pos, 1)
        outi = mem[pos+3]
        res = if arg1 == arg2: 1 else: 0
      debug &"{arg1} == {arg2} = {res} -> &{outi}"
      mem[outi] = res
      pos += 4
    else:
      raise newException(CatchableError, "Invalid opcode: " & $opcode)

# var logger = newConsoleLogger()
# addHandler(logger)

when defined(test):
  import unittest

  test "all":
    check run(@[1,0,0,0,99], @[]) == []
    check run(@[2,3,0,3,99], @[]) == []
    check run(@[2,4,4,5,99,0], @[]) == []
    check run(@[1,1,1,4,99,5,6,0,99], @[]) == []
    check run(@[1002,4,3,4,33], @[]) == []
    check run(@[3,12,6,12,15,1,13,14,13,4,13,99,-1,0,1,9], @[0]) == @[0]
    check run(@[3,12,6,12,15,1,13,14,13,4,13,99,-1,0,1,9], @[1]) == @[1]
    check run(@[3,12,6,12,15,1,13,14,13,4,13,99,-1,0,1,9], @[2]) == @[1]
    check run(@[3,3,1105,-1,9,1101,0,0,12,4,12,99,1], @[0]) == @[0]
    check run(@[3,3,1105,-1,9,1101,0,0,12,4,12,99,1], @[1]) == @[1]
    check run(@[3,3,1105,-1,9,1101,0,0,12,4,12,99,1], @[2]) == @[1]

  test "comparator":
    let prog = @[3,21,1008,21,8,20,1005,20,22,107,8,21,20,1006,20,31,1106,0,36,98,0,0,1002,21,125,20,4,20,1105,1,46,104,999,1105,1,46,1101,1000,1,20,4,20,1105,1,46,98,99]
    check run(prog, @[0]) == @[999]
    check run(prog, @[8]) == @[1000]
    check run(prog, @[9]) == @[1001]

else:
  let inp = "3,225,1,225,6,6,1100,1,238,225,104,0,1102,9,19,225,1,136,139,224,101,-17,224,224,4,224,102,8,223,223,101,6,224,224,1,223,224,223,2,218,213,224,1001,224,-4560,224,4,224,102,8,223,223,1001,224,4,224,1,223,224,223,1102,25,63,224,101,-1575,224,224,4,224,102,8,223,223,1001,224,4,224,1,223,224,223,1102,55,31,225,1101,38,15,225,1001,13,88,224,1001,224,-97,224,4,224,102,8,223,223,101,5,224,224,1,224,223,223,1002,87,88,224,101,-3344,224,224,4,224,102,8,223,223,1001,224,7,224,1,224,223,223,1102,39,10,225,1102,7,70,225,1101,19,47,224,101,-66,224,224,4,224,1002,223,8,223,1001,224,6,224,1,224,223,223,1102,49,72,225,102,77,166,224,101,-5544,224,224,4,224,102,8,223,223,1001,224,4,224,1,223,224,223,101,32,83,224,101,-87,224,224,4,224,102,8,223,223,1001,224,3,224,1,224,223,223,1101,80,5,225,1101,47,57,225,4,223,99,0,0,0,677,0,0,0,0,0,0,0,0,0,0,0,1105,0,99999,1105,227,247,1105,1,99999,1005,227,99999,1005,0,256,1105,1,99999,1106,227,99999,1106,0,265,1105,1,99999,1006,0,99999,1006,227,274,1105,1,99999,1105,1,280,1105,1,99999,1,225,225,225,1101,294,0,0,105,1,0,1105,1,99999,1106,0,300,1105,1,99999,1,225,225,225,1101,314,0,0,106,0,0,1105,1,99999,1008,677,226,224,1002,223,2,223,1005,224,329,1001,223,1,223,107,226,677,224,1002,223,2,223,1006,224,344,101,1,223,223,1007,677,677,224,1002,223,2,223,1006,224,359,1001,223,1,223,8,677,226,224,102,2,223,223,1005,224,374,101,1,223,223,108,226,677,224,102,2,223,223,1006,224,389,1001,223,1,223,1008,677,677,224,1002,223,2,223,1006,224,404,1001,223,1,223,1107,677,677,224,102,2,223,223,1005,224,419,1001,223,1,223,1008,226,226,224,102,2,223,223,1005,224,434,101,1,223,223,8,226,677,224,1002,223,2,223,1006,224,449,101,1,223,223,1007,677,226,224,102,2,223,223,1005,224,464,1001,223,1,223,107,677,677,224,1002,223,2,223,1005,224,479,1001,223,1,223,1107,226,677,224,1002,223,2,223,1005,224,494,1001,223,1,223,7,677,677,224,102,2,223,223,1006,224,509,101,1,223,223,1007,226,226,224,1002,223,2,223,1005,224,524,101,1,223,223,7,677,226,224,102,2,223,223,1005,224,539,101,1,223,223,8,226,226,224,1002,223,2,223,1006,224,554,101,1,223,223,7,226,677,224,102,2,223,223,1005,224,569,101,1,223,223,1108,677,226,224,1002,223,2,223,1005,224,584,101,1,223,223,108,677,677,224,1002,223,2,223,1006,224,599,101,1,223,223,107,226,226,224,1002,223,2,223,1006,224,614,101,1,223,223,1108,226,226,224,1002,223,2,223,1005,224,629,1001,223,1,223,1107,677,226,224,1002,223,2,223,1005,224,644,101,1,223,223,108,226,226,224,1002,223,2,223,1005,224,659,101,1,223,223,1108,226,677,224,1002,223,2,223,1005,224,674,1001,223,1,223,4,223,99,226"
  var prog:seq[int]
  for x in inp.split(","):
    prog.add(x.parseInt)
  # prog[1] = 12
  # prog[2] = 2
  let res = run(prog, @[5])
  # echo res[0]