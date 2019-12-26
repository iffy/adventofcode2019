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
  Point = tuple
    x: int
    y: int
  Direction = enum
    North,
    East,
    South,
    West,
  TurnKind = enum
    Left,
    Right,
  Board = ref object
    tiles: TableRef[Point, char]
    bot: Point
    dir: Direction

proc getBoard(prog:seq[int]):Board =
  new(result)
  result.tiles = newTable[Point, char]()

  let outputs = runWithInput(prog, @[])
  var x = 0
  var y = 0
  for o in outputs:
    let ch = chr(o)
    case ch
    of '.':
      discard
    of '#':
      result.tiles[(x,y)] = '#'
    of '^','<','>','v':
      result.tiles[(x,y)] = '#'
      result.bot = (x,y)
      case ch
      of '^':
        result.dir = North
      of '<':
        result.dir = West
      of '>':
        result.dir = East
      of 'v':
        result.dir = South
      else:
        discard
    of '\n':
      y.inc()
      x = -1
    else:
      discard
    x.inc()

proc `$`(board:Board):string =
  let
    minx = 0
    maxx = max(toSeq(board.tiles.keys()).mapIt(it.x))
    miny = 0
    maxy = max(toSeq(board.tiles.keys()).mapIt(it.y))
  
  for y in miny .. maxy:
    for x in minx .. maxx:
      if board.bot == (x,y):
        case board.dir
        of North:
          result.add('^')
        of East:
          result.add('>')
        of South:
          result.add('v')
        of West:
          result.add('<')
      else:
        result.add board.tiles.getOrDefault((x,y), '.')
    result.add('\n')

proc plus(point:Point, dir:Direction):Point =
  case dir
  of North:
    (point.x, point.y - 1)
  of South:
    (point.x, point.y + 1)
  of West:
    (point.x - 1, point.y)
  of East:
    (point.x + 1, point.y)

template tileAt(board:Board, point:Point):char =
  board.tiles.getOrDefault(point, ' ')

proc turn(card:Direction, dir:TurnKind):Direction =
  if dir == Left:
    case card
    of North: West
    of West: South
    of South: East
    of East: North
  else:
    case card
    of North: East
    of East: South
    of South: West
    of West: North

proc turnToGet(f:Direction, t:Direction):TurnKind =
  case f
  of North:
    if t == East:
      Right
    elif t == West:
      Left
    else:
      raise newException(CatchableError, &"Can't turn from {f} to {t}")
  of South:
    if t == East:
      Left
    elif t == West:
      Right
    else:
      raise newException(CatchableError, &"Can't turn from {f} to {t}")
  of East:
    if t == North:
      Left
    elif t == South:
      Right
    else:
      raise newException(CatchableError, &"Can't turn from {f} to {t}")
  of West:
    if t == North:
      Right
    elif t == South:
      Left
    else:
      raise newException(CatchableError, &"Can't turn from {f} to {t}")

import os
import terminal

proc solve(board:Board, delay = 100):seq[string] =
  result.add("R")
  board.dir = board.dir.turn(Right)
  while true:
    # stdout.eraseScreen()
    # echo $board
    # sleep(delay)

    # go forward as far as you can
    while board.tileAt(board.bot.plus(board.dir)) == '#':
      board.bot = board.bot.plus(board.dir)
      result.add("1")
    
    # stdout.eraseScreen()
    # echo $board
    # sleep(delay)

    # look for a new path that's not the way we came
    var options = {Left, Right}
    var newd:TurnKind
    var found_newd = false
    for opt in options:
      if board.tileAt(board.bot.plus(board.dir.turn(opt))) == '#':
        newd = opt
        found_newd = true
        break
    if not found_newd:
      echo "done"
      break
    result.add($($newd)[0])
    board.dir = board.dir.turn(newd)

proc collapse(unpacked:seq[string]):string =
  ## Collapse digits in a sequence of numbers and R,L
  var parts:seq[string]
  var amount = 0
  for x in unpacked:
    if x in "0123456789":
      amount.inc(x.parseInt())
    else:
      if amount > 0:
        parts.add($amount)
        amount = 0
      parts.add(x)
  if amount > 0:
    parts.add($amount)
    amount = 0
  return parts.join(",")

