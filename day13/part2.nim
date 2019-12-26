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

import terminal

type
  TileKind = enum
    Empty,
    Wall,
    Block,
    HPaddle,
    Ball,
  Point = tuple
    x: int
    y: int

proc toTileKind(x:int):TileKind =
  case x
  of 0: Empty
  of 1: Wall
  of 2: Block
  of 3: HPaddle
  of 4: Ball
  else:
    raise newException(CatchableError, &"Invalid TileKind: {x}")

proc `$`(tile:TileKind):char =
  case tile
  of Empty: ' '
  of Wall: 'H'
  of Block: 'O'
  of HPaddle: '-'
  of Ball: 'o'

proc displayBoard(board:TableRef[Point, TileKind]) =
  # stdout.eraseScreen()
  for pos in board.keys():
    echo pos
    stdout.setCursorPos(pos.x, pos.y)
    stdout.write($board[pos])
  # echo "hi"

import os

proc playGame(prog:seq[int], delay = 10):int=
  var
    in_queue: SimpleQueue[int]
    out_queue: SimpleQueue[int]
  new(in_queue)
  new(out_queue)

  var board = newTable[Point, TileKind]()
  var score = 0
  var ball_x = 0
  var paddle_x = 0
  var p = prog.run(in_queue, out_queue)
  stdout.eraseScreen()
  stdout.hideCursor()
  while out_queue.pending_values() > 0:
    while out_queue.pending_values() > 0:
      let
        x = out_queue.get().read()
        y = out_queue.get().read()
        kind = out_queue.get().read()
      
      if x == -1 and y == 0:
        var score = kind
        stdout.setCursorPos(0, 0)
        stdout.eraseLine()
        stdout.write($score)
      else:
        let kind = kind.toTileKind()
        if kind == Ball:
          ball_x = x
        elif kind == HPaddle:
          paddle_x = x
        board[(x,y)] = kind
        stdout.setCursorPos(x, y+1)
        stdout.write($kind)
    sleep(delay)
    stdout.flushFile()

    if ball_x > paddle_x:
      in_queue.put(1)
    elif ball_x < paddle_x:
      in_queue.put(-1)
    else:
      in_queue.put(0)

  stdout.showCursor()
  sleep(1000)
  return score

