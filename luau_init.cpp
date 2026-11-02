// luau_init.cpp
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
