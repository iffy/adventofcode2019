import tables
import math
import sequtils
import strformat
import strutils
import logging

type
  Material = tuple
    quantity: int
    name: string
  Formula = tuple
    output: Material
    inputs: seq[Material]

proc `$`(m:Material):string =
  return &"{m.quantity} {m.name}"

proc `$`(f:Formula):string =
  result.add(f.inputs.mapIt($it).join(", "))
  result.add(" => ")
  result.add($f.output)

proc parseMaterial(x:string):Material =
  let parts = x.strip().split(" ", 1)
  let quantity = parts[0].strip().parseInt()
  result = (quantity, parts[1])

proc parseFormulas(x:string):TableRef[string,Formula] =
  new(result)
  for line in x.strip().split('\L'):
    let line = line.strip()
    let parts = line.split(" => ", 1)
    let inputs = parts[0].split(",").mapIt(it.parseMaterial)
    let output = parts[1].parseMaterial()
    result[output.name] = (output, inputs)

const
  fuel = "FUEL"
  ore = "ORE"

proc use(stock:TableRef[string,int], mat:Material):Material =
  ## Given a needed amount, use whatever's from the stockpile and
  ## return the rest
  var instock = stock.getOrDefault(mat.name, 0)
  if instock >= mat.quantity:
    # stock has enough
    stock[mat.name] = instock - mat.quantity
    return (0, mat.name)
  elif mat.quantity > instock:
    # stock doesn't have enough
    stock[mat.name] = 0
    return (mat.quantity - instock, mat.name)

proc add(stock:TableRef[string,int], mat:Material) =
  var current = stock.getOrDefault(mat.name, 0)
  stock[mat.name] = current + mat.quantity


proc oreForFuel(formulas:TableRef[string, Formula], quantity:int):int =
  var total_ore = 0
  
  var needs:seq[Material]
  var stock = newTable[string,int]()

  needs.add((quantity, fuel))
  while needs.len > 0:
    var need = needs.pop()
    debug "stock: ", $stock
    debug "NEED ", need
    
    if need.name == ore:
      total_ore += need.quantity
    else:
      let formula = formulas[need.name]

      # use what's already been made
      need = stock.use(need)

      var factor = floor(need.quantity / formula.output.quantity).toInt
      if (need.quantity mod formula.output.quantity) > 0:
        # not quite enough to fulfill the order
        factor.inc()
      debug &" {factor} x ({formula})"
      
      # make it
      let produced = factor * formula.output.quantity
      debug &" --> {produced} {need.name}"
      
      # save the leftover
      let leftover = produced - need.quantity
      if leftover > 0:
        debug &" sto {leftover} {need.name}"
        stock.add((leftover, need.name))
      
      for inp in formula.inputs:
        needs.add((inp.quantity * factor, inp.name))
  result = total_ore
  

proc howMuchFuel(x:string, available_ore = 1000000000000):int =
  let formulas = x.parseFormulas()
  var fuel = 1
  var upper_bound = 0
  var lower_bound = 0
  while true:
    let ore_required = formulas.oreForFuel(fuel)
    if ore_required < available_ore:
      lower_bound = fuel - 1
      fuel *= 2
    else:
      upper_bound = fuel + 1
      break
  
  while true:
    # since I'm not very good at getting binary search exactly right
    if lower_bound == upper_bound:
      return lower_bound

    
    var guess = floor((upper_bound - lower_bound) / 2).toInt() + lower_bound
    if guess == lower_bound:
      return lower_bound
    let ore_required = formulas.oreForFuel(guess)
    if ore_required == available_ore:
      return guess
    elif ore_required < available_ore:
      lower_bound = guess
    else:
      upper_bound = guess

