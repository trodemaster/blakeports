// macports-cache: a local binary archive cache server for MacPorts.
//
// Serves pre-built .tbz2 archives over HTTP, signs them on-demand with an
// RSA/RIPEMD-160 key (compatible with MacPorts' archive verification), and
// watches the cache directory for new archives added via file share.
//
// MacPorts URL pattern: {base_url}/{subport}/{archive}.tbz2
//                   and {base_url}/{subport}/{archive}.tbz2.rmd160
//
// Quick start:
//
//	macports-cache -port 8030 -dir ~/macports-cache-data
//
// Then follow the printed client setup instructions.
package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/ripemd160"
)

// rmd160DigestInfo is the DER-encoded DigestInfo header for RIPEMD-160 using
// the Teletrust OID (1.3.36.3.2.1). This is the OID OpenSSL and MacPorts use
// for -ripemd160 signing/verification. Go's crypto/rsa uses a different OID
// (ISO 1.0.10118.3.0.49), so we build the DigestInfo manually and sign with
// hash=0 (raw bytes) to ensure compatibility.
var rmd160DigestInfo = []byte{
	0x30, 0x21, // SEQUENCE 33 bytes
	0x30, 0x09, // SEQUENCE 9 bytes
	0x06, 0x05, // OID 5 bytes
	0x2b, 0x24, 0x03, 0x02, 0x01, // 1.3.36.3.2.1 (Teletrust RIPEMD-160)
	0x05, 0x00, // NULL
	0x04, 0x14, // OCTET STRING 20 bytes (hash follows)
}

const defaultPort = 8030

func main() {
	port := flag.Int("port", defaultPort, "HTTP listen port")
	dir := flag.String("dir", defaultCacheDir(), "cache directory (also the file-share root)")
	interval := flag.Duration("sign-interval", 15*time.Second, "how often to scan for unsigned archives")
	flag.Parse()

	if err := os.MkdirAll(*dir, 0755); err != nil {
		log.Fatalf("create cache dir: %v", err)
	}

	key, isNew, err := ensureKey(*dir)
	if err != nil {
		log.Fatalf("key setup: %v", err)
	}
	if isNew {
		printSetupInstructions(*dir, *port)
	}

	c := &cache{dir: *dir, key: key}
	go c.signLoop(*interval)

	mux := http.NewServeMux()
	mux.HandleFunc("/pubkey.pem", c.servePubkey)
	mux.HandleFunc("/status", c.serveStatus)
	mux.HandleFunc("/", c.serveFile)

	addr := fmt.Sprintf(":%d", *port)
	log.Printf("macports-cache: serving %s on http://0.0.0.0%s", *dir, addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}

// cache holds server state.
type cache struct {
	dir string
	key *rsa.PrivateKey
	mu  sync.Mutex // guards signing operations
}

// serveFile serves archives and their .rmd160 signatures.
// For .rmd160 requests where the signature doesn't exist yet but the archive
// does, the signature is generated on-demand before serving.
func (c *cache) serveFile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	urlPath := filepath.Clean(r.URL.Path)
	if strings.Contains(urlPath, "..") {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}

	target := filepath.Join(c.dir, urlPath)

	// Sign on-demand: if the .rmd160 is missing but the archive exists, sign it now.
	if strings.HasSuffix(target, ".tbz2.rmd160") {
		if _, err := os.Stat(target); os.IsNotExist(err) {
			archivePath := strings.TrimSuffix(target, ".rmd160")
			if _, err := os.Stat(archivePath); err == nil {
				c.mu.Lock()
				if err := c.sign(archivePath, target); err != nil {
					log.Printf("on-demand sign %s: %v", filepath.Base(archivePath), err)
				}
				c.mu.Unlock()
			}
		}
	}

	http.ServeFile(w, r, target)
}

func (c *cache) servePubkey(w http.ResponseWriter, r *http.Request) {
	http.ServeFile(w, r, filepath.Join(c.dir, "pubkey.pem"))
}

func (c *cache) serveStatus(w http.ResponseWriter, r *http.Request) {
	n, size := c.archiveStats()
	fmt.Fprintf(w, "macports-cache\narchives: %d\nsize_bytes: %d\ncache_dir: %s\n", n, size, c.dir)
}

// signLoop periodically signs any unsigned archives dropped into the cache dir.
func (c *cache) signLoop(interval time.Duration) {
	for {
		time.Sleep(interval)
		c.signAll()
	}
}

