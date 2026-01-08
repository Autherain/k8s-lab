package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/hashicorp/terraform-exec/tfexec"
)

// =============================================================================
// extractStringOutput tests
// =============================================================================

func TestExtractStringOutput(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		outputs  map[string]tfexec.OutputMeta
		key      string
		expected string
	}{
		{
			name:     "empty outputs - returns empty string",
			outputs:  map[string]tfexec.OutputMeta{},
			key:      "some_key",
			expected: "",
		},
		{
			name: "key not found - returns empty string",
			outputs: map[string]tfexec.OutputMeta{
				"other_key": {Value: json.RawMessage(`"value"`)},
			},
			key:      "some_key",
			expected: "",
		},
		{
			name: "valid string value - returns value",
			outputs: map[string]tfexec.OutputMeta{
				"ip_address": {Value: json.RawMessage(`"192.168.1.1"`)},
			},
			key:      "ip_address",
			expected: "192.168.1.1",
		},
		{
			name: "invalid json - returns empty string",
			outputs: map[string]tfexec.OutputMeta{
				"bad_value": {Value: json.RawMessage(`not valid json`)},
			},
			key:      "bad_value",
			expected: "",
		},
		{
			name: "non-string json value - returns empty string",
			outputs: map[string]tfexec.OutputMeta{
				"number": {Value: json.RawMessage(`123`)},
			},
			key:      "number",
			expected: "",
		},
		{
			name: "null json value - returns empty string",
			outputs: map[string]tfexec.OutputMeta{
				"null_value": {Value: json.RawMessage(`null`)},
			},
			key:      "null_value",
			expected: "",
		},
		{
			name: "empty string value - returns empty string",
			outputs: map[string]tfexec.OutputMeta{
				"empty": {Value: json.RawMessage(`""`)},
			},
			key:      "empty",
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			result := extractStringOutput(tt.outputs, tt.key)
			if result != tt.expected {
				t.Errorf("extractStringOutput() = %q, want %q", result, tt.expected)
			}
		})
	}
}

// =============================================================================
// findProjectRoot tests
// =============================================================================

func TestFindProjectRoot(t *testing.T) {
	// Not parallel - modifies working directory

	tests := []struct {
		name        string
		setupFunc   func(t *testing.T) (tmpDir string, cleanup func())
		wantErr     bool
		errContains string
	}{
		{
			name: "finds project root from nested subdirectory",
			setupFunc: func(t *testing.T) (string, func()) {
				t.Helper()

				tmpDir := t.TempDir()
				tmpDir, _ = filepath.EvalSymlinks(tmpDir) // macOS /var -> /private/var

				terraformDir := filepath.Join(tmpDir, "terraform")
				subDir := filepath.Join(tmpDir, "some", "nested", "dir")

				must(t, os.MkdirAll(terraformDir, 0o755))
				must(t, os.MkdirAll(subDir, 0o755))
				must(t, os.WriteFile(filepath.Join(terraformDir, "main.tf"), []byte("# tf"), 0o644))

				originalWd, _ := os.Getwd()
				must(t, os.Chdir(subDir))

				return tmpDir, func() { _ = os.Chdir(originalWd) }
			},
			wantErr: false,
		},
		{
			name: "finds project root from terraform directory itself",
			setupFunc: func(t *testing.T) (string, func()) {
				t.Helper()

				tmpDir := t.TempDir()
				tmpDir, _ = filepath.EvalSymlinks(tmpDir)

				terraformDir := filepath.Join(tmpDir, "terraform")

				must(t, os.MkdirAll(terraformDir, 0o755))
				must(t, os.WriteFile(filepath.Join(terraformDir, "main.tf"), []byte("# tf"), 0o644))

				originalWd, _ := os.Getwd()
				must(t, os.Chdir(tmpDir))

				return tmpDir, func() { _ = os.Chdir(originalWd) }
			},
			wantErr: false,
		},
		{
			name: "no terraform directory - returns error",
			setupFunc: func(t *testing.T) (string, func()) {
				t.Helper()

				tmpDir := t.TempDir()
				tmpDir, _ = filepath.EvalSymlinks(tmpDir)

				originalWd, _ := os.Getwd()
				must(t, os.Chdir(tmpDir))

				return "", func() { _ = os.Chdir(originalWd) }
			},
			wantErr:     true,
			errContains: "could not find terraform/main.tf",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Not parallel - modifies working directory

			expectedDir, cleanup := tt.setupFunc(t)
			t.Cleanup(cleanup)

			got, err := findProjectRoot()

			if tt.wantErr {
				if err == nil {
					t.Error("findProjectRoot() expected error, got nil")
				}

				return
			}

			if err != nil {
				t.Errorf("findProjectRoot() unexpected error = %v", err)
			}

			if got != expectedDir {
				t.Errorf("findProjectRoot() = %q, want %q", got, expectedDir)
			}
		})
	}
}

