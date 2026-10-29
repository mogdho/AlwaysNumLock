#Requires AutoHotkey v2.0
;@Ahk2Exe-SetName AlwaysNumLock
;@Ahk2Exe-SetDescription AlwaysNumLock
;@Ahk2Exe-SetVersion 1.0.0
;@Ahk2Exe-SetCompanyName Mogdho Paul
;@Ahk2Exe-SetCopyright Mogdho Paul - MIT License
;@Ahk2Exe-SetMainIcon assets\icon.ico
;  (Lines starting with ;@Ahk2Exe are only read when building the .exe)


#SingleInstance Force

if !A_IsAdmin {
    try Run('*RunAs "' A_ScriptFullPath '"')  ; try: declining UAC no longer shows an error dialog
    ExitApp()
}

AppName      := "AlwaysNumLock"
SettingsFile := A_ScriptDir "\AlwaysNumLock.ini"   ; Remembers that we already asked about the sign-in screen
IsPaused     := false

; Registry value Windows reads to set Num Lock at the sign-in screen (bit 2 = Num Lock on)
SignInKey   := "HKEY_USERS\.DEFAULT\Control Panel\Keyboard"
SignInValue := "InitialKeyboardIndicators"

; (Force State)
SetNumLockState "AlwaysOn"

; Safety net (e.g. after sleep or the lock screen). Must re-apply "AlwaysOn":
; plain "On" would cancel AlwaysOn mode and let the NumLock key turn it off again.
SetTimer(EnsureNumLock, 5000)

SetupTray()
OfferSignInFix()

EnsureNumLock() {
    if !GetKeyState("NumLock", "T") {
        SetNumLockState "AlwaysOn"
    }
}

; ==============================================================================
; PAUSE  (e.g. for a game that uses the number pad as arrow keys)
; ==============================================================================
TogglePause(*) {
    global IsPaused := !IsPaused
    if IsPaused {
        SetTimer(EnsureNumLock, 0)
        SetNumLockState "On"          ; Still on, but the Num Lock key works normally again
    } else {
        SetNumLockState "AlwaysOn"
        SetTimer(EnsureNumLock, 5000)
    }
    UpdateTray()
}

; ==============================================================================
; NUM LOCK AT THE SIGN-IN SCREEN
; ==============================================================================
SignInNumLockOn() {
    try return (Integer(RegRead(SignInKey, SignInValue, "0")) & 2) ? true : false
    return false
}

SetSignInNumLock(on) {
    ; Change only the Num Lock bit, keep any other bits Windows stored there
    for key in [SignInKey, "HKEY_CURRENT_USER\Control Panel\Keyboard"] {
        try {
            v := Integer(RegRead(key, SignInValue, "0"))
        } catch {
            v := 0
        }
        v := on ? (v | 2) : (v & ~2)
        RegWrite(String(v), "REG_SZ", key, SignInValue)
    }
}

ToggleSignIn(*) {
    try {
        SetSignInNumLock(!SignInNumLockOn())
    } catch as e {
        MsgBox("Couldn't change the sign-in setting:`n`n" e.Message, AppName, 48)
    }
    UpdateTray()
}

; Ask once (on first run) whether to also turn Num Lock on at the sign-in screen
OfferSignInFix() {
    if SignInNumLockOn() || IniRead(SettingsFile, "Setup", "AskedSignIn", "0") = "1"
        return
    IniWrite("1", SettingsFile, "Setup", "AskedSignIn")
    answer := MsgBox("This script starts after you log in, so Num Lock can still be OFF "
        . "while you type your PIN or password.`n`n"
        . "Turn Num Lock on at the Windows sign-in screen too?`n`n"
        . "(You can change this later from the tray icon menu.)", AppName, "YesNo Iconi")
    if (answer = "Yes")
        ToggleSignIn()
}

; ==============================================================================
; TRAY MENU + START WITH WINDOWS  (same block in all three scripts)
; ==============================================================================
SetupTray() {
    tray := A_TrayMenu
    tray.Delete()
    tray.Add(AppName, (*) => 0)
    tray.Disable(AppName)
    tray.Add()
    tray.Add("Pause", TogglePause)
    tray.Add("Start with Windows", ToggleStartup)
    tray.Add("Num Lock on at sign-in screen", ToggleSignIn)
    tray.Add()
    tray.Add("Exit", (*) => ExitApp())
    tray.Default := "Pause"           ; Double-click the tray icon = pause / resume
    OnMessage(0x1A, OnThemeChange)    ; WM_SETTINGCHANGE: follow light/dark taskbar
    UpdateTray()
}

UpdateTray() {
    RefreshIcon()
    A_IconTip := AppName (IsPaused ? " (paused)" : "")
    if IsPaused
        A_TrayMenu.Check("Pause")
    else
        A_TrayMenu.Uncheck("Pause")
    if StartupEnabled()
        A_TrayMenu.Check("Start with Windows")
    else
        A_TrayMenu.Uncheck("Start with Windows")
    if SignInNumLockOn()
        A_TrayMenu.Check("Num Lock on at sign-in screen")
    else
        A_TrayMenu.Uncheck("Num Lock on at sign-in screen")
}

StartupTaskName() => AppName " (AutoHotkey)"