proc parseseq(x:string):seq[string] =
  for c in x:
    result.add($c)

proc stringify(x:seq[string]):string =
  x.join("").strip()

proc collapse(x:string):string =
  x.parseseq().collapse()

proc label(unpacked:seq[string], a:string, b:string, c:string):string =
  let s = unpacked.stringify()
  return s.replace(a, "A").replace(b, "B").replace(c, "C")

proc chunkIntoPatterns(x:string, existing_patterns:seq[string] = @[]):seq[seq[string]] =
  # echo "chunkIntoPatterns: ", x
  # echo "  existing: "
  let max_patterns = 3
  for pattern in existing_patterns:
    # echo "    ", pattern
    if x.startsWith(pattern):
      let rest = x[pattern.len .. ^1]
      if rest == "":
        # DONE
        result.add(@[pattern])
      else:
        # not done
        for child in rest.chunkIntoPatterns(existing_patterns):
          var ret:seq[string]
          ret.add(pattern)
          ret.add(child)
          result.add(ret)
  
  if existing_patterns.len < max_patterns:
    for i in 0 .. x.len - 1:
      let pattern = x[0 .. i]
      if pattern.parseseq.collapse.len > 20:
        break
      var newpatterns:seq[string]
      newpatterns.add(existing_patterns)
      newpatterns.add(pattern)
      for child in x.chunkIntoPatterns(newpatterns):
        result.add(child)

import terminal

proc packageRoutines(unpacked:seq[string]):seq[string] =

  let total_len = unpacked.len()
  let origs = unpacked.stringify()
  var valid_chunks:seq[seq[string]]
  for chunk in origs.chunkIntoPatterns():
    var
      a:string
      b:string
      c:string
    var recipe:seq[string]
    for item in chunk:
      if a == "":
        a = item
      elif b == "" and item != a:
        b = item
      elif c == "" and item != b and item != a:
        c = item
      
      if item == a:
        recipe.add("A")
      elif item == b:
        recipe.add("B")
      elif item == c:
        recipe.add("C")
    if recipe.collapse().len > 20:
      continue
    stdout.setForegroundColor(fgDefault)
    for item in chunk:
      if item == a:
        stdout.setForegroundColor(fgBlue)
      elif item == b:
        stdout.setForegroundColor(fgYellow)
      elif item == c:
        stdout.setForegroundColor(fgGreen)
      else:
        stdout.setForegroundColor(fgRed)
      stdout.write(item.parseseq.collapse & ",")
    stdout.write('\L')
    stdout.setForegroundColor(fgDefault)
    valid_chunks.add(@[
      recipe.collapse,
      a.parseseq.collapse,
      b.parseseq.collapse,
      c.parseseq.collapse,
    ])
  return valid_chunks[0]

  # var acount = 0
  # while true:
  #   var cursor = acount
  #   let apattern = unpacked[0 .. (acount-1)]
  #   if apattern.collapse.len > 20:
  #     continue
    
  #   acount.inc()

  # var i = 0
  # for prog in progs():
  #   var
  #     afactor = prog.count("A")
  #     bfactor = prog.count("B")
  #     cfactor = prog.count("C")
  #   for alen in 1 .. total_len - 3:
  #     let apattern = unpacked[0 .. alen]
  #     if apattern.collapse.len > 20:
  #       continue
  #     for blen in 1 .. total_len - 3:
  #       for clen in 1 .. total_len - 3:
  #         if alen*afactor + blen*bfactor + clen*cfactor > total_len:
  #           break

    # for acount in 1 .. total_len - 2:
    #   let apattern = origs[0..(acount-1)]
    #   if apattern.parseseq.collapse.len > 20:
    #     continue
    #   for bcount in 1 .. (total_len - acount - 1):
    #     let bpattern = origs[]
    #   #   let ccount = total_len - acount - bcount
    #   #   let apattern
    #   #   echo &"{acount} {bcount} {ccount}"

    # i.inc()