// =============================================================================
// loadCredentials tests
// =============================================================================

func TestLoadCredentials(t *testing.T) {
	// Not parallel - modifies global config

	tests := []struct {
		name          string
		fileContent   string
		fileExists    bool
		wantAccessKey string
		wantSecretKey string
		wantErr       bool
		errContains   string
	}{
		{
			name:          "valid credentials - loads successfully",
			fileContent:   `{"access_key": "AKIATEST123", "secret_key": "secretABC456"}`,
			fileExists:    true,
			wantAccessKey: "AKIATEST123",
			wantSecretKey: "secretABC456",
			wantErr:       false,
		},
		{
			name:        "missing access_key - returns error",
			fileContent: `{"secret_key": "secret123"}`,
			fileExists:  true,
			wantErr:     true,
			errContains: "access_key or secret_key missing",
		},
		{
			name:        "missing secret_key - returns error",
			fileContent: `{"access_key": "AKIA123"}`,
			fileExists:  true,
			wantErr:     true,
			errContains: "access_key or secret_key missing",
		},
		{
			name:        "empty credentials - returns error",
			fileContent: `{"access_key": "", "secret_key": ""}`,
			fileExists:  true,
			wantErr:     true,
			errContains: "access_key or secret_key missing",
		},
		{
			name:        "invalid JSON - returns error",
			fileContent: `not valid json at all`,
			fileExists:  true,
			wantErr:     true,
			errContains: "failed to parse JSON",
		},
		{
			name:        "empty file - returns error",
			fileContent: ``,
			fileExists:  true,
			wantErr:     true,
			errContains: "failed to parse JSON",
		},
		{
			name:        "file does not exist - returns error",
			fileExists:  false,
			wantErr:     true,
			errContains: "failed to read credentials file",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup
			tmpDir := t.TempDir()
			credsFile := filepath.Join(tmpDir, "creds.json")

			if tt.fileExists {
				must(t, os.WriteFile(credsFile, []byte(tt.fileContent), 0o600))
			}

			oldConfig := config
			config = Config{
				CredentialsFile: credsFile,
				Quiet:           true,
			}

			t.Cleanup(func() { config = oldConfig })

			// Execute
			creds, err := loadCredentials()

			// Assert
			if tt.wantErr {
				if err == nil {
					t.Error("loadCredentials() expected error, got nil")
				}

				return
			}

			if err != nil {
				t.Errorf("loadCredentials() unexpected error = %v", err)

				return
			}

			if creds.AccessKey != tt.wantAccessKey {
				t.Errorf("AccessKey = %q, want %q", creds.AccessKey, tt.wantAccessKey)
			}

			if creds.SecretKey != tt.wantSecretKey {
				t.Errorf("SecretKey = %q, want %q", creds.SecretKey, tt.wantSecretKey)
			}
		})
	}
}

// =============================================================================
// resolveDefaults tests
// =============================================================================

