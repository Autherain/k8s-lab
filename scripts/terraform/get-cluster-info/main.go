// =============================================================================
// get-cluster-info - Retrieve K8s-Lab cluster info from Terraform state
// =============================================================================
//
// Uses tfexec (official HashiCorp library) to interact with Terraform.
//
// BUILD:
//   cd scripts/terraform/get-cluster-info && go build -o get-cluster-info .
//
// USAGE:
//   get-cluster-info                                    # Auto-detect terraform directory
//   get-cluster-info -t /path/to/terraform              # Specify terraform directory
//   get-cluster-info -c /path/to/creds.json             # Custom credentials file
//   get-cluster-info --json                             # JSON output
//   get-cluster-info --no-init                          # Skip terraform init
//
// =============================================================================

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/charmbracelet/lipgloss"
	"github.com/hashicorp/terraform-exec/tfexec"
	"github.com/spf13/cobra"
)

// =============================================================================
// Constants
// =============================================================================

const (
	// Style constants
	stylePaddingH = 2
	stylePaddingV = 1
	labelWidth    = 14

	// File permissions
	dirPermissions  = 0o700
	filePermissions = 0o600
)

// =============================================================================
// Lip Gloss Styles
// =============================================================================

var (
	// Colors
	cyan   = lipgloss.Color("86")
	green  = lipgloss.Color("42")
	yellow = lipgloss.Color("214")
	red    = lipgloss.Color("196")
	blue   = lipgloss.Color("39")

	// Log styles
	infoIcon    = lipgloss.NewStyle().Foreground(blue).Render("ℹ")
	successIcon = lipgloss.NewStyle().Foreground(green).Render("✓")
	warnIcon    = lipgloss.NewStyle().Foreground(yellow).Render("⚠")
	errorIcon   = lipgloss.NewStyle().Foreground(red).Render("✗")

	// Summary styles
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("15")).
			Background(lipgloss.Color("62")).
			Padding(0, stylePaddingH).
			MarginBottom(1)

	sectionStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(cyan).
			MarginTop(1)

	labelStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("245")).
			Width(labelWidth)

	valueStyle = lipgloss.NewStyle().
			Foreground(green).
			Bold(true)

	pathStyle = lipgloss.NewStyle().
			Foreground(yellow)

	cmdStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("252")).
			Background(lipgloss.Color("236")).
			Padding(0, 1)

	boxStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("62")).
			Padding(stylePaddingV, stylePaddingH).
			MarginTop(1)
)

// =============================================================================
// Types
// =============================================================================

// Credentials holds S3 credentials from the JSON file.
// JSON tags use snake_case to match the expected file format.
type Credentials struct {
	AccessKey string `json:"access_key"` //nolint:tagliatelle
	SecretKey string `json:"secret_key"` //nolint:tagliatelle
}

// ClusterInfo contains cluster information.
// JSON tags use snake_case for consistency with Terraform outputs.
type ClusterInfo struct {
	ControlPlane NodeInfo `json:"control_plane"` //nolint:tagliatelle
	Worker       NodeInfo `json:"worker"`
	SSHKeyPath   string   `json:"ssh_key_path"` //nolint:tagliatelle
}

// NodeInfo contains node IP addresses.
// JSON tags use snake_case for consistency with Terraform outputs.
type NodeInfo struct {
	PublicIP  string `json:"public_ip"`  //nolint:tagliatelle
	PrivateIP string `json:"private_ip"` //nolint:tagliatelle
}

// Config holds global configuration.
type Config struct {
	TerraformDir    string
	CredentialsFile string
	SSHKeyPath      string
	JSONOutput      bool
	NoInit          bool
	NoSaveKey       bool
	Quiet           bool
}

var config Config

// =============================================================================
// Cobra Commands
// =============================================================================

var rootCmd = &cobra.Command{
	Use:   "get-cluster-info",
	Short: "Retrieve K8s-Lab cluster information",
	Long: `Retrieve K8s-Lab cluster information from the Terraform state.

This tool uses tfexec to read the Terraform state stored in an S3 backend.
It displays public and private IPs of the nodes, and can save the SSH key.

Examples:
  # Basic usage (auto-detect terraform directory)
  get-cluster-info

  # Specify terraform directory
  get-cluster-info -t /path/to/terraform

  # Use a custom credentials file
  get-cluster-info -c /path/to/creds.json

  # JSON output for scripting
  get-cluster-info --json

  # Skip terraform init (if already initialized)
  get-cluster-info --no-init`,
	SilenceUsage:  true,
	SilenceErrors: true,
	RunE:          run,
}

