#!/usr/bin/env tclsh
package require platform
set here [file dirname [file normalize [info script]]]
set libs [file join $here libs]

# Always load pure Tcl libraries and detect OS-specific libraries needed for TPM to run
set common_lib [file join $libs common]
set platform_lib [file join $libs [platform::generic]]
if {![file isdirectory $platform_lib]} {
    puts stderr "Unsupported platform: [platform::generic] (missing $platform_lib)"
    exit 1
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
