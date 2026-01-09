# macOS Version Details

This document provides a reference table for macOS versions, Darwin kernel versions, and their corresponding `os.major` values used in MacPorts Portfiles.

## macOS Version Reference Table

| macOS Version | Code Name | Darwin Version | os.major | Release Date | Latest Xcode | Status |
|---------------|-----------|----------------|----------|--------------|--------------|---------|
| Mac OS X 10.0 | Cheetah | Darwin 1.0 | 1 | March 2001 | Xcode Tools 1.0 | Discontinued |
| Mac OS X 10.1 | Puma | Darwin 1.3 | 1 | September 2001 | Xcode Tools 1.0 | Discontinued |
| Mac OS X 10.2 | Jaguar | Darwin 6.0 | 6 | August 2002 | Xcode Tools 1.0 | Discontinued |
| Mac OS X 10.3 | Panther | Darwin 7.0 | 7 | October 2003 | Xcode Tools 1.5 | Discontinued |
| Mac OS X 10.4 | Tiger | Darwin 8.0 | 8 | April 2005 | Xcode Tools 2.5 | Discontinued |
| Mac OS X 10.5 | Leopard | Darwin 9.0 | 9 | October 2007 | Xcode 3.0 | Discontinued |
| Mac OS X 10.6 | Snow Leopard | Darwin 10.0 | 10 | August 2009 | Xcode 3.2.6 | Discontinued |
| Mac OS X 10.7 | Lion | Darwin 11.0 | 11 | July 2011 | Xcode 4.6.3 | Discontinued |
| OS X 10.8 | Mountain Lion | Darwin 12.0 | 12 | July 2012 | Xcode 5.1.1 | Discontinued |
| OS X 10.9 | Mavericks | Darwin 13.0 | 13 | October 2013 | Xcode 6.4 | Discontinued |
| OS X 10.10 | Yosemite | Darwin 14.0 | 14 | October 2014 | Xcode 7.3.1 | Discontinued |
| OS X 10.11 | El Capitan | Darwin 15.0 | 15 | September 2015 | Xcode 8.3.3 | Discontinued |
| macOS 10.12 | Sierra | Darwin 16.0 | 16 | September 2016 | Xcode 9.4.1 | Discontinued |
| macOS 10.13 | High Sierra | Darwin 17.0 | 17 | September 2017 | Xcode 10.1 | Discontinued |
| macOS 10.14 | Mojave | Darwin 18.0 | 18 | September 2018 | Xcode 11.7 | Discontinued |
| macOS 10.15 | Catalina | Darwin 19.0 | 19 | October 2019 | Xcode 12.5.1 | Discontinued |
| macOS 11 | Big Sur | Darwin 20.0 | 20 | November 2020 | Xcode 13.4.1 | Discontinued |
| macOS 12 | Monterey | Darwin 21.0 | 21 | October 2021 | Xcode 14.3.1 | Discontinued |
| macOS 13 | Ventura | Darwin 22.0 | 22 | October 2022 | Xcode 15.4 | Discontinued |
| macOS 14 | Sonoma | Darwin 23.0 | 23 | September 2023 | Xcode 16.1 | Discontinued |
| macOS 15 | Sequoia | Darwin 24.0 | 24 | September 2024 | Xcode 16.1 | Current |
| macOS 26 | Tahoe | Darwin 25.0 | 25 | Future | Xcode 26.1 | Planned |

## MacPorts Legacy Support Compatibility

| Legacy Support Version | Target macOS Versions | Darwin Range | os.major Range | Use Case |
|------------------------|----------------------|--------------|----------------|----------|
| Legacy Support 1.1 | macOS 10.7 and earlier | Darwin 11 and below | os.major <= 11 | Very old systems with basic compatibility needs |
| Legacy Support 1.2 | macOS 10.8 - 11.x | Darwin 12-20 | os.major 12-20 | Intermediate legacy systems |
| Modern MacPorts | macOS 12 and later | Darwin 21+ | os.major >= 21 | Current systems with full modern support |

## SSL/TLS Compatibility Notes

| macOS Version Range | SSL/TLS Issues | Automatic Solution |
|-------------------|----------------|---------------------|
| macOS 10.11 and earlier (Darwin 15) | GitHub SSL handshake failures | GitHub portgroup automatically uses MacPorts curl |
| macOS 10.12 and later (Darwin 16+) | No SSL issues | Standard fetch mechanism works |

**Note:** The GitHub portgroup (github 1.0) automatically handles SSL/TLS issues on older macOS versions. Ports using `PortGroup github 1.0` will automatically use MacPorts curl for fetching on Darwin 15 and earlier.

## Portfile Conditional Logic Examples

### Basic OS Version Check
```tcl
platform darwin {
    if {${os.major} <= 11} {
        # macOS 10.7 and earlier
    } elseif {${os.major} <= 20} {
        # macOS 10.8 - 11.x
    } else {
        # macOS 12 and later
    }
}
```

### GitHub-based Portfile
```tcl
# SSL workaround is automatically handled by github 1.0 portgroup for Darwin 15 and earlier
PortSystem          1.0
PortGroup           github 1.0

github.setup        owner repo version
# No custom fetch logic needed - portgroup handles SSL issues automatically
```

### Legacy Support Selection
```tcl
platform darwin {
    if {${os.major} <= 11} {
        # Legacy Support 1.1 for very old systems
        PortGroup           legacysupport 1.1
    } elseif {${os.major} <= 20} {
        # Legacy Support 1.2 for intermediate systems
        PortGroup           legacysupport 1.2
    }
    # macOS 12+ (Darwin 21+): No legacy support needed
}
```

## References

- [macOS version history - Wikipedia](https://en.wikipedia.org/wiki/MacOS_version_history)
- [MacPorts Development Mailing List Archives](https://lists.macports.org/pipermail/macports-dev/)
- [MacPorts Guide - Portfile Reference](https://guide.macports.org/#reference.portfile)
