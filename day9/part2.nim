import strformat
import sequtils
import strutils
import logging
import algorithm
import asyncdispatch
import tables


proc popLeft[T](s:var seq[T]):T =
  result = s[0]
  s.delete(0, 0)

type
  SimpleQueue[T] = ref object
    name: string
    waiters: seq[Future[T]]
    values: seq[T]

proc pump(q:SimpleQueue) =
  while q.waiters.len > 0 and q.values.len > 0:
    let waiter = q.waiters.popLeft()
    let val = q.values.popLeft()
    waiter.complete(val)

proc get[T](q:SimpleQueue[T]):Future[T] =
  result = newFuture[T]("queue.get")
  q.waiters.add(result)
  q.pump()

proc put[T](q:SimpleQueue[T], val:T) =
  q.values.add(val)
  q.pump()

proc pending_values(q:SimpleQueue):int =
  q.values.len

proc pending_waiters(q:SimpleQueue):int =
  q.waiters.len

proc `$`(q:SimpleQueue):string =
  result = &"[{q.name}: waiters:{q.waiters.len}, vals:{q.values}]"


type
  Program = ref object
    mem: Table[int, int]
    ip: int
    relbase: int

proc getMem(program:Program, address:int):int =
  program.mem.getOrDefault(address, 0)

proc setMem(program:Program, address:int, value:int) =
  program.mem[address] = value
  debug &"  mem[{address}] <- {value}"

proc listMem(program:Program, count:int, address = -1):seq[int] =
  let offset = if address == -1: program.ip else: address
  for i in 0 .. count-1:
    result.add(program.getMem(offset + i))

proc param(program:Program, num:int, is_write = false):int =
  ## Get a parameter in either immediate mode or position mode
  ## num: parameter number (starting at 0)
  let opcode = $program.getMem(program.ip)
  let opcode_revindex = 3 + num
  var modekey = "0"
  if opcode_revindex <= opcode.len:
    modekey = $opcode[^opcode_revindex]
  if modekey == "1" and is_write:
    raise newException(CatchableError, "Invalid mode for write param")
  case modekey
  of "0": # position mode
    let address = program.getMem(program.ip + num + 1)
    if is_write:
      result = address
    else:
      result = program.getMem(address)
  of "1": # immediate mode
    result = program.getMem(program.ip + num + 1)
  of "2": # relative mode
    let immediate_val = program.getMem(program.ip + num + 1)
    let address = program.relbase + immediate_val
    if is_write:
      result = address
    else:
      result = program.getMem(address)
  else:
    raise newException(CatchableError, "Unknown parameter mode: " & $modekey)
  debug &"  param({num}) = {result}"

template writeParam(program: Program, num:int):int =
  program.param(num, true)

proc opcode(program:Program):int =
  return program.getMem(program.ip) mod 100

proc currentState(program:Program):string =
  ## Print out the current program instruction
  let opcode = program.opcode()
  result = &"IP:{program.ip} RELBASE:{program.relbase}"

