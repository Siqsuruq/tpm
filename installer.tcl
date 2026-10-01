namespace eval tpm {
    nx::Class create installer  -mixin Helper {
        :property {pkgdbObj:object,required,type=pkgdb}

        :method init {} {
        }

        :public method install {pkgName {force 0}} {
            foreach unit [${:pkgdbObj} get_installed_packages_by_name $pkgName] {
                if {![dict get $unit managed] && !$force} {
                    :cputs_multi [list red "System package $pkgName requires --force (-f) to install or update."]
                    return
                }
            }
            ${:pkgdbObj} refresh_remote
            set pkg [${:pkgdbObj} find_remote_latest $pkgName]

            if {$pkg eq ""} {
                puts "Package not found: $pkgName"
                return
            }

            set base [string trimright [::tpm::config cget -default_repo_url] "/"]
            set uuid [dict get $pkg uuid_pkg_version]
            set download_url "$base/download/package/$uuid"

			echo "<s fg=green>Downloading from permalink: </s> <s fg=blue>$download_url</s>"
            set tmpchannel [file tempfile temp_file "tpm_pkg_XXXXXX.zip"]
            close $tmpchannel

            if {[catch {
                set token [::http::geturl $download_url -binary true]
                if {[::http::status $token] ne "ok" || [::http::ncode $token] != 200} {
                    error "Download failed: [::http::status $token] [::http::code $token]"
                }
                set data  [::http::data $token]
                set f [open $temp_file wb]
                fconfigure $f -translation binary
                puts -nonewline $f $data
                close $f
                ::http::cleanup $token
            } err]} {
                if {[info exists token]} {::http::cleanup $token}
                puts "✗ Failed to download: $err"
                file delete -force $temp_file
                return
            }

            set sys [::tpm::system new]
            if {[catch {set install_dir [$sys prepare_install_path]} path_err]} {
				echo "<s fg=red>✗ Unable to determine install location: </s> <s fg=yellow>$path_err</s>"
                file delete -force $temp_file
                return
            }
			echo "<s fg=green>Installing to: </s> <s fg=blue>$install_dir</s>"
            if {[catch {
                set entries [::zipfile::decode::content $temp_file]
                :validate_archive_paths $entries $install_dir
                set unit_paths {}
                foreach entry $entries {
                    set destination [file normalize [file join $install_dir $entry]]
                    if {[$sys is_protected_package_path $destination]} {
                        error "Protected package path: $destination"
                    }
                    if {[file isfile $destination] && !$force} {
                        set owned 0
                        foreach unit [${:pkgdbObj} list_installed] {
                            set prefix [file split [dict get $unit path]]
                            set candidate [lrange [file split $destination] 0 [expr {[llength $prefix] - 1}]]
                            if {[string equal -nocase $prefix $candidate] && [dict get $unit managed]} {
                                set owned 1
                            }
                        }
                        if {!$owned} {error "Existing system file requires --force (-f): $destination"}
                    }
                    if {[file tail $entry] eq "pkgIndex.tcl"} {
                        lappend unit_paths [file dirname $destination]
                    } elseif {[string match *.tm $entry]} {
                        lappend unit_paths $destination
                    }
                }
                set unit_paths [lsort -unique $unit_paths]
                if {[llength $unit_paths] == 0} {
                    error "Archive contains no pkgIndex.tcl or Tcl modules"
                }
                foreach path $unit_paths {
                    if {[$sys is_protected_package_path $path]} {
                        error "Protected package path: $path"
                    }
                    foreach unit [${:pkgdbObj} list_installed] {
                        set existing [dict get $unit path]
                        set prefix [file split $existing]
                        set candidate [lrange [file split $path] 0 [expr {[llength $prefix] - 1}]]
                        if {[string equal -nocase $prefix $candidate] && ![dict get $unit managed] && !$force} {
                            error "System package [dict get $unit name] requires --force (-f)"
                        }
                    }
                }
                :extract_zip_to $temp_file $install_dir
                dict set pkg unit_paths $unit_paths
                dict set pkg install_root $install_dir
                dict set pkg files $entries
                :save_manifest $pkg
            } unzip_err]} {
                puts "Failed to unzip: $unzip_err"
                file delete -force $temp_file
                return
            }
            file delete -force $temp_file
            :cputs_multi [list green "Package " yellow "$pkgName"  green " version " blue "[dict get $pkg version]" green " installed successfully."]
            ${:pkgdbObj} refresh
        }

        :method extract_zip_to {zip_path dest_dir} {
            if {![file isdirectory $dest_dir]} {
                file mkdir $dest_dir
            }
            try {
                ::zipfile::decode::unzipfile $zip_path $dest_dir
                return -code ok
            } on error {errMsg opts} {
                return -code error "Failed to unzip '$zip_path': $errMsg"
            }
        }

        :public method update {pkgName {force 0}} {
            ${:pkgdbObj} refresh_remote
            foreach update [${:pkgdbObj} check_updates] {
                if {[dict get $update name] eq $pkgName} {
                    :install $pkgName $force
                    return
                }
            }
            :cputs_multi [list green "No update available for " yellow $pkgName]
        }

        :public method uninstall {pkgName {force 0}} {
            set pkgs [${:pkgdbObj} get_installed_packages_by_name $pkgName]
            if {[llength $pkgs] == 0} {
                :cputs_multi [list green "Cannot find installation information for " yellow "$pkgName"]
                return
            }
            set sys [::tpm::system new]
            # Check every matching installation before deleting anything.
            foreach pkg $pkgs {
                set path [dict get $pkg path]
                if {[$sys is_protected_package_path $path]} {
                    :cputs_multi [list red "Protected package path: $path"]
                    return
                }
                if {![dict get $pkg managed] && !$force} {
                    :cputs_multi [list red "System package $pkgName requires --force (-f) to delete."]
                    return
                }
            }
            foreach pkg $pkgs {
                set indx [dict get $pkg path]
                if {![file exists $indx]} {
                    :cputs_multi [list red_bold "Installed package path does not exist: " red "$indx"]
                    return
                }
                # is it tm file
                if {[string match *.tm [file tail $indx]] == 1} {
                    try {
                        file delete -force -- $indx
                    } on error {errMsg} {
                        :cputs_multi [list red_bold "Failed to delete package " yellow "$pkgName" red_bold " : " red "$errMsg"]
                        return
                    }
                } elseif {[dict get $pkg type] eq "pkgIndex"} {
                    try {
                        file delete -force -- [dict get $pkg path]
                    } on error {errMsg} {
                        :cputs_multi [list red_bold "Failed to delete package " yellow "$pkgName" red_bold " : " red "$errMsg"]
                        return
                    }
                }
                # Keep a shared manifest until all its installation units are gone.
                set manifest [dict get $pkg manifest]
                if {$manifest ne ""} {
                    set remaining 0
                    if {[dict exists $manifest unit_paths]} {
                        foreach path [dict get $manifest unit_paths] {
                            if {[file exists $path]} {set remaining 1}
                        }
                    }
                    if {!$remaining} {file delete -force -- [dict get $pkg manifest_file]}
                }
                :cputs_multi [list green "Removing package from: " blue "$indx"]
                ${:pkgdbObj} refresh
                :cputs_multi [list green "Package " yellow "$pkgName" green " uninstalled successfully."]
            }
        }

        :method save_manifest {manifest} {
            set dir [${:pkgdbObj} get_manifest_dir]
            if {![file isdirectory $dir]} {
                file mkdir $dir
            }
            set uuid [dict get $manifest uuid_pkg_version]
            set path [file join $dir "${uuid}.tpm"]
            set f [open $path w]
            try {
                puts $f $manifest
            } finally {
                close $f
            }
            return $path
        }

        :method validate_archive_paths {entries install_root} {
            set install_root [file normalize $install_root]
            foreach entry $entries {
                # Archive entries must always be relative.
                if {[file pathtype $entry] ne "relative"} {
                    error "Unsafe absolute path in package archive: $entry"
                }
                # Explicit parent traversal is never permitted.
                if {[lsearch -exact [file split $entry] ".."] != -1} {
                    error "Unsafe parent path in package archive: $entry"
                }
                set destination [file normalize [file join $install_root $entry]]
                # Additional normalized containment test.
                set rootParts [file split $install_root]
                set dstParts  [file split $destination]
                if {[llength $dstParts] < [llength $rootParts]} {
                    error "Unsafe package archive path: $entry"
                }
                set candidate [lrange $dstParts 0 [expr {[llength $rootParts] - 1}]]
                if {$::tcl_platform(platform) eq "windows"} {
                    set inside [string equal -nocase [file join {*}$candidate] [file join {*}$rootParts]]
                } else {
                    set inside [expr {$candidate eq $rootParts}]
                }
                if {!$inside} {
                    error "Package archive path escapes installation directory: $entry"
                }
            }
        }
    }
}
