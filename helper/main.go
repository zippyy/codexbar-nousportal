package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	listenAddr       = "127.0.0.1:38417"
	defaultPortalURL = "https://portal.nousresearch.com"
)

var version = "dev"

var requestMu sync.Mutex

type credential struct {
	AccessToken   string
	PortalBaseURL string
	ExpiresAt     time.Time
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", handleHealth)
	mux.HandleFunc("/v1/account", handleAccount)

	server := &http.Server{
		Addr:              listenAddr,
		Handler:           localOnly(mux),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      25 * time.Second,
		IdleTimeout:       30 * time.Second,
	}

	log.Printf("CodexBar Nous Portal helper %s listening on http://%s", version, listenAddr)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}

func localOnly(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host, _, err := net.SplitHostPort(r.RemoteAddr)
		if err != nil {
			http.Error(w, "invalid remote address", http.StatusForbidden)
			return
		}
		ip := net.ParseIP(host)
		if ip == nil || !ip.IsLoopback() {
			http.Error(w, "loopback only", http.StatusForbidden)
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		next.ServeHTTP(w, r)
	})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":      true,
		"version": version,
	})
}

func handleAccount(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	requestMu.Lock()
	defer requestMu.Unlock()

	ctx, cancel := context.WithTimeout(r.Context(), 22*time.Second)
	defer cancel()

	cred, err := loadBestCredential()
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"error": err.Error()})
		return
	}

	if !cred.ExpiresAt.IsZero() && time.Until(cred.ExpiresAt) <= 2*time.Minute {
		_ = runHermesStatus(ctx)
		if refreshed, refreshErr := loadBestCredential(); refreshErr == nil {
			cred = refreshed
		}
	}

	status, body, headers, err := fetchAccount(ctx, cred)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]any{"error": err.Error()})
		return
	}

	if status == http.StatusUnauthorized || status == http.StatusForbidden {
		if refreshErr := runHermesStatus(ctx); refreshErr == nil {
			if refreshed, loadErr := loadBestCredential(); loadErr == nil {
				cred = refreshed
				status, body, headers, err = fetchAccount(ctx, cred)
			}
		}
	}

	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]any{"error": err.Error()})
		return
	}

	if retryAfter := headers.Get("Retry-After"); retryAfter != "" {
		w.Header().Set("Retry-After", retryAfter)
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}

func fetchAccount(ctx context.Context, cred credential) (int, []byte, http.Header, error) {
	base := strings.TrimRight(strings.TrimSpace(cred.PortalBaseURL), "/")
	if base == "" {
		base = defaultPortalURL
	}
	if !strings.HasPrefix(base, "https://") {
		return 0, nil, nil, fmt.Errorf("refusing non-HTTPS Nous Portal URL: %s", base)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, base+"/api/oauth/account", nil)
	if err != nil {
		return 0, nil, nil, err
	}
	req.Header.Set("Authorization", "Bearer "+cred.AccessToken)
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "codexbar-nousportal-helper/"+version)

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return 0, nil, nil, fmt.Errorf("Nous Portal request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1024*1024+1))
	if err != nil {
		return 0, nil, nil, fmt.Errorf("reading Nous Portal response: %w", err)
	}
	if len(body) > 1024*1024 {
		return 0, nil, nil, errors.New("Nous Portal response exceeded 1 MiB")
	}
	if !json.Valid(body) {
		return 0, nil, nil, fmt.Errorf("Nous Portal returned non-JSON HTTP %d", resp.StatusCode)
	}
	return resp.StatusCode, body, resp.Header.Clone(), nil
}

func loadBestCredential() (credential, error) {
	path, err := authPath()
	if err != nil {
		return credential{}, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return credential{}, fmt.Errorf("cannot read Hermes auth at %s: %w", path, err)
	}

	var root map[string]any
	if err := json.Unmarshal(data, &root); err != nil {
		return credential{}, fmt.Errorf("invalid Hermes auth JSON: %w", err)
	}

	candidates := collectCandidates(root)
	if len(candidates) == 0 {
		return credential{}, errors.New("Hermes Nous OAuth access token not found; run `hermes model` to sign in")
	}

	sort.SliceStable(candidates, func(i, j int) bool {
		if candidates[i].ExpiresAt.Equal(candidates[j].ExpiresAt) {
			return i < j
		}
		return candidates[i].ExpiresAt.After(candidates[j].ExpiresAt)
	})
	best := candidates[0]
	if best.PortalBaseURL == "" {
		best.PortalBaseURL = defaultPortalURL
	}
	return best, nil
}

func authPath() (string, error) {
	if home := strings.TrimSpace(os.Getenv("HERMES_HOME")); home != "" {
		return filepath.Join(home, "auth.json"), nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home directory: %w", err)
	}
	return filepath.Join(home, ".hermes", "auth.json"), nil
}

