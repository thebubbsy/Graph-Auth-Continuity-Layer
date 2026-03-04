BeforeAll {
    # Ensure any necessary global mocks are in place before dot-sourcing
    # Since GACL-Manager auto-initializes by calling Initialize-GACL at the end,
    # we define a dummy version first to prevent it from doing actual work during dot-sourcing.
    function Initialize-GACL { return $true }

    # Dot-source the script under test
    . "$PSScriptRoot/GACL-Manager.ps1"
}

Describe "Set-GACLContext" {
    BeforeEach {
        # Reset the registry before each test
        $script:GACL_Registry = @{}
        $script:GACL_CurrentTenant = $null
    }

    Context "Error Path: Connect-MgGraph" {
        It "Should catch exception and write warning message when Connect-MgGraph fails" {
            # Arrange
            $tenantName = "TestTenant"
            $script:GACL_Registry[$tenantName] = "dummy_token"

            Mock Connect-MgGraph { throw "Simulated Connection Failure" }
            Mock Write-Host {}
            Mock Get-MgContext { return $null }
            Mock Invoke-GACLInterception {}
            Mock ConvertTo-SecureString { return "dummy_secure_string" }

            # Act
            $result = Set-GACLContext -TenantName $tenantName

            # Assert
            # Verify Write-Host was called with the correct error message from the catch block
            Assert-MockCalled Write-Host -ParameterFilter { $Object -eq "    [-] Registry Session Expired/Invalid." -and $ForegroundColor -eq "Yellow" } -Times 1 -Exactly

            # Verify Connect-MgGraph was actually attempted. Since we mocked it to throw an exception,
            # it should be called twice (once for the registry token, once for the interactive fallback)
            Assert-MockCalled Connect-MgGraph -Times 2 -Exactly

            # Verify the current tenant was NOT set
            $script:GACL_CurrentTenant | Should -BeNullOrEmpty

            # Verify it eventually returns $false (since the fallback also fails)
            $result | Should -Be $false
        }
    }
}
