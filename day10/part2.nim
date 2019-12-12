import sets
import strutils
import sequtils
import math
import tables
import algorithm

type
  Point = tuple
    x: int
    y: int

  Space = ref object
    width: int
    height: int
    asteroids: HashSet[Point]

proc parseMap(x:string):Space =
  new(result)
  var x = x.strip().split("\n")
  result.height = x.len
  result.width = x[0].strip().len
  result.asteroids.init()
  for row,line in x:
    let line = line.strip()
    for col,ch in line:
      if ch == '#':
        result.asteroids.incl((x:col, y:row))

proc `$`(space:Space):string =
  for row in 0 .. space.height-1:
    for col in 0 .. space.width-1:
      if space.asteroids.contains((x:col, y:row)):
        result.add('#')
      else:
        result.add('.')
    result.add('\n')

proc show(space:Space, markers:seq[Point]):string =
  for row in 0 .. space.height-1:
    for col in 0 .. space.width-1:
      let point = (x:col, y:row)
      if point in markers:
        result.add($markers.find(point))
      else:
        if space.asteroids.contains((x:col, y:row)):
          result.add('#')
        else:
          result.add('.')
    result.add('\n')

proc angle(a, b:Point):float =
  let
    xdiff = (b.x - a.x).toFloat()
    ydiff = (b.y - a.y).toFloat()
  result = arctan2(-ydiff, -xdiff)
  # let's make it 0 at the top and move clockwise to 2PI
  if result < 0:
    result = (2 * PI) + result
  # result = (2*PI) - result
  result += (3 * PI / 2)
  result = result mod (2 * PI)
  # if b.y > a.y and result == 0.0:
  #   result = PI * 3 / 2

proc distance(a, b: Point):float =
  let
    xdiff = (b.x - a.x).toFloat()
    ydiff = (b.y - a.y).toFloat()
  sqrt(xdiff*xdiff + ydiff*ydiff)

proc visibleAsteroids(space:Space, point:Point):int =
  ## Return number of asteroids visible from a point
  var used_angles:HashSet[float]
  used_angles.init()

  for asteroid in space.asteroids:
    if asteroid == point:
      continue
    let angle = angle(point, asteroid)
    if angle in used_angles:
      continue
    used_angles.incl(angle)
    result.inc()

proc bestLocation(space:Space):Point =
  var current_best = 0
  for asteroid in space.asteroids:
    let visible = space.visibleAsteroids(asteroid)
    if visible > current_best:
      result = asteroid
      current_best = visible


proc vaporize(space:Space):seq[Point] =
  let home = space.bestLocation()
  var byangle = newTable[float,seq[Point]]()
  for asteroid in space.asteroids:
    if asteroid == home:
      continue
    let angle = home.angle(asteroid)
    if not byangle.hasKey(angle):
      byangle[angle] = @[]
    byangle[angle].add(asteroid)

  while byangle.len > 0:
    let keys = toSeq(byangle.keys()).sorted()
    for key in keys:
      var candidates = byangle[key].sortedByIt(distance(home, it))
      let zapped = candidates[0]
      result.add(zapped)
      let idx = byangle[key].find(zapped)
      byangle[key].delete(idx)
      if byangle[key].len == 0:
        byangle.del(key)
      space.asteroids.excl(zapped)
      echo space.show(@[home, zapped])

when defined(test):
  import unittest
  test "angle":
    check angle((x:0, y:0), (x:1, y:0)) == (PI / 2)
    check angle((x:0, y:0), (x: -1, y:0)) == (3 * PI / 2)
    check angle((x:0, y:0), (x:0, y:1)) == PI
    check angle((x:0, y:0), (x:0, y: -1)) == 0.0

  test "func":
    let space = parseMap("""
      .#..##.###...#######
      ##.############..##.
      .#.######.########.#
      .###.#######.####.#.
      #####.##.#.##.###.##
      ..#####..#.#########
      ####################
      #.####....###.#.#.##
      ##.#################
      #####.##.###..####..
      ..######..##.#######
      ####.##.####...##..#
      .#####..#.######.###
      ##...#.##########...
      #.##########.#######
      .####.#.###.###.#.##
      ....##.##.###..#####
      .#.#.###########.###
      #.#.#.#####.####.###
      ###.##.####.##.#..##
    """)
    let vaped = space.vaporize()
    check vaped[0] == (x:11,y:12)
    check vaped[1 - 1] == (x:11, y:12)
    check vaped[2 - 1] == (x:12, y:1)
    check vaped[3 - 1] == (x:12, y:2)
    check vaped[10 - 1] == (x:12, y:8)
    check vaped[20 - 1] == (x:16, y:0)
    check vaped[50 - 1] == (x:16, y:9)
    check vaped[100 - 1] == (x:10, y:16)
    check vaped[199 - 1] == (x:9, y:6)
    check vaped[200 - 1] == (x:8, y:2)
    check vaped[201 - 1] == (x:10, y:9)
    check vaped[299 - 1] == (x:11, y:1)

else:
  echo $parseMap("""
    #...##.####.#.......#.##..##.#.
    #.##.#..#..#...##..##.##.#.....
    #..#####.#......#..#....#.###.#
    ...#.#.#...#..#.....#..#..#.#..
    .#.....##..#...#..#.#...##.....
    ##.....#..........##..#......##
    .##..##.#.#....##..##.......#..
    #.##.##....###..#...##...##....
    ##.#.#............##..#...##..#
    ###..##.###.....#.##...####....
    ...##..#...##...##..#.#..#...#.
    ..#.#.##.#.#.#####.#....####.#.
    #......###.##....#...#...#...##
    .....#...#.#.#.#....#...#......
    #..#.#.#..#....#..#...#..#..##.
    #.....#..##.....#...###..#..#.#
    .....####.#..#...##..#..#..#..#
    ..#.....#.#........#.#.##..####
    .#.....##..#.##.....#...###....
    ###.###....#..#..#.....#####...
    #..##.##..##.#.#....#.#......#.
    .#....#.##..#.#.#.......##.....
    ##.##...#...#....###.#....#....
    .....#.######.#.#..#..#.#.....#
    .#..#.##.#....#.##..#.#...##..#
    .##.###..#..#..#.###...#####.#.
    #...#...........#.....#.......#
    #....##.#.#..##...#..####...#..
    #.####......#####.....#.##..#..
    .#...#....#...##..##.#.#......#
    #..###.....##.#.......#.##...##
  """).vaporize()[200-1]