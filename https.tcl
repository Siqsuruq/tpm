# Shared HTTPS transport for repository indexes and package downloads.
namespace eval ::tpm {}

proc ::tpm::https_ca_file {} {
    # Respect OpenSSL's explicit trust-store configuration.
    if {[info exists ::env(SSL_CERT_FILE)] || [info exists ::env(SSL_CERT_DIR)]} {return ""}
    if {$::tcl_platform(os) ne "Linux"} {return ""}
    foreach path {
        /etc/ssl/certs/ca-certificates.crt
        /etc/pki/tls/certs/ca-bundle.crt
        /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
        /etc/ssl/ca-bundle.pem
        /etc/ssl/cert.pem
    } {
        if {[file isfile $path] && [file readable $path]} {return $path}
    }
    return ""
}

proc ::tpm::https_tls_event {event channel args} {
    # HTTP otherwise replaces handshake failures with "failed to use socket".
    if {$event eq "error" && [llength [info commands ::http::registerError]]} {
        ::http::registerError $channel "TLS handshake failed: [lindex $args 0]"
    }
    # Preserve TclTLS's certificate-verification decision on older releases.
    if {$event eq "verify"} {return [::tls::callback $event $channel {*}$args]}
    return
}

proc ::tpm::https_socket {args} {
    set options [list -autoservername 1 -command ::tpm::https_tls_event]
    set caFile [::tpm::https_ca_file]
    if {$caFile ne ""} {lappend options -cafile $caFile}
    return [::tls::socket {*}$options {*}$args]
}

::http::register https 443 ::tpm::https_socket
