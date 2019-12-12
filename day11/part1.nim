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

const
  BLACK = 0
  WHITE = 1

type
  Point = tuple
    x: int
    y: int
  Direction = enum
    Up,
    Right,
    Down,
    Left,

proc turnRight(frm:Direction):Direction =
  case frm
  of Up:
    Right
  of Right:
    Down
  of Down:
    Left
  of Left:
    Up

proc turnLeft(frm:Direction):Direction =
  case frm
  of Up:
    Left
  of Left:
    Down
  of Down:
    Right
  of Right:
    Up

proc move(start:Point, dir:Direction):Point =
  case dir
  of Up:
    (start.x, start.y + 1)
  of Right:
    (start.x + 1, start.y)
  of Down:
    (start.x, start.y - 1)
  of Left:
    (start.x - 1, start.y)

proc moveRobot(prog:seq[int]):string =
  var
    in_queue: SimpleQueue[int]
    out_queue: SimpleQueue[int]
  new(in_queue)
  new(out_queue)
  
  var pos:Point = (0, 0)
  var dir:Direction = Up
  var places = newTable[Point, int]()
  places[pos] = WHITE

  var p = prog.run(in_queue, out_queue)
  while not p.finished:
    if not places.hasKey(pos):
      places[pos] = BLACK
    in_queue.put(places[pos])

    if out_queue.pending_values == 0:
      echo "DONE"
      break
    let topaint = out_queue.get().read()
    places[pos] = topaint
    
    if out_queue.pending_values == 0:
      raise newException(CatchableError, "Missing turn input")
    let turn = out_queue.get().read()
    if turn == 0:
      dir = dir.turnLeft()
    elif turn == 1:
      dir = dir.turnRight()
    else:
      raise newException(CatchableError, "Invalid turn instruction")
    pos = pos.move(dir)
  
  var
    minx, miny, maxx, maxy = 0
  for k in places.keys():
    minx = min(k.x, minx)
    maxx = max(k.x, maxx)
    miny = min(k.y, miny)
    maxy = max(k.y, maxy)
  
  echo minx, " ", maxx
  echo miny, " ", maxy

  for row in miny .. maxy:
    for col in minx .. maxx:
      let color = places.getOrDefault((col, row), BLACK)
      if color == BLACK:
        result.add(" ")
      else:
        result.add("X")
    result.add("\n")

let inp = """3,8,1005,8,324,1106,0,11,0,0,0,104,1,104,0,3,8,102,-1,8,10,101,1,10,10,4,10,1008,8,0,10,4,10,1002,8,1,29,2,1102,17,10,3,8,102,-1,8,10,1001,10,1,10,4,10,1008,8,1,10,4,10,102,1,8,55,2,4,6,10,1,1006,10,10,1,6,14,10,3,8,1002,8,-1,10,101,1,10,10,4,10,1008,8,1,10,4,10,101,0,8,89,3,8,102,-1,8,10,1001,10,1,10,4,10,108,0,8,10,4,10,1002,8,1,110,1,104,8,10,3,8,1002,8,-1,10,1001,10,1,10,4,10,1008,8,1,10,4,10,102,1,8,137,2,9,17,10,2,1101,14,10,3,8,102,-1,8,10,101,1,10,10,4,10,1008,8,0,10,4,10,101,0,8,167,1,107,6,10,1,104,6,10,2,1106,6,10,3,8,1002,8,-1,10,101,1,10,10,4,10,108,1,8,10,4,10,1001,8,0,200,1006,0,52,1006,0,70,1006,0,52,3,8,102,-1,8,10,101,1,10,10,4,10,1008,8,1,10,4,10,1002,8,1,232,1006,0,26,1,104,19,10,3,8,102,-1,8,10,1001,10,1,10,4,10,108,0,8,10,4,10,102,1,8,260,1,2,15,10,2,1102,14,10,3,8,1002,8,-1,10,1001,10,1,10,4,10,108,0,8,10,4,10,1001,8,0,290,1,108,11,10,1006,0,36,1006,0,90,1006,0,52,101,1,9,9,1007,9,940,10,1005,10,15,99,109,646,104,0,104,1,21101,0,666412360596,1,21101,341,0,0,1105,1,445,21101,838366659476,0,1,21102,1,352,0,1106,0,445,3,10,104,0,104,1,3,10,104,0,104,0,3,10,104,0,104,1,3,10,104,0,104,1,3,10,104,0,104,0,3,10,104,0,104,1,21101,0,97713695975,1,21102,1,399,0,1106,0,445,21102,179469028392,1,1,21101,410,0,0,1105,1,445,3,10,104,0,104,0,3,10,104,0,104,0,21102,1,988220650260,1,21101,433,0,0,1105,1,445,21101,0,838345843560,1,21101,444,0,0,1106,0,445,99,109,2,22101,0,-1,1,21102,1,40,2,21102,1,476,3,21101,466,0,0,1106,0,509,109,-2,2105,1,0,0,1,0,0,1,109,2,3,10,204,-1,1001,471,472,487,4,0,1001,471,1,471,108,4,471,10,1006,10,503,1101,0,0,471,109,-2,2106,0,0,0,109,4,1202,-1,1,508,1207,-3,0,10,1006,10,526,21101,0,0,-3,22101,0,-3,1,22102,1,-2,2,21102,1,1,3,21101,0,545,0,1106,0,550,109,-4,2105,1,0,109,5,1207,-3,1,10,1006,10,573,2207,-4,-2,10,1006,10,573,21201,-4,0,-4,1106,0,641,21201,-4,0,1,21201,-3,-1,2,21202,-2,2,3,21102,592,1,0,1106,0,550,21201,1,0,-4,21101,0,1,-1,2207,-4,-2,10,1006,10,611,21101,0,0,-1,22202,-2,-1,-2,2107,0,-3,10,1006,10,633,22102,1,-1,1,21102,1,633,0,106,0,508,21202,-2,-1,-2,22201,-4,-2,-4,109,-5,2105,1,0"""
let parsed = parse_prog(inp)
echo moveRobot(parsed)

