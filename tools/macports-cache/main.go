// macports-cache: a local binary archive cache server for MacPorts.
//
// Serves pre-built .tbz2 archives over HTTP, signs them with an RSA/RIPEMD-160
// key and a signify (Ed25519) key (both formats MacPorts' archive verification
// accepts), and watches the cache directory for new archives added via file
// share.
//
// MacPorts URL pattern: {base_url}/{subport}/{archive}.tbz2
//
//	and {base_url}/{subport}/{archive}.tbz2.rmd160 or .tbz2.sig
//
// Both signatures are needed. Fetching accepts either, but before planning a
// port's build dependencies MacPorts checks archive_site_local for the
// signature type of the official mirrors, which is .sig (portutil.tcl,
// _eval_archive_available). Without a .sig the archive counts as unavailable.
//
// Quick start:
//
//	macports-cache -port 8030 -dir ~/macports-cache-data
//
// Then follow the printed client setup instructions.
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"flag"
	"fmt"
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
	port := flag.Int("port", defaultPort, "HTTP listen port (0 = sign only, for use behind a static file server)")
	dir := flag.String("dir", defaultCacheDir(), "cache directory (also the file-share root)")
	keyDir := flag.String("key-dir", "", "directory for the private keys (default: -dir); pubkey.pem and signify.pub always go in -dir")
	interval := flag.Duration("sign-interval", 15*time.Second, "how often to scan for unsigned archives")
	flag.Parse()

	if *keyDir == "" {
		*keyDir = *dir
	}
	for _, d := range []string{*dir, *keyDir} {
		if err := os.MkdirAll(d, 0755); err != nil {
			log.Fatalf("create %s: %v", d, err)
		}
	}

	key, isNew, err := ensureKey(*keyDir, *dir)
	if err != nil {
		log.Fatalf("key setup: %v", err)
	}
	if isNew {
		printSetupInstructions(*dir, *port)
	}
	sk, err := ensureSignifyKey(*keyDir, *dir)
	if err != nil {
		log.Fatalf("signify key setup: %v", err)
	}

	c := &cache{dir: *dir, key: key, signify: sk, settle: *interval}

	// Sign-only mode: another server (e.g. Caddy file_server) serves the dir.
	if *port == 0 {
		log.Printf("macports-cache: signing archives in %s every %s (no HTTP)", *dir, *interval)
		c.signAll()
		c.signLoop(*interval)
		return
	}
	go c.signLoop(*interval)

	mux := http.NewServeMux()
	mux.HandleFunc("/pubkey.pem", c.servePubkey)
	mux.HandleFunc("/"+signifyPubName, c.serveSignifyPubkey)
	mux.HandleFunc("/status", c.serveStatus)
	mux.HandleFunc("/", c.serveFile)

	addr := fmt.Sprintf(":%d", *port)
	log.Printf("macports-cache: serving %s on http://0.0.0.0%s", *dir, addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}

// cache holds server state.
type cache struct {
	dir     string
	key     *rsa.PrivateKey
	signify *signifyKey
	settle  time.Duration // skip archives modified more recently than this (still being copied)
	mu      sync.Mutex    // guards signing operations
}

