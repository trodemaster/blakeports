# portcompiler.tcl — print the compiler MacPorts would pick for a Portfile,
# without fetching or building anything.
#
# Usage: port-tclsh scripts/portcompiler.tcl <portdir> [<portdir> ...]
#   <portdir> is a directory containing a Portfile (and its files/).
#
# Prints, per directory, configure.compiler, configure.cc, configure.cxx and
# the compiler.blacklist, as evaluated on this machine (OS, arch, Xcode).
package require macports
mportinit
foreach dir $argv {
    set dir [file normalize $dir]
    if {[catch {mportopen file://$dir} m]} {
        puts "$dir: cannot open: $m"
        continue
    }
    set w [ditem_key $m workername]
    puts "== $dir"
    foreach v {configure.compiler configure.cc configure.cxx compiler.blacklist} {
        puts "  $v: [$w eval [list option $v]]"
    }
    mportclose $m
}
