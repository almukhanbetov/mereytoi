// Package promotiontest builds fake App Store signing chains for tests.
// Nothing here is used by the server itself.
package promotiontest

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"time"
)

var (
	oidLeaf         = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 11, 1}
	oidIntermediate = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 2, 1}
)

// AppleChain is a root → intermediate → leaf chain shaped like Apple's.
type AppleChain struct {
	Roots *x509.CertPool
	leaf  *ecdsa.PrivateKey
	x5c   []string
}

// Options let a test break one property of the chain.
type Options struct {
	SkipLeafMarker bool
}

// NewAppleChain creates a fresh chain.
func NewAppleChain(opts Options) *AppleChain {
	rootKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	interKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	leafKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)

	now := time.Now()
	ca := func(serial int64, name string, ext []pkix.Extension) *x509.Certificate {
		return &x509.Certificate{
			SerialNumber:          big.NewInt(serial),
			Subject:               pkix.Name{CommonName: name},
			NotBefore:             now.Add(-time.Hour),
			NotAfter:              now.Add(24 * time.Hour),
			IsCA:                  true,
			BasicConstraintsValid: true,
			KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature,
			ExtraExtensions:       ext,
		}
	}
	rootTmpl := ca(1, "Test Root", nil)
	rootDER, _ := x509.CreateCertificate(rand.Reader, rootTmpl, rootTmpl, &rootKey.PublicKey, rootKey)
	root, _ := x509.ParseCertificate(rootDER)

	interTmpl := ca(2, "Test Intermediate", []pkix.Extension{{Id: oidIntermediate, Value: []byte{5, 0}}})
	interDER, _ := x509.CreateCertificate(rand.Reader, interTmpl, root, &interKey.PublicKey, rootKey)
	inter, _ := x509.ParseCertificate(interDER)

	var leafExt []pkix.Extension
	if !opts.SkipLeafMarker {
		leafExt = []pkix.Extension{{Id: oidLeaf, Value: []byte{5, 0}}}
	}
	leafTmpl := &x509.Certificate{
		SerialNumber:    big.NewInt(3),
		Subject:         pkix.Name{CommonName: "Test Leaf"},
		NotBefore:       now.Add(-time.Hour),
		NotAfter:        now.Add(24 * time.Hour),
		KeyUsage:        x509.KeyUsageDigitalSignature,
		ExtraExtensions: leafExt,
	}
	leafDER, _ := x509.CreateCertificate(rand.Reader, leafTmpl, inter, &leafKey.PublicKey, interKey)

	pool := x509.NewCertPool()
	pool.AddCert(root)
	return &AppleChain{
		Roots: pool,
		leaf:  leafKey,
		x5c: []string{
			base64.StdEncoding.EncodeToString(leafDER),
			base64.StdEncoding.EncodeToString(interDER),
			base64.StdEncoding.EncodeToString(rootDER),
		},
	}
}

// Sign returns payload as an ES256 JWS with the chain in x5c.
func (c *AppleChain) Sign(payload any) string {
	header, _ := json.Marshal(map[string]any{"alg": "ES256", "x5c": c.x5c})
	body, _ := json.Marshal(payload)
	signing := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(body)
	digest := sha256.Sum256([]byte(signing))
	r, s, _ := ecdsa.Sign(rand.Reader, c.leaf, digest[:])
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return signing + "." + base64.RawURLEncoding.EncodeToString(sig)
}