// serveFile serves archives and their .rmd160 and .sig signatures.
// For signature requests where the signature doesn't exist yet but the archive
// does, the signatures are generated on-demand before serving.
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

	// Sign on-demand: if a signature is missing but the archive exists, sign it now.
	if strings.HasSuffix(target, ".tbz2.rmd160") || strings.HasSuffix(target, ".tbz2.sig") {
		if _, err := os.Stat(target); os.IsNotExist(err) {
			archivePath := strings.TrimSuffix(strings.TrimSuffix(target, ".rmd160"), ".sig")
			if _, err := os.Stat(archivePath); err == nil {
				c.mu.Lock()
				if err := c.sign(archivePath); err != nil {
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

func (c *cache) serveSignifyPubkey(w http.ResponseWriter, r *http.Request) {
	http.ServeFile(w, r, filepath.Join(c.dir, signifyPubName))
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
		// AppleDouble files an AFP client may leave behind are not archives.
		if strings.HasPrefix(info.Name(), "._") {
			return nil
		}
		// An archive still arriving over the file share keeps getting a newer
		// mtime; wait until it has been quiet for a full interval.
		if time.Since(info.ModTime()) < c.settle {
			return nil
		}
		if signedSince(path+".rmd160", info) && signedSince(path+".sig", info) {
			return nil // signed, and the archive hasn't been replaced since
		}
		if err := c.sign(path); err != nil {
			log.Printf("sign %s: %v", filepath.Base(path), err)
		} else {
			log.Printf("signed %s", filepath.Base(path))
		}
		return nil
	})
}

// signedSince reports whether sigPath exists and is no older than the archive.
func signedSince(sigPath string, archive os.FileInfo) bool {
	sig, err := os.Stat(sigPath)
	return err == nil && !sig.ModTime().Before(archive.ModTime())
}

// sign writes both signatures for archivePath, in formats MacPorts verifies:
//
//	openssl dgst -ripemd160 -verify pubkey.pem -signature archive.tbz2.rmd160 archive.tbz2
//	signify -V -p signify.pub -x archive.tbz2.sig -m archive.tbz2
//
// Ed25519 signs the whole message, not a digest, so the archive is read into
// memory (the largest are under 1 GB).
func (c *cache) sign(archivePath string) error {
	msg, err := os.ReadFile(archivePath)
	if err != nil {
		return err
	}

	h := ripemd160.New()
	h.Write(msg)
	// Build DigestInfo with Teletrust OID (1.3.36.3.2.1) and sign raw (hash=0).
	em := append(append([]byte(nil), rmd160DigestInfo...), h.Sum(nil)...)
	rsaSig, err := rsa.SignPKCS1v15(rand.Reader, c.key, 0, em)
	if err != nil {
		return err
	}
	if err := writeAtomic(archivePath+".rmd160", rsaSig); err != nil {
		return err
	}
	return writeAtomic(archivePath+".sig", c.signify.sign(msg))
}

// writeAtomic writes then renames, so a client never fetches a half-written file.
func writeAtomic(path string, data []byte) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// signifyPubName is the signify public key's name in the cache dir (and URL).
// MacPorts only uses keys ending in .pub for .sig files.
const signifyPubName = "signify.pub"

// signifyKey is an Ed25519 key in OpenBSD signify's format: a 2-byte
// algorithm tag "Ed" and an 8-byte random key number precede the key or
// signature bytes, base64-encoded under an "untrusted comment:" line.
type signifyKey struct {
	keynum [8]byte
	priv   ed25519.PrivateKey
}

func (k *signifyKey) sign(msg []byte) []byte {
	blob := append(append([]byte("Ed"), k.keynum[:]...), ed25519.Sign(k.priv, msg)...)
	return []byte("untrusted comment: verify with " + signifyPubName + "\n" +
		base64.StdEncoding.EncodeToString(blob) + "\n")
}

// ensureSignifyKey loads the signify key from keyDir, generating one if it
// doesn't exist yet, and (re)writes signify.pub into pubDir. The private
// file holds base64(keynum || Ed25519 seed); it is not signify's own
// (passphrase-protected) secret key format, since only this server reads it.
func ensureSignifyKey(keyDir, pubDir string) (*signifyKey, error) {
	privPath := filepath.Join(keyDir, ".signify.key")
	k := &signifyKey{}
	if data, err := os.ReadFile(privPath); err == nil {
		raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(data)))
		if err != nil || len(raw) != 8+ed25519.SeedSize {
			return nil, fmt.Errorf("%s: not a signify key written by this server", privPath)
		}
		copy(k.keynum[:], raw[:8])
		k.priv = ed25519.NewKeyFromSeed(raw[8:])
	} else if os.IsNotExist(err) {
		if _, err := rand.Read(k.keynum[:]); err != nil {
			return nil, err
		}
		_, priv, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			return nil, fmt.Errorf("generate signify key: %w", err)
		}
		k.priv = priv
		raw := append(append([]byte(nil), k.keynum[:]...), priv.Seed()...)
		if err := os.WriteFile(privPath, []byte(base64.StdEncoding.EncodeToString(raw)+"\n"), 0600); err != nil {
			return nil, fmt.Errorf("write signify key: %w", err)
		}
		log.Printf("Generated new signify key; public key at %s", filepath.Join(pubDir, signifyPubName))
	} else {
		return nil, err
	}

	pub := append(append([]byte("Ed"), k.keynum[:]...), k.priv.Public().(ed25519.PublicKey)...)
	pubFile := "untrusted comment: macports-cache signify public key\n" +
		base64.StdEncoding.EncodeToString(pub) + "\n"
	if err := os.WriteFile(filepath.Join(pubDir, signifyPubName), []byte(pubFile), 0644); err != nil {
		return nil, fmt.Errorf("write signify public key: %w", err)
	}
	return k, nil
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

