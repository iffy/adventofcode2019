import strformat
import sequtils
import strutils
import logging
import algorithm
import asyncdispatch


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
    debug &"{q.name}: complete {val}"
    waiter.complete(val)

proc get[T](q:SimpleQueue[T]):Future[T] =
  result = newFuture[T]("queue.get")
  q.waiters.add(result)
  debug &"{q.name}: get ..."
  q.pump()

proc put[T](q:SimpleQueue[T], val:T) =
  q.values.add(val)
  debug &"{q.name}: put {val}"
  q.pump()

proc `$`(q:SimpleQueue):string =
  result = &"[{q.name}: waiters:{q.waiters.len}, vals:{q.values}]"




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

proc run(name: string, data:seq[int], in_queue:SimpleQueue[int], out_queue:SimpleQueue[int]):Future[void] {.async.} =
  debug name, " inp: ", in_queue
  debug name, " out: ", out_queue
  var
    mem:seq[int]
    pos = 0
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
      # debug $pos & ": " & $mem[pos .. pos+3]
      let
        arg1 = mem.get_param(pos, 0)
        arg2 = mem.get_param(pos, 1)
        outi = mem[pos+3]
      # debug &"{arg1} + {arg2} -> &{outi}"
      mem[outi] = arg1 + arg2
      pos += 4
    of 2: # mul
      # debug $pos & ": " & $mem[pos .. pos+3]
      let
        arg1 = mem.get_param(pos, 0)
        arg2 = mem.get_param(pos, 1)
        outi = mem[pos+3]
      # debug &"{arg1} * {arg2} -> &{outi}"
      mem[outi] = arg1 * arg2
      pos += 4
    of 3: # input/save
      # debug $pos & ": " & $mem[pos .. pos+1]
      let arg1 = mem[pos+1]
      let inp_fut = in_queue.get()
      yield inp_fut
      if inp_fut.failed:
        raise newException(CatchableError, "Failed to get input")
      let inp = inp_fut.read()
      debug &"{name} received {inp}"
      mem[arg1] = inp
      pos += 2
    of 4: # output
      # debug $pos & ": " & $mem[pos .. pos+1]
      let outp = mem.get_param(pos, 0)
      debug &"{name} echo {outp}"
      out_queue.put(outp)
      pos += 2
    of 5: # jump-if-true
      # debug $pos & ": " & $mem[pos .. pos+2]
      let
        arg1 = mem.get_param(pos, 0)
        arg2 = mem.get_param(pos, 1)
      if arg1 != 0:
        pos = arg2
        # debug &"{arg2} -> IP"
      else:
        pos += 3
        # debug "nop"
    of 6: # jump-if-false
      # debug $pos & ": " & $mem[pos .. pos+2]
      let
        arg1 = mem.get_param(pos, 0)
        arg2 = mem.get_param(pos, 1)
      if arg1 == 0:
        pos = arg2
        # debug &"{arg2} -> IP"
      else:
        pos += 3
        # debug "nop"
    of 7: # less-than
      # debug $pos & ": " & $mem[pos .. pos+3]
      let
        arg1 = mem.get_param(pos, 0)
        arg2 = mem.get_param(pos, 1)
        outi = mem[pos+3]
        res = if arg1 < arg2: 1 else: 0
      # debug &"{arg1} < {arg2} = {res} -> &{outi}"
      mem[outi] = res
      pos += 4
    of 8: # equals
      # debug $pos & ": " & $mem[pos .. pos+3]
      let
        arg1 = mem.get_param(pos, 0)
        arg2 = mem.get_param(pos, 1)
        outi = mem[pos+3]
        res = if arg1 == arg2: 1 else: 0
      # debug &"{arg1} == {arg2} = {res} -> &{outi}"
      mem[outi] = res
      pos += 4
    else:
      raise newException(CatchableError, "Invalid opcode: " & $opcode)

