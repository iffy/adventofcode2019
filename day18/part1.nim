import tables
import strutils
import sequtils
import options

type
  Point = tuple
    x: int
    y: int
  State = tuple
    moves: int
    keys: set[char]
    loc: Point
  Board = ref object
    tiles: TableRef[Point, char]
    allkeys: set[char]
    states: TableRef[Point, seq[State]]
  Direction = enum
    Up,
    Down,
    Left,
    Right,

proc plus(point:Point, dir:Direction):Point =
  case dir
  of Up: (point.x, point.y - 1)
  of Down: (point.x, point.y + 1)
  of Left: (point.x - 1, point.y)
  of Right: (point.x + 1, point.y)

proc addState(board:Board, newstate:State) =
  discard board.states.hasKeyOrPut(newstate.loc, @[])
  var toremove = -1
  for i,existing in board.states[newstate.loc]:
    if existing.keys == newstate.keys:
      toremove = i
  if toremove >= 0:
    board.states[newstate.loc].delete(toremove, toremove)
  board.states[newstate.loc].add(newstate)

proc isBetterState(board:Board, newstate:State):bool =
  ## Returns true if the state is better than an existing state
  discard board.states.hasKeyOrPut(newstate.loc, @[])
  result = true
  for existing in board.states[newstate.loc]:
    if existing.keys == newstate.keys:
      result = newstate.moves < existing.moves
      break
  if result:
    board.addState(newstate)

proc move(board:Board, state:State, dir:Direction):Option[State] =
  ## Attempt to move a direction
  let newloc = state.loc.plus(dir)
  let ch = board.tiles.getOrDefault(newloc, ' ')
  case ch
  of '.':
    let newstate:State = (
      moves: state.moves + 1,
      keys: state.keys,
      loc: newloc,
    )
    if board.isBetterState(newstate):
      return some(newstate)
    else:
      return none[State]()
  of 'a'..'z':
    var newkeys = state.keys
    newkeys.incl(ch)
    let newstate:State = (
      moves: state.moves + 1,
      keys: newkeys,
      loc: newloc,
    )
    if board.isBetterState(newstate):
      return some(newstate)
    else:
      return none[State]()
  of 'A'..'Z':
    if state.keys.contains(ch.toLowerAscii()):
      let newstate = (
        moves: state.moves + 1,
        keys: state.keys,
        loc: newloc,
      )
      if board.isBetterState(newstate):
        return some(newstate)
      else:
        return none[State]()
    else:
      return none[State]()
  else:
    return none[State]()

proc parseMap(inp:string):tuple[board:Board, state:State] =
  var loc:Point = (0,0)
  var board:Board
  new(board)
  board.tiles = newTable[Point, char]()
  board.states = newTable[Point, seq[State]]()
  for y, row in toSeq(inp.strip().split('\n')):
    for x, col in row.strip():
      if col == '.' or col in 'a'..'z' or col in 'A'..'Z':
        if col in 'a'..'z':
          board.allkeys.incl(col)
        board.tiles[(x,y)] = col
      elif col == '@':
        board.tiles[(x,y)] = '.'
        loc = (x,y)
  let state:State = (0, {}, loc)
  board.addState(state)
  return (board, state)

proc printMap(board:Board, state:State):string =
  let
    minx = 0
    maxx = max(toSeq(board.tiles.keys()).mapIt(it.x))
    miny = 0
    maxy = max(toSeq(board.tiles.keys()).mapIt(it.y))
  for y in miny .. maxy:
    for x in minx .. maxx:
      var ch = ' '
      if state.loc == (x,y):
        ch = '@'
      else:
        ch = board.tiles.getOrDefault((x,y), ' ')
        if state.keys.contains(ch.toLowerAscii()):
          ch = '.'
      result.add(ch)
    result.add('\n')

proc completedStates(board:Board):seq[State] =
  for states in board.states.values():
    for state in states:
      if state.keys == board.allkeys:
        result.add(state)

proc fewestSteps(x:string):int =
  var parsed = x.parseMap()
  var board = parsed.board
  
  var states:seq[State]
  states.add(parsed.state)
  while states.len > 0:
    let state = states.pop()
    # echo board.printMap(state)
    if state.keys == board.allkeys:
      # this state is complete
      continue
    for d in [Up, Right, Down, Left]:
      let newstate = board.move(state, d)
      if newstate.isSome():
        states.add(newstate.get())
  
  let completed = board.completedStates()
  echo completed
  return min(completed.mapIt(it.moves))

when defined(test):
  import unittest

  test "a":
    check """
    #########
    #b.A.@.a#
    #########
    """.fewestSteps() == 8

  test "b":
    check """
    ########################
    #f.D.E.e.C.b.A.@.a.B.c.#
    ######################.#
    #d.....................#
    ########################
    """.fewestSteps() == 86
  
  test "c":
    check """
    ########################
    #...............b.C.D.f#
    #.######################
    #.....@.a.B.c.d.A.e.F.g#
    ########################
    """.fewestSteps() == 132
  
  test "d":
    check """
    #################
    #i.G..c...e..H.p#
    ########.########
    #j.A..b...f..D.o#
    ########@########
    #k.E..a...g..B.n#
    ########.########
    #l.F..d...h..C.m#
    #################
    """.fewestSteps() == 136
  
  test "e":
    check """
    ########################
    #@..............ac.GI.b#
    ###d#e#f################
    ###A#B#C################
    ###g#h#i################
    ########################
    """.fewestSteps() == 81

