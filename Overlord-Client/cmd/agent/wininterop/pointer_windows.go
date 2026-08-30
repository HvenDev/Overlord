//go:build windows

package wininterop

import "unsafe"

// Literally just a wrapper for pointers so they're not fucked by the shit linter.

//go:nocheckptr
func Pointer(address uintptr) unsafe.Pointer {
	return *(*unsafe.Pointer)(unsafe.Pointer(&address))
}
