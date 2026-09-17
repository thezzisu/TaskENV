package execcontext

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

// TaskENV persists only process defaults, never the API access token. Its
// service keeps this root-only runtime file across daemon restarts. The normal
// orchestrator /init request still overrides it on every launch/resume/fork.
type taskenvState struct {
	User    string            `json:"user"`
	Workdir *string           `json:"workdir"`
	EnvVars map[string]string `json:"envVars"`
}

func (d *Defaults) RestoreTaskENVState() error {
	path := os.Getenv("TASKENV_ENVD_STATE")
	if path == "" {
		return nil
	}
	body, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	var state taskenvState
	if err := json.Unmarshal(body, &state); err != nil {
		return err
	}
	if state.User == "" {
		return fmt.Errorf("saved TaskENV user is empty")
	}
	d.User, d.Workdir = state.User, state.Workdir
	for key, value := range state.EnvVars {
		d.EnvVars.Store(key, value)
	}
	return nil
}

func (d *Defaults) SaveTaskENVState() error {
	path := os.Getenv("TASKENV_ENVD_STATE")
	if path == "" {
		return nil
	}
	values := make(map[string]string)
	d.EnvVars.Range(func(key, value string) bool { values[key] = value; return true })
	body, err := json.Marshal(taskenvState{User: d.User, Workdir: d.Workdir, EnvVars: values})
	if err != nil {
		return err
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".context-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	if _, err := file.Write(body); err != nil {
		file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(file.Name(), path)
}
