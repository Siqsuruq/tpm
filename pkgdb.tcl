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
                if {![dict exists $latest_local $name] ||
                    [package vcompare $local_v [dict get $latest_local $name]] > 0} {
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
			set systemObj [::tpm::system create]
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
			# Group raw Tcl packages by physical directory.
			foreach pkg ${:provided_pkgs} {
				set path [file normalize [dict get $pkg path]]
				dict lappend groups $path $pkg
			}
			set installed {}
			dict for {path provides} $groups {
				set name [:infer_unit_name $path $provides]
				set version [:infer_unit_version $name $provides]
				set provided_names {}
				set indexes {}
				set types {}
				foreach pkg $provides {
					set pkgName [dict get $pkg name]
					set index [dict get $pkg indx]
					set type [dict get $pkg type]
					if {[lsearch -exact $provided_names $pkgName] == -1} {
						lappend provided_names $pkgName
					}
					if {[lsearch -exact $indexes $index] == -1} {
						lappend indexes $index
					}
					if {[lsearch -exact $types $type] == -1} {
						lappend types $type
					}
				}
				lappend installed [dict create name $name version $version path $path provided_names $provided_names provided_count [llength $provided_names] provides $provides indexes $indexes types $types]
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
			# Fallback: first provided package.
			return [dict get [lindex $provides 0] name]
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
			foreach unit ${:installed_pkgs} {
				# Main distribution name.
				if {[dict get $unit name] eq $name} {
					return $unit
				}
				# One of the Tcl packages provided by this distribution.
				if {[lsearch -exact [dict get $unit provided_names] $name] != -1} {
					return $unit
				}
			}
			return ""
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
    }
}