func collectCandidates(root map[string]any) []credential {
	var out []credential
	if providers, ok := root["providers"].(map[string]any); ok {
		appendCredential(&out, providers["nous"])
	}

	if pool, ok := root["credential_pool"].(map[string]any); ok {
		collectCredentialValue(&out, pool["nous"])
	}
	return out
}

func collectCredentialValue(out *[]credential, value any) {
	switch v := value.(type) {
	case []any:
		for _, item := range v {
			collectCredentialValue(out, item)
		}
	case map[string]any:
		if _, hasToken := v["access_token"]; hasToken {
			appendCredential(out, v)
			return
		}
		for _, item := range v {
			collectCredentialValue(out, item)
		}
	}
}

func appendCredential(out *[]credential, value any) {
	m, ok := value.(map[string]any)
	if !ok {
		return
	}
	token := strings.TrimSpace(stringValue(m["access_token"]))
	if token == "" {
		return
	}
	portal := strings.TrimSpace(stringValue(m["portal_base_url"]))
	exp := expiryFromMap(m)
	if exp.IsZero() {
		exp = jwtExpiry(token)
	}
	*out = append(*out, credential{AccessToken: token, PortalBaseURL: portal, ExpiresAt: exp})
}

func expiryFromMap(m map[string]any) time.Time {
	for _, key := range []string{"expires_at", "expiry", "expires"} {
		if t := parseTimeValue(m[key]); !t.IsZero() {
			return t
		}
	}
	return time.Time{}
}

func parseTimeValue(v any) time.Time {
	switch x := v.(type) {
	case string:
		x = strings.TrimSpace(x)
		if x == "" {
			return time.Time{}
		}
		if t, err := time.Parse(time.RFC3339, x); err == nil {
			return t
		}
		if n, err := strconv.ParseFloat(x, 64); err == nil {
			return unixTime(n)
		}
	case float64:
		return unixTime(x)
	case json.Number:
		if n, err := x.Float64(); err == nil {
			return unixTime(n)
		}
	}
	return time.Time{}
}

func unixTime(n float64) time.Time {
	if n > 1e12 {
		return time.UnixMilli(int64(n))
	}
	if n > 0 {
		return time.Unix(int64(n), 0)
	}
	return time.Time{}
}

func jwtExpiry(token string) time.Time {
	parts := strings.Split(token, ".")
	if len(parts) < 2 {
		return time.Time{}
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return time.Time{}
	}
	var claims map[string]any
	if err := json.Unmarshal(payload, &claims); err != nil {
		return time.Time{}
	}
	return parseTimeValue(claims["exp"])
}

func stringValue(v any) string {
	if s, ok := v.(string); ok {
		return s
	}
	return ""
}

func runHermesStatus(ctx context.Context) error {
	bin, err := findHermes()
	if err != nil {
		return err
	}

	cmd := exec.CommandContext(ctx, bin, "status")
	cmd.Env = withCommonPath(os.Environ())
	output, err := cmd.CombinedOutput()
	if err != nil {
		text := strings.TrimSpace(string(output))
		if len(text) > 300 {
			text = text[:300] + "…"
		}
		if text != "" {
			return fmt.Errorf("hermes status failed: %s", text)
		}
		return fmt.Errorf("hermes status failed: %w", err)
	}
	return nil
}

func findHermes() (string, error) {
	if configured := strings.TrimSpace(os.Getenv("HERMES_BIN")); configured != "" {
		if info, err := os.Stat(configured); err == nil && !info.IsDir() {
			return configured, nil
		}
	}

	home, _ := os.UserHomeDir()
	for _, candidate := range []string{
		filepath.Join(home, ".local", "bin", "hermes"),
		"/opt/homebrew/bin/hermes",
		"/usr/local/bin/hermes",
		"/usr/bin/hermes",
	} {
		if info, err := os.Stat(candidate); err == nil && !info.IsDir() {
			return candidate, nil
		}
	}

	pathEnv := commonPath()
	if found, err := exec.LookPath("hermes"); err == nil {
		return found, nil
	}
	for _, dir := range strings.Split(pathEnv, ":") {
		candidate := filepath.Join(dir, "hermes")
		if info, err := os.Stat(candidate); err == nil && !info.IsDir() {
			return candidate, nil
		}
	}
	return "", errors.New("Hermes executable not found; install Hermes or set HERMES_BIN")
}

func commonPath() string {
	home, _ := os.UserHomeDir()
	parts := []string{
		filepath.Join(home, ".local", "bin"),
		"/opt/homebrew/bin",
		"/usr/local/bin",
		"/usr/bin",
		"/bin",
		"/usr/sbin",
		"/sbin",
	}
	if existing := strings.TrimSpace(os.Getenv("PATH")); existing != "" {
		parts = append(parts, existing)
	}
	return strings.Join(parts, ":")
}

func withCommonPath(env []string) []string {
	out := make([]string, 0, len(env)+1)
	for _, item := range env {
		if !strings.HasPrefix(item, "PATH=") {
			out = append(out, item)
		}
	}
	return append(out, "PATH="+commonPath())
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