; True if a logon task exists AND points at this script's current location
StartupEnabled() {
    try {
        svc := ComObject("Schedule.Service")
        svc.Connect()
        task := svc.GetFolder("\").GetTask(StartupTaskName())
        return InStr(task.Definition.Actions.Item(1).Arguments, A_ScriptFullPath)
            || task.Definition.Actions.Item(1).Path = A_ScriptFullPath
    }
    return false
}

ToggleStartup(*) {
    try {
        svc := ComObject("Schedule.Service")
        svc.Connect()
        root := svc.GetFolder("\")
        if StartupEnabled() {
            root.DeleteTask(StartupTaskName(), 0)
        } else {
            ; Task Scheduler starts the script with admin rights at logon — no UAC pop-up
            user := EnvGet("USERDOMAIN") "\" A_UserName
            td := svc.NewTask(0)
            td.RegistrationInfo.Description := "Starts " AppName " when you log in."
            td.Principal.RunLevel := 1                   ; Run with highest privileges
            td.Principal.LogonType := 3                  ; Only when the user is logged on
            td.Settings.DisallowStartIfOnBatteries := false
            td.Settings.StopIfGoingOnBatteries := false
            td.Settings.ExecutionTimeLimit := "PT0S"     ; Never stop it
            td.Settings.MultipleInstances := 2           ; Don't start a second copy
            td.Settings.Priority := 4                    ; Normal priority (default is below normal)
            trigger := td.Triggers.Create(9)             ; At log on
            trigger.UserId := user
            action := td.Actions.Create(0)               ; Start a program
            if A_IsCompiled {
                action.Path := A_ScriptFullPath
            } else {
                action.Path := A_AhkPath
                action.Arguments := '"' A_ScriptFullPath '"'
            }
            action.WorkingDirectory := A_ScriptDir
            root.RegisterTaskDefinition(StartupTaskName(), td, 6, user, , 3)
        }
    } catch as e {
        MsgBox("Couldn't change the startup setting:`n`n" e.Message, AppName, 48)
    }
    UpdateTray()
}

; ==============================================================================
; TRAY ICON  (built into this file, so the script works on its own anywhere)
; White lines on a dark taskbar, black lines on a light one; faded when paused.
; ==============================================================================
RefreshIcon(*) {
    try TraySetIcon("HICON:*" TrayIcon(IsPaused, TaskbarIsDark()), , true)   ; true = keep our icon even while suspended
}

TaskbarIsDark() {
    try return !RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme")
    return true
}

; Windows broadcasts this when the theme (light/dark) changes
OnThemeChange(wParam, lParam, msg, hwnd) {
    SetTimer(RefreshIcon, -300)
}

TrayIcon(paused, dark) {
    static cache := Map()
    key := paused "|" dark
    if cache.Has(key)
        return cache[key]
    data := IconData(paused, dark)
    want := SysGet(49)                 ; Tray icon size for the current display scaling
    best := 0
    for size in data                   ; Sizes are sorted: take the first one big enough
        if (size >= want) {
            best := size
            break
        }
    if !best
        for size in data
            best := size
    b64 := data[best]
    DllCall("crypt32\CryptStringToBinary", "str", b64, "uint", 0, "uint", 1, "ptr", 0, "uint*", &n := 0, "ptr", 0, "ptr", 0)
    png := Buffer(n)
    DllCall("crypt32\CryptStringToBinary", "str", b64, "uint", 0, "uint", 1, "ptr", png, "uint*", &n, "ptr", 0, "ptr", 0)
    return cache[key] := DllCall("CreateIconFromResourceEx", "ptr", png, "uint", n, "int", 1, "uint", 0x30000, "int", want, "int", want, "uint", 0, "ptr")
}

; PNG images of the tray icon at several sizes, as text
; d / dp = dark taskbar (normal / paused), l / lp = light taskbar (normal / paused)
IconData(paused, dark) {
    static d := Map(16, "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAFzSURBVDhPpdPPi49RFAbwsbCYsFDTWLKysJ3SZPIPDPZExMJuUlLKRohMWWCDRCgWfjSFlYUsTGhGarJgWMywUOysZPE5Ot/O++2d13ehPHV7n9M597nPue+5Q0MtYB3uYnnAmomIkXb9X8AF/MAh7MEu7MZBLEXEre6eFcAzXGvF4y1+BnP94kHAE9wsfj0iAo8qnsbL7p4VwFPcKH4Sv3Ex44g4/y8C2ULPQcVrWnw6Iub7xYOAA/iGczhV39M4m5eIo909aW0VjuBeruy7AWbbcUTcr7rjEbG6OTVv9xce4g4u4wo+4g0+4you4TYe4GfWNALvU6RjLJ0dLhcnujlM4UsTvC1La/GpBmY99pVAtjeMD/iK0RqsxZ5A3iyOYUPTKDbmJBafSsFWbjP29wWwkA6Kb8W24nsbB3XQGLZXLkd9qRF4jHfYiYkUwI6ciRJ41c1FxIv8Q00Lm3LC6hF9r5X8NSbxvJurtrf0BP4XfwDEHjpKZ19CUQAAAABJRU5ErkJggg==",
        20, "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAHcSURBVDhPrZQ/SJZRFMbFBHH5QCEQ9+bGoMEpnVpsbdMh14aGBlNpCyEaGhQLsVGnz88+aesj/0T+g4jQ/ggpIjUIESQavxPPx3nfDpeLEfTA5b3nuec5997zPu/b0pIBcBvYBnaBnTAUvwXumVlrqssCGDYzA7aApcxY07qZjaXaLIBl4FPKRwCrf8spoRMAb0J8BXhkZtcCVwM+l6LzAKwAmz7vAL56C86Ai87XgY+pNoukYLtO4gWPgS7n/6ng6+TKl4A7wOXALQB7peg8AA3gi5ldSNcKABuyUMpnAfQDJ8A7L64WyHt6WYrlz1/AzVRbArgKPAZmgWn1y72m3kmsK/4I3E/giedPAn2xWG9I/Ka3CnwA3uvqwKlv8h04dF5fjPKUf+ragaLgnHYvLBHhtmm4QC2oZHIqwD7wqiBkgdL1MjBwIwieesFq4K5rhFhfV9NqCuT6pgWUFK5/17lnHtc9Hgo5g879sVpSsPlj8ORp52aTgvdDzniu4GJxZe/ZQzObAXrEae7imsed/mYnNXfdqpmtFwWfA0fNIANg3gu+TNcKuE/LHt5ywQu3h/yloXlR7NCf1UxO1ddG4g6jwIH/AOKQ16bMrBt4oJtkcsRNmFlbOPT/w2+5xinkFF187QAAAABJRU5ErkJggg==",
        24, "iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAJFSURBVEhLtZRLiM5hFMZnGB9ya5TLaFJYyGqMFLJyLXYWiow11mRhIZuxs6DQjCjFZhqlL5eNpCxsiJjcx4jcKcmlxszv0fl33ul4+76PGebUqfd93uec5/+e8/5PXV0VA1ZL6gKu1/DzwKY89o8maa2GYUBbnqOmAVc9cCswE5jhPj2sDV8H9AOPJNXneaoa8AD4nuOVDOiV9BkYn59VNaAH+CZpsu0ljQHaHT8ekwFPgY//JACsyWq+PXB7/4eAvagosC1wRy4ATLK9NVDSAeAOcERSKXBHVKJRb/KVVGtgDtDkPiusDd8A/AQeDveZtti1XcRKZd7v+4GE+f6r/Q95jt9M0jRgL3ASOAUc9a+KjX0NdFvNM/yF8y3O4vfb7WLyRuBuDKpkwAdgJ/AkP8sNeClpbiEA7HbwNLDUy1O4pMXmwA5gMCTYB7RGrvsS4JBzDieBTgdahq5VwYDHzvskaWx+nkzSbOddKgDgmAPLfG8D7QRQBpanQHu6znsPTHVsEXAOOAs0u8B855VzgSIZ0BFKYY2d6HjRdO/FFMduB+6FvxUohyAbxSlZFCj+cOBV4kq66di8mgLe1HvAG2CXY/VRwJ6145vtxfi4WOX5FuQCRUnyJkuaEPfA/SAwLvBKNs4Dr8l5FxNw0IE9Nk8kNYTgBne71RfnDQLrTaQCt2ST1nlnksBC4IeDNhXfAu+ipyJn/bHXFHkWZ7dL5yuTuImsAC4Dz4DnQJ+7rc1vpX4AW4Ab4Sxy+yRdAzYOJR9t+wWjzeRHKtEAzgAAAABJRU5ErkJggg==",
        32, "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAALQSURBVFhH7ZdbiE1hFMfHLZcm15Lc39A8yYMXyS3kTnlyKUy5FIZccnukZl7cYtxSM6LwoBRPRlIeJB5IKQ+ESEopl0b5La1p7TNrL/vsc7Zm8uJfX6e+/7r897fXt9Y+NTX/USWAMcBW4AhwOGcpv0tEJsYYfw1gNvBZCgD4CayJsQoDGAh8sKAtQD2wrsI67kSMizELQUTmWLC2yOUBuGh+9ZErBGC5BToduTwAe8xve+QKAVhqgc6H/b5AE/AQOCciQwJ/wPy2+v3CyBHQ1FlyHbgW+G4X8MxnBz6JSB/Hd7uA5iDgtoj0cHy3C9DrqdfyJXADGBX4LhOQ3ILmyClEpFfcU3TlLZiXHHHk8gCcMr+NkSsEYBjwxYI1AouBhTlrEbAPaDefCTFmYYjIDOB9Z8lVhooGVsVYFQEMB9YD++1JdG0DrgDfXYJX2h2Bs8BJ4Lnj2oFb+v5dDI23SUTGx5wliMi0ZPBUAvALOKF+wG7gW7TJAvBVRFbG3Jq8FnhrRteBBpv/Wesg8M5s2+xXj1y/B6KtXxfM9gcwOiVAZ76JvJciykBPyz2YBl0dbbIAtJr9hkisMKKqqSciI5JKN7/J0SYLrj/sTBEissyI2PG0IO8Al3wBicjYIGCq8xmqjQu4q/VRCpbukOkGlSUgORWX5KmI9DP7TAE6D/QGBL8GF7OQgBYfyPhJZl9OwGC/byjVVVEBm30U4KOIDDL7cgJ6A0+CX6OLWb0AHTTAUeAN8BiY7rhMAQqgDriv19pOsdZx2QLcLfhj6iXv3QMYGY56SoZN/4y9vZZnRyQWGHEzRZSB/vHQbphkB+ZHmywAx8x+SyR0BnS0U+AQMEuHUNYClgAPzPa1/b7QFhttnc9M64ZJjrqUABOxNnmiagA80paqX0SRy4PWQcxdghaTDhngas66rEUkIgPUR0R6WsNqzbD16wwwN+b8p/gNzAe52Yk5GIEAAAAASUVORK5CYII=",
        40, "iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAPOSURBVFhH7ZhbiFZlFIbVTClLBS1FxMlSqDRKosQj2EFDOqCXQXlhqdFFF6XiTVSYioKi5ZWQCEkHKxMC8aoiG1AIMkVRyCw6aJJpkYXms+T9WXtas/rds///H9GLeWHBzPeuwzt7f3t965tevXpwBQBMA54FngMWVbCFwCwz65dzdSuANjP7zJoEcACYmPN2C4ABwMFQ7Hfgp4p2MsW15fwtQ6/TCwhLzGyomV1f0QYDTwJnPccbOX/LAN7z5O2Zqwpgi+f4KnMtA9jhb+n9zEUA44Hr8roALHeB32SuZQDbPfmHmTOzPsAMYJf73J19BDNb5fzXmWsZZQKBEcAF4Lz73JV9hCsp8EYzuxdYdlUKLAAsvtoFLu0ReCkEgR9kroCZvSIfM7sncwKw8nIKrPVBYFvmCgATgOeBIZkTLncf3OzJD2WuKoCdnuPLzLUM4Al/fSqwHXgEmGJmU8tMPsCDwMYQvyTn7xYAW4sizUJPz8yuzbkbhpldAwxUE3Yb4FPJBjM7nYr+JQu//wP8mXzOAu+a2Sid1SHvwIYGWWCYxiHgCHACOB7sR+1B4I9U/DDwDDDazG7VdgD2ai5LAuX3Q8qpGt8BbwN3ZD2dAIwEvo3FqwI4A9wH3AR8n/kqKHJkXR1QCwnOm8xsATC/C3sV+M1jjqnH+c96zev8yeaYbGvCMLvPzPpmbRJ3M/C3O63IfBmAB4B//3sWtRyLsl8ZgHkh9v9PUYNmcJic+TJok2svhXjtvVuyXxl8ZKv9kcDjmZfDuFBgWuIeBj5WiwBe0xcded07dDkK8ZoNb4s+wIsevwt4KnKCf93nPP7RzGeB04t1n5aVeEc4jzemWN34fk4Cx4QcallbgbeKmyEwM+Voa1agkg8LfqeA/R2B1QT2Dr4z3efpjgStCIwA5jq/PK2XCnSf+3UWA7/q4pW/1JYF+l1YnFpRp85fUeBE4BNv1HtUL/HNCwRe9vX5cb1AFYEF/MIvny1xvWmB2n++fFqvVmcx8EKKLRWoIxBY7UfgavdZlnJ0KTD2wSlhfaz/0+egRAC/AB+lWB3+uc2MLngzGw4c9dNFx9mb+XLvx2wh8LHI1WBmt4cCszJfBv//S55w7qzjNwjon9cFHzIueOzszBfNtvaagE+1V7JPPehrBF6P4jzHO2Z2Q/avB69dTOwSWf8UAl4KBTQGtQNflNhujWUhZhuwNvyuL1ZNPsdFE38sxGzKujoBWF84NwLgcw20nkNPr2HoSpv3Zl0Ak3yM0hfblWlUmpNzmNlDmorq+NezlY3u+x5UxUX7L6+eCox2bgAAAABJRU5ErkJggg==",
        48, "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAR/SURBVGhD7ZlZrF5TFMerCFFTUVMMwUtFtTQIbxVEJPpAEYnQB0kjiJg9SJBKhBBDRTwIRRNTJEioBylRQ0TbqFy0lKghQpsUpYbit+R/ss7Nuuue7zvn3J6vceP+kp07rP+39l7fPnuvtfeZNGmCcQywr5nNAeYCZ7do0p8BHJJ9bhfMbCfgDmCjbQPAr8ATwLTcx8Aws8nAS3kw2wLwiWYz9zUQgCtT5y8Cd/mMtGlPAluCn8dyX51jZjsCH3uH4pKsaQNwErDZ/f0BHJQ1nWJmBwK/eYdD2T4WgKfDhM7J9k4BDgf+9ACWZXvGZ6zvAgXuDwGcnu2dYmaHaao9gDeyPQKcBXyoZmY7ZHsJ8GA5euC0bO+UJgH4Frs8DGrdeAtgN+A94GHgd+Cz8RbAZP+5q+9Un4+rAEp8x5oIoFP+VwEoq7ruq/9qAK9newQ4wMx+AlbXBLCoDGDgiQw4NATwTrZHvGrdv67KBB7angFMAb73AH7WjGRNGzzIojh0n8dkTeeY2eOhwyHgHGAWcGyLNlPfNrA0+PqgzCEDBTgC2FR23BUDX8ARMzsSeAv4Kw+kDb7Nrh3Isw/MMLMFwE3Ajaldbma3AWuAv9Og1gKLgSVm9hzwFPAI8H7U+uC/BR4ALgNuSH2o3yuAk/PY+qKFqucc+CcOrCl6vLSzJJ8a0DcacdY3AXhNsx59VuKl8LLsYCwAb5vZzmmbHDPAeuWWPOYR+KNRfkBn1PuA+cBFDdrFwN3poL40fus6uAOXVny2V7sF+CF8/tE85mGULYEVLlSn52dNE/ziasS6cJ83Z20TlBs858iHfk7NmoKUpNZnexuAT9PgdbDpP/19AF4NvmZme4GZ7QVscFHljYMf0mcAJ0if7SXAqhiA10T7VOj2BI4HZpvZ7tleot0s+Dou2wvcWfG8Kb1X2E/RTlJ6Ab4Dzs064Vl1GJ/6/ZJGNxxFXeUaLdIzo6YEeD7oZmV7QYMArlIFClyoxeW6jXr0KrS1AXgyvBc4T5uF63R+HlVOdBKAme0d/w7r5eD4f7fVBhAB9nDd1wMLIKI7H9cNKXdU2BsFoPoHuMeztBLd3KwRnQag+1DX/NIrzbcIYGHQqLI9MWtEZwGY2Z1u141b9XbWLoBddPXot3hb/EsZtd12EoAWr9v0bqDnEVE0CUD3RvFvv4KUdnb8v9s6CeBdt31hZit9ylfo2FihrQ0AuN6LNFW1L7huXY9drT6AlMg+ynbgGR+0OtGerbZG1ycV2tpEphxSvqICtgKvmNn0qClpmshiKfFltrfBDynDeCkxaqa8+p3WL6sL4OXgq3rteTFXfHM6C/Ta0urwrXHUSQ24LmubABwF/Og+Nve95QCuDR1qR7gduMCne16fJrt0t+pxCT7eDL/rS1nkmbzO3zxVwwraL8ZKH0vymEfgN8rFYu2AlX7VvjgbxoLXXvXvlVVvA89mB23QrlK+WvJTmc69W7OuKX66q1zgPVHJDFytx6JFu0ZvHrMvARytE1/FZ/o1naVPzb4mmKBD/gU2h00X2S9qLgAAAABJRU5ErkJggg==")
    static dp := Map(16, "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAFaSURBVDhPpZNZS0NBDIWLuyAiKPqgfVGLWPeqiEvdqCguxVrrQn0QH1ygCiL4878jaTMyvRYRPBDuZJIcksy5qVQESZ2SdoEbSZVg5gMHknri/B8AVoE7ICNpHEj7N+Mk+WRNE4BDYCPyR6JzDih+J7eCpIKkLTsDm8AnsO/+CnCSrGlCTCBpEagBa+b/icBGCAQGSR1RzAh+HwGYBKqSloGlxPcWmEnW1GEBYA/YkfQIfAAvwDHw5P6z55jNS2oLxbbdB1sWsG0zA+tAGSgBl/Yyfp83Akn3lhMILCmXaMrup/wVFlrEpoGr4BSBOVehqe4a6AYmgHcgK6kduLA9mBpdWOWYYBbo9blrkvpcgYGgy3fxCvT7shsEks6tAz8PAcNObB3Y8rLuDwZlutQrgaDge0hbsduYy/oNOG0Rs7uGqKxd4Mx/Intrs6onjQJHLWIlSQN1gv/iC5/2/JBmG9U7AAAAAElFTkSuQmCC",
        20, "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAHASURBVDhPrZTrS1VREMXtYVof+iAEJYRCmEEgFlHQNSXqFlwfZRZlZRqRQVTa/w+/Feu0zr3bw6640MBwzsyePc81e2KiQsBN4AWwU2NJy5JOde9VSdIN4AfwDHhS4c2c3+rerRKwLulVV18SsAG87OqrFOPNQr4EPABmC92jfwUdkjMEtvwv6SywCxwD+5KmY9MfJ8PS4RlfBH4C74Cp2Izl0CVvFPJF4DYwU+jGKnkAvPkbLIKAna6+Sm4+8Dk4tHNP/XkyH/hf0iFwrXt3SJlkD1jN9y3wzSzpQNJjYK/VAR8krcT+BALc+MvAF+BTJmr2RmwDr+0wQezQZ9b7vLX9CHwF5trsHiaLBhIlZcou27DZljRZsZmM40GjyDoNGwxckTRfXHBpxy67sLlqLmQHbaDWYKqFQAydvnd1KTr36ciBI18verkQ3Wi7Sod5GFyegdz7g0Nj0ufm5oHoOnTJDeqzaveANUkXcu4p2mE/8lSG1JN0Ljpv1yhDN7URKuShJZvfTa9QcDrs4WJ69jRRVzIIZ2FnBvmuwRw8nrCJ7rsf3TLCcsD8Po9Ay5bvA+eBO52zku9KOl0k/f/oF20vy9C01cW9AAAAAElFTkSuQmCC",
        24, "iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAI3SURBVEhLtZbrS1VREMXtnT0oLCMTovJDfZCIAqMoIXrQi0p7qIVZWVba8/+H34p1Wvty3N17jNKBwX1m7z1rz8yauQ4NDRBJxyXdAh4C9/voA+COpJP13Q0FOAF8BL4A7zp0LTpR++gU4C6wKukMMCxprxXYU9b59kM+AE9rH50CzAKLtb2f2DnwStKOem+gADMGkLTL35K2AReBeeBK2xnwDHj5XwBJxZqkFeBbO+ebBTCWYrrwXzcdwCLpAvACuCxpe+vsPwFseZFN04bfkvYVNWVD2/I9HprO1j46BRgBllLUxegSsCzpTctm58smQe1jnTjXwHnguqRrpmLqYAfv83cOuJGc9+ySnoe6vjcdOg+3ne+W9AT4mbSsRu3E48Av/ORCAmcD8Dl27xuo3PF9+5mXdKABACZj9OuPJj212nEDlLQ52iN9ztk2Bfww2wrA1XB7pBdWHwmzmkjc2fV+kRDB/XK7GJxvT83RfHugOZ9mUmOLvQAsOK22STpsR6nN/pw76Cg96gcBOKLvsc0VflcApcMfJ3qPj+bFGwLkR8aXHKapWpy1AXbGZma54C7uo78CSLHcnR4V55pDfwKUFJ1yF2fKjg0CcEoMsK7IdeunLwpAbxa11znnTjfTfhdZ0qXQdNKH2wzx2rZE9Tpcbzq34+xEajJdNg4Bb5NHN5PDXajUTefX30xjuT62t8+WtWvi/WMF3GGNAvc8jt36bc2Inin1AE6HPYPO+r+Q8Z7zrZZf0NpO9ZhGjS4AAAAASUVORK5CYII=",
        32, "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAL0SURBVFhH7ZbpS1VRFMVtjgwKosFsoshyyKAsS8uyEIwysmgus8HKZv9/+O1Yr3Uf5x7ufe/d0D61YfMee51hnT3evr7/0qNExC5gFJiIiIt1KhwYj4g9+Rl/LcAA8AZYA371oFr3ATiVn9VYImIb8Az4ClwHhoDTXXQyIj4CbyNid35mIwEOA9+B+RzrJBFxzZ4YyrFGAhy3W6/mWCcBzpnASI41kog4BvwEpjP7ZuASsOjX7khx4LwJDKf2xlJHwNn+w7HW780M31gCEfEA+KREc8a/kFcKfMMJKCf0cmDFSTqX4RtLwOU54xKdU6NK8XUj4CoQgcoqSN2eyrpVATBoV5dc3E2AKyZwJscaicoLeAV8duYfBY74N9fCPg68U3Kuy0yIiEMm8UWZ79ITISWfvCNdtV2Vseo2fDI/q6tExE65zUmkl0hHgBsRseyXvY+Ix66EKbt7UXbjKs057yvO0HnDHWcDcAB4mUy0VL/51XqdPKHan/S+MV8su3Ct0/CqOkeeOZHfXZTVE2+cNfvhGtVrnvqyefeC18CFirWpToucPdlfIuCZr5jeKQE1Ahz0xYq5XtzT7PdIlyfKU1JuaTL1/IWkjxTFXeHYl6+pkqQ/jOZA0XDylqsPjHsaNmkC6X9GYH+yR6Urdy8oP9qHlTtkuUFVEbBNidUqOQ2giNgirI5ARGxyBag0i1Jtv7YpAcVLSamyUpavFI2lA4HtiV37RKKdV40IRMRZv0DJJk88V7UYqyMgD9x32couT0wk9zQioMMuuzc8VEdMsEoCxvY6/to3ExFbC6yWgKtABKZKwB+sFffMpipY6lQF6cWFdKoCDRK563YJqBHlglty0f8H8zVVYo+uKbwlwDNgyQfKTQNyeY3qI+Wu8sIzQYn2SF6sWNtSNzrNgmXdoTCVCEjUzfwauUjJp0SqUnlKTUtx7gduOXzSfG2q2qOqGs/vbouSyRNu1s2npJ4T0rEixk7WoQLP9yR2fb73FKp/Jr8Bc979Zf8jiwIAAAAASUVORK5CYII=",
        40, "iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAPFSURBVFhH7Zj7b9RVEMWRagURKqBFBZHwDlCjBXlIeLUJiZC0lPIMbxVpfYCR//8z5DTnbu6O3939brem/NCTTLK7M3fuuffOnZm7mzZtYB0QEV9GxPFhBNgXEZuzrzVFRHwK3AReAX8Cfw0hS8Ad4Ivsd00QER8Ct01MBB8B91vKQ+Al8AfwWAvN/keGj0nkfgOmImKLSLeUceBQRDz3bp7P/kdGRFwFXuuIs64tgEv2MZd1IwOYBd4A17KuRkTs1K7l34WIOC2CEXEr60YGMGOCM1kXER8AXwE/O9Z2ZRsBOOMdnM+6kTGA4CeOr1+AX7WL2UZYT4IfAbuB74Dl945gAXBKqeR9Jji1QbAX2hCMiO+Bf9frFg/Mg74oisOPs04Apv/PPKgq8DewmHVtAVy3j1VXo56IiP2Or9+9m3uBPS1kEvgauOA6rlo8lf2vCYDL7kiWTFQTSl7qey2uKB292y2NvbkmfaHKlxJwJaUrOQ88ddUo8sRSvkv/uLZxpdFF2xYRY8n3WJ6/J9RGAT9FxF33cQ8qUW+nnrBM/sKlTbZHgO0Sh8O8dLaRiLTG3ks+NYf8XouIicynC1qdHZQuWP1fkyz7yIq80g5FxOdeoCat9RKNyX6KlPmeyUfm1YFWYUPtzkXgGHB0gPzg7lo1WDupndNnHenZBvsm+dE7LLLzjTEKbLWRburprO8Ht1o6zs6F0eKyXT8Ah30SumT/3UWVJ0+i98Zk1veDVux4EsGV2Bz23VG1bMoQ+7O+ENRt0+r31DrnMSXZOe1u7pj9oFKgrxD0RDtqG+CkxqupjYiDtU7wi/GZ4/WbrO9J0N2ynpoiWMpd16NnEEH7uGJZdJzvTT5GIri1fPeFWOgMbEGwhk/jrV559e+rJlgD+NbdyHT9exuCerADN5zQZ/JNHZmg23kdzWyD87YE9ahSjlyIiM9q/UgE3eepjjamjjYEC9SKeaGX6t9XTdD5UcVe5U39nBL4iTS2L0FPfsYlUEn5H51I8jEUwU4e1EQ6EtdR5bqVGEpjx1wia4LbKx9apP44Uk0WiQu5QXCZ7UtwQs5t0JUCBsE7qNtdErUaiK4Ys914JlbgRqPMvy/r62NSrN1Q0c82TdCFcfKu+0OVrKtqpbJ9Ezy3OnY1FL2rkN8TCmCVO902JWilhl4i/aLJaZyaDTUIxYeOfaAPNRn2oefAxcyrC8C5ylg5b5DIrnTK4/Lhf8J0VMP40O4phTWGQBd0SfxPlN4R6qD7ydmIONDgQxVDN3aQD+llN1Tcb6At3gE6EJxAWR1E2wAAAABJRU5ErkJggg==",
        48, "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAR9SURBVGhD7Zj5kxRFEIVB11uDQzFEwGUDwhDFg0M8UBQQueRyYQUFD/ACNPz/f3lpfBOvtMjpme4eemAJ9kVkDGxlZ1VW3rVu3RoeYUh6RtLWiHhD0o6etE3SC1nmA0FErJd0UNL1iPhd0h/8zkA/S/oiIp7Ne8wNPvxxSX9J+k3Sn5Juz0B8x/d3JS1jzbzXXCBpjze9ZUKZgxFxoA9JOiLpR0m/Ii8iPst7DQ7f/iVcxre3O/P0gaQtkn6yLJR5LvMMCjaQdMM+fzGvzwJiAJdyTLyW1wcFWcM3hQ+fyusZWKwtQCV9VBSQ9HpeHxRJgdN5vYak7Q7OC3mthqSPV5UCEfGEpDOS/nGwX848NVajAguSvpF02AG6nHlqrEYF1vv3SUm/PHIWKHDGWlNgUDyOCtBqrOS1Gg9TgamFzApc71AHHkoho5M8k9druG9CialdpqRPHpgCzvFXvRmK3NdAYiW/tbxbEbEx8wwOSZ9LuuMOks50UdLmiNjUh7htSV/78HS350sNmSsi4sXSkaKED3BzBirflt+tea+5QdJL3FjDoSAGlDx9FR/PvNDKXHzfpn5L0rsNxFS2z90mhyDfQ/x7menKE9dR9/v0RecqvsJ7lSw0YZ/3JL0t6dV8tqlwoLI5OXzsJivCheoDlUMR3J/WMn2Y75OyI7JlsuxsudNYvZbZCLfCp9wG4wqky740mnElnbU80iQPALPKI1mgzHetI2c9sPvJ4xBzr6RdHelDt9BYj41P+KZHDwB2rTcbvmukiPhA0rXOg7/9tAzsS3m9C/xoxYY3q8BF5vuZtwuoDbilZf0wsTCWIoXZIuJKXu8DipMvodw+Vplu/imwJXEnZG3O6yNExFM2FwpMfHFAAM8h8Oe1AhclbqwoQE80dnPIiIhXTAt5vSAivnQcdFOACpvX/YaDCRFEnHCoxcwHaOCyAvl1wgURy1DVIfbeVvMUOB3ftwLkZGbdJQcXAq813VwXBVwMD0XETicLMhU1ZKydGESBiHi6/r/TGpnl+frvXmtVoIb3JtBX5qZADT+N3yFWyPUN650UcENHnbjg/mpH5gGDKuAczW0hbEteBz0U2G//H71QE8yZBwymgF+VebBis015vaCrAjy98HdblHrRmG4HUYDg9eFP5LWMLgpw+Pr/diMs8XL9d68NosBZK3DZrTTF6lw+mHlbFZC011mNrvaYpL+RPSGr9VOgqZC5mHB43OeKsxBKNJm8tZB5ksNlaDvgOxkRG2qegq6F7L9Wou0tpw0NrQS9zJilyuCfU3RGRHzV2koAuwaM3EpjSmuDUyMbEZQoUZq5vZm3C1zwbtiiY5a8B5LeqWYBBhPSHMG7SMWcRHaHUqHJ53zP4RlEihVQhEesTvL8S5zgqsgi3R7JZ74HflEmsOqBhtvrSsV6fE8cLHgGyANN/m4SwVsGGia69mcc/NFZoXzYl0aDTPF5T2XcPFbIvF0IRch2jQE+EVRFm3AfrtFGTofwN1ZnDyajx4D8bRNZHrP08C8Wa1jD//gXM0qfr16T9wsAAAAASUVORK5CYII=")
    static l := Map(16, "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAHHSURBVDhPpZO9a5RBEMZfCwvR8F72+c3uHRxoZWEriCj+A8b0imIwhV04ECFgIyqKAQu10RAUI5jCDwRNZSEWEZVEBLHwq4haCNpZic3JvOwdl9eDFD6w7MzOzLMzs7NFMQBJI8Ad4MuQ9bDVajHo/w+AS8BPYBI4JGkcOGhmx4BV4FY9Zg2AJ5Jme3qMcXdPlnQOWO47D4Okx5JuZnmu2Wx2gQeuAzOSluoxayBpUdINl4HTMcY/ki5n/eK6BLmEKgNHSmnzgG0GWOk7D4OZTQDfgQuSzkjy/ayk87mJJ+oxjg1Ax8wWJC2YWddrjzF2JT2v6Xezz3RRFBur6Nzd38B94Lakq8A1SR/M7JWkz8B1SVeAeUn3zOyX+1QEwDsnqWXl58f95hDCqbrNzKaAr5Ui6bWkaTPbAnzyWsuyHJV0JKXkz9hpt9ubgPfAt5RS9MGS9LEi8M5KOhljTF6nr0ajsdUn0QlCCFNO6L3IhNtDCEf7BJLeegYuhxB2mdmefH44E3TyRTuBfVmelLTay+AR8AY4YGZ7nQAY85nIN76o28zsmb9QRVCW5TZgyT+RpB++8od6CewHntZtZrYSQthREfwv/gIxsYVtGKbMpgAAAABJRU5ErkJggg==",
        20, "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAIlSURBVDhPrVQ7aBVBFF1UEJv3eHPO3bfIK5+1pWBhpVY22tppoa2FhYU/7EQQC4tIlBBLU8VoxM6gScRfQIIYf6AiwRSCBBQVIme5sw7DEhE8cGHumXvPfPbMFkULSB4juQBgCcDLJJZIPid5qiiKDXlfKwAc7ff7awCeAbiTB8l5nz+T97aC5AMAb3I+Bcm5v9U00A5IPop5CGFHWZaXQgi7IwdgCsDbpmk9kJwF8FTjwWCwBcBnHZHkz6qqTDyAaQCv895WpILD4XCzduKCXzqdThD/r4IP0yOT3GZmx81se+QA3ATwrmlaDwBmSL4vimJjPhcB4IkslPOtCCHsNbPvJBddfNa9N68cwIKZ/QJwMO9t0Ov1dpK8THIcwKjuqyzLNQVJNeuIq5ED8A3AVdWb2UgIYU8jRnKXmalRhSv6qgBekXyho5P84Yt8BfBJvL8g1a1oXouEEPbXggBukFyNlkjhtpnxr7wYQujkNeJIfgBwvybcAo3rZWAzOxBzktdccDLh9imSXK+rtlp0fW0BFWn7EgghnHDuur/dac8PK/dFDjn3x2qpYPwxVFUlgVEvHk8FAZzTvNecbRO8FY/sd3aR5BiArV485oJTyrvdbg/AiEJjr5kj+TgK3gawXCctIDnhgvfyuQj5NL3DI34fd3VM+ctD4wlZSnZxa03mNeK8/2S6wmkz+yhDZyGvXTGziuR5ksstNeIuFEWxKdn0/8NvpprNXqtC+6MAAAAASUVORK5CYII=",
        24, "iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAALPSURBVEhLtVRdiE1RFN53jEG4d876vnXOHd1MmJKnQQp5Mn6KNw+KmGc8kwcP8sKbBwohSvEiSpOfF0l58ELE5HeYyeR3Rkl+aphG67T3OHO6d/zcZtWqfb797fWdvdbay7kaBqBDVc+TvAWgqpO8JCIb8mf/aCKyWlVH4jgeIVnTbd8cwNZ8jHGN5A0ffHOSJHG5XFbzYrEoYW24iKxR1SEAT51zhXycmkbyMYBvebyaAXhB8lNbW9uU/F5NI9kN4KuqzvBQA4D9qtpN8lg2GIAekoN1CQBYZSmzuiRJYjnvDFx/g7oFOnICWwK3LoEkSaZ7qABgXxzH9wEcds41Be7/pmjCi3zd93cngFkkW8zjOE7C2uPrVPUHySf/1Kaq2q6qg5ZzS5U5ySH/wH4GzPZV9Yu9h3yMMRZFUUlVd6vqKQCnSR6xv/IBUgfwBsAFy3kWJ/nK+HbOzpPca7cbDV4qlSKSD6w7wtMPHRNGgl8PANgO4Hl2hISREtzikOyPomh2KgBgpwfPAFji0xN8oTmAbSSHw1+LyB6Si3LcdpKLARz0rXwoCJww5ebm5vbRa1UxAM98qj465ybl94OpatnzrqYAyaMmICJL7dsGmqqeVNUuEVkWDlrr+oMfRKRomIgsIHmR5DkRqRgWx/Fcn9KuvEAaDMDxUA8rbKVSmeZ5adEBWC1meu494/qUXP4rAdvIFNlGcRosKxBeOMnXobgk7xiWJMmccQWsqCQfknwLYEdKcq6QFbC29tyNqtpPsgfASo/NGyNgKalW5NbW1qnZb5KPgoBzbnJmy+ZSQ4bX4nlXUgDAAZ/DXX6eNGYO27rR3+qzT8WwiKz1Inluk01a3/ZnUxTAfJLffVEHAbwD8D7r4THZtcNbsG7K8ezcQKifqq4YlY6iaDnJayRfkuwj2evd1n2qejfUg+QmkrfDXo7bq6o3Sa7/fbEJtl8ByCweSDTn1wAAAABJRU5ErkJggg==",
        32, "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAANvSURBVFhH7VdNqJVlEP7UxIzu/fzmeeace+vqdXEho1W0cBNRJhmpmYIrf8AfyAKzIhXvraWBbirDn0wClQJ1IQS6UhGhhYguDCFoUWgkEgRCJlcQZQ7zXd4znu90v/DixgeGc3ifeWfmnXdm3nOy7DHGiaIoZqrqRpKfA9heJc5/AmBOtPG/AeB1kn83m8174xVVvQNgVbRVGyLSC+B6o9G4R/IgyfWquqabAPhKVU3/Tl9f32C0WQsiMt9ORPJ05LoBwHe+b33kakFElrqhPZHrBlXd4vs2Ra4WACwxQwC+TdeHhoamkdypqucB7M/zvEh5kiNeCxvT9dqoCsCcu4NW0QE4GvgJD+BnL7RWECT/yrJsasJPeAB7QwZOZlk2KeEnNgBrT2/LX0keF5FnU/6hBZB0wd7IOabEBcND6wJVXZCkeNwgudv3vRu5Wujp6QHJmz4JdwBYTHJhF1kkIttUddTqA8Bz0WZtAHhVVf+0IMxoKXbCUlLOv98EsCLa+k80m80GybUkh+0kJiQ/APADyX+t7Vx+s+kI4BuSX5O8knCjAE7Y/Sc2hhuNxoY8z2dHn2NQ1ZdJXk9Plp4wFVW9C2CX7QOwmeStqBNteFH+o6rLo29z/jTJa7YRwDGSH1oLdRKSn5L8w+vitA8iS/n2qJsKgAOue1tEBtoCsDffq/ZsG1EBy1Z65wBWRp1OIHnIM7GujRCRZU6M69VT1T4Ao8kofjHqdEIyHz5uIwC84xmII3etqp4ieTgtoKIoZqUBiMjckuvt7RUbXKp6xupjzFgyIR8YUJ0CsKyU7eVpvjw4OPikcV0CmGQdYLbKVrV6Km3WCsBmvRdaS9zR88ZVBZDn+QxrQ7+WFpfWVa0AALxXnsQzcKMoity4qgCyLHsCwKUyc+5sR2mzVgD20AD4QlWvqupFkq+URJcAjHtBVc+p6jXLorV4yVUGkHTBA69eee8pADwTuuClqDMwMDA9rqnqVvfzURtB8i0nfmwjKmB/PEjeLWeBqr4ZdToBwJee6ffbCHsDANzy03wGYJ49QhXyNoCfvEB/9z2/2IjtoFvKaz5FWz7smtoCMIjI6rJw4lzvNONJXrCRar+IyrWoG/fZp4iMRN9jsGIiuQvAkSoh+b0VUX9//1O+bbK/oIeibti3T0TeCC4fLe4DokSkVH4UsNAAAAAASUVORK5CYII=",
        40, "iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAR8SURBVFhH7VhZaF1VFL2aqji+vLPWvve9EBxqBI0VFdGiUcFZRCv6KagfdcQPP5zoj6jUVlpQrParYCkoDlFrQSh+qWgKCoITioJaxVnUqDigHWQ9ziknu8nLTV5K+5EFG/LO2mefdc+090lRzGMvgOQ5JG8EcCuAW2rYzWZ2SVEUB/pYc4r+/v6jzOw1M9tZluWMTH1IfhhCWOzjzgmqqjqU5EfZYL+S/KaOAfgpfZT66UN9/J6h5YwD7ABwd7vdZrvdPqSONRqNfgDXkPwrxnjMx+8ZAJ6tqmongC2eqwuSG2KMdzzXM0huUnAze85zOaqqWjQ4OHiwbxfMbHkU+L7negbJjQpO8gXPFUWxP4DzSL6ivWZmJ3sHgeRDUeC7nusZ3QQCGCC53cz+I6nDcJL3EfamwMNJnhZCWBavlX1LYAKAu/Z1gffMC5wKmcDnPZcA4L5Wq6VTfIrnBJIr96TAzj1IctRzCSRPNbPbBgYG4Dlhj96DANZHgR97ri4AbI4CxzzXMwBcmRUKG83sUjMbMbOzp7ERABeQXJsKBuVyH39OQPKpJHI2FsVp9g7wsWeDvhDCEbqEZSq3VJWQXGNm48oYyQD8Kct+/wPgj9xHlQyAZ5rN5pHK1SmuxhgeHq5fyJZlWakcAvApgB8AfJ+M5NfagyR/zwc3s09I3lBV1TFlWS7UdiD5tkqzTLQEyu+rPKbGIPkFySdDCCd4PRMQQhgk+ZmvhqezuIS/ATi91WoZyS/Tks7EUgyvaxcAjMoxfvE6kjeRXNrNANxP8ufYb6vuuPi3lvkRzazvM4mt1gyrH4D3iqJY4LWpjisB/B2dVni+GwCcT3JbfiD0WPJ+3RBCuD7ru/ssNpvNRXE/yc7yfDdok2svqW/cczuqqjra+3VDLNm2xQla4nkJPDEJ1LMy50IIF5F8ieSYmT2gE53zenfocZQJVG14bO4D4A71V1EL4NqcE3S6Sf4bt8flnvcCz80oVcsKvCnLx2szvvPiA/CtEziUufTpDiX5hF6GihFCuDjjO0/a2Qrs09WTfpD8heQHGV9H4H7pDwlTQRFCuC7jexK4CyGEq2MuXZ631xCovmeQ3EzyRwB6eE04qT0LVP5M1Yy/+WsKXGxmL+uiNrO3NF7O9ySQ5L2x49K8PaGOwAQ9+GOsDXn7rAVq/8W2cS2tcjHJ2/O+0wlUCiS5KqbAVVoJM1uWx6gjML8HR1I7yeP0Tx+dPokg+R3JF/O+Sv7+mpGoxJtZi+Tnyi5KZyQf94/7mGY7AgFckXMdADg+E6h/ldVGvAfHM4E6pcPer9lsNoaGhg7y7YKKjDjz6n+Z5zuDaIbiFL+qveJ9psACAA8mcfEDNQtPm9lh3nkyxA9cH8fe3mg0Js9CAO6UUxxApdYWAG90sTdVlsk/Ls0ogIdTjFhajU3SLzclga1ZjHVe1wQAeDQ5azNPZ/KLgV9XQRtjaPZ2853KUgw9af3enBRlWZ5pZiqj1gCY0uKJXl2W5VU+RgjhQpIrasZYOdN9P4+6+B/bv2K8mTug+AAAAABJRU5ErkJggg==",
        48, "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAVOSURBVGhD7VldjF1TFL7tTEMw7j37+9Y5906GiZoHoloahKcSRCQ8KBWJqAeJSIn474MEIRFC0Ip4EG1p4i8Smvh5aFpBNUKFZlRLiVZF0KRMx2j9dMi62Vv2LPfn3Mm5ExPzJWvu3LvWXnt/+2etfdYplWYwjdHf3w8AZwO4mORFeUXt0zQ93zk3YH1OFXpJ3k9yr4j8NVkh+QvJZ6rVqtgOuonZJNelafrPQPT/yUhoS/IzXU3bUVcgIjf4ToO8SvJBvyKdyLMAxtSH+gOwyvbVDfSQ3OZnflxEllqDTuCcO0NE9qs/AAdJ1qxNoRCRKoBffYfDVj8ZAHg+bCcNCFZfKCqVyiCA3/wW2mD1DdDT7oACeCwQcM6dZ/WFIkmSY3WpPYG3rD4GyQtJbgWwtVQqzbL6AACPRytwrtUXijwEFi1a1AvgnSzLwuHcOa0I1Gq1I0i+T/JJkgcAfDGtCGie0D+Dg4OHkxwH8OV0I1CHRqwZAkXjf0VAs6peEwDs/q8S2Gj1MdI0zUj+DOCTNgRWBgJTkciOUQJ+tt6zeoPZWZalfX19LW+ZJJ+YMgJZlh0J4HvtjOSIroi16RB6Na9fDnW7JUlykjUoHADWhBkjOeycu0REFqRpenIHMl9nG8Ab6sev6Mchh3QVWZYdR3Jf6DjMXqcSt5+SAxwjTdO5JN8l+UejgekKWWlCVJ8pdnRl7ydJMo/ktQCWA7jDyDIA95DcTvJPM6gdAFaTXAvgJQDPAXiK5AfGdpzktwBWALgOwO2mj+Uicn2apmfasbWEHlSSa0gesrOYY0ZV9mlkiX3qgERkjx/0BPtmK2b6WV8ul+fGPptBqw0bQsPJirYHsKlUKs2Jw2SnEtrpJ8ldmlvsgCdAt0bE+iCAR51zVwO4ModcRfIhkmNhABplwqx7n6tIXtOgbUMheReAHwIJAE/bMceYRfJD37keriXWIA+0cCUi9b3uBx0+77S2eaC5QURGvI+RcrmcWJs64iQFYJfVdwIAn4fBqwA40Hb5WwDAm34b6UrMt/o6kiQpA/jRGzarOPRkWTYPwGlqb5UBAD6KCeidaGBgwFk759zRJE8luVBEjrL6AI1mgYCInGL1dagz3W/ecJvVp2l6Fsk9UXT4zjm32NopNKsaAiO1Wo2xTbVa1QpH/WIYDqmIXBDbBAB4OSKwwOrraEeA5I0ispHkFXq4vN1e3XrWNg8BTYYAHhGRyzRY+EOqz8//uk4UQqBcLlfi79F56Y9/97q2BGIA6PP233SNQAyt+URnpdfq8xLQ+4+IPKxZWhOdlt2tjaJQAs65pT4ujzrnGqb5DgjcG52BYQCnWxtFYQSccw9owUorbpVKpXE464DA0NDQYVp69FW8MQCjjcJtIQT08PrBr2v1iKjIQ0DrRvF3LUH6vhfGv3tdIQQ2KwEAX5HcotVpzdz62Ght8xAAcJuIrPe32le0Xy1DNolq7QmYRPap1QN4we/TnRqzvWzX8kkD27aJTHOIiNRfUZH8XUReB3BCbBOQK5GZq8TXVt8J9JnAXiUarZRGMD0DrbK6AsBrgUDTq4Tu6zBzInKoWUhrBw2N4UktkPCTcqu1zQMROZ7kT97X/pZVDpK3KFPf4SiA+0heLiK63Je2kMVqR/Ju3S5+EtTH29E20klZqcEghz+VJUqa5G4fttXHWjvmCdDIAGBzINGphHa+sy2+1L66CH/+7tX+vbLet0XkxdCwU9F2GlWiV0tzRGSFHlRrm0e8v03NDnhT6JWZ5E1+W+SVm/XNo/WlcM6dKCLLGrRpKiKiD/fnWF8zmEGB+BvtBlezAgZraQAAAABJRU5ErkJggg==")
    static lp := Map(16, "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAGlSURBVDhPpVPvS1RREL2UWYK0vplz5u5uGwtWRGupZRH9TjGKUsnUSuyD+CENKojAvz/O472lvQQFHbjcmXtnzpuZe15Kkzjn7s8BfCS51y75EfFiOBxeKOIn4e73IuITgGsRMV9V1WXt8kUC4EmZMwGSL0k+bP2IyK0N4I67b42D/4SIWCf5WDbJRyRPc85r8t39LoA3Zc4ECoJlkl9zzvfl/xNB00JN0GCqNUTw1xZIXo2IAwArAG4X+37OeaHMqVFV1YK7rwJ4BuCzu/8k+QXAa3c/lh8RJ4rRiojFlNKZOlnTBXDk7msAnqrniHhAcicitknu6mV0rmcUAclDxdQEZrYtkqIo9Xzd3U9JLpV3ZnYDwPs2cCsibkmFjeo+pJTOk7wC4IeZjVJKZ0m+0xykRglLFY4Jcs43B4PBjPrW05GcbRRYE4xGo2nNguQ3M7uoYf9O8LapIPV6PeScQ7Yq0PC63a4qSP1+31tlNhXstf2sa1jSvZK1zGwgTQD4DmCjvNPZWFQq1903m59oX6vRwoaZXSL5qrzTBzudzlxN8L/4BUB3SuCvPqT/AAAAAElFTkSuQmCC",
        20, "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAICSURBVDhPrVRraxRBEBxNfH442O2qvj05OcHzwQmiQRRMoohR4RI1mojGiy8kEcRH8v+/SJ29m826UQ4saHa7pqemp6dnUmpBlmXXSL4kuXGE3UgpHWvOa4WZXQXww8yek3zcNDN7qnEAN5tzWwFgleSrJl8HgDWSm02+FQpWFqVfFAUBLJvZuZJz94f/WrSCMjSzZ+HOA9gCsEfyw2AwOC3S3R/NkmFdcE4TAey7+2Q4HJ4SOavgmqz08zzvAFjodDp5yc265TGAN39rC3dXB2w0+Vao+AB21Ichvuru65H5OP53SV5szq2gkyS5COCevmb2luS3sI/uvkLyXY17T3JJ8c0OSCQLM/sC4HOc6Ja24+4vALyWoBaRoMbEa7wW+4nk16IoBlNBM3ugSWVLNDAX296TUErpRDNAXIiPp15cqarAAHrdbvdC6cfWJLhSclmWnZfV5oyrVouemraAgpS+7qq7X49g1emnFg7/cllLAJeCO7hddUE9DO6ubPZVtyMEFzQuKx+IQ4Kx5bLr57vd7h0A93u93tkIXpagFpav2xKHtDgajU5GjG7XQYYqagj+AR2arl5V9BaY2XpVQzO7opqRfBIrL4WpHyW2E6e4G/14KCa47/Ho/oYcNbOZbZvZpDR33yZ5t9/vnzGzW3og6uMRM8nz/HZK6Xgt6f+HX1Qsb+PcI6ZHAAAAAElFTkSuQmCC",
        24, "iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAJ+SURBVEhLtVZrTxRBEFxRxCfn7VT13J4X8UGiH4wxmmg0YmJE4yuioCIQRQUUEB/8/y+m1h5cxzvQCJ10brd2tuu6u7rvimKAkeyY2SSAJwAe9fHHJO+32+1T+bs7Wgiha2afSG4A+DDISX52P5fH2NZIPiC5bmZne73e4bGxsUPy8fHxkXQt1xcBsEJyJo+xrZGcJvkmx/uZgocQFoqi2J8/G2hm9twJhh3aB+AKgNdmdqMZjOSLEML8fxGoFKo1gI8AvjZrvisEACoRhBDU+C+7TiAjeRnAq7IsrxdFMdTA/51gz5vsMq31XVXVkeSSrDzdl2V50mU6ncfY1kZHR0uSi2qqMnHX/RLJdwlTcGESQR4jt2EzuwRgguQtSVF98ADL/jkbQrijmjdxki91Xu8BuC05K8tm8INm9gzAppdlXe5BtBKWzGxVjQwhnBcByTXh/nw5veNS3tS8kDxWR48xXnRwoqoqqDy5K7CXYlVlU7bdbjfk54SVZXkNwHdXW93Qm9J2r9crm2nlpkamTDTZ+fNkKo/mxczu1YDXb6PT6dDPjKieUlID2yIAMKeyCmu1WicUSL2JMR4VFkI47llO9iVQRmb2zVf1bNJ3RpBWyJSy1/pI33hHAj3QS74WFlOwjOCAMFfWmq+Rp39F4DMwI52HEC7Uh/4kqEsUYzxtZgtSjfZVXwJv8kafJv82+pqLBsHWLsqu6yY7wc8mA7gqmUqufripEF0PeVZvfT7S5PY9q/WinmjoarTdbrdIvvc6znu6c5mvuETvarDUH8ebZ+trDaF+z2OMtkWt+gN4qHWs0W+6MJUn9SPGeMbMpgad1b8QLcFfie2x/QDpJKHNfzyEMgAAAABJRU5ErkJggg==",
        32, "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAANfSURBVFhH7VdpTxRBEB28Iya703X07Hqs0RVlQU0UUcELDQnGI6jxxAMUEBAB//8X89aazUwzu+wQ4JMvqSzp6q6urqpXNUTRf/SJWq120ns/QkRjzHyzm0CvqtfiOK6ENnYNZq6JyDdm/sPMW30I9i2KyMXQ1m5wlJk/iMgvZr7PzEPMfKmXOOduM/OyiCyIyKnQYCkQUV1EfovITKjrBRG5Z5EYCnWlUK1WGwirqt4Ndb2gqlfhgHOuFepKIY7jc8y8KSKTgeoQEd1S1Vd4bbPZPJ5Vish1c2A4u14a3RwwNmwg1/glokdZ/UE4MEtEP1FoqHgi+oSopPp9dwA1YRFYQpGq6nRWv+8OGD0fgKK4HI0qq9wzB4wFmz1Y0Al7FnvGAufcaYQ6DPFOUNU7cICILoe6UgC9VPWzqq6g8uM4PuucO4PfUNJ1zAJm/o7i3JOZICIJnBCRNVQ+qAeHUHxWiBsisop1Y8Yq2KGqF0JbO6LRaJxA2FBEeAkEeWTmhyIyby/7ISJvURciMoFwoyFhHXq7fBrnUhuwlyTJcM/Z4L1XVZ3LTLSOiMi6vRqvW0N4MXRwLo7jUbt4DXrbh+FVZGfBe38+vBsArd7hIBFNJUnSAoWKxCj23pyZUVX0gi/MfCPcG5ybNOfmvfeDudtt5iOnT3OKLlBVjyaEnJvRvma/jfTtUxJhKTP10HjsIwV5X6zX6xTuKULaH+I4HskpkiRpN5yw49lHxnMMm2wB4e+sA0mSSKoDdWGHiF5470c7xvIdMt+gihxAF0RhpZRT1dkoig6boW4ODIABNiHb57KvLeUA8oWitIkH+i2ljaWbA61W61i6bnRcydZVKQeI6IoVJqoc1PsItpihQgcQASJ6Cdpi3SIxltos5QCMOefGiWhORF6jI6aKHg5ElUqlivzjHCZmFEVHMueKHTAWwIGJnOIf2nnPwljwdQcWdC5O0ZUFGCQWric5RRegFuzydv/H1Az3FMF7Pw4HkN6cAjPAXoTveYQJjSkpEvtIeWatFzMB1f4GUQz3pgJ71g0xT5aRppwDALqZqmLaoWfjf4H1IrEJuGU8H/TeP0b6LIXb9mfObYFVGE7h3R2gmFAHmAdoPgWC9SlrMGmOB9BaM/rwTHsdn+/9purA8Bd5jumicJ41LAAAAABJRU5ErkJggg==",
        40, "iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAQqSURBVFhH7Zj7bxtFEMevbWh5xrmbx8VpIAjCQ0ARpDwaqkJIpUptJKC0Ja1KQ0rpI7wF/7+EPtactV4n9rkXlP6QrzSS7dmb/d7u7Mx3XRTHOAKY2aKIvDuLVVW1XBTFyTzWocLMXlbVLXd/bGa/mdnvbc3dn5jZzcXFRcvjHhbmzOx7iInIYxG5q6rbLe2Oqj40s1/d/UdeNA/eGWwT5FT1F3c/t7Ky8jykW9ppM3vTzHZZzaqqLuTxO0NENlT1T7Y497WFql4ihoh8k/s6Q0Quq+pfIvJ17kvR6/XKWLUxqOp5CLr7d7mvM0RkMwhu5r6iKE6oal9Vr5Jr8/PzVT4AiMgnQfDb3NcZkwj2+/0XyS9V/VlVH8QqjuHICBZF8dzS0pK4+4dmtvcsEhygrusPKCXPLEHKzzHBg9CGoJl95O7/HNUpnloHOSjkYVEUZ3IfUNW1/60O0gXM7A8zu5H72sLMrhCjSzc6EGVZvkZ+qeojVrOqqrPuXk+zuq5dRJbKslynj4eyOZfHPxSo6pehSJ5AlAnDHsb31Pht6A+5xQuyeoeiC09QgBMbqBJ3v2BmO9E1BmZm97Dk+w6yKhuzW9f1Zl3XLxVFcSqLzfd2QEaZ2Rdmdit03O3EttGEzeRmdp/WFmPfEpFXMNKBkxq++2E7PKuqP2QxmWObw1eWZS/nMwLejgCJEkY172d7bFljCFhWqN/vKy/IpCIy9Mf27u0Tp7Fmvp+IkfMagrdgYKzORRF5R1XfnmIfu/vdIHCLlYvPu1VVfbbP+DETkU9jhVHr1MjxHF1eXn4hBpHI53P/JITUepAeGF4uHzcJZrbKTvDsvqtIe2ISBlEacv8UnIx8guAgN2e9dzSSjXQgh3N/Q5AT94j6lfqoYxRZpHqsbq6Y5+Jy1BBke+fTAWVZvh/PX3X3N1If4IXIwSD4au6fRBC1vAVBdx+0O0pN4gfTCBLjK4xOFBens4m/G0Hys/nCdbOqquuJH0wjOAS74e7/cstLf+9CcIiFhYWVuNmtZa6pBLmwq+o1EbkXimjkpHYmGHKePno5Dz4DQS5Vd9z9eq/XW0j9nQii8yg/E0rHVIINVldXz0StvZT+/tQEyb9o9rS3NQp4VVXvjT49mSCTI1YpHxRlVf2bHUkDzEQwrYNMxJZEH72d5FCKU9FjhwTpyY0zmsDNqI+QWM8FAm12IkEaNcEZkJeAFpiLP5MGBONuPJJjgdM5sQa8UDI/f9WNYbBN0equxZ9DbUAX4S+NoT6Mf782Qkq1AXOj2OnhB3ehuNdyUumJyKAtyE4wCvgNyPEcYgOBEJ+Jwba3iYFcIwZXios5rxHUdf15Mzhq3kSLoI1SZgvZro2QWLPEQMJRwvZNgRFwSNg2kpm2NslYsbquX89j0DE4sS1irDPuKfL+GK3wH7tmRxUWXSl+AAAAAElFTkSuQmCC",
        48, "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAT1SURBVGhD7Vn7UxxFEN4DiU84drp75k6R05KyFPEVNUGjqIkmEoWIQJQY0YQYNMTy///N+rZ64th3e7tL9hJS8lU1Bzezs/NNTz/JslM8wVhaWnqamft5ni/mef5yE3HOvRRCeN6u+ajQIaIPvfc3mfkuER3is6mIyG/M/PlgMHjGvmCSwOYvich9Zv7de/+HiPzZVPAcnheRIxHZhjbtiyYC59ybeCkzH0BABtpg5g8aypqI7DPzHSXxqX3XJNDx3m/plcHpLdkJTdDr9UREftW19hcWFp61c1oFXiAiv3jvD73339vx4wA2gCulNtGz460CXgMnpff4Gzs+Ap0qAw0hnI8EiOhFO94qUgLMvG7HUzjnFmCc3vtrdiyF9371pBGYYuarzPy3GueOnZDiJBJ4ipm/E5ELMFBowU5IcRIJdPBjd3d3WkRuPYkaKKAe65RAq/jfEdB047odS/HYCFQFMhBAtloVBx5LINNM8qodN+iARFWW6b3/+JERUB//k+Yt+y0UJB0R+UHrg4NutztvJ7QOZv5MRO5pLbA1Pz8/mJubc91uN28iOG0Ruawnj+RwM8aQiUJEXkBGGlNqPb3bx5D4LA4Cn337romBiGaJaHPEpiAoUIYqsDFEr0/k7qua3/Dev20FVRkzv488B5tQf39Lf99GdYWKi4i+1Hz/AhFtxHlxLuzJOXe+5D3vOOeWQwje7q0KMNQ1GJU9xVRwhdINJQTgZj9JF8RmvPc3UrLJM3AIQ+sbza1D6+maZZiCf9ea9w7cZVOJNS4zf4v18jyHm0QD4LjrodwEkR8rS860YEfLwzl3DnWviLxWR4joI61xEYFhnF/rKRcNAL1ar9vnxsh7zLxXu/DHPY3eJYTwqh2vAzSt8EK944Xh6nV7186tA8QG7V7c9d7/nGVZaWAsghTUJiK7drAJNDhB9cXpQyuV6h8DaFKv0wFijh2PmIG69O6VdhywANohmG/HItTFwjgLAsiJSlKKmX6/zxAcoB2MIKIv1A5qE9iyg9g0VKje4Qib6vV6AzsPIKJrloDtTmhARMl5TyP7Hvql6ZwIuOOHJgCfjFoXtgHj0gX3Rp1cHQJwiyGEcyGEV9RZ3Nf6eSidaIVAlmVn0j/g1rBgv99/Lv0eqEPAYEadB2qHiRF4AKgaaldbmbLjdQkghUA6jfnIr+DB7BygVQLwz2gtYjE15iHUJcDMZ9UGig61GvMQWiOgXWU0rLYXFxdzOx5Rl0CWZdP4HhrVNGOku22FAIwXm4dPtmMWNQlMp3/oNTqanZ2l9Hsde3gCyG309Hfg5xGsQggbIzZWi0AIYQVeDVltCOGiiPylHYxRXq0xgaFAhmDinNvRdHkXXggkSlReGcgQQzRvQp6DzPRKnufddE5E3UCWphJjezlVGJFK7FsNKIrCf3l5+T8u2sJ7/1WdVAITN4moSInLXFoV4BrxIk3mUDbehtfK83zFzq0DBDy4WE3mbo5L5nAv34q1gGaAZ2G8UDciZpnoeIzQeBmyUWx+PUmnQWS1wXr4HXaCgAltIt1Ys3u2mNbWeFrQHCJKVon+2+lBQQM7wLVEDm8LGvtsmeh6RUFDRDfqtnHOENHF+GBTiYVMlmXxzk8551bVFobmV4mS2Sgz8FIgKuLeavGOqzFW1B2ulEVnFCZJM2DoeSuYh1p6Ih2LU5ziX/wDffDQpjl85hYAAAAASUVORK5CYII=")

    return dark ? (paused ? dp : d) : (paused ? lp : l)
}