let inp = """1,380,379,385,1008,2607,501667,381,1005,381,12,99,109,2608,1101,0,0,383,1101,0,0,382,20102,1,382,1,20102,1,383,2,21101,37,0,0,1106,0,578,4,382,4,383,204,1,1001,382,1,382,1007,382,41,381,1005,381,22,1001,383,1,383,1007,383,24,381,1005,381,18,1006,385,69,99,104,-1,104,0,4,386,3,384,1007,384,0,381,1005,381,94,107,0,384,381,1005,381,108,1105,1,161,107,1,392,381,1006,381,161,1102,-1,1,384,1105,1,119,1007,392,39,381,1006,381,161,1102,1,1,384,20102,1,392,1,21102,22,1,2,21102,0,1,3,21102,138,1,0,1105,1,549,1,392,384,392,21001,392,0,1,21102,1,22,2,21102,3,1,3,21101,0,161,0,1106,0,549,1102,0,1,384,20001,388,390,1,20102,1,389,2,21102,1,180,0,1105,1,578,1206,1,213,1208,1,2,381,1006,381,205,20001,388,390,1,20102,1,389,2,21102,1,205,0,1105,1,393,1002,390,-1,390,1102,1,1,384,20101,0,388,1,20001,389,391,2,21102,228,1,0,1105,1,578,1206,1,261,1208,1,2,381,1006,381,253,20102,1,388,1,20001,389,391,2,21102,1,253,0,1106,0,393,1002,391,-1,391,1102,1,1,384,1005,384,161,20001,388,390,1,20001,389,391,2,21102,1,279,0,1105,1,578,1206,1,316,1208,1,2,381,1006,381,304,20001,388,390,1,20001,389,391,2,21101,304,0,0,1106,0,393,1002,390,-1,390,1002,391,-1,391,1101,0,1,384,1005,384,161,21002,388,1,1,20102,1,389,2,21101,0,0,3,21102,338,1,0,1105,1,549,1,388,390,388,1,389,391,389,20102,1,388,1,20101,0,389,2,21101,4,0,3,21101,0,365,0,1106,0,549,1007,389,23,381,1005,381,75,104,-1,104,0,104,0,99,0,1,0,0,0,0,0,0,420,18,19,1,1,20,109,3,21201,-2,0,1,22102,1,-1,2,21101,0,0,3,21101,0,414,0,1106,0,549,22101,0,-2,1,22102,1,-1,2,21101,0,429,0,1106,0,601,1201,1,0,435,1,386,0,386,104,-1,104,0,4,386,1001,387,-1,387,1005,387,451,99,109,-3,2106,0,0,109,8,22202,-7,-6,-3,22201,-3,-5,-3,21202,-4,64,-2,2207,-3,-2,381,1005,381,492,21202,-2,-1,-1,22201,-3,-1,-3,2207,-3,-2,381,1006,381,481,21202,-4,8,-2,2207,-3,-2,381,1005,381,518,21202,-2,-1,-1,22201,-3,-1,-3,2207,-3,-2,381,1006,381,507,2207,-3,-4,381,1005,381,540,21202,-4,-1,-1,22201,-3,-1,-3,2207,-3,-4,381,1006,381,529,22102,1,-3,-7,109,-8,2106,0,0,109,4,1202,-2,41,566,201,-3,566,566,101,639,566,566,2101,0,-1,0,204,-3,204,-2,204,-1,109,-4,2106,0,0,109,3,1202,-1,41,594,201,-2,594,594,101,639,594,594,20101,0,0,-2,109,-3,2105,1,0,109,3,22102,24,-2,1,22201,1,-1,1,21102,1,499,2,21101,766,0,3,21102,984,1,4,21102,630,1,0,1106,0,456,21201,1,1623,-2,109,-3,2106,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,2,2,0,0,2,2,2,0,2,2,0,2,2,0,2,0,2,2,2,2,0,0,0,2,2,2,2,0,2,2,2,2,0,2,2,2,0,1,1,0,2,2,0,0,0,2,2,2,0,0,2,2,2,0,0,0,0,0,2,2,2,2,2,0,2,0,2,2,2,2,2,2,0,0,2,2,0,0,1,1,0,2,2,2,2,2,2,2,0,2,2,2,2,2,0,2,2,0,0,2,2,2,0,2,2,2,0,0,2,0,0,2,2,2,2,2,0,2,0,1,1,0,2,2,2,2,2,0,2,2,2,0,2,2,2,2,0,0,0,0,2,2,2,2,2,2,0,2,2,0,0,0,2,2,2,0,0,0,2,0,1,1,0,2,2,2,0,2,2,2,2,2,2,2,2,0,0,0,0,2,0,2,0,2,2,2,0,2,2,2,2,2,2,2,2,0,2,0,2,2,0,1,1,0,2,2,2,2,2,2,0,0,2,0,0,0,2,2,2,0,0,2,0,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0,0,2,2,0,1,1,0,0,2,2,2,2,0,2,2,2,0,2,2,2,2,2,2,2,2,0,2,2,2,2,2,0,0,2,2,2,2,2,0,0,0,2,0,2,0,1,1,0,0,2,2,0,2,2,0,2,2,0,0,2,2,2,2,2,0,2,2,0,2,2,2,2,2,2,2,2,2,2,2,0,2,0,2,2,2,0,1,1,0,2,0,2,0,0,2,0,0,2,2,2,0,2,2,0,2,2,2,2,2,2,2,2,0,2,2,2,2,2,0,2,2,2,2,2,2,0,0,1,1,0,2,2,2,2,2,2,2,2,2,0,2,2,0,2,2,0,0,0,2,2,0,2,2,2,2,2,2,2,0,2,2,0,0,2,0,2,0,0,1,1,0,2,0,0,0,2,2,0,2,0,2,2,0,2,2,2,2,0,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0,2,0,0,1,1,0,2,2,2,0,2,2,2,0,0,2,2,2,0,2,2,0,2,2,2,2,2,2,0,2,2,2,2,2,0,0,0,2,0,2,2,2,0,0,1,1,0,2,2,2,2,0,2,0,2,0,0,2,2,2,2,0,0,0,2,2,2,2,0,2,2,2,0,0,2,2,2,2,2,2,2,2,2,2,0,1,1,0,0,2,2,0,0,2,2,2,2,2,2,2,2,2,0,2,2,2,2,2,2,0,2,2,2,0,2,2,2,0,0,2,2,2,0,2,2,0,1,1,0,2,2,0,0,0,2,2,2,2,0,2,0,0,2,2,0,2,2,2,2,0,0,2,2,2,0,2,2,2,0,2,2,2,0,2,2,2,0,1,1,0,2,2,2,2,2,0,0,2,0,2,2,2,0,2,2,2,2,2,2,0,2,0,2,2,2,2,0,2,0,0,2,0,2,2,0,2,2,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,68,30,70,17,8,95,58,65,89,47,70,26,8,7,65,13,54,62,14,76,19,56,81,92,65,56,46,12,32,48,52,92,70,30,90,26,97,53,52,49,43,93,5,20,81,91,23,4,60,46,14,90,66,33,56,57,89,29,17,45,81,11,39,9,97,68,86,36,92,25,41,66,92,50,25,96,70,82,96,45,47,26,21,97,16,55,93,90,14,24,86,65,19,44,66,36,60,86,79,95,47,37,82,8,34,17,89,74,17,74,40,97,43,92,26,94,14,58,9,68,48,32,42,60,31,35,96,88,71,93,80,78,66,32,76,13,45,86,53,31,82,77,11,69,67,63,88,16,94,77,48,11,90,53,54,12,92,27,66,77,86,31,36,91,50,55,98,72,53,92,33,64,61,23,52,31,25,69,89,18,94,1,80,83,30,13,47,71,91,35,55,19,89,57,92,77,46,54,77,59,9,13,20,4,57,81,22,61,33,83,18,38,24,41,83,48,70,82,33,7,8,41,56,47,85,89,85,65,93,40,95,73,47,87,24,42,10,64,71,77,57,18,21,8,30,83,55,10,94,19,52,80,89,67,40,1,80,60,36,71,80,77,62,16,23,40,68,50,17,81,26,22,65,92,47,46,43,21,81,20,50,40,84,90,97,73,95,39,12,76,9,41,92,59,8,10,32,54,34,59,32,26,74,63,90,13,46,96,40,98,52,34,65,95,16,73,54,74,28,73,2,36,69,19,68,71,33,24,44,53,56,7,58,25,15,49,77,40,30,59,87,29,36,65,71,92,21,14,44,5,4,34,87,81,71,36,42,59,20,76,36,39,27,68,62,85,80,96,66,56,96,86,53,60,52,7,65,77,8,51,88,10,26,77,74,57,78,22,19,6,86,33,91,66,15,81,15,37,36,98,17,48,82,5,37,82,76,36,65,17,18,54,47,73,5,54,84,77,4,73,16,54,10,12,6,76,97,45,63,30,26,54,97,60,44,12,80,94,33,16,43,88,85,52,5,73,30,23,41,76,10,92,79,13,52,95,67,4,41,10,96,7,92,80,33,2,60,25,83,49,20,42,83,31,49,71,25,74,52,48,83,12,50,26,13,86,21,21,50,7,31,71,77,12,91,2,18,93,22,15,28,40,27,41,84,10,85,93,65,67,13,80,36,10,52,79,2,29,18,48,47,42,4,12,12,75,44,41,21,75,69,6,63,61,29,51,59,58,9,70,25,57,39,67,83,6,90,63,56,2,58,96,5,94,85,22,92,14,58,91,16,1,55,58,24,77,74,41,70,49,90,23,26,54,74,70,40,65,38,31,2,80,93,21,60,56,3,94,87,53,73,59,73,26,21,76,66,94,81,60,43,39,14,18,89,33,73,47,2,96,50,76,84,27,43,1,29,45,59,37,81,82,56,19,71,20,90,48,67,21,16,16,40,77,22,96,32,47,15,87,74,42,98,97,52,83,96,9,51,95,34,29,16,44,3,32,65,86,25,93,1,20,95,26,6,22,58,33,46,3,38,94,95,85,57,52,11,14,12,28,86,92,55,45,26,60,57,21,3,84,7,12,57,17,86,41,46,37,89,4,91,1,12,46,71,5,84,21,83,7,56,95,40,20,26,65,51,90,2,64,33,69,4,92,58,88,8,58,46,31,19,24,35,28,40,58,52,4,56,28,38,6,89,73,74,94,16,70,59,93,8,66,8,50,89,56,5,5,71,30,86,20,70,64,35,90,54,59,1,36,3,40,31,37,77,21,74,38,7,15,5,43,14,67,38,96,90,36,84,81,66,8,33,77,73,64,3,35,96,12,91,71,60,43,30,44,87,61,21,37,68,43,24,29,26,57,75,31,76,36,32,92,95,39,54,75,79,90,98,49,34,38,79,55,53,36,47,35,3,79,89,70,84,43,58,7,92,57,96,96,23,35,59,56,78,9,4,42,35,46,86,61,34,36,89,33,5,51,56,88,34,10,44,86,95,95,20,97,15,41,85,42,37,1,8,29,48,10,6,51,61,53,97,72,83,8,41,15,27,38,20,70,59,70,66,95,31,46,22,73,68,27,45,31,61,51,10,5,81,37,27,34,30,95,83,67,10,52,26,87,56,64,70,78,14,86,76,94,15,82,70,18,26,48,94,15,52,39,47,51,15,51,20,14,23,45,29,8,9,47,9,30,27,76,57,98,57,73,72,13,35,26,45,70,30,84,91,65,12,6,91,98,78,40,501667"""
var parsed = parse_prog(inp)
parsed[0] = 2
discard playGame(parsed, 0)