func (c *cache) signAll() {
	c.mu.Lock()
	defer c.mu.Unlock()

	_ = filepath.Walk(c.dir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() || !strings.HasSuffix(path, ".tbz2") {
			return err
		}
		sigPath := path + ".rmd160"
		if _, err := os.Stat(sigPath); err == nil {
			return nil // already signed
		}
		if err := c.sign(path, sigPath); err != nil {
			log.Printf("sign %s: %v", filepath.Base(path), err)
		} else {
			log.Printf("signed %s", filepath.Base(path))
		}
		return nil
	})
}

// sign creates an RSA/RIPEMD-160 signature for archivePath, writing it to sigPath.
// The format is compatible with MacPorts archive verification:
//
//	openssl dgst -ripemd160 -sign privkey.pem -out archive.tbz2.rmd160 archive.tbz2
//	openssl dgst -ripemd160 -verify pubkey.pem -signature archive.tbz2.rmd160 archive.tbz2
func (c *cache) sign(archivePath, sigPath string) error {
	f, err := os.Open(archivePath)
	if err != nil {
		return err
	}
	defer f.Close()

	h := ripemd160.New()
	if _, err := io.Copy(h, f); err != nil {
		return err
	}

	// Build DigestInfo with Teletrust OID (1.3.36.3.2.1) and sign raw (hash=0).
	em := append(append([]byte(nil), rmd160DigestInfo...), h.Sum(nil)...)
	sig, err := rsa.SignPKCS1v15(rand.Reader, c.key, 0, em)
	if err != nil {
		return err
	}
	return os.WriteFile(sigPath, sig, 0644)
}

func (c *cache) archiveStats() (int, int64) {
	var n int
	var totalSize int64
	_ = filepath.Walk(c.dir, func(path string, info os.FileInfo, err error) error {
		if err == nil && !info.IsDir() && strings.HasSuffix(path, ".tbz2") {
			n++
			totalSize += info.Size()
		}
		return nil
	})
	return n, totalSize
}

// ensureKey loads the RSA private key from dir, generating a new 2048-bit
// keypair if one doesn't exist yet. Returns (key, wasCreated, error).
func ensureKey(dir string) (*rsa.PrivateKey, bool, error) {
	privPath := filepath.Join(dir, ".privkey.pem")
	pubPath := filepath.Join(dir, "pubkey.pem")

	if data, err := os.ReadFile(privPath); err == nil {
		if block, _ := pem.Decode(data); block != nil {
			if key, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
				return key, false, nil
			}
		}
	}

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, false, fmt.Errorf("generate key: %w", err)
	}

	privPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(key),
	})
	if err := os.WriteFile(privPath, privPEM, 0600); err != nil {
		return nil, false, fmt.Errorf("write private key: %w", err)
	}

	pubDER, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	if err != nil {
		return nil, false, fmt.Errorf("marshal public key: %w", err)
	}
	pubPEM := pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubDER})
	if err := os.WriteFile(pubPath, pubPEM, 0644); err != nil {
		return nil, false, fmt.Errorf("write public key: %w", err)
	}

	return key, true, nil
}

func defaultCacheDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Library", "Caches", "macports-cache")
}

func printSetupInstructions(dir string, port int) {
	log.Printf("Generated new RSA signing key pair in %s", dir)
	log.Printf("")
	log.Printf("=== CLIENT SETUP (run on each MacPorts machine) ===")
	log.Printf("")
	log.Printf("1. Download the public key:")
	log.Printf("   curl -o /opt/local/share/macports/macports-cache-pubkey.pem http://HOSTNAME:%d/pubkey.pem", port)
	log.Printf("")
	log.Printf("2. Add to /opt/local/etc/macports/pubkeys.conf:")
	log.Printf("   /opt/local/share/macports/macports-cache-pubkey.pem")
	log.Printf("")
	log.Printf("3. Add to /opt/local/etc/macports/archive_sites.conf:")
	log.Printf("   name    local_cache")
	log.Printf("   urls    http://HOSTNAME:%d/", port)
	log.Printf("")
	log.Printf("Then: sudo port -b install <portname>")
	log.Printf("")
	log.Printf("=== BUILD MACHINE SETUP ===")
	log.Printf("")
	log.Printf("Mount the cache directory (%s) via AFP/SMB, then:", dir)
	log.Printf("   ./scripts/submit-archive.sh <portname> /Volumes/macports-cache")
}
