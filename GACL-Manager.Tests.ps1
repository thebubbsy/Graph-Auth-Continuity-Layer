# GACL-Manager.Tests.ps1

BeforeAll {
    # Load the orchestrator script
    . "$PSScriptRoot/GACL-Manager.ps1"
}

Describe "Initialize-GACL" {
    Context "When EnablePersistentStorage is true and TokenPath points to an invalid JSON file" {
        It "Should catch the parsing exception and emit a descriptive warning" {
            # Arrange
            $mockTokenPath = "C:\GACL_Cache_Corrupt.json"
            $mockExceptionMsg = "Invalid JSON primitive: error."

            Mock Test-Path { return $true }
            Mock Get-Content { return "Corrupted Data" }
            Mock ConvertFrom-Json {
                throw (New-Object System.Exception $mockExceptionMsg)
            }
            Mock Write-Host {}
            Mock Write-Warning {}

            # Act
            Initialize-GACL -EnablePersistentStorage -TokenPath $mockTokenPath

            # Assert
            Should -Invoke -CommandName Write-Warning -Times 1 -ParameterFilter {
                $Message -eq "  [GACL] Failed to load registry: $mockExceptionMsg"
            }
        }
    }
}
