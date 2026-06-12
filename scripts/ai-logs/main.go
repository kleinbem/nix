package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type LogEntry struct {
	Timestamp string `json:"timestamp"`
	Unit      string `json:"unit"`
	Message   string `json:"message"`
	Priority  string `json:"priority"`
}

type SinkSummary struct {
	LastCheck   string   `json:"last_check"`
	ErrorCount  int      `json:"error_count"`
	Status      string   `json:"status"`
	RecentUnits []string `json:"recent_units"`
}

func getMachineStatus(machine string) bool {
	cmd := exec.Command("machinectl", "status", machine)
	err := cmd.Run()
	return err == nil
}

func getRecentErrors(lines int, unit, machine string) (interface{}, error) {
	if machine != "" && !getMachineStatus(machine) {
		return map[string]string{"offline": fmt.Sprintf("Machine '%s' is currently offline or not found.", machine)}, nil
	}

	args := []string{"-p", "3", "-n", strconv.Itoa(lines), "--output", "json"}
	if unit != "" {
		args = append(args, "-u", unit)
	}
	if machine != "" {
		args = append(args, "--machine", machine)
	}

	cmd := exec.Command("journalctl", args...)
	var out bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return map[string]string{"error": fmt.Sprintf("Failed to fetch logs: %s", stderr.String())}, nil
	}

	var logs []LogEntry
	linesArr := bytes.Split(out.Bytes(), []byte("\n"))
	for _, line := range linesArr {
		if len(line) == 0 {
			continue
		}
		var raw map[string]interface{}
		if err := json.Unmarshal(line, &raw); err != nil {
			continue
		}

		entry := LogEntry{}
		if tsStr, ok := raw["__REALTIME_TIMESTAMP"].(string); ok {
			if tsMicro, err := strconv.ParseInt(tsStr, 10, 64); err == nil {
				entry.Timestamp = time.Unix(0, tsMicro*1000).Format(time.RFC3339)
			}
		}

		if u, ok := raw["UNIT"].(string); ok {
			entry.Unit = u
		} else if su, ok := raw["_SYSTEMD_UNIT"].(string); ok {
			entry.Unit = su
		} else {
			entry.Unit = "unknown"
		}

		if m, ok := raw["MESSAGE"].(string); ok {
			entry.Message = m
		}
		if p, ok := raw["PRIORITY"].(string); ok {
			entry.Priority = p
		}

		logs = append(logs, entry)
	}

	return logs, nil
}

func main() {
	linesPtr := flag.Int("n", 30, "Number of log lines to fetch")
	flag.IntVar(linesPtr, "lines", 30, "Number of log lines to fetch")
	unitPtr := flag.String("u", "", "Specific systemd unit to filter by")
	flag.StringVar(unitPtr, "unit", "", "Specific systemd unit to filter by")
	machinePtr := flag.String("m", "", "Filter by NixOS container/machine name")
	flag.StringVar(machinePtr, "machine", "", "Filter by NixOS container/machine name")
	jsonPtr := flag.Bool("json", false, "Output in raw JSON format")
	sinkPtr := flag.Bool("sink", false, "Update the persistent health sink")

	flag.Parse()

	res, err := getRecentErrors(*linesPtr, *unitPtr, *machinePtr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	logs, isSlice := res.([]LogEntry)
	logsDict, isDict := res.(map[string]string)

	if *sinkPtr {
		ex, err := os.Executable()
		if err == nil {
			pwd, _ := os.Getwd()
			idx := strings.Index(pwd, "kleinbem/nix")
			var flakePath string
			if idx != -1 {
				flakePath = pwd[:idx+len("kleinbem/nix")]
			} else {
				flakePath = filepath.Dir(filepath.Dir(filepath.Dir(ex)))
			}
			sinkPath := filepath.Join(flakePath, "scratch/ai-health.json")
			os.MkdirAll(filepath.Dir(sinkPath), 0755)

			status := "Healthy"
			errCount := 0
			var recentUnits []string
			if isSlice {
				errCount = len(logs)
				if errCount > 0 {
					status = "Degraded"
				}
				unitMap := make(map[string]bool)
				for _, l := range logs {
					if l.Unit != "" {
						unitMap[l.Unit] = true
					}
				}
				for k := range unitMap {
					recentUnits = append(recentUnits, k)
				}
			} else {
				status = "Degraded"
			}

			summary := SinkSummary{
				LastCheck:   time.Now().Format(time.RFC3339),
				ErrorCount:  errCount,
				Status:      status,
				RecentUnits: recentUnits,
			}
			b, _ := json.MarshalIndent(summary, "", "  ")
			os.WriteFile(sinkPath, b, 0644)
		}
	}

	if *jsonPtr {
		if isSlice {
			b, _ := json.MarshalIndent(logs, "", "  ")
			fmt.Println(string(b))
		} else {
			b, _ := json.MarshalIndent(logsDict, "", "  ")
			fmt.Println(string(b))
		}
	} else {
		if isDict {
			if msg, ok := logsDict["offline"]; ok {
				fmt.Printf("INFO: %s (Services are on-demand) ✅\n", msg)
				os.Exit(0)
			}
			if msg, ok := logsDict["error"]; ok {
				fmt.Printf("FAILED: %s\n", msg)
				os.Exit(1)
			}
		}

		if isSlice && len(logs) == 0 {
			machineText := ""
			if *machinePtr != "" {
				machineText = " in " + *machinePtr
			}
			fmt.Printf("No recent errors found%s. System looks healthy. ✅\n", machineText)
			return
		}

		if isSlice {
			fmt.Printf("--- Semantic Log Summary (Last %d errors) ---\n", len(logs))
			for _, log := range logs {
				fmt.Printf("[%s] %s: %s\n", log.Timestamp, log.Unit, log.Message)
			}
		}
	}
}
