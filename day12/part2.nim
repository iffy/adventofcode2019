import db_sqlite
import sequtils
import algorithm
import strutils

type
  Component = ref object
    pos: int
    vel: int
  Body = ref object
    x: Component
    y: Component
    z: Component

proc newComponent(pos:int, vel:int = 0):Component =
  new(result)
  result.pos = pos
  result.vel = vel

proc newBody(x:int, y:int, z:int):Body =
  new(result)
  result.x = newComponent(x)
  result.y = newComponent(y)
  result.z = newComponent(z)

proc copy(comps:seq[Component]):seq[Component] =
  for thing in comps:
    result.add(newComponent(thing.pos, thing.vel))

proc hash(comp:Component):string =
  return $comp.pos & "," & $comp.vel

proc hash(comps:seq[Component]):string =
  var parts:seq[string]
  for thing in comps:
    parts.add(thing.hash())
  result = parts.join("/")

proc accelFromGravity(a, b:int):int =
  ## Calculate acceleration from two positions
  if a == b:
    return 0
  elif a < b:
    return 1
  else:
    return -1

template applyGravity(toward:Component, frm:Component) =
  ## Apply gravity to `toward` body from `frm` body
  toward.vel += accelFromGravity(toward.pos, frm.pos)

template applyVelocity(comp:Component) =
  comp.pos += comp.vel

proc step(comps:seq[Component]) =
  # update velocity
  for comp1 in comps:
    for comp2 in comps:
      if comp1 == comp2:
        continue
      comp1.applyGravity(comp2)
  
  # update position
  for comp in comps:
    comp.applyVelocity()

proc display(comps:seq[Component]):string =
  let positions = comps.mapIt(it.pos).sorted()
  for i in positions[0]..positions[^1]:
    if i in positions:
      result.add("X")
    else:
      result.add(" ")

proc findCycle(comps:seq[Component]):int =
  ## Find the cycle within a group of positions and velocities
  let initial = comps.hash()
  var step = 0
  while true:
    comps.step()
    step.inc()
    # echo comps.display()
    if comps.hash() == initial:
      break
  return step

proc stepsToRepeat(bodies:seq[Body]):int =
  let xcycle = bodies.mapIt(it.x).findCycle()
  echo "xcycle: ", $xcycle
  let ycycle = bodies.mapIt(it.y).findCycle()
  echo "ycycle: ", $ycycle
  let zcycle = bodies.mapIt(it.z).findCycle()
  echo "zcycle: ", $zcycle
  let interval = max([xcycle, ycycle, zcycle])
  result = interval
  while true:
    if (result mod xcycle == 0) and (result mod ycycle == 0) and (result mod zcycle == 0):
      break
    result += interval

when defined(test):
  import unittest

  test "some":
    echo findCycle(@[
      newComponent(-1),
      newComponent(2),
      newComponent(4),
      newComponent(3),
    ])
    var bodies = @[
      newBody(-1,0,2),
      newBody(2,-10,-7),
      newBody(4,-8,8),
      newBody(3,5,-1),
    ]
    check stepsToRepeat(bodies) == 2772
else:
  var bodies = @[
    newBody(13, -13, -2),
    newBody(16, 2, -15),
    newBody(7, -18, -12),
    newBody(-3, -8, -8),
  ]
  echo stepsToRepeat(bodies)
