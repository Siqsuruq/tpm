# Internal helper, launched by installer in a fresh Tcl process.
lassign $argv requestFile resultFile
set ch [open $requestFile r]
set request [read $ch]
close $ch
::tcl::tm::path list
set auto_path [concat [dict get $request paths] $auto_path]
foreach path [dict get $request module_paths] {::tcl::tm::path add $path}
set missing {}
rename ::package ::original_package
proc ::package {args} {
    if {[catch {::original_package {*}$args} value options]} {
        if {[lindex $args 0] eq "require" &&
            [dict get $options -errorcode] eq {TCL PACKAGE UNFOUND}} {
            lappend ::missing [dict create require [lrange $args 1 end] message $value]
        }
        return -options $options $value
    }
    return $value
}
set requireArgs [dict get $request require]
proc prepare_target {paths name} {
    # Register the target archive first, so its actual exported version is
    # checked even if repository metadata is wrong or another version exists.
    foreach dir $paths {
        set index [file join $dir pkgIndex.tcl]
        if {[file isfile $index]} {source $index}
        foreach module [glob -nocomplain -directory $dir *.tm] {
            if {[regexp {^(.+)-([0-9][[:alnum:].]*)\.tm$} [file tail $module] -> moduleName version] && $moduleName eq $name} {
                package ifneeded $name $version [list source $module]
            }
        }
    }
    set latest ""
    foreach version [package versions $name] {
        if {$latest eq "" || [package vcompare $version $latest] > 0} {set latest $version}
    }
    if {$latest eq ""} {return [list $name]}
    return [list -exact $name $latest]
}
if {[catch {
    if {[dict exists $request target_paths] && [llength [dict get $request target_paths]]} {
        set requireArgs [prepare_target [dict get $request target_paths] [lindex $requireArgs 0]]
    }
    package require {*}$requireArgs
} value options]} {
    if {$missing ne "" && [dict get $options -errorcode] eq {TCL PACKAGE UNFOUND}} {
        # Ignore earlier, caught optional errors: find the original failure
        # that actually propagated out of the root require.
        set requirement $requireArgs
        foreach failure $missing {
            if {[dict get $failure message] eq $value} {
                set requirement [dict get $failure require]
                break
            }
        }
        set result [dict create status missing require $requirement message $value]
    } else {
        set result [dict create status error message $value options $options]
        # A loader may catch require errors and replace them with its own
        # diagnostic. Only consider failed requires named in that diagnostic;
        # unrelated optional probes must not become installation dependencies.
        set words [regexp -all -inline {[[:alnum:]_:.-]+} $value]
        set alternatives {}
        foreach failure $missing {
            set requirement [dict get $failure require]
            set name [lindex $requirement [expr {[lindex $requirement 0] eq "-exact" ? 1 : 0}]]
            if {$name in $words && [lsearch -exact $alternatives $requirement] < 0} {
                lappend alternatives $requirement
            }
        }
        if {[llength $alternatives]} {
            dict set result status alternatives
            dict set result requirements $alternatives
        }
    }
} else {
    set result [dict create status ok version $value]
}
set ch [open $resultFile w]
puts $ch $result
close $ch