else:
  echo """
#################################################################################
#...#.......#...U...#.....#...........#.#.....#.......#...#...#.......#.........#
#.###.#.#####.###.#.#.#####.###.#####.#.#.###.#.#.###H#.#.#.###.#.#####.#######.#
#p..#.#...#...#.#.#...#......c#.#...#...#...#.#.#.#.....#.#.#...#...#...#...#...#
#.#.#N###.#.###.#.#####.#######.#.#.###.###.#.#.#.#######.#I#.#####.#.###.#.#.#.#
#.#.#...#.......#.#.....#.....#...#.#...#...#.#.#.#.....#.#.#.#...#...#...#.#.#.#
###.###.#########.#.#####.###.#####.#.###.###.###.#.###.#.#.#.#.#.#######.#.#.###
#...#...#.#.T.#...#...#...#.#.......#...#...#.....#...#.#...#...#.#..q..#.#.#...#
#.###.###.#.#.#.###.###.###.###.#######.#.#.#########.#.#########.#.###.#.#.###.#
#.#...#...#.#...#...#...#...#...#...#...#.#.........#.#.........#...#.#...#...#.#
#.#.#####.#.#####.###.###.###.###.#.###.#.#########.#.#######.#######.#######.#.#
#...#.....#.....#.#.#...#..b..#...#e..#.#.#...#...#...#.....#.......#.....#...#.#
#.###.###.#####.#.#.###.#######.#####.#.#.#.###.#.#######.#.#######.#.###.#B###.#
#.#...#.#.#...#.#.....#.............#.#.#.#.....#.........#.W.....#.#.#.#.....#.#
#.###.#.#.#.#.#.#####.###############.#.#.#########.#.#######.#####.#.#.#######.#
#.....#...#.#.#...#...#.....#.........#.#.....#...#.#...#.....#...#.#.#.....#...#
#######.###.#K###.#.###.#####.#########.#####.#.#.#####.#######.#.#.#.#.#.#.#.#.#
#.......#...#...#...#.......#...#...#.#.#.#...#.#.......#....d#g#.#...#.#.#.#.#.#
#.#######.#####.#########.#.###.#A#.#.#.#.#.###.#######.#.###.#.#.###.###.###.#.#
#.#...#...#...#.#.......#.#.#...#.#.#...#...#...#.......#.#...#.#...#.#...#...#.#
#.#.#.###.#.###.###.###.###.#.#.#.#.#####.###.#.#########.#.###.###.#.#.#.#.###.#
#...#.....#.....#...#.#.#...#.#.#.#.#...#.#...#.....#...#.#...#.#...#...#.#...#j#
###########.#####.###.#.#.#.#.#.#.#.#.#.#.#######.#.#.#.#.#####.#V###########.###
#.....#.F...#..m..#...#...#.#.#.#.#...#.#.......#.#.#.#.#.#..r#.#.#.........#...#
###Y#.#.#####.###.#.#####.###.###.#####.#######.#.#.#.#.#.#.#.#.#.###.#####.###.#
#...#.#...#...#v#.#.....#.#...#...#.L...#...#...#.#...#.#...#...#...#.#...#.#...#
#.#.#####.#.###.#.#####.###.###.###.###.#.###.#########.###########.#.#.###.#.#.#
#.#.#.....#.#.....#...#...#.......#.#.#.#.....#.......#.........#...#.#...#.#.#.#
#.#.#.#####X#.#####.#.###.#.#######.#.#.#.#####.#####.#.#########.###.###.#.#.#.#
#.#.#.......#.......#.#...#...#.....#...#.#.......#...#.....#.....#...Z.#...#.#.#
#.###################.#.#####.#.#####.###.#######.#.###.###.#.#####.###.#.###.#.#
#.#..............y..#.#.....#.#.#...#...#.........#.#...#...#.#...#.#.#.#.....#.#
#.#D###.###########.#.#####.###.#.#####.###########.#####.#.#.###.#.#.#.###.#####
#.#.#...#...........#.#.....#...#.....#.#..s....#...#...#.#.#...#...#.#...#.#...#
#.#.#.#######.#######.#.#####.###.###.#.#.###.###.###.#.#.#.###.#.###.###.###.#.#
#...#.#.....#.#.......#.#.....#.#.#.#.#.#...#.....#...#...#.#...#.......#k..#.#.#
#.###.#.###.#.#.#######.#.#.###.#.#.#.#.###.#######.#####.###.#############.#.#.#
#...#.R.#...#.#...#...#.#.#...#.#...#...#...#.......#.#...#...#.....#.....#...#.#
###.#####.#######.###.#.#####.#.###.#####.#######.###.#.###.###.###.#.###.#####.#
#.......#.....G.......#.......#...................#.......#.....#..x..#......f..#
#######################################.@.#######################################
#...#o..........#...#.................#.........#.....#...................#.....#
#.###.#.#######.#.#.#.###############.#.#.#.#####.#.#.#.#############.###.#.###.#
#.....#.#.....#.#.#...#.....#.......#.#.#.#.......#.#.#.....#.......#...#...#...#
#.#####.###.###.#.#####.#####.#####.#.#.#.#########.#######.#.#####.#########.#.#
#.#...#...#...#.#...#...#.....#.#...#...#.#.......#.........#.#.#...#.......#.#.#
#.###.###.###.#.###.#.#.#.#####.#.#####.#.#######.###########.#.#.###.#####.#.#.#
#...#...#...#.#.#...#.#.#...#...#.......#...#.....#.....#.....#.......#...#.#.#.#
###.#.#.###.#.#.#.###.#####.#.#.###########.#.#####.###.#.#.###########.#.#.#.###
#.....#.#...#.#...#.#.......#.#.........#...#.......#...#.#.#...#.......#.#.#...#
#########.###.#####.#.#########.#######.#.###.#######.###.###.#.###.#.#####.#.#.#
#.......#.#.....#.....#.......#.#.....#.#.#.#...#...#...#.....#...#.#.#.....#.#.#
#.#####.#.#.###.#.#########.#.#.#.###.#.#.#.###.###.###.#########.#.#.#.#######.#
#...#.....#.#.#...#.......#.#...#.#.#...#.#...#.......#...#.....#.#.#.#.#.......#
#.#.#######.#.#####.#####.#.#####.#.#####.#.#########.###.#.###.#.###.#.#.###.#O#
#.#.#...#.....#.....#...#...#..i#.#...#.#.#.........#.#...#.#...#.#...#.#.#...#.#
###.#.#.#####.###.#####.#####.###.#.#.#.#.###.#.#####.#.###.#.###.#.###.#.#.###.#
#...#.#...#.......#.........#.....#.#.#.#...#.#.......#.#...#...#.#.....#.#...#.#
#.###.###.###########.#######.#####.#.#.###.#.#######.#.#.#####.#.#####.###.#.#.#
#.....#.#...........#...#...#.....#.#.#.#.S.#...#...#.#.#.....#.#.#...#...#.#.#.#
#######.###########.###.#.#.#####.#.#.#.#.###.###.#.###.###.###M#.#.#.###.###.#.#
#.......#.....#...#...#.#.#.....#...#...#...#.#...#.......#.#.#.#...#.#.#.....#.#
#.#.#####.#.#.###.#####.#.#####.#######.###.#.#.#####.#####.#.#.#####.#.###.#####
#.#.....#.#.#.......#.....#...#.......#.#..l#.#.....#.#.....#.#.#...C.#.....#...#
#.#####.#.#.#######.#.#####.#.#####.###.#.#####.###.#.#.#####.#.#.#########.#.#.#
#.#...#z#.#.#.....#.#...#...#.....#.....#.....#.#..w#.#.#...#...#.#.......#.#.#.#
#.#.#J#.#.#.#.#####.###.#.#######.###########.#.#.#####.#.#.#####.#.#####.###.#.#
#.#.#.#...#.#.#.....#...#...#...#.....#.#.....#.#.....#...#...#...#.....#...#.#.#
###.#.#####.#.#.#####.#####.#.###.###.#.#.#####.#####.#######.#.#######.###.#.#.#
#...#.....#.#...#.#...#.#...#...#...#.#.#a#.....#.........#.#.#.......#.#.#...#n#
#.#######.#.#.###.#Q###.#.#####P###.#.#.#.#######.#######.#.#.#.###.###.#.#####.#
#.#.........#.....#.#...#...#...#.#.#...#.#...#...#.....#.#.#.#...#.#.....#...#.#
#.#################.#.#.###.#.#.#.#.#####.#.#.#.###.###.#.#.#.#####.#.#####.#.#.#
#.#.........#.....#.#.#.#.....#...#.....#...#.#.#.#...#.....#.....#.....#...#...#
#.#.#######.#.###.#.###.#.#######.#####.#####.#.#.###.###########.#######.#######
#...#.....#.#.#.#.#...#...#.....#...#.#.#...#...#...#...#.#.....#.#.....#...#...#
#.#####.###.#.#.#.###.#####.###.###.#.#.#.#######.#####.#.#.###.#.#.###.#.#.#.#.#
#...#...#...#.#.#...#.#.....#.#.#.....#.#.......#.....#...#.#.#...#...#.#.#...#.#
###.#.#.#.###.#.#.###.#.#####.#.#######.#.#####.#.###.###.#.#.#######.#.#######.#
#.....#.#.......#....t..#......u........#.....#..h..#...E.#...........#.........#
#################################################################################
""".fewestSteps()