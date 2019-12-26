type
  Triple = tuple
    x: int
    y: int
    z: int
  Body = ref object
    pos: Triple
    vel: Triple

proc newBody(x:int, y:int, z:int):Body =
  new(result)
  result.pos = (x,y,z)
  result.vel = (0,0,0)

proc accelFromGravity(a, b:int):int =
  ## Calculate acceleration from two positions
  if a == b:
    return 0
  elif a < b:
    return 1
  else:
    return -1

proc applyGravity(toward:Body, frm:Body) =
  ## Apply gravity to `toward` body from `frm` body
  toward.vel.x += accelFromGravity(toward.pos.x, frm.pos.x)
  toward.vel.y += accelFromGravity(toward.pos.y, frm.pos.y)
  toward.vel.z += accelFromGravity(toward.pos.z, frm.pos.z)

proc applyVelocity(body:Body) =
  body.pos = (
    body.pos.x + body.vel.x,
    body.pos.y + body.vel.y,
    body.pos.z + body.vel.z,
  )

proc step(bodies:seq[Body]) =
  # update velocity
  for body1 in bodies:
    for body2 in bodies:
      if body1 == body2:
        continue
      body1.applyGravity(body2)
  
  # update position
  for body in bodies:
    body.applyVelocity()

template sum(trip:Triple):int =
  abs(trip.x) + abs(trip.y) + abs(trip.z)

proc energy(body:Body):int =
  return body.pos.sum() * body.vel.sum()

proc energy(bodies:seq[Body]):int =
  for body in bodies:
    result += body.energy()

when defined(test):
  import unittest

  test "gravity 1":
    var a = newBody(3,0,0)
    var b = newBody(5,0,0)
    applyGravity(a, b)
    applyGravity(b, a)
    check a.vel.x == 1
    check b.vel.x == -1
  
  test "gravity 2":
    var a = newBody(4,0,0)
    var b = newBody(4,0,0)
    applyGravity(a, b)
    applyGravity(b, a)
    check a.vel.x == 0
    check b.vel.x == 0

  test "some":
    var bodies = @[
      newBody(-1,0,2),
      newBody(2,-10,-7),
      newBody(4,-8,8),
      newBody(3,5,-1),
    ]
    bodies.step()
    check bodies[0].pos == (2,-1,1)
    check bodies[0].vel == (3,-1,-1)
    check bodies[1].pos == (3,-7,-4)
    check bodies[1].vel == (1,3,3)
    for i in 1..9:
      bodies.step()
    check bodies[0].pos == (2,1,-3)
    check bodies[0].vel == (-3,-2,1)

    check energy(bodies) == 179
else:
  var bodies = @[
    newBody(13, -13, -2),
    newBody(16, 2, -15),
    newBody(7, -18, -12),
    newBody(-3, -8, -8),
  ]
  for i in 1..1000:
    bodies.step()
  echo bodies.energy()
