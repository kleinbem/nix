package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	INTERVAL       = 300 * time.Second
	WORKSPACE_ROOT = "/home/martin/Develop/github.com/kleinbem/nix"
)

var LOG_FILE = filepath.Join(WORKSPACE_ROOT, "scratch/guardian.log")

func logMsg(message string) {
	timestamp := time.Now().Format("2006-01-02 15:04:05")
	entry := fmt.Sprintf("[%s] %s\n", timestamp, message)
	fmt.Print(entry)

	f, err := os.OpenFile(LOG_FILE, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		fmt.Printf("Failed to open log file: %v\n", err)
		return
	}
	defer f.Close()
	f.WriteString(entry)
}

type ErrorEntry struct {
	Unit string `json:"unit"`
}

func runHealthCheck() {
	logMsg("Running scheduled health check...")

	aiLogsPath := filepath.Join(WORKSPACE_ROOT, "scripts/ai-logs.sh")
	cmd := exec.Command(aiLogsPath, "--json")
	var out bytes.Buffer
	cmd.Stdout = &out

	if err := cmd.Run(); err == nil {
		var errors []ErrorEntry
		if err := json.Unmarshal(out.Bytes(), &errors); err == nil {
			if len(errors) > 0 {
				logMsg(fmt.Sprintf("Detected %d system errors.", len(errors)))
				
				units := make(map[string]bool)
				for _, e := range errors {
					if e.Unit != "" {
						units[e.Unit] = true
					}
				}

				for unit := range units {
					if strings.HasPrefix(unit, "container@") {
						logMsg(fmt.Sprintf("Attempting restart of %s...", unit))
						restartCmd := exec.Command("sudo", "systemctl", "restart", unit)
						if err := restartCmd.Run(); err != nil {
							logMsg(fmt.Sprintf("Failed to restart %s: %v", unit, err))
						}
					}
				}
			} else {
				logMsg("System looks healthy. ✅")
			}
		} else {
			logMsg(fmt.Sprintf("Guardian parse error: %v", err))
		}
	} else {
		logMsg(fmt.Sprintf("Guardian cmd error: %v", err))
	}
}

func main() {
	os.MkdirAll(filepath.Dir(LOG_FILE), 0755)
	logMsg("Guardian started. Monitoring infrastructure...")

	for {
		runHealthCheck()
		time.Sleep(INTERVAL)
	}
}