proc run(data:seq[int], in_queue:SimpleQueue[int], out_queue:SimpleQueue[int], name = ""):Future[void] {.async.} =
  var program:Program
  new(program)
  for i,x in data:
    program.setMem(i, x)

  while true:
    let opcode = program.opcode()
    if opcode == 99:
      program.ip += 1
      break

    case opcode
    of 1: # add
      debug &"{program.ip}: ADD {program.listMem(4)}"
      let
        arg1 = program.param(0)
        arg2 = program.param(1)
        outi = program.writeParam(2)
      program.setMem(outi, arg1 + arg2)
      program.ip += 4
    of 2: # mul
      debug &"{program.ip}: MUL {program.listMem(4)}"
      let
        arg1 = program.param(0)
        arg2 = program.param(1)
        outi = program.writeParam(2)
      program.setMem(outi, arg1 * arg2)
      program.ip += 4
    of 3: # input/save
      debug &"{program.ip}: IN {program.listMem(2)}"
      let arg1 = program.writeParam(0)
      let inp_fut = in_queue.get()
      yield inp_fut
      if inp_fut.failed:
        raise newException(CatchableError, "Failed to get input")
      let inp = inp_fut.read()
      debug &"{name} received {inp}"
      program.setMem(arg1, inp)
      program.ip += 2
    of 4: # output
      debug &"{program.ip}: OUT {program.listMem(2)}"
      let outp = program.param(0)
      debug &"{name} echo {outp}"
      out_queue.put(outp)
      program.ip += 2
    of 5: # jump-if-true
      debug &"{program.ip}: IF!0 {program.listMem(3)}"
      let
        arg1 = program.param(0)
        arg2 = program.param(1)
      if arg1 != 0:
        program.ip = arg2
        debug &"  JUMP to {arg2}"
      else:
        program.ip += 3
    of 6: # jump-if-false
      debug &"{program.ip}: IF0 {program.listMem(3)}"
      let
        arg1 = program.param(0)
        arg2 = program.param(1)
      if arg1 == 0:
        program.ip = arg2
        debug &"  JUMP to {arg2}"
      else:
        program.ip += 3
    of 7: # less-than
      debug &"{program.ip}: LT {program.listMem(4)}"
      let
        arg1 = program.param(0)
        arg2 = program.param(1)
        outi = program.writeParam(2)
        res = if arg1 < arg2: 1 else: 0
      program.setMem(outi, res)
      program.ip += 4
    of 8: # equals
      debug &"{program.ip}: EQ {program.listMem(4)}"
      let
        arg1 = program.param(0)
        arg2 = program.param(1)
        outi = program.writeParam(2)
        res = if arg1 == arg2: 1 else: 0
      # debug &"{arg1} == {arg2} = {res} -> &{outi}"
      program.setMem(outi, res)
      program.ip += 4
    of 9: # adjust-base
      debug &"{program.ip}: REBASE {program.listMem(2)}"
      let
        arg1 = program.param(0)
      let oldrelbase = program.relbase
      program.relbase.inc(arg1)
      debug &"  relbase {oldrelbase} -> {program.relbase}"
      program.ip += 2
    else:
      raise newException(CatchableError, "Invalid opcode: " & $opcode)

proc runWithInput(prog:seq[int], inputs:seq[int], name = ""):seq[int] =
  var
    in_queue: SimpleQueue[int]
    out_queue: SimpleQueue[int]
  new(in_queue)
  new(out_queue)
  for i in inputs:
    in_queue.put(i)
  asyncCheck run(prog, in_queue, out_queue, name)
  for i in 0 .. out_queue.pending_values - 1:
    result.add(out_queue.get().read())

proc parse_prog(prog:string):seq[int] =
  for x in prog.split(","):
    result.add(x.parseInt)

# var logger = newConsoleLogger()
# addHandler(logger)

when defined(test):
  import unittest

  test "duplicate":
    let start = "109,1,204,-1,1001,100,1,100,1008,100,16,101,1006,101,0,99"
    let parsed = parse_prog(start)
    let output = parsed.runWithInput(@[])
    check output == parsed
  
  test "case2":
    let prog = parse_prog("1102,34915192,34915192,7,4,7,99,0")
    let output = prog.runWithInput(@[])
    check ($output[0]).len == 16
  
  test "case3":
    let prog = parse_prog("104,1125899906842624,99")
    let output = prog.runWithInput(@[])
    check output[0] == 1125899906842624

