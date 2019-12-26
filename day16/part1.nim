import sequtils
import strutils

const PAT = @[0,1,0,-1]

proc coefficients(n:int, length:int, pattern = PAT):seq[int] =
  var first = true
  while true:
    for num in pattern:
      for i in 0 .. n:
        if first:
          first = false
        else:
          result.add(num)
          if result.len == length:
            return

proc oneFFT(data:seq[int], pattern = PAT):seq[int] =
  for i in 0 .. data.len()-1:
    var num:int
    for pair in zip(coefficients(i, data.len, pattern), data):
      num += pair.a * pair.b
    result.add(num.abs() mod 10)

proc doFFT(start:seq[int], iterations:int, pattern = PAT):seq[int] =
  var data = start
  for i in 0 .. iterations - 1:
    data = data.oneFFT(pattern)
  return data

proc doFFT(start:string, iterations:int, pattern = PAT):string =
  var input:seq[int]
  for c in start:
    input.add(($c).parseInt)
  return input.doFFT(iterations, pattern).mapIt($it).join("")

when defined(test):
  import unittest

  test "a":
    check doFFT("12345678", 1) == "48226158"
    check doFFT("48226158", 1) == "34040438"
    check doFFT("34040438", 1) == "03415518"
    check doFFT("03415518", 1) == "01029498"

  test "b":
    check doFFT("80871224585914546619083218645595", 100)[0..7] == "24176176"
    check doFFT("19617804207202209144916044189917", 100)[0..7] == "73745418"
    check doFFT("69317163492948606335995924319873", 100)[0..7] == "52432133"

else:
  echo doFFT("59791871295565763701016897619826042828489762561088671462844257824181773959378451545496856546977738269316476252007337723213764111739273853838263490797537518598068506295920453784323102711076199873965167380615581655722603274071905196479183784242751952907811639233611953974790911995969892452680719302157414006993581489851373437232026983879051072177169134936382717591977532100847960279215345839529957631823999672462823375150436036034669895698554251454360619461187935247975515899240563842707592332912229870540467459067349550810656761293464130493621641378182308112022182608407992098591711589507803865093164025433086372658152474941776320203179747991102193608", 100)[0..7]