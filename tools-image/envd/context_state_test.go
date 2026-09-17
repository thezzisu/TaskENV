package execcontext

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/e2b-dev/infra/packages/envd/internal/utils"
)

func TestTaskENVDefaultsSurviveRestartAndReplacement(t *testing.T) {
	path := filepath.Join(t.TempDir(), "context.json")
	t.Setenv("TASKENV_ENVD_STATE", path)
	dir := "/workspace/project"
	original := &Defaults{User: "ubuntu", Workdir: &dir, EnvVars: utils.NewMap[string, string]()}
	original.EnvVars.Store("DISPLAY", ":1")
	if err := original.SaveTaskENVState(); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatalf("private state: %v %v", info, err)
	}
	restored := &Defaults{User: "root", EnvVars: utils.NewMap[string, string]()}
	if err := restored.RestoreTaskENVState(); err != nil {
		t.Fatal(err)
	}
	display, _ := restored.EnvVars.Load("DISPLAY")
	if restored.User != "ubuntu" || *restored.Workdir != dir || display != ":1" {
		t.Fatal("process defaults were lost")
	}
	restored.EnvVars.Store("DISPLAY", ":2")
	if err := restored.SaveTaskENVState(); err != nil {
		t.Fatal(err)
	}
	if err := original.RestoreTaskENVState(); err != nil {
		t.Fatal(err)
	}
	display, _ = original.EnvVars.Load("DISPLAY")
	if display != ":2" {
		t.Fatal("updated defaults were not saved")
	}
}

func TestTaskENVRejectsCorruptDefaults(t *testing.T) {
	path := filepath.Join(t.TempDir(), "context.json")
	t.Setenv("TASKENV_ENVD_STATE", path)
	defaults := &Defaults{User: "root", EnvVars: utils.NewMap[string, string]()}
	if err := defaults.RestoreTaskENVState(); err != nil {
		t.Fatal(err)
	}
	for _, body := range []string{"broken", `{ "user": "" }`} {
		if err := os.WriteFile(path, []byte(body), 0600); err != nil {
			t.Fatal(err)
		}
		if defaults.RestoreTaskENVState() == nil {
			t.Fatal("corrupt state must not silently fall back to root")
		}
	}
}