func TestResolveDefaults(t *testing.T) {
	// Not parallel - modifies global config

	homeDir := os.Getenv("HOME")

	tests := []struct {
		name                string
		inputConfig         Config
		setupFunc           func(t *testing.T) string // Returns terraform dir path
		wantSSHKeyPath      string
		wantCredentialsFile string
		wantErr             bool
		errContains         string
	}{
		{
			name: "sets default SSH key path when empty",
			inputConfig: Config{
				SSHKeyPath: "",
			},
			setupFunc: func(t *testing.T) string {
				t.Helper()
				tmpDir := t.TempDir()
				terraformDir := filepath.Join(tmpDir, "terraform")
				must(t, os.MkdirAll(terraformDir, 0o755))

				return terraformDir
			},
			wantSSHKeyPath: filepath.Join(homeDir, ".ssh", "k8s-lab.pem"),
			wantErr:        false,
		},
		{
			name: "preserves custom SSH key path",
			inputConfig: Config{
				SSHKeyPath: "/custom/path/my-key.pem",
			},
			setupFunc: func(t *testing.T) string {
				t.Helper()
				tmpDir := t.TempDir()
				terraformDir := filepath.Join(tmpDir, "terraform")
				must(t, os.MkdirAll(terraformDir, 0o755))

				return terraformDir
			},
			wantSSHKeyPath: "/custom/path/my-key.pem",
			wantErr:        false,
		},
		{
			name: "sets default credentials path when empty",
			inputConfig: Config{
				CredentialsFile: "",
			},
			setupFunc: func(t *testing.T) string {
				t.Helper()
				tmpDir := t.TempDir()
				terraformDir := filepath.Join(tmpDir, "terraform")
				must(t, os.MkdirAll(terraformDir, 0o755))

				return terraformDir
			},
			wantErr: false,
		},
		{
			name: "preserves custom credentials path",
			inputConfig: Config{
				CredentialsFile: "/custom/creds.json",
			},
			setupFunc: func(t *testing.T) string {
				t.Helper()
				tmpDir := t.TempDir()
				terraformDir := filepath.Join(tmpDir, "terraform")
				must(t, os.MkdirAll(terraformDir, 0o755))

				return terraformDir
			},
			wantCredentialsFile: "/custom/creds.json",
			wantErr:             false,
		},
		{
			name:        "non-existent terraform dir - returns error",
			inputConfig: Config{},
			setupFunc: func(_ *testing.T) string {
				return "/nonexistent/terraform/directory"
			},
			wantErr:     true,
			errContains: "terraform directory not found",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			terraformDir := tt.setupFunc(t)

			oldConfig := config
			config = tt.inputConfig
			config.TerraformDir = terraformDir

			t.Cleanup(func() { config = oldConfig })

			// Execute
			err := resolveDefaults()

			// Assert
			if tt.wantErr {
				if err == nil {
					t.Error("resolveDefaults() expected error, got nil")
				}

				return
			}

			if err != nil {
				t.Errorf("resolveDefaults() unexpected error = %v", err)

				return
			}

			if tt.wantSSHKeyPath != "" && config.SSHKeyPath != tt.wantSSHKeyPath {
				t.Errorf("SSHKeyPath = %q, want %q", config.SSHKeyPath, tt.wantSSHKeyPath)
			}

			if tt.wantCredentialsFile != "" && config.CredentialsFile != tt.wantCredentialsFile {
				t.Errorf("CredentialsFile = %q, want %q", config.CredentialsFile, tt.wantCredentialsFile)
			}

			// Check default credentials path is set correctly
			if tt.inputConfig.CredentialsFile == "" && tt.wantCredentialsFile == "" {
				expectedCredsPath := filepath.Join(terraformDir, "backend.json")
				if config.CredentialsFile != expectedCredsPath {
					t.Errorf("CredentialsFile = %q, want %q", config.CredentialsFile, expectedCredsPath)
				}
			}
		})
	}
}

// =============================================================================
// ClusterInfo JSON marshaling tests
// =============================================================================

