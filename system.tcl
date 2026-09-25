namespace eval tpm {
    nx::Class create system -mixin Helper {
        :variable instance:object

        :public object method create {args} {
            return [expr {[info exists :instance] ? ${:instance} : [set :instance [next]]}]
        }

        :public method get_install_path {} {
            # Choose the first writable entry of the saved pre-libs auto_path.
            # tpm's own libs/ is already excluded upstream (config.tcl), as it
            # holds tpm's dependencies and must never receive user packages.
            # Note the full list is used here, not ::tpm::libsdirs, which is
            # filtered down to top-level roots only.
            set checked {}
            foreach path $::tpm::autopaths {
                lappend checked $path
                if {[file writable $path]} {
                    return $path
                }
            }

            set msg "No writable library directory found for installation."
            append msg "\nThe following directories were checked:"
            foreach path $checked {
                append msg "\n  - $path"
            }
            append msg "\nNone of them are writable."
            append msg "\nRe-run as a user with write access to one of these directories,"
            append msg " or change the ownership/permissions of the directory to install into."
            error $msg
        }

        :public method print_summary {} {
			# Show table with general information about installed Tcl
            set base [file dirname [file normalize [info script]]]
            set table [zesty::Table new -box {type "rounded"}]
            $table addColumn -name "System information" -width 20 -style {fg green}
            $table addColumn -name "*" -justify "left" -style {fg blue bold 1}
            $table addRow "Tcl Version" "[info patchlevel]"
            $table addRow "Tcl Platform" "[platform::generic]"
            $table addRow "Config path" "[file join $base var config]"
            $table addRow "Tcl executable path" "[info nameofexecutable]"
            $table addRow "Tcl library path" "$::tcl_library"
            $table addRow "Tcl auto_path" "$::tpm::autopaths"
            $table addRow "Tcl modules path" "[::tcl::tm::path list]"
            $table display

			# Show table with path and check if this directory is writable so tpm can download package there
            set table [zesty::Table new -box {type "rounded"}]
            $table addColumn -name "Package path(s):" -width 40 -style {fg green}
            $table addColumn -name "Writable" -justify "left" -style {fg blue bold 1}
            foreach path $::tpm::autopaths {
                $table addRow "$path" "[:check_writable $path]"
            }
            $table display

        }

        :method check_writable {path} {
            # Inline <s ...> markup is rendered as colored text by zesty's parser.
            if {[file writable $path]} {
                return [zesty::parseStyleDictToXML "writable" {fg green bold 1}]
            } else {
                return [zesty::parseStyleDictToXML "not writable" {fg red bold 1}]
            }
        }

        :public method get_tcl_version_major {args} {
            set major [lindex [split $::tcl_version "."] 0]
            return $major
        }

        :public method get_tcl_version_minor {args} {
            set minor [lindex [split $::tcl_version "."] 1]
            return $minor
        }
    }
}
