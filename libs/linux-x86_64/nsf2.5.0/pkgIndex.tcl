set __dir__ $dir 
foreach index [concat \
		   [glob -nocomplain [file join $dir * pkgIndex.tcl]] \
		   [glob -nocomplain [file join $dir * * pkgIndex.tcl]] \
		   [glob -nocomplain [file join $dir * * * pkgIndex.tcl]]] {
  set dir [file dirname $index]
  source $index
} 
set dir $__dir__ 
unset __dir__ 



if {[package vsatisfies [package provide Tcl] 9]} {
    package ifneeded nsf 2.5.0 \
	    "[list load [file join $dir libtcl9nsf2.5.0.so]];
             [list package provide nsf 2.5.0]"
} else {
    package ifneeded nsf 2.5.0 \
	    "[list load [file join $dir libnsf2.5.0.so]];
             [list package provide nsf 2.5.0]"
}