func init() {
	// Flags
	rootCmd.Flags().StringVarP(&config.TerraformDir, "terraform-dir", "t", "",
		"Directory containing Terraform files (default: auto-detect)")

	rootCmd.Flags().StringVarP(&config.CredentialsFile, "credentials", "c", "",
		"Path to credentials JSON file (default: <terraform-dir>/backend.json)")

	rootCmd.Flags().StringVarP(&config.SSHKeyPath, "ssh-key", "k", "",
		"Path where to save the SSH key (default: ~/.ssh/k8s-lab.pem)")

	rootCmd.Flags().BoolVarP(&config.JSONOutput, "json", "j", false,
		"Output in JSON format")

	rootCmd.Flags().BoolVar(&config.NoInit, "no-init", false,
		"Skip Terraform initialization (useful if already initialized)")

	rootCmd.Flags().BoolVar(&config.NoSaveKey, "no-save-key", false,
		"Do not save SSH key to disk")

	rootCmd.Flags().BoolVarP(&config.Quiet, "quiet", "q", false,
		"Quiet mode (less output)")
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		logError("%v", err)
		os.Exit(1)
	}
}

// =============================================================================
// Main Logic
// =============================================================================

func run(_ *cobra.Command, _ []string) error {
	ctx := context.Background()

	tf, err := setupEnvironment(ctx)
	if err != nil {
		return err
	}

	return executeAndDisplay(ctx, tf)
}

func setupEnvironment(ctx context.Context) (*tfexec.Terraform, error) {
	if err := resolveDefaults(); err != nil {
		return nil, err
	}

	if err := checkPrerequisites(); err != nil {
		return nil, err
	}

	creds, err := loadCredentials()
	if err != nil {
		return nil, err
	}

	tf, err := setupTerraform(creds)
	if err != nil {
		return nil, err
	}

	if !config.NoInit {
		if err := initTerraform(ctx, tf); err != nil {
			return nil, err
		}
	}

	return tf, nil
}

func executeAndDisplay(ctx context.Context, tf *tfexec.Terraform) error {
	info, err := getClusterInfo(ctx, tf)
	if err != nil {
		return err
	}

	if !config.NoSaveKey {
		if err := saveSSHKey(ctx, tf); err != nil {
			logWarning("Failed to save SSH key: %v", err)
		}
	}

	if config.JSONOutput {
		printJSON(info)
	} else {
		printSummary(info)
	}

	return nil
}

func resolveDefaults() error {
	if config.TerraformDir == "" {
		projectRoot, err := findProjectRoot()
		if err != nil {
			return fmt.Errorf(
				"failed to find terraform directory: %w\n\nUse --terraform-dir to specify it manually",
				err,
			)
		}

		config.TerraformDir = filepath.Join(projectRoot, "terraform")
	}

	if _, err := os.Stat(config.TerraformDir); os.IsNotExist(err) {
		return fmt.Errorf("terraform directory not found: %s", config.TerraformDir)
	}

	if config.CredentialsFile == "" {
		config.CredentialsFile = filepath.Join(config.TerraformDir, "backend.json")
	}

	if config.SSHKeyPath == "" {
		config.SSHKeyPath = filepath.Join(os.Getenv("HOME"), ".ssh", "k8s-lab.pem")
	}

	return nil
}

func findProjectRoot() (string, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return "", err
	}

	dir := cwd
	for {
		if _, err := os.Stat(filepath.Join(dir, "terraform", "main.tf")); err == nil {
			return dir, nil
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}

		dir = parent
	}

	return "", fmt.Errorf("could not find terraform/main.tf from %s", cwd)
}

func checkPrerequisites() error {
	if _, err := exec.LookPath("terraform"); err != nil {
		return errors.New("terraform is not installed or not in PATH")
	}

	if _, err := os.Stat(config.CredentialsFile); os.IsNotExist(err) {
		return fmt.Errorf(
			"credentials file not found: %s\n\n"+
				"Create the file with your S3 credentials:\n"+
				"  cp %s/backend.json.example %s",
			config.CredentialsFile, config.TerraformDir, config.CredentialsFile,
		)
	}

	return nil
}

func loadCredentials() (*Credentials, error) {
	logInfo("Loading credentials from %s", pathStyle.Render(config.CredentialsFile))

	data, err := os.ReadFile(config.CredentialsFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read credentials file: %w", err)
	}

	var creds Credentials
	if err := json.Unmarshal(data, &creds); err != nil {
		return nil, fmt.Errorf("failed to parse JSON file: %w", err)
	}

	if creds.AccessKey == "" || creds.SecretKey == "" {
		return nil, fmt.Errorf("access_key or secret_key missing in %s", config.CredentialsFile)
	}

	logSuccess("Credentials loaded")

	return &creds, nil
}

func setupTerraform(creds *Credentials) (*tfexec.Terraform, error) {
	execPath, err := exec.LookPath("terraform")
	if err != nil {
		return nil, fmt.Errorf("terraform not found: %w", err)
	}

	tf, err := tfexec.NewTerraform(config.TerraformDir, execPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create Terraform instance: %w", err)
	}

	env := map[string]string{
		"AWS_ACCESS_KEY_ID":     creds.AccessKey,
		"AWS_SECRET_ACCESS_KEY": creds.SecretKey,
	}

	openStackVars := []string{
		"OS_AUTH_URL", "OS_TENANT_ID", "OS_TENANT_NAME",
		"OS_USERNAME", "OS_PASSWORD", "OS_REGION_NAME",
	}

	for _, v := range openStackVars {
		if val := os.Getenv(v); val != "" {
			env[v] = val
		}
	}

	if err := tf.SetEnv(env); err != nil {
		return nil, fmt.Errorf("failed to configure environment variables: %w", err)
	}

	return tf, nil
}

