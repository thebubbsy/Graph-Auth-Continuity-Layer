BeforeAll {
    # Dot-source the main script
    . $PSScriptRoot/GACL-Manager.ps1
}

Describe "GACL-Manager.ps1 Tests" {
    Context "Initialize-GACL" {
        It "should handle JSON parsing errors and display a warning" {
            # Arrange
            $mockPath = "C:\fake\token.json"
            $mockContent = '{"invalid_json": "missing quote}'

            # Mock file system and console cmdlets
            Mock Test-Path { return $true }
            Mock Get-Content { return $mockContent }

            # Mock ConvertFrom-Json to simulate an invalid JSON exception
            Mock ConvertFrom-Json { throw [System.Management.Automation.RuntimeException]::new("Invalid JSON primitive: missing.") }

            # Mock Write-Warning and Write-Host to verify calls and suppress output
            Mock Write-Warning {}
            Mock Write-Host {}

            # Act
            Initialize-GACL -EnablePersistentStorage -TokenPath $mockPath

            # Assert
            Should -Invoke -CommandName Write-Warning -Times 1 -ParameterFilter {
                $Message -match "\[GACL\] Failed to load registry"
            }
        }
    }
}
