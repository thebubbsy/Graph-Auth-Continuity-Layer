BeforeAll {
    # Dot-source the main script to load functions and initialize variables
    # The script auto-initializes upon dot-sourcing
    . "$PSScriptRoot/GACL-Manager.ps1"
}

Describe "Initialize-GACL" {
    BeforeEach {
        # Reset script scope variables to ensure test isolation
        $script:GACL_Registry = @{}
        $script:GACL_TokenPath = $null
    }

    It "should use volatile memory mode when persistent storage is not enabled" {
        Mock Write-Host {}

        Initialize-GACL

        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -like "*Volatile Memory Mode Active*"
        }
        $script:GACL_TokenPath | Should -BeNullOrEmpty
    }

    It "should use volatile memory mode when TokenPath is not provided even if EnablePersistentStorage is switched on" {
        Mock Write-Host {}

        Initialize-GACL -EnablePersistentStorage

        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -like "*Volatile Memory Mode Active*"
        }
        $script:GACL_TokenPath | Should -BeNullOrEmpty
    }

    It "should set GACL_TokenPath but do nothing else if file does not exist" {
        Mock Test-Path { return $false }

        Initialize-GACL -TokenPath "C:\temp\dummy.json" -EnablePersistentStorage

        $script:GACL_TokenPath | Should -Be "C:\temp\dummy.json"
        Assert-MockCalled Test-Path -Times 1 -ParameterFilter {
            $Path -eq "C:\temp\dummy.json"
        }
        $script:GACL_Registry.Count | Should -Be 0
    }

    It "should load registry from token path if file exists and has valid AuthTokens" {
        Mock Test-Path { return $true }
        Mock Write-Host {}
        Mock Get-Content { return '{ "AuthTokens": { "TenantA": "token_a", "TenantB": "token_b" } }' }

        Initialize-GACL -TokenPath "C:\temp\dummy.json" -EnablePersistentStorage

        Assert-MockCalled Test-Path -Times 1
        Assert-MockCalled Get-Content -Times 1 -ParameterFilter {
            $Path -eq "C:\temp\dummy.json"
        }

        $script:GACL_Registry.Count | Should -Be 2
        $script:GACL_Registry["TenantA"] | Should -Be "token_a"
        $script:GACL_Registry["TenantB"] | Should -Be "token_b"
    }

    It "should handle JSON without AuthTokens property gracefully" {
        Mock Test-Path { return $true }
        Mock Write-Host {}
        Mock Get-Content { return '{ "OtherData": "value" }' }

        Initialize-GACL -TokenPath "C:\temp\dummy.json" -EnablePersistentStorage

        Assert-MockCalled Test-Path -Times 1
        $script:GACL_Registry.Count | Should -Be 0
    }

    It "should emit warning if reading or parsing cache fails" {
        Mock Test-Path { return $true }
        Mock Write-Host {}
        Mock Write-Warning {}
        Mock Get-Content { throw "File read error" }

        Initialize-GACL -TokenPath "C:\temp\dummy.json" -EnablePersistentStorage

        Assert-MockCalled Write-Warning -Times 1 -ParameterFilter {
            $Message -like "*Failed to load registry:*"
        }
        $script:GACL_Registry.Count | Should -Be 0
    }
}
