import strutils
import math

proc fuel_required(mass:int):int =
  floor(mass / 3).toInt - 2

proc total_fuel_required(mass:int):int =
  var last = mass
  while last > 0:
    last = last.fuel_required()
    if last > 0:
      result.inc(last)
    

when defined(testmode):
  import unittest

  test "given":
    check total_fuel_required(14) == 2
    check total_fuel_required(1969) == 966
    check total_fuel_required(100756) == 50346
else:
  var total = 0
  for line in open("dec1_input.txt", fmRead).lines:
    if line.len > 0:
      total.inc(total_fuel_required(line.parseInt))
    else:
      echo line
  echo total