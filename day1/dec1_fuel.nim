import strutils
import math

proc fuel_required(mass:int):int =
  floor(mass / 3).toInt - 2

when defined(testmode):
  import unittest
  test "given":
    check fuel_required(12) == 2
    check fuel_required(14) == 2
    check fuel_required(1969) == 654
    check fuel_required(100756) == 33583

else:
  var total = 0
  for line in open("dec1_input.txt", fmRead).lines:
    total.inc(fuel_required(line.parseInt))
  echo total
