namespace eval tpm {
    nx::Class create pkgdb -mixin Helper {
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
        :public method check_updates {} {
            if {[llength ${:available_pkgs}] == 0} {
                :refresh_remote
            }
            set updates {}
            foreach local ${:installed_pkgs} {
                set name    [dict getnull $local name]
                set local_v [dict getnull $local version]
                set remote  [:find_remote_latest $name]
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
            set :installed_pkgs {} ;# reset
            set base_dir [file normalize [file dirname [info script]]]
            
            set pkgParserObj [::tpm::pkgParser new -pkgDirs $::tpm::libsdirs]
            set :installed_pkgs [$pkgParserObj get_packages]
        }

        :public method list_installed {} {
            if {[llength ${:installed_pkgs}] == 0} {
                puts " (none found)"
            } else {
                foreach pkgDict ${:installed_pkgs} {
                    set line [list \
                        cyan " - " \
                        yellow [format "%-20s" [dict getnull $pkgDict name]] \
                        green  [format "%-8s" [dict getnull $pkgDict version]] \
                        cyan  [format "%-40s" [dict getnull $pkgDict path]] \
                        magenta [format "%-9s" [dict getnull $pkgDict type]] \
                    ]
                    :cputs_multi $line
                }
            }
        }

        :public method is_installed {pkg} {
            foreach pkgDict ${:installed_pkgs} {
                if {[dict getnull $pkgDict name] eq $pkg} {
                    return 1
                }
            }
            return 0
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