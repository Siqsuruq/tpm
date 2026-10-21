#!/usr/bin/env tclsh
set here [file dirname [file normalize [info script]]]
set libs [file join $here libs]

# Always load pure Tcl libraries
set common_lib [file join $libs common]
# Detect OS-specific libraries
switch -exact -- $::tcl_platform(os) {
    "Linux" {
        set platform_lib [file join $libs linux]
    }
    "Windows NT" {
        set platform_lib [file join $libs win]
    }
    "Darwin" {
        set platform_lib [file join $libs mac]
    }
    default {
        return -code error "Unsupported operating system: $::tcl_platform(os)"
    }
}
# Platform-specific libs first, common libs second.
# Both take precedence over system-installed packages.
set auto_path [linsert $auto_path 0 $platform_lib $common_lib]

package require nx
package require http
package require tls
package require json
package require zipfile::decode
package require fileutil
package require dicttool
package require platform
package require inifile
package require zesty

namespace import zesty::echo

source [file join $here https.tcl]

# Load modules
foreach file {config.tcl helper.tcl pkgParser.tcl system.tcl net.tcl installer.tcl pkgdb.tcl app.tcl} {
    source [file join [file dirname [file normalize [info script]]] $file]
}

set app [::tpm::app new]
$app start