func TestClusterInfoJSON(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name           string
		input          ClusterInfo
		wantFields     []string // Expected field names in JSON
		wantPublicIP   string
		wantPrivateIP  string
		wantSSHKeyPath string
	}{
		{
			name: "marshals with snake_case field names",
			input: ClusterInfo{
				ControlPlane: NodeInfo{
					PublicIP:  "1.2.3.4",
					PrivateIP: "10.0.0.1",
				},
				Worker: NodeInfo{
					PublicIP:  "5.6.7.8",
					PrivateIP: "10.0.0.2",
				},
				SSHKeyPath: "/home/user/.ssh/key.pem",
			},
			wantFields:     []string{"control_plane", "worker", "ssh_key_path"},
			wantPublicIP:   "1.2.3.4",
			wantPrivateIP:  "10.0.0.1",
			wantSSHKeyPath: "/home/user/.ssh/key.pem",
		},
		{
			name: "handles empty values",
			input: ClusterInfo{
				ControlPlane: NodeInfo{},
				Worker:       NodeInfo{},
				SSHKeyPath:   "",
			},
			wantFields:     []string{"control_plane", "worker", "ssh_key_path"},
			wantPublicIP:   "",
			wantPrivateIP:  "",
			wantSSHKeyPath: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			data, err := json.Marshal(tt.input)
			if err != nil {
				t.Fatalf("json.Marshal() error = %v", err)
			}

			var result map[string]any
			if err := json.Unmarshal(data, &result); err != nil {
				t.Fatalf("json.Unmarshal() error = %v", err)
			}

			// Check expected field names
			for _, field := range tt.wantFields {
				if _, ok := result[field]; !ok {
					t.Errorf("expected field %q in JSON output", field)
				}
			}

			// Check nested fields
			if cp, ok := result["control_plane"].(map[string]any); ok {
				if _, ok := cp["public_ip"]; !ok {
					t.Error("expected 'public_ip' field in control_plane")
				}

				if _, ok := cp["private_ip"]; !ok {
					t.Error("expected 'private_ip' field in control_plane")
				}
			}
		})
	}
}

// =============================================================================
// Credentials JSON tests
// =============================================================================

func TestCredentialsJSON(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name          string
		jsonInput     string
		wantAccessKey string
		wantSecretKey string
		wantErr       bool
	}{
		{
			name:          "unmarshals valid credentials",
			jsonInput:     `{"access_key": "AKIA123", "secret_key": "secret456"}`,
			wantAccessKey: "AKIA123",
			wantSecretKey: "secret456",
			wantErr:       false,
		},
		{
			name:          "handles extra fields gracefully",
			jsonInput:     `{"access_key": "AKIA123", "secret_key": "secret456", "extra": "ignored"}`,
			wantAccessKey: "AKIA123",
			wantSecretKey: "secret456",
			wantErr:       false,
		},
		{
			name:          "handles missing fields as empty strings",
			jsonInput:     `{}`,
			wantAccessKey: "",
			wantSecretKey: "",
			wantErr:       false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			var creds Credentials

			err := json.Unmarshal([]byte(tt.jsonInput), &creds)

			if tt.wantErr {
				if err == nil {
					t.Error("expected error, got nil")
				}

				return
			}

			if err != nil {
				t.Errorf("unexpected error = %v", err)

				return
			}

			if creds.AccessKey != tt.wantAccessKey {
				t.Errorf("AccessKey = %q, want %q", creds.AccessKey, tt.wantAccessKey)
			}

			if creds.SecretKey != tt.wantSecretKey {
				t.Errorf("SecretKey = %q, want %q", creds.SecretKey, tt.wantSecretKey)
			}
		})
	}
}

// =============================================================================
// checkPrerequisites tests
// =============================================================================

func TestCheckPrerequisites(t *testing.T) {
	// Not parallel - modifies global config

	tests := []struct {
		name        string
		setupFunc   func(t *testing.T) string // Returns credentials file path
		wantErr     bool
		errContains string
	}{
		{
			name: "credentials file exists - no error",
			setupFunc: func(t *testing.T) string {
				t.Helper()
				tmpDir := t.TempDir()
				credsFile := filepath.Join(tmpDir, "backend.json")
				must(t, os.WriteFile(credsFile, []byte(`{}`), 0o600))

				return credsFile
			},
			wantErr: false,
		},
		{
			name: "credentials file missing - returns error",
			setupFunc: func(t *testing.T) string {
				t.Helper()

				return "/nonexistent/path/creds.json"
			},
			wantErr:     true,
			errContains: "credentials file not found",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			credsFile := tt.setupFunc(t)

			oldConfig := config
			config = Config{
				CredentialsFile: credsFile,
				TerraformDir:    "/some/dir",
			}

			t.Cleanup(func() { config = oldConfig })

			err := checkPrerequisites()

			if tt.wantErr {
				if err == nil {
					t.Error("checkPrerequisites() expected error, got nil")
				}

				return
			}

			if err != nil {
				t.Errorf("checkPrerequisites() unexpected error = %v", err)
			}
		})
	}
}

// =============================================================================
// Test helpers
// =============================================================================

func must(t *testing.T, err error) {
	t.Helper()

	if err != nil {
		t.Fatal(err)
	}
}
