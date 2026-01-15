# Tests für die Cooldown-Logik (verhindert Popup-Spam)

Describe 'Cooldown-Logik' {
    function Should-Alert {
        param(
            [datetime]$LastAlertTime,
            [int]$CooldownSeconds
        )
        if (-not $LastAlertTime) { return $true }
        $elapsed = (Get-Date) - $LastAlertTime
        return ($elapsed.TotalSeconds -ge $CooldownSeconds)
    }

    It 'blockiert Warnung innerhalb des Cooldown-Fensters' {
        $lastAlert = (Get-Date).AddSeconds(-5)
        $result = Should-Alert -LastAlertTime $lastAlert -CooldownSeconds 10
        $result | Should -BeFalse
    }

    It 'erlaubt Warnung nach Ablauf des Cooldown-Fensters' {
        $lastAlert = (Get-Date).AddSeconds(-12)
        $result = Should-Alert -LastAlertTime $lastAlert -CooldownSeconds 10
        $result | Should -BeTrue
    }

    It 'erlaubt Warnung wenn noch nie gewarnt wurde' {
        $result = Should-Alert -LastAlertTime $null -CooldownSeconds 10
        $result | Should -BeTrue
    }
}
``