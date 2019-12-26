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

type
  TileKind = enum
    Unexplored,
    Empty,
    DeadEnd,
    Wall,
  Point = tuple
    x: int
    y: int
  Board = ref object
    tiles: TableRef[Point, TileKind]
    distance: TableRef[Point, int]
    droid: Point
    goal: Point
    in_queue: SimpleQueue[int]
    out_queue: SimpleQueue[int]
  Direction = enum
    UP = 1,
    DOWN = 2,
    LEFT = 3,
    RIGHT = 4,
  

proc printMap(board:Board):string =
  var points = toSeq(board.tiles.keys())
  points.add(board.droid)
  let
    minx = min(points.mapIt(it.x))
    maxx = max(points.mapIt(it.x))
    miny = min(points.mapIt(it.y))
    maxy = max(points.mapIt(it.y))
  for y in miny .. maxy:
    for x in minx .. maxx:
      var p = " "
      if board.droid == (x,y):
        p = "D"
      elif board.goal == (x,y):
        p = "M"
      else:
        let thing = board.tiles.getOrDefault((x,y), Unexplored)
        case thing
        of Unexplored: p = " "
        of Empty:
          if (x,y) == (0,0):
            p = "S"
          else:
            p = "."
        of DeadEnd:
          if (x,y) == (0,0):
            p = "S"
          else:
            p = $(board.distance.getOrDefault((x,y), 0) mod 10)
        of Wall: p = " "
      result.add(p)
    result.add('\n')

proc plus(point:Point, dir:Direction):Point =
  case dir
  of Up:
    return (point.x, point.y - 1)
  of Down:
    return (point.x, point.y + 1)
  of Left:
    return (point.x - 1, point.y)
  of Right:
    return (point.x + 1, point.y)

proc whats(board:Board, point:Point):TileKind =
  board.tiles.getOrDefault(point, Unexplored)

proc whats(board:Board, dir:Direction):TileKind =
  board.whats(board.droid.plus(dir))

proc land(board:Board, point:Point) =
  ## Perform board updates when droid lands on a spot
  let distance = board.distance.getOrDefault(board.droid, 0) + 1
  let existing_distance = board.distance.getOrDefault(point, -1)
  if distance < existing_distance or existing_distance == -1:
    board.distance[point] = distance
  board.droid = point
  var num_dead = 0
  for d in [UP, RIGHT, DOWN, LEFT]:
    let tile = board.whats(d)
    if tile == Wall or tile == DeadEnd:
      num_dead.inc()
  
  if num_dead >= 3:
    board.tiles[point] = DeadEnd

proc move(board:Board, dir:Direction) =
  ## Attempt to move a droid
  var dest_point = board.droid.plus(dir)
  board.in_queue.put(dir.ord)
  let res = board.out_queue.get().read()
  case res
  of 0:
    board.tiles[dest_point] = Wall
    board.land(board.droid)
  of 1, 2:
    if board.whats(dest_point) != DeadEnd:
      board.tiles[dest_point] = Empty
    if res == 2:
      board.goal = dest_point
    board.land(dest_point)
  else:
    raise newException(CatchableError, &"Unknown output: {res}")

proc nextUndead(board:Board):Direction =
  ## Find the next undead space
  var secondary_choices:seq[Direction]
  for d in [UP, RIGHT, DOWN, LEFT]:
    let tile = board.whats(d)
    if tile == Wall or tile == DeadEnd:
      continue
    elif tile == Unexplored:
      return d
    else:
      secondary_choices.add(d)
  if secondary_choices.len == 0:
    raise newException(CatchableError, "No choices left")
  return secondary_choices[0]

proc makeBoard(prog:seq[int]):Board =
  new(result)
  new(result.in_queue)
  new(result.out_queue)
  asyncCheck prog.run(result.in_queue, result.out_queue)

  result.droid = (0,0)
  return result

proc timeOxygenReplenishment(board:var Board):int = 
  echo "Mapping starting from ", $board.droid
  board.distance = newTable[Point, int]()
  board.distance[board.droid] = 0
  board.tiles = newTable[Point, TileKind]()
  board.tiles[board.droid] = Empty

  while true:
    try:
      board.move(board.nextUndead())
    except:
      break
    if board.droid == board.goal and board.goal != (0,0):
      break
  echo board.printMap()

  board.distance = newTable[Point, int]()
  board.distance[board.droid] = 0
  board.tiles = newTable[Point, TileKind]()
  board.tiles[board.droid] = Empty

  while true:
    try:
      board.move(board.nextUndead())
    except:
      break
  echo board.printMap()
  result = max(toSeq(board.distance.values()))


