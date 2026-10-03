namespace eval tpm {
    nx::Class create app -mixin Helper {
        :property {pkgdbObj:object,type=pkgdb,substdefault {[::tpm::pkgdb new]}}
        :property {netObj:object,type=net,substdefault {[::tpm::net new]}}
        :property {sysObj:object,type=system,substdefault {[::tpm::system new]}}

        :method init {} {
        }

        :public method start {} {
			set bb [zesty::box \
				-title {name "TPM - Tcl Package Manager" anchor "nw"} \
				-content [subst {text "<s fg=green>Welcome to tpm (NX version) Version: [::tpm::config cget -tpm_version]</s>\n \
				<s fg=green>Type </s><s fg=blue>'help'</s><s fg=green> for commands. Type  </s><s fg=blue>'exit'</s><s fg=green> to quit</s> \n \
				<s fg=green>Repository: </s><s fg=blue>[::tpm::config cget -default_repo_url]</s>"}] \
				-box {size {300 5}} \
				-paddingX 1 \
				-paddingY 0
			]
			zesty::echo $bb
			:show_separator

            while {1} {
                puts -nonewline "> "
                flush stdout
                if {[gets stdin line] < 0 || $line eq "exit"} {
                    :cputs green "Goodbye!"
                    break
                }
                if {$line eq ""} {
                    continue
                }
                :process_command $line
            }
        }

        :method process_command {line} {
            set cmd [lindex $line 0]
            set args [lrange $line 1 end]

            switch -- $cmd {
                installed {
                    :list_local {*}$args
                }
                available {
                    :list_remote
                }
                updates {
                    :list_updates
                }
                system {
                    ${:sysObj} print_summary
                }
                delete {
                    set force 0
                    set version ""
                    set all 0
                    set names {}
                    set invalid 0
                    for {set i 0} {$i < [llength $args]} {incr i} {
                        set arg [lindex $args $i]
                        switch -- $arg {
                            -f - --force {set force 1}
                            --all {set all 1}
                            --version {
                                incr i
                                set value [lindex $args $i]
                                if {$version ne "" || $value eq "" || [catch {package vcompare $value 0}]} {
                                    set invalid 1
                                } else {set version $value}
                            }
                            default {
                                if {[string match -* $arg]} {set invalid 1} else {lappend names $arg}
                            }
                        }
                    }
                    if {$invalid || [llength $names] != 1 || ($all && $version ne "")} {
                        :cputs_multi [list green "Usage: " blue "delete <package> \[--version <version>|--all\] \[--force|-f\]"]
                    } else {
                        try {
                            :delete_package [lindex $names 0] $force $version $all
                        } on error {message} {:show_error $message}
                    }
                }
                install - update {
                    set force 0
                    set names {}
                    set invalid 0
                    foreach arg $args {
                        if {$arg in {--force -f}} {
                            set force 1
                        } elseif {[string match -* $arg]} {
                            set invalid 1
                        } else {
                            lappend names $arg
                        }
                    }
                    if {$invalid || [llength $names] != 1} {
                        :cputs_multi [list green "Usage: " blue "$cmd <package> \[--force|-f\]"]
                    } else {
                        try {
                            :${cmd}_package [lindex $names 0] $force
                        } on error {message} {
                            :show_error $message
                        }
                    }
                }
                help {
                    :help
                }
                default {
                    :cputs_multi [list red "Unknown command: " blue "$cmd"]
                    :help
                }
            }
        }

		:method list_local {args} {
			:show_title "Locally installed packages:"

			set table [zesty::Table new -box {type "rounded"}]
			$table addColumn -name "Package" -width 30 -style {fg yellow}
			$table addColumn -name "Version" -width 10 -style {fg green}
			$table addColumn -name "Origin" -width 8 -style {fg green}
			$table addColumn -name "Path" -width 60 -style {fg cyan}
			$table addColumn -name "Provides" -justify "left" -style {fg gray}
			if {[llength $args] == 0} {
				set pkgs [${:pkgdbObj} list_installed]
				if {[llength $pkgs] > 0} {
					foreach pkgDict $pkgs {
						$table addRow [dict get $pkgDict name] [dict get $pkgDict version] [dict get $pkgDict origin] [dict get $pkgDict path] [dict get $pkgDict provided_count]
					}
				} else {
					$table addRow "<s fg=red>There are no packages installed.</s>" "" "" "" ""
				}
			} else {
				foreach pkg $args {
					set found 0
					foreach unit [${:pkgdbObj} list_installed] {
						if {[dict get $unit name] eq $pkg || [lsearch -exact [dict get $unit provided_names] $pkg] >= 0} {
							$table addRow [dict get $unit name] [dict get $unit version] [dict get $unit origin] [dict get $unit path] [dict get $unit provided_count]
							set found 1
						}
					}
					if {!$found} {
						$table addRow "$pkg <s fg=red>is not installed.</s>" "" "" "" ""
					}
				}
			}
			$table display
			:show_separator
		}

        :public method list_remote {} {
            try {
                set net [::tpm::net new]
                set packages [$net fetch_package_index]
                $net destroy
				set table [zesty::Table new -box {type "rounded"}]
				$table addColumn -name "Package" -width 25 -style {fg yellow}
				$table addColumn -name "Version" -width 10 -style {fg green}
				$table addColumn -name "Platform" -width 15 -style {fg blue}
				$table addColumn -name "Description" -justify "left" -style {fg gray}
                foreach pkg $packages {
					$table addRow "[dict get $pkg package_name]" "[dict get $pkg version]" "[dict get $pkg platform_name]" "[dict get $pkg package_description]"
                }
				$table display
            } on error {errMsg} {
				:show_error $errMsg
            }
        }

        :public method list_updates {} {
            try {
                set updates [${:pkgdbObj} check_updates]
				:show_title "Available package updates:"

				set table [zesty::Table new -box {type "rounded"}]
				$table addColumn -name "Package" -width 25 -style {fg yellow}
				$table addColumn -name "Local Version" -width 15 -style {fg green}
				$table addColumn -name "Remote Version" -width 15 -style {fg blue}
                if {[llength $updates] == 0} {
                    :cputs_multi [list green " ✓ " yellow "All packages are up to date."]
                    return
                }
                foreach upd $updates {
                    set line [list \
                        cyan " - " \
                        yellow [format "%-20s" [dict get $upd name]] \
                        green  [format "%-8s" [dict get $upd local_version]] \
                        magenta " -> " \
                        green  [format "%-8s" [dict get $upd remote_version]] \
                    ]
                    :cputs_multi $line
                }
            } on error {errMsg} {
                :show_error $errMsg
            }
        }

        :method install_package {pkgName {force 0}} {
            set inst [::tpm::installer new -pkgdbObj ${:pkgdbObj}] 
            try {$inst install $pkgName $force} finally {$inst destroy}
        }

        :method update_package {pkgName {force 0}} {
            set inst [::tpm::installer new -pkgdbObj ${:pkgdbObj}]
            try {$inst update $pkgName $force} finally {$inst destroy}
        }

        :method delete_package {pkgName {force 0} {version ""} {all 0}} {
			:show_title "Deleting locally installed package:"
            :cputs_multi [list green " " yellow "$pkgName"]

            if {![${:pkgdbObj} is_installed $pkgName]} {
                :cputs_multi [list green "Package " yellow "$pkgName" green " is not installed."]
                return
            }
            set inst [::tpm::installer new -pkgdbObj ${:pkgdbObj}] 
            try {$inst uninstall $pkgName $force $version $all} finally {$inst destroy}
			:show_separator
        }


		
		
        :method help {} {
			:show_title "Help:"
			set data {
				{"installed" "List all locally installed packages"}
				{"installed name(s)" "Show version info of a specific installed package(s)"}
				{"available" "List packages in the remote repository"}
				{"install name [-f|--force]" "Install latest repository version; force required for system packages"}
				{"update name [-f|--force]" "Install a newer repository version; force required for system packages"}
				{"updates" "Check installed packages for available updates"}
				{"delete name [-f|--force]" "Delete package; force required for system packages"}
				{"delete name --version VERSION" "Delete only the specified version; add -f for system packages"}
				{"delete name --all" "Delete all installed versions; add -f for system packages"}
				{"system" "Shows current system information"}
				{"help" "Show this help message"}
				{"exit" "Exit the package manager"}
			}
			set table [zesty::Table new -lines {show "false"} -header  {show "false"} -showEdge "false"	]
			$table addColumn -name "Command" -width 30 -style {fg yellow}
			$table addColumn -name "Description" -style {fg green}
			foreach line $data {
				$table addRow "[lindex $line 0]" "[lindex $line 1]"
			}
			$table display
			:show_separator
        }
    }
}
