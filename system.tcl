namespace eval tpm {
    nx::Class create system -mixin Helper {
        :variable instance:object

        :public object method create {args} {
            return [expr { [info exists :instance] ? ${:instance} : [set :instance [next]] }]
        }

        # Return the user-configured install directory.
        # Empty string means no custom path is configured.
        :public method get_custom_install_path {} {
            set path [string trim [::tpm::config cget -install_path]]
            if {$path eq ""} {
                return ""
            }
            return [file normalize $path]
        }

        # Determine where TPM would install a package.
        :public method get_install_path {} {
            # First priority: user-configured TPM package directory.
            set custom_path [:get_custom_install_path]
            if {$custom_path ne ""} {
                return $custom_path
            }
            # Fallback: first writable Tcl package directory.
            foreach path $::tpm::autopaths {
                if {[file isdirectory $path] && [file writable $path]} {
                    return [file normalize $path]
                }
            }
            return ""
        }

        # Prepare and validate the actual installation directory.
        :public method prepare_install_path {} {
            set install_path [:get_install_path]
            if {$install_path eq ""} {
                set msg "No writable library directory found for installation."
                append msg "\nThe following directories were checked:"
                foreach path $::tpm::autopaths {
                    append msg "\n  - $path"
                }
                append msg "\nNone of them are writable."
                error $msg
            }
            # Custom path may not exist yet.
            if {![file exists $install_path]} {
                file mkdir $install_path
            }
            if {![file isdirectory $install_path]} {
                error "Install path is not a directory: $install_path"
            }
            if {![file writable $install_path]} {
                error "Install path is not writable: $install_path"
            }
            return $install_path
        }

        # Directories TPM should scan for installed packages.
        :public method get_package_paths {} {
            set paths {}
            # User-defined TPM package directory.
            set custom_path [:get_custom_install_path]
            if {$custom_path ne "" && [file isdirectory $custom_path]} {
                lappend paths $custom_path
            }
            # Original Tcl package paths.
            foreach path $::tpm::autopaths {
                if {![file isdirectory $path]} {
                    continue
                }
                set path [file normalize $path]
                if {[lsearch -exact $paths $path] == -1} {
                    lappend paths $path
                }
            }
            # Tcl Module (.tm) paths.
            foreach path [::tcl::tm::path list] {
                if {![file isdirectory $path]} {
                    continue
                }
                set path [file normalize $path]
                if {[lsearch -exact $paths $path] == -1} {
                    lappend paths $path
                }
            }
            return $paths
        }

        :public method print_summary {} {
			:show_title "System information:"
 
			# General Tcl / TPM information.
            set table [zesty::Table new -box {type "rounded"}]
            $table addColumn -name "System information" -width 20 -style {fg green}
            $table addColumn -name "*" -justify "left" -style {fg blue bold 1}
            $table addRow "Tcl Version" [info patchlevel]
            $table addRow "Tcl Platform" [platform::generic]
            $table addRow "Config path" [::tpm::config cget -config_path]
            $table addRow "Tcl executable path" [info nameofexecutable]
            $table addRow "Tcl library path" $::tcl_library
            # Tcl package paths without TPM's private libs/.
            $table addRow "Tcl package path" $::tpm::autopaths
            # Actual runtime auto_path, including TPM private dependencies
            # and potentially the configured custom package directory.
            $table addRow "Runtime auto_path" $::auto_path
            $table addRow "Tcl modules path" [::tcl::tm::path list]
            set custom_path [:get_custom_install_path]
            if {$custom_path eq ""} {
                set custom_path "not configured"
            }
            $table addRow "Custom install path" $custom_path
            set install_path [:get_install_path]
            if {$install_path eq ""} {
                set install_path "no writable install path"
            }
            $table addRow "Install path" $install_path
            $table display

            # Directories TPM actually scans for packages.
            set table [zesty::Table new -box {type "rounded"}]
            $table addColumn -name "Package path(s):" -width 40 -style {fg green}
            $table addColumn -name "Writable" -justify "left" -style {fg blue bold 1}
            foreach path [:get_package_paths] {
                $table addRow $path [:check_writable $path]
            }
            $table display
			:show_separator
        }

        :method check_writable {path} {
            if {[file writable $path]} {
                return [zesty::parseStyleDictToXML "writable" {fg green bold 1}]
            }
            return [zesty::parseStyleDictToXML "not writable" {fg red bold 1}]
        }

        :public method get_tcl_version_major {} {
            return [lindex [split $::tcl_version "."] 0]
        }

        :public method get_tcl_version_minor {} {
            return [lindex [split $::tcl_version "."] 1]
        }

        :method paths_equal {a b} {
            set a [file normalize $a]
            set b [file normalize $b]
            if {$::tcl_platform(platform) eq "windows"} {
                return [string equal -nocase $a $b]
            }
            return [expr {$a eq $b}]
        }

        :method is_subpath {path parent} {
            set path   [file normalize $path]
            set parent [file normalize $parent]
            set pathParts   [file split $path]
            set parentParts [file split $parent]
            if {[llength $pathParts] < [llength $parentParts]} {
                return 0
            }
            set candidate [lrange $pathParts 0 [expr {[llength $parentParts] - 1}]]

            if {$::tcl_platform(platform) eq "windows"} {
                return [string equal -nocase [file join {*}$candidate] [file join {*}$parentParts]]
            }
            return [expr {$candidate eq $parentParts}]
        }

        :public method is_runtime_package_path {path} {
            # The Tcl library (including ZIPFS builds) belongs to the runtime.
            return [:is_subpath $path $::tcl_library]
        }

        :public method is_protected_package_path {path} {
            # ZIPFS is part of Tcl itself and is not a normal removable filesystem package location.
            if {[string match {//zipfs:*} $path]} {
                return 1
            }
            set path [file normalize $path]
            # Never allow deletion of TPM's own dependencies.
            set tpm_libs [file normalize [file join [::tpm::config cget -tpm_path] libs]]
            if {[:is_subpath $path $tpm_libs]} {
                return 1
            }
            # Protect Tcl's own library tree.
            if {![string match {//zipfs:*} $::tcl_library]} {
                set tcl_library [file normalize $::tcl_library]
                if {[:is_subpath $path $tcl_library]} {
                    return 1
                }
            }
            # Never force-delete an entire package search root.
            # Example:
            #
            #   C:/Tcl/lib            <- protected
            #   C:/Tcl/lib/tk9.0      <- may be forced
            foreach root [:get_package_paths] {
                if {[:paths_equal $path $root]} {
                    return 1
                }
            }
            return 0
        }
    }
}