let inp = """3,1033,1008,1033,1,1032,1005,1032,31,1008,1033,2,1032,1005,1032,58,1008,1033,3,1032,1005,1032,81,1008,1033,4,1032,1005,1032,104,99,101,0,1034,1039,1001,1036,0,1041,1001,1035,-1,1040,1008,1038,0,1043,102,-1,1043,1032,1,1037,1032,1042,1105,1,124,102,1,1034,1039,1002,1036,1,1041,1001,1035,1,1040,1008,1038,0,1043,1,1037,1038,1042,1106,0,124,1001,1034,-1,1039,1008,1036,0,1041,1002,1035,1,1040,102,1,1038,1043,102,1,1037,1042,1106,0,124,1001,1034,1,1039,1008,1036,0,1041,1001,1035,0,1040,1002,1038,1,1043,101,0,1037,1042,1006,1039,217,1006,1040,217,1008,1039,40,1032,1005,1032,217,1008,1040,40,1032,1005,1032,217,1008,1039,37,1032,1006,1032,165,1008,1040,33,1032,1006,1032,165,1101,0,2,1044,1106,0,224,2,1041,1043,1032,1006,1032,179,1101,0,1,1044,1105,1,224,1,1041,1043,1032,1006,1032,217,1,1042,1043,1032,1001,1032,-1,1032,1002,1032,39,1032,1,1032,1039,1032,101,-1,1032,1032,101,252,1032,211,1007,0,62,1044,1106,0,224,1101,0,0,1044,1106,0,224,1006,1044,247,101,0,1039,1034,1002,1040,1,1035,102,1,1041,1036,101,0,1043,1038,1001,1042,0,1037,4,1044,1106,0,0,60,10,88,42,71,78,10,10,70,23,65,29,47,58,86,53,77,61,77,63,18,9,20,68,45,15,67,3,95,10,14,30,81,53,3,83,46,31,95,43,94,40,21,54,93,91,35,80,9,17,81,94,59,83,49,96,61,63,24,85,69,82,45,71,48,39,32,69,93,11,90,19,78,54,79,66,6,13,76,2,67,69,10,9,66,43,73,2,92,39,12,99,33,89,18,9,78,11,96,23,55,96,49,12,85,93,49,22,70,93,59,76,68,55,66,54,32,34,36,53,64,84,87,61,43,79,7,9,66,40,69,9,76,92,18,78,49,39,80,32,70,52,74,37,86,11,77,51,15,28,84,19,13,75,28,86,3,82,93,15,79,61,93,93,31,87,43,67,44,83,78,43,46,46,12,89,19,85,44,95,65,24,70,93,50,98,72,66,80,23,87,19,97,40,25,9,49,6,81,35,9,52,71,27,63,3,96,94,21,24,48,79,67,72,72,15,85,93,22,95,34,3,63,21,79,9,51,92,45,87,25,41,80,13,88,68,66,18,85,75,39,80,17,54,93,89,65,21,91,73,53,60,69,29,82,99,5,22,65,9,69,61,80,63,38,71,61,61,11,68,30,74,11,26,53,59,97,2,12,74,79,44,73,72,27,17,34,92,26,27,88,66,5,97,34,81,86,30,35,6,64,36,34,65,80,12,90,65,95,21,90,55,43,71,89,56,97,91,27,27,73,80,34,22,48,89,84,35,88,90,47,4,32,77,31,2,82,66,76,43,74,68,56,78,36,59,66,58,75,89,96,51,51,97,34,49,86,70,26,46,89,43,99,97,66,32,51,32,77,33,86,92,56,68,64,39,83,55,25,98,24,56,73,21,98,39,24,67,21,4,76,10,32,91,53,82,37,59,72,63,78,43,67,2,72,69,50,71,19,72,92,51,12,93,61,88,24,84,35,93,30,63,70,7,78,83,42,63,6,25,24,73,76,22,99,68,14,85,14,75,32,88,42,47,97,2,91,97,51,79,12,71,91,7,1,87,82,21,98,63,37,19,85,1,48,77,54,76,12,92,28,91,25,85,88,8,92,32,67,18,56,51,67,58,80,59,77,76,25,7,73,58,72,96,75,15,27,37,23,83,58,68,83,50,67,41,39,89,24,1,83,63,8,64,54,76,50,3,89,97,74,48,15,91,22,37,71,77,9,1,85,38,23,58,10,75,86,72,80,59,24,64,7,63,85,53,61,89,68,7,80,4,68,56,39,66,31,69,6,7,76,88,17,89,42,64,56,11,97,65,64,71,88,61,31,32,53,88,99,55,73,20,90,10,86,32,50,89,53,83,42,80,28,63,98,38,85,72,57,88,23,52,96,77,39,65,88,40,26,91,56,1,94,51,94,24,20,81,74,23,45,72,56,22,84,70,44,50,68,32,98,51,75,3,61,75,59,3,7,98,76,45,78,47,74,60,69,78,54,67,29,63,47,79,72,57,73,44,63,98,6,93,36,20,27,90,77,39,44,64,68,47,48,69,78,29,76,48,1,81,10,67,32,72,47,89,83,18,39,85,65,97,15,59,13,74,29,84,50,80,94,8,27,83,67,43,75,52,96,17,82,29,83,45,85,82,71,76,44,30,10,91,16,7,31,63,2,68,75,46,70,28,93,91,17,13,81,57,93,32,27,65,61,93,11,84,10,66,14,83,14,77,26,77,13,86,21,84,87,87,34,99,69,88,1,74,61,72,54,93,16,76,54,86,63,94,13,79,24,97,0,0,21,21,1,10,1,0,0,0,0,0,0"""
var parsed = parse_prog(inp)
var board = parsed.makeBoard()
echo board.timeOxygenReplenishment()
