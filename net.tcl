namespace eval tpm {
    nx::Class create net {
        :property {repo_url:substdefault {[::tpm::config cget -default_repo_url]}}
        :property {progress_current 0}

        :public method http_progress {bar task token total current} {
            # total == 0 means Content-Length was not provided.
            if {$total <= 0} {
                return
            }

            set percent [expr {
                min(100, int(($current * 100.0) / $total))
            }]

            # zesty advance is relative, so calculate the difference.
            set delta [expr {$percent - ${:progress_current}}]

            if {$delta > 0} {
                $bar advance $task $delta
                set :progress_current $percent
            }
        }

        :public method fetch_package_index {} {
            :cputs green "Fetching packages from remote repository: ${:repo_url}"

            if {${:repo_url} eq ""} {
                return -code error "No repository URL configured."
            }

            set base [string trimright ${:repo_url} "/"]
            set listUrl "$base/packages/list_packages"

            #
            # Zesty progress bar.
            #
            set bar [zesty::Bar new]
            set task [$bar addTask -name "Fetching package index" -total 100]

            set :progress_current 0
            set token ""

            try {
                set token [::http::geturl $listUrl -binary true -keepalive 1 -progress [list [self] http_progress $bar $task]]

                #
                # Make sure we end at 100%.
                #
                if {${:progress_current} < 100} {
                    $bar advance $task [expr {100 - ${:progress_current}}]
                    set :progress_current 100
                }

                if {[::http::status $token] ne "ok"} {
                    return -code error "Failed to fetch package list from $listUrl"
                }

                set body [::http::data $token]

                ::http::cleanup $token
                set token ""

                set jsonDict [::json::json2dict $body]

                if {![dict exists $jsonDict data]} {
                    return -code error "Invalid response: missing 'data' key"
                }

                return [dict get $jsonDict data]

            } finally {
                if {$token ne ""} {
                    catch {::http::cleanup $token}
                }

                $bar destroy
            }
        }
    }
}
