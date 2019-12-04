import strutils

let
  first = 234208
  last = 765869

proc isvalid(x:int):bool =
  let s = $x
  var
    lastc = ""
    has_double = false
  for c in s:
    let c = $c
    if lastc != "":
      let
        last_int = lastc.parseInt()
        c_int = c.parseInt()
      if last_int == c_int:
        has_double = true
      if c_int < last_int:
        return false
    lastc = c
  return has_double


var num = 0
for i in first..last:
  if i.isvalid:
    num.inc()
    echo $i

echo "total: ", $num
