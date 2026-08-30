//go:build !(linux && cgo) && !(darwin && cgo) && !windows

package plugins

import "errors"

func loadNativePlugin(manifest PluginManifest, data []byte) (NativePlugin, error) {
	return nil, errors.New("native plugins not supported on this platform (requires cgo on linux/darwin, or windows)")
}
