import strformat
import sequtils
import strutils
import logging
import algorithm


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
    mem:seq[int]
    pos = 0
    ipos = 0
  for x in data:
    mem.add(x)
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

proc run_sequence(prog:seq[int], nums:seq[int], initial_input = 0):int =
  var answer = initial_input
  for num in nums:
    answer = run(prog, @[num, answer])[^1]
  result = answer

proc parse_prog(prog:string):seq[int] =
  for x in prog.split(","):
    result.add(x.parseInt)

# from on https://github.com/narimiran/itertools/blob/master/src/itertools.nim
iterator distinctPermutations*[T](s: openArray[T]): seq[T] =
  ## Iterator which yields distinct permutations of ``s``.
  var x = @s
  x.sort(cmp)
  yield x
  while x.nextPermutation():
    yield x

when defined(test):
  import unittest

  test "example":
    check parse_prog("3,15,3,16,1002,16,10,16,1,16,15,15,4,15,99,0,0").run_sequence(@[4,3,2,1,0]) == 43210
    check parse_prog("3,23,3,24,1002,24,10,24,1002,23,-1,23,101,5,23,23,1,24,23,23,4,23,99,0,0").run_sequence(@[0,1,2,3,4]) == 54321
    check parse_prog("3,31,3,32,1002,32,10,32,1001,31,-2,31,1007,31,0,33,1002,33,7,33,1,33,31,31,1,32,31,31,4,31,99,0,0,0").run_sequence(@[1,0,4,3,2]) == 65210

else:
  let inp = parse_prog"3,8,1001,8,10,8,105,1,0,0,21,38,63,72,85,110,191,272,353,434,99999,3,9,102,4,9,9,101,2,9,9,102,3,9,9,4,9,99,3,9,1001,9,4,9,102,2,9,9,1001,9,5,9,1002,9,5,9,101,3,9,9,4,9,99,3,9,1001,9,2,9,4,9,99,3,9,1001,9,3,9,102,2,9,9,4,9,99,3,9,101,2,9,9,102,2,9,9,1001,9,2,9,1002,9,4,9,101,2,9,9,4,9,99,3,9,1002,9,2,9,4,9,3,9,102,2,9,9,4,9,3,9,101,2,9,9,4,9,3,9,101,2,9,9,4,9,3,9,101,1,9,9,4,9,3,9,101,2,9,9,4,9,3,9,1002,9,2,9,4,9,3,9,101,2,9,9,4,9,3,9,101,1,9,9,4,9,3,9,1002,9,2,9,4,9,99,3,9,1001,9,1,9,4,9,3,9,102,2,9,9,4,9,3,9,1001,9,2,9,4,9,3,9,102,2,9,9,4,9,3,9,1001,9,2,9,4,9,3,9,101,2,9,9,4,9,3,9,1002,9,2,9,4,9,3,9,1001,9,2,9,4,9,3,9,1001,9,2,9,4,9,3,9,1001,9,1,9,4,9,99,3,9,1001,9,1,9,4,9,3,9,1001,9,1,9,4,9,3,9,1001,9,2,9,4,9,3,9,102,2,9,9,4,9,3,9,1002,9,2,9,4,9,3,9,102,2,9,9,4,9,3,9,1002,9,2,9,4,9,3,9,1002,9,2,9,4,9,3,9,101,2,9,9,4,9,3,9,101,2,9,9,4,9,99,3,9,1001,9,2,9,4,9,3,9,1002,9,2,9,4,9,3,9,101,1,9,9,4,9,3,9,102,2,9,9,4,9,3,9,1001,9,2,9,4,9,3,9,1002,9,2,9,4,9,3,9,102,2,9,9,4,9,3,9,1001,9,2,9,4,9,3,9,1002,9,2,9,4,9,3,9,102,2,9,9,4,9,99,3,9,1002,9,2,9,4,9,3,9,101,1,9,9,4,9,3,9,101,2,9,9,4,9,3,9,101,1,9,9,4,9,3,9,101,2,9,9,4,9,3,9,102,2,9,9,4,9,3,9,101,2,9,9,4,9,3,9,1002,9,2,9,4,9,3,9,1002,9,2,9,4,9,3,9,101,2,9,9,4,9,99"
  var maxval = 0
  for sequence in distinctPermutations([0,1,2,3,4]):
    var answer:int
    answer = run_sequence(inp, sequence)
    if answer > maxval:
      maxval = answer
      echo "new best: ", $sequence
  echo maxval

