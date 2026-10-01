namespace eval tpm {
    nx::Class create pkgdb {
		# Raw Tcl package registrations discovered by pkgParser.
		:property {provided_pkgs ""}
		# Physical installed package/distribution units.
		:property {installed_pkgs ""}
		:property {available_pkgs ""}

        :method init {} {
            :refresh
        }

        :public method refresh_remote {} {
            set net [::tpm::net new]
            try {
                set pkgs [$net fetch_package_index]
                set :available_pkgs $pkgs
            } finally {
                $net destroy
            }
        }

        :public method find_remote_package {name} {
            foreach pkg ${:available_pkgs} {
                if {[dict get $pkg package_name] eq $name} {
                    return $pkg
                }
            }
            return ""
        }

        # Return the remote package dict with the highest version matching $name,
        # or "" if no remote package with that name exists.
        :public method find_remote_latest {name} {
            set latest ""
            set latest_ver ""
            foreach pkg ${:available_pkgs} {
                if {[dict get $pkg package_name] ne $name} {
                    continue
                }
                set ver [dict get $pkg version]
                if {$latest eq "" || [package vcompare $ver $latest_ver] > 0} {
                    set latest     $pkg
                    set latest_ver $ver
                }
            }
            return $latest
        }

        # Check local installed packages against the remote repository and return
        # a list of dicts {name local_version remote_version latest_remote_pkg}
        # for every installed package that has a newer version available remotely.
        #
        # A package name may be installed at several versions at once (e.g. a
        # tcllib directory whose pkgIndex.tcl declares both 1.3 and 2.3). For the
        # purpose of update detection the package counts as installed at its
        # highest local version, so at most one row is emitted per name and older
        # co-installed versions do not produce phantom updates.
        :public method check_updates {} {
            if {[llength ${:available_pkgs}] == 0} {
                :refresh_remote
            }

            # Group installed entries by name, keeping the highest version seen.
            set latest_local [dict create]
            foreach local ${:installed_pkgs} {
                set name    [dict getnull $local name]
                set local_v [dict getnull $local version]
                if {$name eq "" || $local_v eq ""} {
                    continue
                }
                if {![dict exists $latest_local $name] || [package vcompare $local_v [dict get $latest_local $name]] > 0} {
                    dict set latest_local $name $local_v
                }
            }

            set updates {}
            dict for {name local_v} $latest_local {
                set remote [:find_remote_latest $name]
                if {$remote eq ""} {
                    continue
                }
                set remote_v [dict get $remote version]
                if {[package vcompare $remote_v $local_v] > 0} {
                    lappend updates [dict create \
                        name           $name \
                        local_version  $local_v \
                        remote_version $remote_v \
                        remote_pkg     $remote]
                }
            }
            return $updates
        }

		:public method refresh {} {
		    set :provided_pkgs {}
			set :installed_pkgs {}
			set systemObj [::tpm::system new]
			set pkgDirs [$systemObj get_package_paths]
			set pkgParserObj [::tpm::pkgParser new -pkgDirs $pkgDirs]
			try {
				set :provided_pkgs [$pkgParserObj get_packages]
			} finally {
				$pkgParserObj destroy
			}
			:group_installed_packages
			return ${:installed_pkgs}
		}
		
		:method group_installed_packages {} {
			set groups [dict create]
			set group_paths [dict create]
			set group_types [dict create]
			set systemObj [::tpm::system new]
			# Group raw Tcl package registrations into physical installation units.
			foreach pkg ${:provided_pkgs} {
				set type [dict get $pkg type]
				switch -- $type {
					tm {
						# A Tcl Module is itself the installation unit.
						set unit_path [file normalize [dict get $pkg indx]]
					}
					default {
						# A pkgIndex-based package normally owns its directory.
						set unit_path [file normalize [dict get $pkg path]]
					}
				}
				# Embedded/runtime packages share physical directories. Keep each
				# registration visible rather than inventing a directory package name.
				if {[$systemObj is_runtime_package_path $unit_path] || [string match {//zipfs:*} $unit_path]} {
					set type runtime
					set key [list $type [dict get $pkg name] [dict get $pkg version]]
					# A parent index may source child indexes. Prefer the child
					# location for the same runtime registration, without duplicate rows.
					if {[dict exists $group_paths $key]} {
						if {[llength [file split $unit_path]] <= [llength [file split [dict get $group_paths $key]]]} {
							continue
						}
						dict set groups $key {}
					}
				} else {
					set key [list $type $unit_path]
				}
				dict lappend groups $key $pkg
				dict set group_paths $key $unit_path
				dict set group_types $key $type
			}
			set manifests [:load_manifests]
			set installed {}
			dict for {key provides} $groups {
				set path [dict get $group_paths $key]
				set type [dict get $group_types $key]
				set name [:infer_unit_name $path $provides]
				set version [:infer_unit_version $name $provides]
				if {$type eq "runtime"} {
					set name [dict get [lindex $provides 0] name]
					set version [dict get [lindex $provides 0] version]
				}
				set provided_names {}
				set indexes {}
				foreach pkg $provides {
					set pkgName [dict get $pkg name]
					set index [dict get $pkg indx]
					if {[lsearch -exact $provided_names $pkgName] == -1} {
						lappend provided_names $pkgName
					}
					if {[lsearch -exact $indexes $index] == -1} {
						lappend indexes $index
					}
				}
				# Determine whether TPM owns this installation.
				set manifest [:find_manifest_for_path $path $manifests]
				set managed 0
				set manifest_file ""
				if {$manifest ne "" && $type ne "runtime"} {
					set managed 1
					set manifest_file [dict get $manifest manifest_file]
				}
				set origin [expr {$managed ? "tpm" : "system"}]
				lappend installed [dict create name $name version $version path $path type $type managed $managed origin $origin \
					manifest_file $manifest_file manifest $manifest provided_names $provided_names \
					provided_count [llength $provided_names] provides $provides indexes $indexes]
			}

			set :installed_pkgs $installed
		}

		:method infer_unit_name {path provides} {
			set dirname [file tail [file normalize $path]]
			# First try an exact case-sensitive prefix.
			set best ""
			foreach pkg $provides {
				set name [dict get $pkg name]
				if {[string first $name $dirname] == 0} {
					if {[string length $name] > [string length $best]} {
						set best $name
					}
				}
			}
			if {$best ne ""} {
				return $best
			}
			# Then try case-insensitive matching.
			set lowerDir [string tolower $dirname]
			foreach pkg $provides {
				set name [dict get $pkg name]
				if {[string first [string tolower $name] $lowerDir] == 0} {
					if {[string length $name] > [string length $best]} {
						set best $name
					}
				}
			}
			if {$best ne ""} {
				return $best
			}
			# No provided package clearly identifies the distribution.
			# Use the physical installation name rather than arbitrarily picking the first Tcl package.
			set physical [file tail [file normalize $path]]
			if {[string match *.tm $physical]} {
				set physical [file rootname $physical]
			}
			return $physical
		}

		:method infer_unit_version {name provides} {
			# Exact package-name match.
			foreach pkg $provides {
				if {[dict get $pkg name] eq $name} {
					return [dict get $pkg version]
				}
			}
			# Case-insensitive fallback.
			foreach pkg $provides {
				if {[string equal -nocase [dict get $pkg name] $name]} {
					return [dict get $pkg version]
				}
			}
			# If everything provides the same version, that's safe too.
			set versions {}
			foreach pkg $provides {
				set version [dict get $pkg version]
				if {[lsearch -exact $versions $version] == -1} {
					lappend versions $version
				}
			}
			if {[llength $versions] == 1} {
				return [lindex $versions 0]
			}
			# Cannot safely infer a distribution version.
			return ""
		}

		:public method find_installed_unit {name} {
			set best ""
			foreach unit ${:installed_pkgs} {
				# Exact installation-unit name always wins.
				if {[dict get $unit name] eq $name} {
					return $unit
				}
				# Package is provided by this unit.
				if {[lsearch -exact [dict get $unit provided_names] $name] == -1} {
					continue
				}
				# Prefer the most specific/deepest installation path.
				if {$best eq "" || [string length [dict get $unit path]] > [string length [dict get $best path]]} {
					set best $unit
				}
			}
			return $best
		}

        :public method list_installed {} {
			return ${:installed_pkgs}
		}

        :public method is_installed {pkg} {
			return [expr {[:find_installed_unit $pkg] ne ""}]
		}
		
        :public method get_installed_packages_by_name {pkg} {
            set result {}
            # puts "Searching for installed packages named '$pkg'... ${:installed_pkgs}"
            foreach pkgDict ${:installed_pkgs} {
                if {[dict getnull $pkgDict name] eq $pkg} {
                    lappend result $pkgDict
                }
            }
            return $result
        }

        :public method get_manifest_dir {} {
			return [file join [::tpm::config cget -tpm_path] var installed]
		}

		:method load_manifests {} {
			set result {}
			set dir [:get_manifest_dir]
			if {![file isdirectory $dir]} {
				return $result
			}
			foreach path [glob -nocomplain -types f -directory $dir *.tpm] {
				set f [open $path r]
				try {
					set data [string trim [read $f]]
				} finally {
					close $f
				}
				if {$data eq ""} {
					continue
				}
				# Manifest is stored as a Tcl dictionary, not executable Tcl.
				if {[catch {dict size $data}]} {
					continue
				}
				dict set data manifest_file $path
				lappend result $data
			}
			return $result
		}

		:method paths_equal {a b} {
			set a [file normalize $a]
			set b [file normalize $b]
			if {$::tcl_platform(platform) eq "windows"} {
				return [string equal -nocase $a $b]
			}
			return [expr {$a eq $b}]
		}

		:method find_manifest_for_path {path manifests} {
			foreach manifest $manifests {
				if {[dict exists $manifest unit_paths]} {
					foreach unit_path [dict get $manifest unit_paths] {
						if {[:paths_equal $path $unit_path]} {
							return $manifest
						}
					}
				}
				if {![dict exists $manifest unit_path]} {
					continue
				}
				set unit_path [dict get $manifest unit_path]
				if {$unit_path eq ""} {
					continue
				}
				if {[:paths_equal $path $unit_path]} {
					return $manifest
				}
			}
			return ""
		}
    }
}