func initTerraform(ctx context.Context, tf *tfexec.Terraform) error {
	logInfo("Initializing Terraform...")

	err := tf.Init(ctx, tfexec.Upgrade(false))
	if err != nil {
		return fmt.Errorf("terraform init failed: %w", err)
	}

	logSuccess("Terraform initialized")

	return nil
}

func getClusterInfo(ctx context.Context, tf *tfexec.Terraform) (*ClusterInfo, error) {
	logInfo("Retrieving cluster information...")

	outputs, err := tf.Output(ctx)
	if err != nil {
		return nil, fmt.Errorf("terraform output failed: %w", err)
	}

	info := &ClusterInfo{
		SSHKeyPath: config.SSHKeyPath,
	}

	info.ControlPlane.PublicIP = extractStringOutput(outputs, "control_plane_public_ip")
	info.ControlPlane.PrivateIP = extractStringOutput(outputs, "control_plane_private_ip")
	info.Worker.PublicIP = extractStringOutput(outputs, "worker_public_ip")
	info.Worker.PrivateIP = extractStringOutput(outputs, "worker_private_ip")

	if info.ControlPlane.PublicIP == "" {
		return nil, errors.New("no data found - the cluster may not be deployed")
	}

	logSuccess("Information retrieved")

	return info, nil
}

func extractStringOutput(outputs map[string]tfexec.OutputMeta, key string) string {
	v, ok := outputs[key]
	if !ok {
		return ""
	}

	var result string
	if err := json.Unmarshal(v.Value, &result); err != nil {
		return ""
	}

	return result
}

func saveSSHKey(ctx context.Context, tf *tfexec.Terraform) error {
	outputs, err := tf.Output(ctx)
	if err != nil {
		return err
	}

	key := extractStringOutput(outputs, "ssh_private_key")
	if key == "" {
		logWarning("No SSH key found in outputs")

		return nil
	}

	sshDir := filepath.Dir(config.SSHKeyPath)
	if err := os.MkdirAll(sshDir, dirPermissions); err != nil {
		return fmt.Errorf("failed to create %s: %w", sshDir, err)
	}

	if err := os.WriteFile(config.SSHKeyPath, []byte(key), filePermissions); err != nil {
		return fmt.Errorf("failed to write SSH key: %w", err)
	}

	logSuccess("SSH key saved: %s", pathStyle.Render(config.SSHKeyPath))

	return nil
}

// =============================================================================
// Output
// =============================================================================

func printJSON(info *ClusterInfo) {
	data, _ := json.MarshalIndent(info, "", "  ")
	fmt.Println(string(data))
}

func printSummary(info *ClusterInfo) {
	fmt.Println()

	fmt.Println(titleStyle.Render("🚀 K8S-LAB CLUSTER"))

	cpSection := sectionStyle.Render("CONTROL-PLANE")
	cpPublic := labelStyle.Render("Public IP:") + " " + valueStyle.Render(info.ControlPlane.PublicIP)
	cpPrivate := labelStyle.Render("Private IP:") + " " + info.ControlPlane.PrivateIP

	workerSection := sectionStyle.Render("WORKER")
	workerPublic := labelStyle.Render("Public IP:") + " " + valueStyle.Render(info.Worker.PublicIP)
	workerPrivate := labelStyle.Render("Private IP:") + " " + info.Worker.PrivateIP

	sshSection := sectionStyle.Render("SSH CONNECTION")
	sshKey := labelStyle.Render("Key:") + " " + pathStyle.Render(info.SSHKeyPath)

	cpCmd := cmdStyle.Render(fmt.Sprintf("ssh -i %s ubuntu@%s", info.SSHKeyPath, info.ControlPlane.PublicIP))
	workerCmd := cmdStyle.Render(fmt.Sprintf("ssh -i %s ubuntu@%s", info.SSHKeyPath, info.Worker.PublicIP))

	content := fmt.Sprintf(`%s
  %s
  %s

%s
  %s
  %s

%s
  %s

  Control-plane:
  %s

  Worker:
  %s`,
		cpSection, cpPublic, cpPrivate,
		workerSection, workerPublic, workerPrivate,
		sshSection, sshKey,
		cpCmd, workerCmd,
	)

	fmt.Println(boxStyle.Render(content))
	fmt.Println()
}

// =============================================================================
// Logging
// =============================================================================

func logInfo(format string, args ...any) {
	if config.Quiet {
		return
	}

	fmt.Printf("%s %s\n", infoIcon, fmt.Sprintf(format, args...))
}

func logSuccess(format string, args ...any) {
	if config.Quiet {
		return
	}

	fmt.Printf("%s %s\n", successIcon, fmt.Sprintf(format, args...))
}

func logWarning(format string, args ...any) {
	fmt.Printf("%s %s\n", warnIcon, fmt.Sprintf(format, args...))
}

func logError(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "%s %s\n", errorIcon, fmt.Sprintf(format, args...))
}