let inp = """1,330,331,332,109,3914,1101,0,1182,15,1102,1,1457,24,1002,0,1,570,1006,570,36,1002,571,1,0,1001,570,-1,570,1001,24,1,24,1106,0,18,1008,571,0,571,1001,15,1,15,1008,15,1457,570,1006,570,14,21102,1,58,0,1105,1,786,1006,332,62,99,21102,333,1,1,21101,0,73,0,1105,1,579,1101,0,0,572,1101,0,0,573,3,574,101,1,573,573,1007,574,65,570,1005,570,151,107,67,574,570,1005,570,151,1001,574,-64,574,1002,574,-1,574,1001,572,1,572,1007,572,11,570,1006,570,165,101,1182,572,127,1002,574,1,0,3,574,101,1,573,573,1008,574,10,570,1005,570,189,1008,574,44,570,1006,570,158,1106,0,81,21102,1,340,1,1105,1,177,21102,477,1,1,1106,0,177,21102,1,514,1,21101,0,176,0,1105,1,579,99,21102,1,184,0,1105,1,579,4,574,104,10,99,1007,573,22,570,1006,570,165,102,1,572,1182,21101,375,0,1,21101,0,211,0,1106,0,579,21101,1182,11,1,21102,1,222,0,1105,1,979,21102,388,1,1,21101,0,233,0,1106,0,579,21101,1182,22,1,21102,244,1,0,1106,0,979,21101,0,401,1,21101,255,0,0,1105,1,579,21101,1182,33,1,21101,266,0,0,1106,0,979,21101,0,414,1,21102,277,1,0,1105,1,579,3,575,1008,575,89,570,1008,575,121,575,1,575,570,575,3,574,1008,574,10,570,1006,570,291,104,10,21102,1182,1,1,21101,0,313,0,1106,0,622,1005,575,327,1102,1,1,575,21101,327,0,0,1105,1,786,4,438,99,0,1,1,6,77,97,105,110,58,10,33,10,69,120,112,101,99,116,101,100,32,102,117,110,99,116,105,111,110,32,110,97,109,101,32,98,117,116,32,103,111,116,58,32,0,12,70,117,110,99,116,105,111,110,32,65,58,10,12,70,117,110,99,116,105,111,110,32,66,58,10,12,70,117,110,99,116,105,111,110,32,67,58,10,23,67,111,110,116,105,110,117,111,117,115,32,118,105,100,101,111,32,102,101,101,100,63,10,0,37,10,69,120,112,101,99,116,101,100,32,82,44,32,76,44,32,111,114,32,100,105,115,116,97,110,99,101,32,98,117,116,32,103,111,116,58,32,36,10,69,120,112,101,99,116,101,100,32,99,111,109,109,97,32,111,114,32,110,101,119,108,105,110,101,32,98,117,116,32,103,111,116,58,32,43,10,68,101,102,105,110,105,116,105,111,110,115,32,109,97,121,32,98,101,32,97,116,32,109,111,115,116,32,50,48,32,99,104,97,114,97,99,116,101,114,115,33,10,94,62,118,60,0,1,0,-1,-1,0,1,0,0,0,0,0,0,1,0,16,0,109,4,2102,1,-3,586,21001,0,0,-1,22101,1,-3,-3,21102,0,1,-2,2208,-2,-1,570,1005,570,617,2201,-3,-2,609,4,0,21201,-2,1,-2,1106,0,597,109,-4,2106,0,0,109,5,2102,1,-4,629,21001,0,0,-2,22101,1,-4,-4,21102,1,0,-3,2208,-3,-2,570,1005,570,781,2201,-4,-3,653,20101,0,0,-1,1208,-1,-4,570,1005,570,709,1208,-1,-5,570,1005,570,734,1207,-1,0,570,1005,570,759,1206,-1,774,1001,578,562,684,1,0,576,576,1001,578,566,692,1,0,577,577,21101,0,702,0,1106,0,786,21201,-1,-1,-1,1106,0,676,1001,578,1,578,1008,578,4,570,1006,570,724,1001,578,-4,578,21101,731,0,0,1106,0,786,1106,0,774,1001,578,-1,578,1008,578,-1,570,1006,570,749,1001,578,4,578,21101,0,756,0,1105,1,786,1106,0,774,21202,-1,-11,1,22101,1182,1,1,21101,774,0,0,1105,1,622,21201,-3,1,-3,1106,0,640,109,-5,2105,1,0,109,7,1005,575,802,21002,576,1,-6,21002,577,1,-5,1105,1,814,21101,0,0,-1,21102,1,0,-5,21102,1,0,-6,20208,-6,576,-2,208,-5,577,570,22002,570,-2,-2,21202,-5,63,-3,22201,-6,-3,-3,22101,1457,-3,-3,2101,0,-3,843,1005,0,863,21202,-2,42,-4,22101,46,-4,-4,1206,-2,924,21102,1,1,-1,1106,0,924,1205,-2,873,21102,35,1,-4,1106,0,924,1202,-3,1,878,1008,0,1,570,1006,570,916,1001,374,1,374,1201,-3,0,895,1102,2,1,0,1202,-3,1,902,1001,438,0,438,2202,-6,-5,570,1,570,374,570,1,570,438,438,1001,578,558,921,21001,0,0,-4,1006,575,959,204,-4,22101,1,-6,-6,1208,-6,63,570,1006,570,814,104,10,22101,1,-5,-5,1208,-5,39,570,1006,570,810,104,10,1206,-1,974,99,1206,-1,974,1102,1,1,575,21102,1,973,0,1106,0,786,99,109,-7,2105,1,0,109,6,21101,0,0,-4,21101,0,0,-3,203,-2,22101,1,-3,-3,21208,-2,82,-1,1205,-1,1030,21208,-2,76,-1,1205,-1,1037,21207,-2,48,-1,1205,-1,1124,22107,57,-2,-1,1205,-1,1124,21201,-2,-48,-2,1105,1,1041,21101,-4,0,-2,1106,0,1041,21102,-5,1,-2,21201,-4,1,-4,21207,-4,11,-1,1206,-1,1138,2201,-5,-4,1059,2101,0,-2,0,203,-2,22101,1,-3,-3,21207,-2,48,-1,1205,-1,1107,22107,57,-2,-1,1205,-1,1107,21201,-2,-48,-2,2201,-5,-4,1090,20102,10,0,-1,22201,-2,-1,-2,2201,-5,-4,1103,2101,0,-2,0,1106,0,1060,21208,-2,10,-1,1205,-1,1162,21208,-2,44,-1,1206,-1,1131,1105,1,989,21102,439,1,1,1106,0,1150,21101,0,477,1,1105,1,1150,21101,0,514,1,21101,1149,0,0,1105,1,579,99,21101,1157,0,0,1105,1,579,204,-2,104,10,99,21207,-3,22,-1,1206,-1,1138,2102,1,-5,1176,2101,0,-4,0,109,-6,2105,1,0,46,11,52,1,9,1,52,1,9,1,52,1,9,1,12,7,33,1,9,1,12,1,5,1,33,1,9,1,12,1,5,1,9,1,23,1,9,1,12,1,5,1,9,1,23,1,9,1,12,1,5,1,9,1,23,1,9,1,12,1,5,1,9,1,23,1,9,1,12,1,5,13,19,13,12,1,15,1,1,1,19,1,1,1,22,1,15,13,5,7,22,1,17,1,9,1,5,1,3,1,24,1,17,1,9,1,5,1,3,1,24,1,17,1,9,1,5,1,3,1,18,7,17,13,3,1,1,9,46,1,1,1,3,1,1,1,1,1,5,1,46,13,3,1,48,1,3,1,1,1,1,1,1,1,3,1,48,1,3,13,46,1,5,1,1,1,1,1,3,1,1,1,46,9,1,1,3,13,42,1,3,1,5,1,9,1,42,1,3,1,5,1,9,1,42,1,3,1,5,1,9,1,40,7,5,1,9,1,40,1,1,1,9,1,9,1,30,13,9,1,9,1,30,1,9,1,11,1,9,1,30,1,9,1,11,1,9,1,30,1,9,1,11,1,9,1,30,1,9,1,11,11,30,1,9,1,52,1,9,1,52,1,9,1,52,1,9,1,52,1,9,1,52,11,22"""
var parsed = parse_prog(inp)
var board = parsed.getBoard()
echo $board
let solution = board.solve()
echo solution.stringify()
echo solution.collapse()

let inprog = solution.packageRoutines()
var indata:seq[int]
for row in inprog:
  for ch in row:
    indata.add(ord(ch))
  indata.add(ord('\n'))

indata.add(ord('n')) # no video feed
indata.add(ord('\n'))

parsed[0] = 2
let output = parsed.runWithInput(indata)
echo $output