// ensureKey loads the RSA private key from keyDir, generating a new 2048-bit
// keypair if one doesn't exist yet, and (re)writes pubkey.pem into pubDir so
// clients can fetch it. Returns (key, wasCreated, error).
func ensureKey(keyDir, pubDir string) (*rsa.PrivateKey, bool, error) {
	privPath := filepath.Join(keyDir, ".privkey.pem")

	var key *rsa.PrivateKey
	isNew := false
	if data, err := os.ReadFile(privPath); err == nil {
		if block, _ := pem.Decode(data); block != nil {
			key, _ = x509.ParsePKCS1PrivateKey(block.Bytes)
		}
	}
	if key == nil {
		var err error
		if key, err = rsa.GenerateKey(rand.Reader, 2048); err != nil {
			return nil, false, fmt.Errorf("generate key: %w", err)
		}
		privPEM := pem.EncodeToMemory(&pem.Block{
			Type:  "RSA PRIVATE KEY",
			Bytes: x509.MarshalPKCS1PrivateKey(key),
		})
		if err := os.WriteFile(privPath, privPEM, 0600); err != nil {
			return nil, false, fmt.Errorf("write private key: %w", err)
		}
		isNew = true
	}

	pubDER, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	if err != nil {
		return nil, false, fmt.Errorf("marshal public key: %w", err)
	}
	pubPEM := pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubDER})
	if err := os.WriteFile(filepath.Join(pubDir, "pubkey.pem"), pubPEM, 0644); err != nil {
		return nil, false, fmt.Errorf("write public key: %w", err)
	}

	return key, isNew, nil
}

func defaultCacheDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Library", "Caches", "macports-cache")
}

func printSetupInstructions(dir string, port int) {
	if port == 0 {
		log.Printf("Generated new RSA signing key pair; public key at %s", filepath.Join(dir, "pubkey.pem"))
		log.Printf("Configure clients with: sudo scripts/setup-client.sh http://<server>/")
		return
	}
	log.Printf("Generated new RSA signing key pair in %s", dir)
	log.Printf("")
	log.Printf("=== CLIENT SETUP (run on each MacPorts machine) ===")
	log.Printf("")
	log.Printf("1. Download the public keys:")
	log.Printf("   curl -o /opt/local/share/macports/macports-cache-pubkey.pem http://HOSTNAME:%d/pubkey.pem", port)
	log.Printf("   curl -o /opt/local/share/macports/macports-cache.pub http://HOSTNAME:%d/%s", port, signifyPubName)
	log.Printf("")
	log.Printf("2. Add both to /opt/local/etc/macports/pubkeys.conf:")
	log.Printf("   /opt/local/share/macports/macports-cache-pubkey.pem")
	log.Printf("   /opt/local/share/macports/macports-cache.pub")
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
