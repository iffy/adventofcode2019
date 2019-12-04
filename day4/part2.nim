import strutils

let
  first = 234208
  last = 765869

proc isvalid(x:int):bool =
  let s = $x
  var
    lastc = ""
    runlen = 0
    has_double = false
  for c in s:
    let c = $c
    if lastc != "":
      let
        last_int = lastc.parseInt()
        c_int = c.parseInt()
      if last_int == c_int:
        # match in row
        runlen.inc()
      else:
        # different character
        if runlen == 1:
          has_double = true
        runlen = 0
    
      if c_int < last_int:
        return false
    lastc = c
  if runlen == 1:
    has_double = true
  return has_double


when defined(test):
  import unittest
  test "foo":
    check 112233.isvalid()
    check 123444.isvalid() == false
    check 111122.isvalid() == true
    check 111223.isvalid() == true
else:
  var num = 0
  for i in first..last:
    if i.isvalid:
      num.inc()
      echo $i

  echo "total: ", $num
