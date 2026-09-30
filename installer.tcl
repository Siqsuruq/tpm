namespace eval tpm {
    nx::Class create installer  -mixin Helper {
        :property {pkgdbObj:object,required,type=pkgdb}

        :method init {} {
        }

        :public method install {pkgName} {
            ${:pkgdbObj} refresh_remote
            set pkg [${:pkgdbObj} find_remote_package $pkgName]

            if {$pkg eq ""} {
                puts "Package not found: $pkgName"
                return
            }

            set base [string trimright [::tpm::config cget -default_repo_url] "/"]
            set uuid [dict get $pkg uuid_pkg_version]
            set download_url "$base/download/package/$uuid"

			echo "<s fg=green>Downloading from permalink: </s> <s fg=blue>$download_url</s>"
            set temp_file [file tempfile tmpfile "tpm_pkg_XXXXXX.zip"]
            # close $tmpfile

            if {[catch {
                set token [::http::geturl $download_url -binary true]
                set data  [::http::data $token]
                set f [open $temp_file wb]
                fconfigure $f -translation binary
                puts -nonewline $f $data
                close $f
                ::http::cleanup $token
            } err]} {
                puts "✗ Failed to download: $err"
                file delete -force $temp_file
                return
            }

            if {[catch {set install_dir [[::tpm::system new] get_install_path]} path_err]} {
				echo "<s fg=red>✗ Unable to determine install location: </s> <s fg=yellow>$path_err</s>"
                file delete -force $temp_file
                return
            }
			echo "<s fg=green>Installing to: </s> <s fg=blue>$install_dir</s>"
            if {[catch {
                # exec unzip -o $temp_file -d $install_dir
                :extract_zip_to $temp_file $install_dir
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

        :public method uninstall {pkgName} {
            set pkgs [${:pkgdbObj} get_installed_packages_by_name $pkgName]
            if {[llength $pkgs] == 0} {
                :cputs_multi [list green "Cannot find installation information for " yellow "$pkgName"]
                return
            }
            foreach pkg $pkgs {
                set indx [dict get $pkg indx]
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
                    }
                } elseif {[string match pkgIndex.tcl [file tail $indx]] == 1} {
                    try {
                        file delete -force -- [dict get $pkg path]
                    } on error {errMsg} {
                        :cputs_multi [list red_bold "Failed to delete package " yellow "$pkgName" red_bold " : " red "$errMsg"]
                    }
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
