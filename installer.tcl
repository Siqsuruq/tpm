namespace eval tpm {
    variable dependency_probe [file join [file dirname [file normalize [info script]]] dependency-probe.tcl]
    variable probe_serial 0
    nx::Class create installer  -mixin Helper {
        :property {pkgdbObj:object,required,type=pkgdb}
        :property {probe_timeout 30000}
        :variable plans {}
        :variable active {}
        :variable staged_paths {}
        :variable stage_root ""

        :method init {} {
        }

        :public method install {pkgName {force 0}} {
            ${:pkgdbObj} refresh_remote
            set pkg [${:pkgdbObj} find_remote_latest $pkgName]
            if {$pkg eq ""} {
                :cputs_multi [list red "Package not found: $pkgName"]
                return
            }
            set channel [file tempfile stage]
            close $channel
            file delete -- $stage
            file mkdir $stage
            set :stage_root $stage
            set :plans {}
            set :active {}
            set :staged_paths {}
            try {
                :stage_package $pkg $force
                # All probes and ownership checks pass before writing installed files.
                foreach plan ${:plans} {
                    set dest [dict get $plan install_root]
                    foreach entry [dict get $plan files] {
                        set source [file join [dict get $plan stage] $entry]
                        set target [file join $dest $entry]
                        if {[file isdirectory $source]} {file mkdir $target; continue}
                        file mkdir [file dirname $target]
                        file copy -force -- $source $target
                    }
                    dict unset plan stage
                    :save_manifest $plan
                    :cputs_multi [list green "Installed " yellow [dict get $plan package_name] green " version " blue [dict get $plan version]]
                }
                ${:pkgdbObj} refresh
            } on error {message options} {
                return -options $options $message
            } finally {
                file delete -force -- $stage
                set :stage_root ""
                set :plans {}
                set :active {}
                set :staged_paths {}
            }
        }

        :method stage_package {pkg force} {
            set pkgName [dict get $pkg package_name]
            if {[lsearch -exact ${:active} $pkgName] >= 0} {error "Dependency cycle involving $pkgName"}
            foreach plan ${:plans} {
                if {[dict get $plan package_name] eq $pkgName} {
                    if {[dict get $plan uuid_pkg_version] ne [dict get $pkg uuid_pkg_version]} {error "Conflicting dependency versions for $pkgName"}
                    return
                }
            }
            if {[llength ${:plans}] + [llength ${:active}] >= 64} {error "Dependency limit exceeded (64 packages)"}
            lappend :active $pkgName
            foreach unit [${:pkgdbObj} get_installed_packages_by_name $pkgName] {
                if {![dict get $unit managed] && !$force} {
                    error "System package $pkgName requires --force (-f) to install or update."
                }
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
                error "Failed to download $pkgName: $err"
            }

            set sys [::tpm::system new]
            if {[catch {set install_dir [$sys prepare_install_path]} path_err]} {
				echo "<s fg=red>✗ Unable to determine install location: </s> <s fg=yellow>$path_err</s>"
                file delete -force $temp_file
                error $path_err
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
                set stage [file join ${:stage_root} [llength ${:staged_paths}]]
                :extract_zip_to $temp_file $stage
                lappend :staged_paths $stage
                set loaded_version [:resolve_dependencies $pkg $force $stage]
                if {[package vcompare $loaded_version [dict get $pkg version]] != 0} {
                    dict set pkg repository_version [dict get $pkg version]
                    dict set pkg version $loaded_version
                    :cputs_multi [list yellow "Repository version differs from archive for $pkgName; using registered version $loaded_version."]
                }
                dict set pkg unit_paths $unit_paths
                dict set pkg install_root $install_dir
                dict set pkg files $entries
                dict set pkg stage $stage
                lappend :plans $pkg
            } unzip_err]} {
                file delete -force $temp_file
                error $unzip_err
            }
            file delete -force $temp_file
            set :active [lrange ${:active} 0 end-1]
        }

        :method resolve_dependencies {pkg force stage} {
            if {[dict exists $pkg dependencies]} {
                foreach dependency [dict get $pkg dependencies] {
                    set args [list [dict get $dependency name]]
                    if {[dict exists $dependency version]} {lappend args [dict get $dependency version]}
                    if {[dict exists $dependency exact] && [dict get $dependency exact]} {set args [linsert $args 0 -exact]}
                    set seen {}
                    while {1} {
                        set result [:probe_package $args]
                        if {[dict get $result status] eq "ok"} {break}
                        if {[dict get $result status] eq "alternatives"} {
                            set missing [:resolve_alternative $result $seen $force]
                            lappend seen $missing
                            continue
                        }
                        if {[dict get $result status] ne "missing"} {error "Dependency load failed: [dict get $result message]"}
                        set missing [dict get $result require]
                        if {[lsearch -exact $seen $missing] >= 0 || [llength $seen] >= 64} {
                            error "Dependency still unavailable after staging: $missing"
                        }
                        lappend seen $missing
                        :resolve_requirement $missing $force
                    }
                }
            }
            set seen {}
            for {set attempt 0} {$attempt < 64} {incr attempt} {
                set result [:probe_package [list [dict get $pkg package_name]] $stage]
                switch -- [dict get $result status] {
                    ok {return [dict get $result version]}
                    error {error "Package [dict get $pkg package_name] failed to load: [dict get $result message]"}
                    alternatives {
                        set requirement [:resolve_alternative $result $seen $force]
                        lappend seen $requirement
                    }
                    missing {
                        set requirement [dict get $result require]
                        if {[lsearch -exact $seen $requirement] >= 0} {
                            error "Dependency still unavailable after staging: $requirement"
                        }
                        lappend seen $requirement
                        :resolve_requirement $requirement $force
                    }
                    default {error "Invalid dependency probe result"}
                }
            }
            error "Dependency retry limit exceeded"
        }

        :method resolve_alternative {result seen force} {
            foreach requirement [dict get $result requirements] {
                if {[lsearch -exact $seen $requirement] >= 0} {continue}
                set exact [expr {[lindex $requirement 0] eq "-exact"}]
                set args $requirement
                if {$exact} {set args [lrange $args 1 end]}
                set name [lindex $args 0]
                if {[lsearch -exact ${:active} $name] >= 0} {continue}
                if {[${:pkgdbObj} find_remote_dependency $name [lrange $args 1 end] $exact] eq ""} {continue}
                :resolve_requirement $requirement $force
                return $requirement
            }
            error "Package failed to load: [dict get $result message]. No compatible untried dependency in repository: [dict get $result requirements]"
        }

        :method resolve_requirement {requirement force} {
            set exact [expr {[lindex $requirement 0] eq "-exact"}]
            if {$exact} {set requirement [lrange $requirement 1 end]}
            set name [lindex $requirement 0]
            if {$name eq "Tcl"} {error "Package needs a different Tcl runtime: $requirement"}
            if {$name eq [lindex ${:active} end]} {error "Downloaded archive does not register requested package $name (requirement: $requirement)"}
            if {[lsearch -exact ${:active} $name] >= 0} {error "Dependency cycle: [join ${:active} { -> }] -> $name"}
            set dependency [${:pkgdbObj} find_remote_dependency $name [lrange $requirement 1 end] $exact]
            if {$dependency eq ""} {error "No compatible repository package for dependency: $requirement"}
            :cputs_multi [list green "Resolving dependency " yellow $name green " version " blue [dict get $dependency version]]
            :stage_package $dependency $force
        }

        :method probe_package {requirement {target_stage ""}} {
            set dirs {}
            set target_dirs {}
            set queue ${:staged_paths}
            while {[llength $queue]} {
                set path [lindex $queue 0]
                set queue [lrange $queue 1 end]
                lappend dirs $path
                if {$target_stage ne "" && [string first "$target_stage/" "$path/"] == 0} {lappend target_dirs $path}
                lappend queue {*}[glob -nocomplain -types d -directory $path *]
            }
            set system [::tpm::system new]
            set paths [concat $dirs [$system get_package_paths]]
            set request [dict create paths $paths module_paths ${:staged_paths} require $requirement]
            dict set request target_paths $target_dirs
            set channel [file tempfile requestFile]
            puts $channel $request
            close $channel
            set channel [file tempfile resultFile]
            close $channel
            set pipe ""
            set wake ::tpm::probe_tick_[incr ::tpm::probe_serial]
            try {
                set pipe [open [list | [info nameofexecutable] $::tpm::dependency_probe $requestFile $resultFile 2>@1] r]
                fconfigure $pipe -blocking 0
                set started [clock milliseconds]
                set diagnostics ""
                while {![eof $pipe]} {
                    # Drain output so package diagnostics cannot fill the pipe.
                    append diagnostics [read $pipe]
                    set diagnostics [string range $diagnostics end-4095 end]
                    if {[clock milliseconds] - $started >= ${:probe_timeout}} {
                        foreach process [pid $pipe] {
                            if {$::tcl_platform(platform) eq "windows"} {
                                catch {exec taskkill /PID $process /T /F}
                            } else {
                                catch {exec kill -KILL -- $process}
                            }
                        }
                        error "Dependency probe timed out after ${:probe_timeout} ms: $requirement"
                    }
                    after 25 [list set $wake 1]
                    vwait $wake
                }
                close $pipe
                set pipe ""
                set channel [open $resultFile r]
                try {set result [string trim [read $channel]]} finally {close $channel}
                if {[catch {dict get $result status}]} {error "Dependency probe exited without a result: $requirement\n$diagnostics"}
                return $result
            } finally {
                if {$pipe ne ""} {catch {close $pipe}}
                unset -nocomplain $wake
                file delete -force -- $requestFile $resultFile
            }
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

        :method read_delete_selection {} {
            puts -nonewline "Select installation number, 'all', or Enter to cancel: "
            flush stdout
            if {[gets stdin answer] < 0} {return ""}
            return [string trim $answer]
        }

        :method select_deletion {pkgs} {
            :cputs_multi [list green "Multiple installations found:"]
            set number 0
            foreach pkg $pkgs {
                incr number
                :cputs_multi [list yellow "$number. " green "[dict get $pkg version] " cyan "[dict get $pkg origin] " blue [dict get $pkg path]]
            }
            while {1} {
                set answer [:read_delete_selection]
                if {$answer eq ""} {
                    :cputs_multi [list green "Deletion cancelled."]
                    return {}
                }
                if {$answer eq "all"} {return $pkgs}
                if {[string is integer -strict $answer] && $answer >= 1 && $answer <= [llength $pkgs]} {
                    return [list [lindex $pkgs [expr {$answer - 1}]]]
                }
                :cputs_multi [list red "Invalid selection. Choose 1-[llength $pkgs], 'all', or Enter to cancel."]
            }
        }

        :public method uninstall {pkgName {force 0} {version ""} {all 0}} {
            if {$all && $version ne ""} {error "Use either --version or --all"}
            set pkgs [${:pkgdbObj} get_installed_packages_by_name $pkgName]
            if {$version ne ""} {
                package vcompare $version 0
                set matches {}
                foreach pkg $pkgs {
                    set installedVersion [dict get $pkg version]
                    if {$installedVersion ne "" && [package vcompare $installedVersion $version] == 0} {lappend matches $pkg}
                }
                set pkgs $matches
            }
            if {[llength $pkgs] == 0} {
                :cputs_multi [list green "Cannot find installation information for " yellow "$pkgName"]
                return
            }
            if {!$all && $version eq "" && [llength $pkgs] > 1} {
                set pkgs [:select_deletion $pkgs]
                if {[llength $pkgs] == 0} {return}
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
