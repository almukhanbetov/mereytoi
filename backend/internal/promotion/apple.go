package promotion

import (
	"crypto/ecdsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"os"
	"strings"
	"time"
)

// Apple signs StoreKit 2 transactions and App Store Server Notifications V2
// as JWS (ES256) with the certificate chain in the x5c header. The chain
// must lead to Apple Root CA - G3 and carry Apple's marker extensions.
var (
	oidAppleLeaf         = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 11, 1}
	oidAppleIntermediate = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 2, 1}
)

// AppleVerifier checks signed data from the App Store.
type AppleVerifier struct {
	roots       *x509.CertPool
	BundleID    string
	Environment string // "Sandbox" or "Production"
	Now         func() time.Time
}

// NewAppleVerifier trusts exactly the given root certificates.
func NewAppleVerifier(roots *x509.CertPool, bundleID, environment string) *AppleVerifier {
	return &AppleVerifier{roots: roots, BundleID: bundleID, Environment: environment, Now: time.Now}
}

// LoadAppleVerifier reads the Apple Root CA - G3 certificate (DER or PEM).
func LoadAppleVerifier(rootFile, bundleID, environment string) (*AppleVerifier, error) {
	data, err := os.ReadFile(rootFile)
	if err != nil {
		return nil, err
	}
	if block, _ := pem.Decode(data); block != nil {
		data = block.Bytes
	}
	cert, err := x509.ParseCertificate(data)
	if err != nil {
		return nil, fmt.Errorf("apple root certificate: %w", err)
	}
	pool := x509.NewCertPool()
	pool.AddCert(cert)
	if environment != "Sandbox" && environment != "Production" {
		return nil, fmt.Errorf("APPLE_IAP_ENVIRONMENT must be Sandbox or Production")
	}
	return NewAppleVerifier(pool, bundleID, environment), nil
}

// AppleTransaction is the part of a JWSTransactionDecodedPayload we use.
type AppleTransaction struct {
	TransactionID         string `json:"transactionId"`
	OriginalTransactionID string `json:"originalTransactionId"`
	BundleID              string `json:"bundleId"`
	ProductID             string `json:"productId"`
	Type                  string `json:"type"`
	AppAccountToken       string `json:"appAccountToken"`
	Environment           string `json:"environment"`
	PurchaseDate          int64  `json:"purchaseDate"`
	RevocationDate        int64  `json:"revocationDate"`
	RevocationReason      *int   `json:"revocationReason"`
}

// AppleNotification is the part of a ResponseBodyV2DecodedPayload we use.
type AppleNotification struct {
	NotificationType string `json:"notificationType"`
	Subtype          string `json:"subtype"`
	NotificationUUID string `json:"notificationUUID"`
	Data             struct {
		BundleID              string `json:"bundleId"`
		Environment           string `json:"environment"`
		SignedTransactionInfo string `json:"signedTransactionInfo"`
	} `json:"data"`
}

// ErrAppleSignature means the data isn't signed by Apple.
var ErrAppleSignature = errors.New("apple signature invalid")

// VerifyTransaction checks a signed transaction and that it belongs to this
// app and environment.
func (v *AppleVerifier) VerifyTransaction(jws string) (AppleTransaction, error) {
	var tx AppleTransaction
	if err := v.verifyJWS(jws, &tx); err != nil {
		return tx, err
	}
	if tx.BundleID != v.BundleID {
		return tx, fmt.Errorf("apple transaction for another app")
	}
	if tx.Environment != v.Environment {
		return tx, fmt.Errorf("apple transaction from %s, expected %s", tx.Environment, v.Environment)
	}
	if tx.TransactionID == "" || tx.ProductID == "" {
		return tx, fmt.Errorf("apple transaction incomplete")
	}
	return tx, nil
}

// VerifyNotification checks a notification and the transaction inside it.
func (v *AppleVerifier) VerifyNotification(signedPayload string) (AppleNotification, AppleTransaction, error) {
	var n AppleNotification
	if err := v.verifyJWS(signedPayload, &n); err != nil {
		return n, AppleTransaction{}, err
	}
	if n.Data.BundleID != v.BundleID || n.Data.Environment != v.Environment {
		return n, AppleTransaction{}, fmt.Errorf("apple notification for another app or environment")
	}
	if n.Data.SignedTransactionInfo == "" {
		return n, AppleTransaction{}, nil
	}
	tx, err := v.VerifyTransaction(n.Data.SignedTransactionInfo)
	return n, tx, err
}

func (v *AppleVerifier) verifyJWS(jws string, out any) error {
	parts := strings.Split(jws, ".")
	if len(parts) != 3 {
		return ErrAppleSignature
	}
	headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return ErrAppleSignature
	}
	var header struct {
		Alg string   `json:"alg"`
		X5C []string `json:"x5c"`
	}
	if json.Unmarshal(headerJSON, &header) != nil || header.Alg != "ES256" || len(header.X5C) < 2 {
		return ErrAppleSignature
	}
	certs := make([]*x509.Certificate, len(header.X5C))
	for i, c := range header.X5C {
		der, err := base64.StdEncoding.DecodeString(c)
		if err != nil {
			return ErrAppleSignature
		}
		if certs[i], err = x509.ParseCertificate(der); err != nil {
			return ErrAppleSignature
		}
	}
	leaf, intermediate := certs[0], certs[1]
	if !hasExtension(leaf, oidAppleLeaf) || !hasExtension(intermediate, oidAppleIntermediate) {
		return ErrAppleSignature
	}
	inter := x509.NewCertPool()
	for _, c := range certs[1:] {
		inter.AddCert(c)
	}
	if _, err := leaf.Verify(x509.VerifyOptions{
		Roots:         v.roots,
		Intermediates: inter,
		CurrentTime:   v.Now(),
		KeyUsages:     []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
	}); err != nil {
		return ErrAppleSignature
	}
	pub, ok := leaf.PublicKey.(*ecdsa.PublicKey)
	if !ok {
		return ErrAppleSignature
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(sig) != 64 {
		return ErrAppleSignature
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	r, s := new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])
	if !ecdsa.Verify(pub, digest[:], r, s) {
		return ErrAppleSignature
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return ErrAppleSignature
	}
	if err := json.Unmarshal(payload, out); err != nil {
		return ErrAppleSignature
	}
	return nil
}

func hasExtension(c *x509.Certificate, oid asn1.ObjectIdentifier) bool {
	for _, e := range c.Extensions {
		if e.Id.Equal(oid) {
			return true
		}
	}
	return false
}
