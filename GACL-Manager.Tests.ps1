# GACL-Manager.Tests.ps1

BeforeAll {
    # Dot-source the main script to load its functions into the current scope
    . "$PSScriptRoot/GACL-Manager.ps1"
}

Describe "GACL-Manager - Set-GACLContext Error Handling" {
    Context "When Connect-MgGraph fails using a Registry token" {
        BeforeEach {
            # Reset registry state
            $script:GACL_Registry = @{}
            $script:GACL_CurrentTenant = $null
        }

        It "Should catch the exception and output a warning message via Write-Host" {
            # Arrange
            $TenantName = "FaultyTenant"
            $script:GACL_Registry[$TenantName] = "mock_invalid_token"

            # Mock Connect-MgGraph to throw an exception when called with -AccessToken
            Mock Connect-MgGraph { throw "Simulated Connection Exception" } -ParameterFilter { $null -ne $AccessToken }
            # Mock Connect-MgGraph for the fallback interactive authentication to simulate a failure there too or just let it pass
            Mock Connect-MgGraph {} -ParameterFilter { $null -eq $AccessToken }

            Mock Get-MgContext { return $null }
            Mock Invoke-GACLInterception { return $false }
            Mock ConvertTo-SecureString { return "mock_secure_string" }
            Mock Write-Host {}

            # Act
            $result = Set-GACLContext -TenantName $TenantName

            # Assert
            # Verify that Write-Host was called with the specific warning message
            Assert-MockCalled Write-Host -ParameterFilter {
                $Object -match '\[-\] Registry Session Expired/Invalid\.' -and
                $ForegroundColor -eq 'Yellow'
            } -Times 1 -Exactly

            # Verify Connect-MgGraph was called twice: once for registry token, once for interactive fallback
            Assert-MockCalled Connect-MgGraph -Times 2

            # Result should be true because interactive fallback connects successfully based on the mock
            $result | Should -Be $true

            # Ensure the current tenant is updated by the interactive fallback
            $script:GACL_CurrentTenant | Should -Be $TenantName
        }
    }
}
