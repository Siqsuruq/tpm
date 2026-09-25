namespace eval tpm {
    nx::Object create config {
        :object property {basedir:substdefault {[file dirname [file normalize [info script]]]}}
        :object property {default_repo_url "https://tclrepo.daidze.org/api/v2"}
        :object property {tpm_version ""}
        :object property {tpm_path:substdefault {[file dirname [file normalize [info script]]]}}
        :object property {config_path ""}
        :object property {install_path ""}

        :public object method init {} {
            set :config_path [file join ${:basedir} var config.ini]
            :read_config
            :init_package_paths
			:init_custom_package_path
        }

        :object method read_config {} {
            set f ""
            try {
                set f [::ini::open ${:config_path} r]
                set :default_repo_url [::ini::value $f "repository" "default_repo_url"]
                set :tpm_version [::ini::value $f "tpm" "version"]
                set :install_path [::ini::value $f "custom_packages" "install_path"]
            } on error {errMsg} {
                puts "Failed to load config: $errMsg"
            } finally {
                if {$f ne ""} {
                    catch {::ini::close $f}
                }
            }
        }
		
		:object method init_custom_package_path {} {
			set path [string trim ${:install_path}]
			if {$path eq ""} {
				return
			}
			set path [file normalize $path]
			set :install_path $path
			# Make custom-installed packages visible to Tcl itself.
			if {[lsearch -exact $::auto_path $path] == -1} {
				lappend ::auto_path $path
			}
		}

        :object method init_package_paths {} {
            set libs_root [file normalize [file join ${:tpm_path} libs]]
            set filtered_auto_path {}
            foreach path $::auto_path {
                if {[:is_subpath $path $libs_root]} {
                    continue
                }
                lappend filtered_auto_path $path
            }
            # Original Tcl package paths, excluding TPM's private libs.
            set ::tpm::autopaths $filtered_auto_path
            # Top-level Tcl library roots.
            set ::tpm::libsdirs [:get_top_level_paths $filtered_auto_path]
        }

        :object method is_subpath {path parent} {
            set path   [file normalize $path]
            set parent [file normalize $parent]
            set pathParts   [file split $path]
            set parentParts [file split $parent]
            if {[llength $pathParts] < [llength $parentParts]} {
                return 0
            }
            set candidate [lrange $pathParts 0 [expr {[llength $parentParts] - 1}]]
            # Windows paths are case-insensitive.
            if {$::tcl_platform(platform) eq "windows"} {
                return [string equal -nocase [file join {*}$candidate] [file join {*}$parentParts]]
            }
            return [expr {$candidate eq $parentParts}]
        }

        :object method get_top_level_paths {paths} {
            set topLevels {}
            foreach path $paths {
                set isSubfolder 0
                foreach other $paths {
                    if {$path eq $other} {
                        continue
                    }
                    #
                    # If $path lives under $other, it is not a top-level root.
                    #
                    if {[:is_subpath $path $other]} {
                        set isSubfolder 1
                        break
                    }
                }

                if {!$isSubfolder} {
                    lappend topLevels $path
                }
            }
            return $topLevels
        }
    }
}