proc run_sequence(prog:seq[int], nums:seq[int], initial_input = 0):int =
  var queues:seq[SimpleQueue[int]]
  for i,num in nums:
    var queue:SimpleQueue[int]
    new(queue)
    queue.name = &"input{i}"
    queues.add(queue)
    queue.put(num)
  for i,num in nums:
    asyncCheck run(&"prog{i}", prog, queues[i], queues[(i+1) mod queues.len])
  
  echo "before start"
  for queue in queues:
    echo $queue
  
  echo "STARTING"
  queues[0].put(initial_input)

  echo "after start"
  for queue in queues:
    echo $queue

  let final_p = queues[0].get()
  if not final_p.finished:
    raise newException(CatchableError, "Expected program to be finished, but it isn't")
  result = final_p.read()

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

# var logger = newConsoleLogger()
# addHandler(logger)

when defined(test):
  import unittest

  test "example":
    check parse_prog("3,26,1001,26,-4,26,3,27,1002,27,2,27,1,27,26,27,4,27,1001,28,-1,28,1005,28,6,99,0,0,5").run_sequence(@[9,8,7,6,5]) == 139629729
    check parse_prog("3,52,1001,52,-5,52,3,53,1,52,56,54,1007,54,5,55,1005,55,26,1001,54,-5,54,1105,1,12,1,53,54,53,1008,54,0,55,1001,55,1,55,2,53,55,53,4,53,1001,56,-1,56,1005,56,6,99,0,0,0,0,10").run_sequence(@[9,7,8,5,6]) == 18216

else:
  let inp = parse_prog"3,8,1001,8,10,8,105,1,0,0,21,38,63,72,85,110,191,272,353,434,99999,3,9,102,4,9,9,101,2,9,9,102,3,9,9,4,9,99,3,9,1001,9,4,9,102,2,9,9,1001,9,5,9,1002,9,5,9,101,3,9,9,4,9,99,3,9,1001,9,2,9,4,9,99,3,9,1001,9,3,9,102,2,9,9,4,9,99,3,9,101,2,9,9,102,2,9,9,1001,9,2,9,1002,9,4,9,101,2,9,9,4,9,99,3,9,1002,9,2,9,4,9,3,9,102,2,9,9,4,9,3,9,101,2,9,9,4,9,3,9,101,2,9,9,4,9,3,9,101,1,9,9,4,9,3,9,101,2,9,9,4,9,3,9,1002,9,2,9,4,9,3,9,101,2,9,9,4,9,3,9,101,1,9,9,4,9,3,9,1002,9,2,9,4,9,99,3,9,1001,9,1,9,4,9,3,9,102,2,9,9,4,9,3,9,1001,9,2,9,4,9,3,9,102,2,9,9,4,9,3,9,1001,9,2,9,4,9,3,9,101,2,9,9,4,9,3,9,1002,9,2,9,4,9,3,9,1001,9,2,9,4,9,3,9,1001,9,2,9,4,9,3,9,1001,9,1,9,4,9,99,3,9,1001,9,1,9,4,9,3,9,1001,9,1,9,4,9,3,9,1001,9,2,9,4,9,3,9,102,2,9,9,4,9,3,9,1002,9,2,9,4,9,3,9,102,2,9,9,4,9,3,9,1002,9,2,9,4,9,3,9,1002,9,2,9,4,9,3,9,101,2,9,9,4,9,3,9,101,2,9,9,4,9,99,3,9,1001,9,2,9,4,9,3,9,1002,9,2,9,4,9,3,9,101,1,9,9,4,9,3,9,102,2,9,9,4,9,3,9,1001,9,2,9,4,9,3,9,1002,9,2,9,4,9,3,9,102,2,9,9,4,9,3,9,1001,9,2,9,4,9,3,9,1002,9,2,9,4,9,3,9,102,2,9,9,4,9,99,3,9,1002,9,2,9,4,9,3,9,101,1,9,9,4,9,3,9,101,2,9,9,4,9,3,9,101,1,9,9,4,9,3,9,101,2,9,9,4,9,3,9,102,2,9,9,4,9,3,9,101,2,9,9,4,9,3,9,1002,9,2,9,4,9,3,9,1002,9,2,9,4,9,3,9,101,2,9,9,4,9,99"
  var maxval = 0
  for sequence in distinctPermutations([5,6,7,8,9]):
    var answer:int
    answer = run_sequence(inp, sequence)
    if answer > maxval:
      maxval = answer
      echo "new best: ", $sequence
  echo maxval

