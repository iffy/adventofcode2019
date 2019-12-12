import sets
import strutils
import math

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

proc angle(a, b:Point):float =
  let
    xdiff = (b.x - a.x).toFloat()
    ydiff = (b.y - a.y).toFloat()
  arctan2(ydiff, xdiff)

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

proc bestLocationCount(space:Space):int =
  for asteroid in space.asteroids:
    result = max(result, space.visibleAsteroids(asteroid))

when defined(test):
  import unittest
  test "first":
    check parseMap("""
      .#..#
      .....
      #####
      ....#
      ...##
    """).bestLocationCount() == 8
  test "second":
    check parseMap("""
      ......#.#.
      #..#.#....
      ..#######.
      .#.#.###..
      .#..#.....
      ..#....#.#
      #..#....#.
      .##.#..###
      ##...#..#.
      .#....####
    """).bestLocationCount() == 33
  test "third":
    check parseMap("""
      #.#...#.#.
      .###....#.
      .#....#...
      ##.#.#.#.#
      ....#.#.#.
      .##..###.#
      ..#...##..
      ..##....##
      ......#...
      .####.###.
    """).bestLocationCount() == 35
  test "fourth":
    check parseMap("""
      .#..#..###
      ####.###.#
      ....###.#.
      ..###.##.#
      ##.##.#.#.
      ....###..#
      ..#.#..#.#
      #..#.#.###
      .##...##.#
      .....#.#..
    """).bestLocationCount() == 41
  test "fifth":
    check parseMap("""
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
    """).bestLocationCount() == 210

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
  """).bestLocationCount()