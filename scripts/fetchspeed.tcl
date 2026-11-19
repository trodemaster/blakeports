# fetchspeed.tcl — time MacPorts mirror downloads the way base fetches them.
#
# Usage: port-tclsh scripts/fetchspeed.tcl [options] [port ...]
#
#   -kind archive|distfile  what to fetch (default archive)
#   -count N                random ports to test when none are named (default 2)
#   -min-mb M, -max-mb M    file size range for random ports (default 10, 150)
#   -tries N                random ports to look at before giving up (default 150)
#   -seed S                 random seed (default: from the clock)
#   -tsv FILE               append one row per fetch to FILE, tab-separated:
#       first_configured first_stock kind port file size label url bytes secs
#       MBps ttfb slowest5s_MBps below1MBps_secs getsize_secs x_cache age
#       x_served_by cache(cold|warm|-) error
#
# Everything MacPorts decides is asked of base itself: the archive or
# distfile name and mirror list come from the port's own interpreter
# (get_portimage_name, portfetch::mirror_sites), the mirror ranking from
# portfetch::sortsites (ping times, ping cache, preferred_hosts and
# host_blacklist), and every transfer is Pextlib's `curl getsize` and
# `curl fetch` with the options portarchivefetch passes. The script only adds
# timing, and a `curl -I` afterwards to read the CDN's cache headers.
#
# For each file it fetches, in this order:
#   fastly-1  packages.macports.org (or distfiles.), normally a cache miss
#   fastly-2  the same URL again, normally a cache hit
#   origin    packages-origin.macports.org (or distfiles-origin.), no CDN
#   fcix      mirror.fcix.net
# Random ports are picked so a run is likely to hit files the CDN hasn't
# cached yet; the origin is asked first (it isn't behind the CDN) to check
# the file exists and its size.

package require macports
package require Pextlib

set kind archive
set count 2
set min_mb 10
set max_mb 150
set tries 150
set seed [clock clicks]
set tsv ""
set ports [list]
for {set i 0} {$i < [llength $argv]} {incr i} {
    set a [lindex $argv $i]
    switch -- $a {
        -kind   { set kind   [lindex $argv [incr i]] }
        -count  { set count  [lindex $argv [incr i]] }
        -min-mb { set min_mb [lindex $argv [incr i]] }
        -max-mb { set max_mb [lindex $argv [incr i]] }
        -tries  { set tries  [lindex $argv [incr i]] }
        -seed   { set seed   [lindex $argv [incr i]] }
        -tsv    { set tsv    [lindex $argv [incr i]] }
        default { lappend ports $a }
    }
}
if {$kind ni {archive distfile}} {
    puts stderr "error: -kind must be archive or distfile"
    exit 1
}

mportinit
expr {srand($seed)}

set group [expr {$kind eq "archive" ? "macports_archives" : "macports_distfiles"}]
set cdn_host [expr {$kind eq "archive" ? "packages.macports.org" : "distfiles.macports.org"}]
set origin_host [expr {$kind eq "archive" ? "packages-origin.macports.org" : "distfiles-origin.macports.org"}]
# portarchivefetch and portfetch pass --disable-epsv (archivefetch.use_epsv
# and fetch.use_epsv default to no), and no other fixed options.
set fixed_args [list --disable-epsv]
set tmpdir [file join [expr {[info exists env(TMPDIR)] ? $env(TMPDIR) : "/tmp"}] fetchspeed.[pid]]
file mkdir $tmpdir

