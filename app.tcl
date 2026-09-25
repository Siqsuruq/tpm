namespace eval tpm {
    nx::Class create app -mixin Helper {
        :property {pkgdbObj:object,type=pkgdb,substdefault {[::tpm::pkgdb new]}}
        :property {netObj:object,type=net,substdefault {[::tpm::net new]}}
        :property {sysObj:object,type=system,substdefault {[::tpm::system new]}}

        :method init {} {
        }

        :public method start {} {
        set v [::tpm::config cget -tpm_version]
        set bb [zesty::box \
            -title {name "TPM - Tcl Package Manager" anchor "nw"} \
            -content {text "<s fg=green>Welcome to tpm (NX version) Version: $v</s>\n \
            <s fg=green>Type </s><s fg=blue>'help'</s><s fg=green> for commands. Type  </s><s fg=blue>'exit'</s><s fg=green> to quit</s> \n \
            <s fg=green>Repository: </s><s fg=blue>[::tpm::config cget -default_repo_url]</s>"} \
            -box {size {300 5}} \
            -paddingX 1 \
            -paddingY 0
        ]

        zesty::echo $bb
            :cputs red "------------------------------------------------------"

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
                    :cputs green "System information:"
                    :cputs red "------------------------------------------------------"
                    ${:sysObj} print_summary
                }
                install {
                    if {[llength $args] != 1} {
                        :cputs_multi [list green "Usage: " blue "install <package>"]
                    } else {
                        :install_package [lindex $args 0]
                    }
                }
                delete {
                    if {[llength $args] != 1} {
                        :cputs_multi [list green "Usage: " blue "delete <package>"]
                    } else {
                        :delete_package [lindex $args 0]
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
            :cputs green "Locally installed packages:"
            :cputs red "------------------------------------------------------"
			set table [zesty::Table new -box {type "rounded"}]
            $table addColumn -name "Package" -width 40 -style {fg yellow}
			$table addColumn -name "Version" -width 10 -style {fg green}
			$table addColumn -name "Path" -width 50 -style {fg cyan}
            $table addColumn -name "Type" -justify "left" -style {fg gray}
            if {[llength $args] == 0} {
				set pkgs [${:pkgdbObj} list_installed]
				if {$pkgs ne ""} {
					foreach pkgDict $pkgs {
						$table addRow "[dict get $pkgDict name]" "[dict get $pkgDict version]" "[dict get $pkgDict path]" "[dict get $pkgDict type]"
					}
				} else {
					$table addRow "<s fg=red>There is no packages installed.</s>" "" "" ""
				}
            } else {
                foreach pkg $args {
                    if {[${:pkgdbObj} is_installed $pkg]} {
                        set versions [${:pkgdbObj} get_installed_packages_by_name $pkg]
                        foreach pkgDict $versions {
							$table addRow "[dict get $pkgDict name]" "[dict get $pkgDict version]" "[dict get $pkgDict path]" "[dict get $pkgDict type]"
                        }
                    } else {
						$table addRow "$pkg <s fg=red>is not installed.</s>" "" "" ""
                    }
                }
            }
			$table display
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
                :cputs_multi [list red_bold "Error: " red "$errMsg"]
            }
        }

        :public method list_updates {} {
            try {
                set updates [${:pkgdbObj} check_updates]
                :cputs green "Available package updates:"
                :cputs red "------------------------------------------------------"
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
                :cputs_multi [list red_bold "Error: " red "$errMsg"]
            }
        }

        :method install_package {pkgName} {
            set inst [::tpm::installer new -pkgdbObj ${:pkgdbObj}] 
            $inst install $pkgName
            $inst destroy
        }

        :method delete_package {pkgName} {
            :cputs_multi [list green "Deleting locally installed package: " yellow "$pkgName"]
            :cputs red "------------------------------------------------------"
            if {![${:pkgdbObj} is_installed $pkgName]} {
                :cputs_multi [list green "Package " yellow "$pkgName" green " is not installed."]
                return
            }
            set inst [::tpm::installer new -pkgdbObj ${:pkgdbObj}] 
            $inst uninstall $pkgName
            $inst destroy
        }

        :method help {} {
			set data {
				{"installed" "List all locally installed packages"}
				{"installed <s fg=red>name(s)</s>" "Show version info of a specific installed package(s)"}
				{"available" "List packages in the remote repository"}
				{"install <s fg=red>name</s>" "Install package from the remote repository"}
				{"updates" "Check installed packages for available updates"}
				{"delete <s fg=red>name</s>" "Delete (uninstall) package"}
				{"system" "Shows current system information"}
				{"help" "Show this help message"}
				{"exit" "Exit the package manager"}
			}

			zesty::echo [zesty::box -title {name "Help" anchor "nw" style {fg 159}} -box {style {bold 1 fg gray}} \
				-content [list text $data \
					table {
						enabled "true"
						columns {20 60}
						alignments {"left" "left" "left"}
						styles {
							{bold 1}
							{}
						}
					} \
				]
			]
        }
    }
}
