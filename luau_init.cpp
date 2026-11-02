// luau_init.cpp
//
// Walks the MSVC CRT initializer lists in order: __xi_a..__xi_z (C
// initializers) then __xc_a..__xc_z (C++ static constructors). This is
// what mainCRTStartup does for a normal MSVC executable.
//
// NOT called at runtime in the Odin build: Odin links with mainCRTStartup,
// which already runs this sequence before main(). Calling
// luau_run_static_ctors() a second time re-runs non-idempotent C++
// initializers and crashes. Kept for hosts that supply their own entry
// point and do not get the CRT init walk for free.
extern "C" {
typedef void (__cdecl *_PVFV)(void);
typedef int  (__cdecl *_PIFV)(void);
int  __cdecl _initterm_e(_PIFV *pfbegin, _PIFV *pfend);
void __cdecl _initterm  (_PVFV *pfbegin, _PVFV *pfend);
extern _PIFV __xi_a[], __xi_z[];
extern _PVFV __xc_a[], __xc_z[];

int luau_run_static_ctors(void) {
    int rc = _initterm_e(__xi_a, __xi_z);
    if (rc != 0) return rc;
    _initterm(__xc_a, __xc_z);
    return 0;
}
}
