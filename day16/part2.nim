import sequtils
import strutils

proc doLastHalfFFT(data:seq[int]):seq[int] =
  result = newSeq[int](data.len)
  var i = data.len() - 1
  var val = 0
  while i >= 0:
    val = (val + data[i]) mod 10
    result[i] = val
    i.dec()

proc doFFT(start:seq[int], iterations:int, offset = 0):seq[int] =
  var data = start[offset..^1]
  for i in 0 .. iterations - 1:
    data = data.doLastHalfFFT()
  return data

proc doFFT(data:string, iterations:int, offset = 0):string =
  var input:seq[int]
  for c in data:
    input.add(($c).parseInt)
  return input.doFFT(iterations, offset).mapIt($it).join("")

proc getSignal(start:string, iterations:int):string =
  let repeat = 10000
  let offset = start[0..6].parseInt()
  var data:string
  for i in 0 .. repeat-1:
    data.add(start)
  if offset > (data.len / 2).toInt:
    # the pattern is all 1s
    return doFFT(data, iterations, offset)[0 .. 7]
  else:
    raise newException(CatchableError, "I can't do that")

when defined(test):
  import unittest

  test "a":
    check doFFT("12345678", 1) == "48226158"
    check doFFT("48226158", 1) == "34040438"
    check doFFT("34040438", 1) == "03415518"
    check doFFT("03415518", 1) == "01029498"
  
  test "offset":
    check doFFT("12345678", 1, offset = 3) == "26158"
    check doFFT("48226158", 1, offset = 3) == "40438"
    check doFFT("34040438", 1, offset = 3) == "15518"
    check doFFT("03415518", 1, offset = 3) == "29498"

  test "b":
    check doFFT("80871224585914546619083218645595", 100)[0..7] == "24176176"
    check doFFT("19617804207202209144916044189917", 100)[0..7] == "73745418"
    check doFFT("69317163492948606335995924319873", 100)[0..7] == "52432133"

  test "signal":
    check getSignal("03036732577212944063491565474664", 100) == "84462026"
    check getSignal("02935109699940807407585447034323", 100) == "78725270"
    check getSignal("03081770884921959731165446850517", 100) == "53553731"

else:
  echo getSignal("59791871295565763701016897619826042828489762561088671462844257824181773959378451545496856546977738269316476252007337723213764111739273853838263490797537518598068506295920453784323102711076199873965167380615581655722603274071905196479183784242751952907811639233611953974790911995969892452680719302157414006993581489851373437232026983879051072177169134936382717591977532100847960279215345839529957631823999672462823375150436036034669895698554251454360619461187935247975515899240563842707592332912229870540467459067349550810656761293464130493621641378182308112022182608407992098591711589507803865093164025433086372658152474941776320203179747991102193608", 100)