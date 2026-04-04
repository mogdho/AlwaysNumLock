#Requires AutoHotkey v2.0

if !A_IsAdmin {
    Run('*RunAs "' A_ScriptFullPath '"')
    ExitApp()
}

; (Force State)
SetNumLockState "AlwaysOn"


SetTimer(EnsureNumLock, 5000) 

EnsureNumLock() {
    if !GetKeyState("NumLock", "T") {
        SetNumLockState "On"
    }
}
