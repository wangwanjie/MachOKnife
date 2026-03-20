#include "CoreMachOC.h"

// Xcode links local Clang package targets as object files even when they only
// provide public headers. This anchor keeps the shim target linkable.
void CoreMachOCAnchor(void) {}