when defined(test):
  import unittest
  
  test "b":
    check howMuchFuel("""
    157 ORE => 5 NZVS
    165 ORE => 6 DCFZ
    44 XJWVT, 5 KHKGT, 1 QDVJ, 29 NZVS, 9 GPVTF, 48 HKGWZ => 1 FUEL
    12 HKGWZ, 1 GPVTF, 8 PSHF => 9 QDVJ
    179 ORE => 7 PSHF
    177 ORE => 5 HKGWZ
    7 DCFZ, 7 PSHF => 2 XJWVT
    165 ORE => 2 GPVTF
    3 DCFZ, 7 NZVS, 5 HKGWZ, 10 PSHF => 8 KHKGT""") == 82892753
  
  test "c":
    check howMuchFuel("""
    2 VPVL, 7 FWMGM, 2 CXFTF, 11 MNCFX => 1 STKFG
    17 NVRVD, 3 JNWZP => 8 VPVL
    53 STKFG, 6 MNCFX, 46 VJHF, 81 HVMC, 68 CXFTF, 25 GNMV => 1 FUEL
    22 VJHF, 37 MNCFX => 5 FWMGM
    139 ORE => 4 NVRVD
    144 ORE => 7 JNWZP
    5 MNCFX, 7 RFSQX, 2 FWMGM, 2 VPVL, 19 CXFTF => 3 HVMC
    5 VJHF, 7 MNCFX, 9 VPVL, 37 CXFTF => 6 GNMV
    145 ORE => 6 MNCFX
    1 NVRVD => 8 CXFTF
    1 VJHF, 6 MNCFX => 4 RFSQX
    176 ORE => 6 VJHF""") == 5586022
  
  test "d":
    check howMuchFuel("""
    171 ORE => 8 CNZTR
    7 ZLQW, 3 BMBT, 9 XCVML, 26 XMNCP, 1 WPTQ, 2 MZWV, 1 RJRHP => 4 PLWSL
    114 ORE => 4 BHXH
    14 VRPVC => 6 BMBT
    6 BHXH, 18 KTJDG, 12 WPTQ, 7 PLWSL, 31 FHTLT, 37 ZDVW => 1 FUEL
    6 WPTQ, 2 BMBT, 8 ZLQW, 18 KTJDG, 1 XMNCP, 6 MZWV, 1 RJRHP => 6 FHTLT
    15 XDBXC, 2 LTCX, 1 VRPVC => 6 ZLQW
    13 WPTQ, 10 LTCX, 3 RJRHP, 14 XMNCP, 2 MZWV, 1 ZLQW => 1 ZDVW
    5 BMBT => 4 WPTQ
    189 ORE => 9 KTJDG
    1 MZWV, 17 XDBXC, 3 XCVML => 2 XMNCP
    12 VRPVC, 27 CNZTR => 2 XDBXC
    15 KTJDG, 12 BHXH => 5 XCVML
    3 BHXH, 2 VRPVC => 7 MZWV
    121 ORE => 7 VRPVC
    7 XCVML => 6 RJRHP
    5 BHXH, 4 VRPVC => 5 LTCX
    """) == 460664

else:
  echo howMuchFuel("""
  1 GZJM, 2 CQFGM, 20 SNPQ, 7 RVQG, 3 FBTV, 27 SQLH, 10 HFGCF, 3 ZQCH => 3 SZCN
4 FCDL, 6 NVPW, 21 GZJM, 1 FBTV, 1 NLSNB, 7 HFGCF, 3 SNPQ => 1 LRPK
15 FVHTD, 2 HBGFL => 4 BCVLZ
4 GFGS => 4 RVQG
5 BCVLZ, 4 LBQV => 7 TWSRV
6 DWKTF, 4 VCKL => 4 KDJV
16 WZJB => 4 RBGJQ
8 RBGJQ, 5 FCDL, 2 LWBQ => 1 MWSX
100 ORE => 7 WBRL
7 PGZGQ => 5 FVHTD
1 JCDML, 2 TWSRV => 9 JSQSB
3 WZJB, 1 NXNR => 6 XFPVS
7 JPCPK => 8 JCDML
11 LWBQ, 8 XFPVS => 9 PSPFR
2 TWSRV => 8 NVPW
2 LBQV => 1 PMJFD
2 LCZBD => 3 FBTV
1 WBQC, 1 ZPNKQ => 8 JPCPK
44 HFGCF, 41 PSPFR, 26 LMSCR, 14 MLMDC, 6 BWTHK, 3 PRKPC, 13 LRPK, 50 MWSX, 8 SZCN => 1 FUEL
1 XFPVS => 4 BJRSZ
1 GWBDR, 1 MBQC => 4 HZPRB
2 BJRSZ, 9 KDJV, 1 XFPVS => 8 SNVL
7 PMJFD, 30 SNVL, 1 BJRSZ => 2 JMTG
8 SNVL, 1 RBGJQ => 9 FCDL
2 HZPRB => 6 NLSNB
2 GRDG => 9 VCKL
1 FVHTD => 9 WZJB
130 ORE => 2 GRDG
3 WZJB, 1 GFGS, 1 NXNR => 9 SNPQ
9 VCKL => 5 WBQC
1 WBRL, 11 FPMPB => 7 PGZGQ
118 ORE => 3 LMSCR
3 SQLH, 1 PMJFD, 4 XJBL => 7 MLMDC
1 LMSCR, 10 GRDG => 2 TBDH
6 DWKTF => 2 SQLH
2 BJRSZ, 1 PGZGQ, 3 NXNR => 7 MBQC
5 PRKPC => 7 NXNR
9 SQLH => 5 LCZBD
1 FCDL => 9 CQFGM
5 PGZGQ, 1 TBDH => 8 HBGFL
15 JSQSB => 5 HFGCF
2 PGZGQ, 1 VCKL => 4 ZPNKQ
3 FBTV, 3 JMTG => 5 QLHKT
1 ZGZST, 2 LCZBD => 7 GFGS
2 RVQG => 4 ZQCH
1 ZPNKQ => 5 LBQV
3 LWBQ => 8 XJBL
1 LBQV, 9 JCDML => 3 GWBDR
8 VCKL, 6 FVHTD => 9 DWKTF
3 JCDML => 3 ZGZST
160 ORE => 5 FPMPB
3 SQLH, 22 LBQV, 5 BCVLZ => 6 PRKPC
1 WZJB => 2 GZJM
10 ZGZST => 2 LWBQ
5 TBDH, 19 NXNR, 9 QLHKT, 2 KDJV, 1 SQLH, 1 GWBDR, 6 HFGCF => 4 BWTHK
""")