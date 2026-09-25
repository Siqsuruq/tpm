namespace eval tpm {
    nx::Class create pkgParser {
        :property {pkgDirs ""}
        :property {pkgs ""}

        :method init {} {
            next
            :parse_package_files
        }

        # Recursively find files matching $pattern.
        :public method findFiles {basedir pattern} {
            set basedir [file normalize $basedir]
            set fileList {}
            if {![file isdirectory $basedir]} {
                return $fileList
            }
            # Files in current directory.
            foreach fileName [glob -nocomplain -types {f r} -directory $basedir $pattern] {
                lappend fileList $fileName
            }
            # Recurse into subdirectories.
            foreach dirName [glob -nocomplain -types {d r} -directory $basedir *] {
                lappend fileList {*}[:findFiles $dirName $pattern]
            }
            return $fileList
        }

        # Add one discovered package.
        # All package sources go through this method so duplicate handling remains consistent.
        :method add_package {name version path index type} {
            set path  [file normalize $path]
            set index [file normalize $index]
            # Validate package version.
            if {[catch {package vcompare $version 0}]} {
                return
            }
            # Avoid duplicates.
            foreach existing ${:pkgs} {
                if {[dict get $existing name] eq $name && [dict get $existing version] eq $version && [dict get $existing indx] eq $index} {
                    return
                }
            }
            lappend :pkgs [dict create name $name version $version path $path indx $index type $type]
        }

        # Discover package indexes and Tcl modules.
        :public method parse_package_files {} {
            set :pkgs {}
            foreach dir ${:pkgDirs} {
                if {![file isdirectory $dir]} {
                    continue
                }
                set dir [file normalize $dir]
                set indexFiles [:findFiles $dir "pkgIndex.tcl"]
                set tmFiles    [:findFiles $dir "*.tm"]
                puts "-----------------------------------------------------"
                puts "Parsing package directory: $dir"
                puts "Found [llength $indexFiles] pkgIndex.tcl files"
                puts "Found [llength $tmFiles] Tcl module files"
                puts "-----------------------------------------------------"
                foreach pkgFile $indexFiles {
                    :parse_pkgIndex $pkgFile
                }
                foreach tmFile $tmFiles {
                    :parse_tm $tmFile
                }
            }
            return ${:pkgs}
        }

        # pkgIndex.tcl is executable Tcl code.
        # Evaluate it inside a disposable interpreter and inspect the package ifneeded registrations it creates.
        :public method parse_pkgIndex {indexfile} {
			set indexfile [file normalize $indexfile]
			set pkgdir [file dirname $indexfile]
			set slave [interp create]
			try {
				interp eval $slave [list set dir $pkgdir]
				interp eval $slave [list set auto_path $::auto_path]
				# Snapshot package registrations before sourcing this pkgIndex.
				set before [dict create]
				foreach pkg [interp eval $slave {package names}] {
					foreach ver [interp eval $slave [list package versions $pkg]] {
						set script [interp eval $slave [list package ifneeded $pkg $ver]]
						dict set before [list $pkg $ver] $script
					}
				}
				# Execute this pkgIndex.
				interp eval $slave [list source $indexfile]
				# Only collect registrations added/changed by this pkgIndex.
				foreach pkg [interp eval $slave {package names}] {
					foreach ver [interp eval $slave [list package versions $pkg]] {
						set script [interp eval $slave [list package ifneeded $pkg $ver]]
						if {$script eq ""} {
							continue
						}
						set key [list $pkg $ver]
						if {[dict exists $before $key]} {
							if {[dict get $before $key] eq $script} {
								continue
							}
						}
						:add_package $pkg $ver $pkgdir $indexfile pkgIndex
					}
				}
			} on error {errMsg} {
				puts "Warning: failed to parse pkgIndex '$indexfile': $errMsg"
			} finally {
				interp delete $slave
			}
		}

        # Parse Tcl Module filename.
        :public method parse_tm {tmfile} {
            set tmfile [file normalize $tmfile]
            set filename [file tail $tmfile]
            if {![regexp {^([[:alpha:]_][[:alnum:]_]*)-([0-9][[:alnum:].]*)\.tm$} $filename -> pkg ver]} {
                puts "Warning: invalid Tcl module filename: $filename"
                return
            }
            if {[catch {package vcompare $ver 0}]} {
                puts "Warning: invalid package version '$ver' in '$filename'"
                return
            }
            :add_package $pkg $ver [file dirname $tmfile] $tmfile tm
        }

        :public method get_packages {} {
            return ${:pkgs}
        }
    }
}