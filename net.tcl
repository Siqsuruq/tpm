namespace eval tpm {
    nx::Class create net -mixin Helper {
        :property {repo_url:substdefault {[::tpm::config cget -default_repo_url]}}

        :public method fetch_package_index {} {
			:show_title "Fetching packages from remote repository: ${:repo_url}"


            if {${:repo_url} eq ""} {
                return -code error "No repository URL configured."
            }

            set base [string trimright ${:repo_url} "/"]
            set query [::http::formatQuery platform [::platform::generic]]
            set listUrl "$base/packages/list_platform_packages?$query"

            # Animate independently of download size, with elapsed time only.
            set bar [zesty::Bar new -setColumns {zSpinner zName zElapsed}]
            set token ""

            try {
                $bar configureColumn zSpinner -spinnerStyle dots
                $bar addTask -name "Fetching package index" -mode indeterminate
                set token [::http::geturl $listUrl -binary true -keepalive 1]

                if {[::http::status $token] ne "ok"} {
                    set detail [lindex [::http::error $token] 0]
                    if {$detail eq ""} {set detail [::http::status $token]}
                    return -code error "Failed to fetch package list from $listUrl: $detail"
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
