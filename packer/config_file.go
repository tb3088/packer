package packer

import (
	"os"
	"path/filepath"
)

// ConfigFile returns the default path to the configuration file (config).
// On Unix-like systems it is rooted in the HOME directory while on Windows
// the LOCALAPPDATA directory.
func ConfigFile() (string, error) {
	dir, err := homeDir()
	if err != nil {
		return "", err
	}

	return filepath.Join(dir, config_file), nil
}

// ConfigDir returns the configuration directory containing ConfigFile.
func ConfigDir() (string, error) {
	dir, err := homeDir()
	if err != nil {
		return "", err
	}

	return filepath.Join(dir, config_dir), nil
}

// ConfigTmpDir returns the configuration tmp directory for Packer
func ConfigTmpDir() (string, error) {
	if tmpdir := os.Getenv("PACKER_TMP_DIR"); tmpdir != "" {
		return filepath.Abs(tmpdir)
	}
	configdir, err := configDir()
	if err != nil {
		return "", err
	}
	td := filepath.Join(configdir, "tmp")
	_, err = os.Stat(td)
	if os.IsNotExist(err) {
		if err = os.MkdirAll(td, 0755); err != nil {
			return "", err
		}
	} else if err != nil {
		return "", err
	}
	return td, nil
}