else:
  let inp = """1102,34463338,34463338,63,1007,63,34463338,63,1005,63,53,1101,3,0,1000,109,988,209,12,9,1000,209,6,209,3,203,0,1008,1000,1,63,1005,63,65,1008,1000,2,63,1005,63,904,1008,1000,0,63,1005,63,58,4,25,104,0,99,4,0,104,0,99,4,17,104,0,99,0,0,1101,37,0,1005,1101,30,0,1013,1102,1,33,1019,1102,1,25,1003,1102,1,28,1018,1101,26,0,1006,1102,1,866,1029,1101,760,0,1023,1102,39,1,1012,1102,23,1,1009,1101,281,0,1026,1102,1,20,1011,1102,1,34,1008,1101,0,36,1017,1101,38,0,1000,1102,0,1,1020,1102,278,1,1027,1101,21,0,1010,1102,875,1,1028,1101,0,212,1025,1102,1,1,1021,1102,1,24,1014,1102,763,1,1022,1101,0,31,1007,1102,1,221,1024,1101,0,32,1002,1102,1,29,1004,1102,1,35,1016,1102,22,1,1015,1101,0,27,1001,109,9,1207,-6,26,63,1005,63,199,4,187,1105,1,203,1001,64,1,64,1002,64,2,64,109,19,2105,1,-4,4,209,1001,64,1,64,1106,0,221,1002,64,2,64,109,-33,1207,5,37,63,1005,63,241,1001,64,1,64,1106,0,243,4,227,1002,64,2,64,109,16,2102,1,-2,63,1008,63,23,63,1005,63,269,4,249,1001,64,1,64,1106,0,269,1002,64,2,64,109,16,2106,0,0,1106,0,287,4,275,1001,64,1,64,1002,64,2,64,109,-11,21101,40,0,0,1008,1016,38,63,1005,63,311,1001,64,1,64,1105,1,313,4,293,1002,64,2,64,109,4,21107,41,40,-9,1005,1011,329,1105,1,335,4,319,1001,64,1,64,1002,64,2,64,109,-14,21108,42,42,5,1005,1011,353,4,341,1106,0,357,1001,64,1,64,1002,64,2,64,109,2,2107,33,0,63,1005,63,379,4,363,1001,64,1,64,1105,1,379,1002,64,2,64,109,-7,1201,2,0,63,1008,63,25,63,1005,63,401,4,385,1105,1,405,1001,64,1,64,1002,64,2,64,109,11,1201,-8,0,63,1008,63,28,63,1005,63,429,1001,64,1,64,1106,0,431,4,411,1002,64,2,64,109,-7,2108,26,1,63,1005,63,449,4,437,1105,1,453,1001,64,1,64,1002,64,2,64,109,9,1206,7,465,1105,1,471,4,459,1001,64,1,64,1002,64,2,64,109,4,21102,43,1,-3,1008,1015,42,63,1005,63,491,1106,0,497,4,477,1001,64,1,64,1002,64,2,64,109,7,21108,44,43,-7,1005,1018,517,1001,64,1,64,1105,1,519,4,503,1002,64,2,64,109,-28,2101,0,7,63,1008,63,29,63,1005,63,545,4,525,1001,64,1,64,1105,1,545,1002,64,2,64,109,11,2107,28,-7,63,1005,63,561,1105,1,567,4,551,1001,64,1,64,1002,64,2,64,109,-4,2101,0,-1,63,1008,63,26,63,1005,63,587,1105,1,593,4,573,1001,64,1,64,1002,64,2,64,109,9,1206,7,607,4,599,1105,1,611,1001,64,1,64,1002,64,2,64,109,-10,1208,1,27,63,1005,63,627,1106,0,633,4,617,1001,64,1,64,1002,64,2,64,109,26,1205,-9,649,1001,64,1,64,1106,0,651,4,639,1002,64,2,64,109,-20,1208,0,23,63,1005,63,669,4,657,1105,1,673,1001,64,1,64,1002,64,2,64,109,-7,2102,1,1,63,1008,63,28,63,1005,63,693,1105,1,699,4,679,1001,64,1,64,1002,64,2,64,109,18,21102,45,1,-6,1008,1014,45,63,1005,63,725,4,705,1001,64,1,64,1106,0,725,1002,64,2,64,109,-23,1202,6,1,63,1008,63,25,63,1005,63,751,4,731,1001,64,1,64,1106,0,751,1002,64,2,64,109,20,2105,1,6,1106,0,769,4,757,1001,64,1,64,1002,64,2,64,109,-22,2108,39,10,63,1005,63,789,1001,64,1,64,1106,0,791,4,775,1002,64,2,64,109,3,1202,6,1,63,1008,63,32,63,1005,63,815,1001,64,1,64,1105,1,817,4,797,1002,64,2,64,109,23,21107,46,47,-9,1005,1012,835,4,823,1106,0,839,1001,64,1,64,1002,64,2,64,109,1,1205,-1,853,4,845,1105,1,857,1001,64,1,64,1002,64,2,64,109,-2,2106,0,8,4,863,1001,64,1,64,1105,1,875,1002,64,2,64,109,-8,21101,47,0,-2,1008,1010,47,63,1005,63,897,4,881,1106,0,901,1001,64,1,64,4,64,99,21102,27,1,1,21101,0,915,0,1105,1,922,21201,1,27810,1,204,1,99,109,3,1207,-2,3,63,1005,63,964,21201,-2,-1,1,21102,1,942,0,1106,0,922,22101,0,1,-1,21201,-2,-3,1,21101,957,0,0,1106,0,922,22201,1,-1,-2,1106,0,968,22101,0,-2,-2,109,-3,2106,0,0"""
  let parsed = parse_prog(inp)
  let output = parsed.runWithInput(@[2])
  echo $output