proc host_of {url} {
    regexp {[a-zA-Z]+://([a-zA-Z0-9\.\-_]+)} $url -> host
    return $host
}

proc mb {bytes} { return [format %.1f [expr {$bytes / 1048576.0}]] }

# --- runner -----------------------------------------------------------------

puts "== runner"
puts "  os: $macports::os_platform $macports::os_major $macports::os_arch, macOS $macports::macos_version"
puts "  build_arch: $macports::build_arch, MacPorts [macports::version]"
puts "  preferred_hosts: $macports::preferred_hosts"
puts "  host_blacklist: $macports::host_blacklist"
puts "  kind: $kind, seed: $seed"

if {$kind eq "archive" && $macports::os_platform eq "darwin" && $macports::os_major < 10} {
    puts "\nThe MacPorts buildbots publish no darwin_$macports::os_major archives,"
    puts "so base never fetches an archive here. Use -kind distfile."
    exit 0
}

# --- the file base would fetch for a port -----------------------------------

# Returns a dict for the port's archive or first distfile: port, file, and
# urls, a dict of label -> URL (cdn, origin, fcix) built from the mirror
# group's sites the way base builds them for this port. Errors if the port
# can't be opened or the CDN isn't in its mirror list.
proc port_file {name porturl} {
    global kind group cdn_host origin_host
    set m [mportopen $porturl [dict create subport $name] {}]
    set w [ditem_key $m workername]
    try {
        if {$kind eq "archive"} {
            # This machine may not use the stock group (archive_sites.conf can
            # turn it off); it is still what a stock install fetches from.
            global archive_sites_shown
            if {![info exists archive_sites_shown]} {
                set archive_sites_shown 1
                puts "  archive_sites in use here: [$w eval {option archive_sites}]"
            }
            set file [file rootname [$w eval get_portimage_name]].tbz2
            set subdir [$w eval {option archive.subdir}]
            set sites [$w eval [list portfetch::mirror_sites $group "" "" \
                [$w eval portarchivefetch::get_full_archive_sites_path]]]
        } else {
            set distfiles [$w eval {option distfiles}]
            if {$distfiles eq ""} {
                error "no distfiles"
            }
            set file [$w eval [list getdistname [lindex $distfiles 0]]]
            set subdir ""
            set sites [$w eval [list portfetch::mirror_sites $group "" "" \
                [$w eval portfetch::get_full_mirror_sites_path]]]
        }
        set cdn [lsearch -inline -glob $sites "*://$cdn_host/*"]
        if {$cdn eq ""} {
            error "$cdn_host isn't in this port's $group list"
        }
        # The origin, with the scheme base uses for the CDN on this OS.
        regsub "://$cdn_host/" $cdn "://$origin_host/" origin
        set urls [dict create]
        foreach {label site} [list cdn $cdn origin $origin \
                fcix [lsearch -inline -glob $sites "*://mirror.fcix.net/*"]] {
            if {$site eq ""} {
                continue
            }
            # As portarchivefetch and portfetch assemble them.
            if {$kind eq "archive"} {
                set site [expr {[string index $site end] eq "/" ? $site : "${site}/"}]$subdir
            }
            dict set urls $label [$w eval [list portfetch::assemble_url $site $file]]
        }
        # Rank the group's sites with base's own sortsites, once.
        global ranked
        if {![info exists ranked]} {
            set ranked 1
            rank_sites $w $sites
        }
    } finally {
        mportclose $m
    }
    return [dict create port $name file $file urls $urls]
}

proc sorted_with_pings {w sites} {
    # Ping times base already had (from its 24-hour cache, or 0/-1 from
    # preferred_hosts/host_blacklist) are marked "c"; the rest it pinged now.
    set cached [dict create]
    foreach site $sites {
        set host [host_of $site]
        if {[macports::get_pingtime $host] ne ""} {
            dict set cached $host 1
        }
    }
    $w eval [list set portfetch::urlmap(fetchspeed) $sites]
    $w eval {
        set fetchspeed_urls [list fetchspeed x]
        portfetch::sortsites fetchspeed_urls fetchspeed
    }
    set out [list]
    foreach site [$w eval {set portfetch::urlmap(fetchspeed)}] {
        set host [host_of $site]
        lappend out $site "[macports::get_pingtime $host][expr {[dict exists $cached $host] ? " c" : "  "}]"
    }
    return $out
}

proc rank_sites {w sites} {
    global first_configured first_stock
    puts "\n== mirror ranking (portfetch::sortsites; ms, c = from base's cache;"
    puts "   0 = preferred_hosts, 5000/10000 = ping failed)"
    set conf [sorted_with_pings $w $sites]
    set first_configured [host_of [lindex $conf 0]]
    if {$macports::host_blacklist ne "" || $macports::preferred_hosts ne ""} {
        puts "  as configured:"
        foreach {site ms} $conf { puts [format "    %10s  %s" $ms $site] }
        # Again with stock settings, as on a fresh install.
        set macports::host_blacklist {}
        set macports::preferred_hosts {}
        set macports::host_cache [dict create]
        set stock [sorted_with_pings $w $sites]
        puts "  stock macports.conf (no preferred_hosts or host_blacklist):"
    } else {
        set stock $conf
        puts "  stock macports.conf (no preferred_hosts or host_blacklist), same as configured:"
    }
    foreach {site ms} $stock { puts [format "    %10s  %s" $ms $site] }
    set first_stock [host_of [lindex $stock 0]]
    puts "  base tries first: $first_configured as configured, $first_stock with stock settings"
}

# --- picking ports ----------------------------------------------------------

set candidates [list]
if {[llength $ports] > 0} {
    foreach name $ports {
        if {[catch {mportlookup $name} res] || [llength $res] < 2} {
            puts "$name: not found"
            continue
        }
        lappend candidates $name [dict get [lindex $res 1] porturl]
    }
    set want [expr {[llength $candidates] / 2}]
    set check_size 0
} else {
    # Shuffle the whole index (later sources first, so the official tree
    # wins over a local overlay like blakeports for a port in both).
    set seen [dict create]
    set all [list]
    foreach {name info} [lreverse [mportlistall]] {
        # lreverse swaps each pair: info comes first
        lassign [list $name $info] info name
        if {[dict exists $seen $name] || ![dict exists $info porturl]} {
            continue
        }
        dict set seen $name 1
        lappend all [list $name [dict get $info porturl]]
    }
    set n [llength $all]
    while {$n} {
        set j [expr {int($n * rand())}]
        set t [lindex $all $j]
        lset all $j [lindex $all [incr n -1]]
        lset all $n $t
    }
    foreach p [lrange $all 0 [expr {$tries - 1}]] {
        lappend candidates {*}$p
    }
    set want $count
    set check_size 1
}

set files [list]
set looked 0
foreach {name porturl} $candidates {
    if {[llength $files] >= $want} {
        break
    }
    incr looked
    if {[catch {port_file $name $porturl} pf]} {
        if {!$check_size} { puts "$name: $pf" }
        continue
    }
    # The origin isn't behind the CDN, so asking it doesn't warm the cache.
    set url [dict get $pf urls origin]
    if {[catch {curl getsize $url} size] || $size <= 0} {
        if {!$check_size} { puts "$name: [dict get $pf file] not on $origin_host" }
        continue
    }
    if {$check_size && ($size < $min_mb * 1048576 || $size > $max_mb * 1048576)} {
        continue
    }
    dict set pf size $size
    lappend files $pf
}
puts "\n== files ([llength $files] of $want wanted, $looked ports looked at)"
foreach pf $files {
    puts "  [dict get $pf port]: [dict get $pf file] ([mb [dict get $pf size]] MB)"
}
if {[llength $files] == 0} {
    puts "no file found; try more -tries or a wider -min-mb/-max-mb"
    exit 1
}

# --- timed fetches ----------------------------------------------------------

# Progress callback for curl fetch: same signature as base's
# ui_progress_download (update <type> <total> <now> <speed>).
proc progress {action args} {
    global samples t0 ttfb
    if {$action eq "update"} {
        lassign $args type total now speed
        set t [clock milliseconds]
        if {$now > 0 && $ttfb < 0} {
            set ttfb [expr {$t - $t0}]
        }
        if {[llength $samples] == 0 || $t - [lindex $samples end-1] >= 250} {
            lappend samples $t $now
        }
    }
    return 0
}

# Slowest 5-second stretch and time spent below 1 MB/s, from the samples.
proc profile {} {
    global samples
    set slowest ""
    set below 0.0
    set pts $samples
    for {set i 0} {$i + 3 < [llength $pts]} {incr i 2} {
        lassign [lrange $pts $i $i+3] ta na tb nb
        if {$tb > $ta && ($nb - $na) / (($tb - $ta) / 1000.0) < 1048576} {
            set below [expr {$below + ($tb - $ta) / 1000.0}]
        }
        for {set j [expr {$i + 2}]} {$j + 1 < [llength $pts]} {incr j 2} {
            set tj [lindex $pts $j]
            if {$tj - $ta >= 5000} {
                set r [expr {([lindex $pts $j+1] - $na) / (($tj - $ta) / 1000.0)}]
                if {$slowest eq "" || $r < $slowest} {
                    set slowest $r
                }
                break
            }
        }
    }
    return [list $slowest $below]
}

proc cache_headers {url} {
    set curlbin [expr {[file executable /opt/local/bin/curl] ? "/opt/local/bin/curl" : "curl"}]
    set h [dict create x-cache - x-served-by - age -]
    if {![catch {exec $curlbin -sI -m 20 $url} out]} {
        foreach line [split $out \n] {
            if {[regexp -nocase {^(x-cache|x-served-by|age):\s*(.*?)\s*$} $line -> k v]} {
                dict set h [string tolower $k] $v
            }
        }
    }
    return $h
}

set rows [list]
proc timed_fetch {label pf url} {
    global fixed_args tmpdir samples t0 ttfb kind rows
    set out [file join $tmpdir [dict get $pf file]]
    file delete -force $out
    # Before fetching an archive, base checks it and its signature exist
    # (_archive_available: curl getsize, no options); portfetch fetches
    # distfiles directly.
    set hs ""
    if {$kind eq "archive"} {
        set h0 [clock milliseconds]
        catch {curl getsize $url}
        catch {curl getsize ${url}.sig}
        set hs [format %.2f [expr {([clock milliseconds] - $h0) / 1000.0}]]
    }
    set samples [list]
    set ttfb -1
    set t0 [clock milliseconds]
    set err ""
    if {[catch {curl fetch --progress progress {*}$fixed_args $url $out} e]} {
        set err $e
    }
    set secs [expr {max(([clock milliseconds] - $t0) / 1000.0, 0.001)}]
    set bytes [expr {[file exists $out] ? [file size $out] : 0}]
    file delete -force $out
    lassign [profile] slowest below
    set h [expr {[string match *macports.org* [host_of $url]] && ![string match *-origin.* [host_of $url]]
        ? [cache_headers $url] : [dict create x-cache - x-served-by - age -]}]
    # cold: the CDN's copy is no older than this fetch, so this fetch filled
    # it (a cache miss); warm: it was already cached.
    set cache -
    if {[string is integer -strict [dict get $h age]]} {
        set cache [expr {[dict get $h age] <= ([clock milliseconds] - $t0) / 1000 + 2 ? "cold" : "warm"}]
    }
    set mbs [format %.2f [expr {$bytes / $secs / 1048576.0}]]
    set slow5 [expr {$slowest eq "" ? "-" : [format %.2f [expr {$slowest / 1048576.0}]]}]
    set ttfbs [expr {$ttfb < 0 ? "-" : [format %.2f [expr {$ttfb / 1000.0}]]}]
    puts [format "  %-9s %7s MB/s  %6.1f s  ttfb %5s s  slowest-5s %6s MB/s  <1MB/s %5.1f s  %s" \
        $label $mbs $secs $ttfbs $slow5 $below \
        [expr {$cache eq "-" ? "" : "$cache (x-cache: [dict get $h x-cache], age [dict get $h age])"}]]
    if {[dict get $h x-served-by] ne "-"} {
        puts "            x-served-by: [dict get $h x-served-by]"
    }
    if {$err ne ""} {
        puts "            error: $err"
    }
    lappend rows [list $kind [dict get $pf port] [dict get $pf file] [dict get $pf size] $label $url \
        $bytes [format %.2f $secs] $mbs $ttfbs $slow5 [format %.1f $below] $hs \
        [dict get $h x-cache] [dict get $h age] [dict get $h x-served-by] $cache $err]
}

foreach pf $files {
    set urls [dict get $pf urls]
    puts "\n== [dict get $pf port]: [dict get $pf file] ([mb [dict get $pf size]] MB)"
    puts "  [dict get $urls cdn]"
    timed_fetch fastly-1 $pf [dict get $urls cdn]
    timed_fetch fastly-2 $pf [dict get $urls cdn]
    timed_fetch origin $pf [dict get $urls origin]
    if {[dict exists $urls fcix]} {
        timed_fetch fcix $pf [dict get $urls fcix]
    }
}
file delete -force $tmpdir

puts "\nbase tries first: $first_configured as configured, $first_stock with stock settings"
if {$tsv ne ""} {
    set fd [open $tsv a]
    foreach r $rows {
        puts $fd [join [concat [list $first_configured $first_stock] $r] \t]
    }
    close $fd
}
