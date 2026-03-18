# --------------------------------------------------------------------------------
# GACL-Manager.ps1
# Bubbsy's Graph Auth Continuity Layer (GACL) | Core Orchestrator
# --------------------------------------------------------------------------------
# Author: Matthew J Bubb (BUBBSY)
# Version: 1.1.0
# Description: Centralized Identity Continuity & Multi-Tenant Propagation Framework
# --------------------------------------------------------------------------------

$script:GACL_Registry = @{}
$script:GACL_CurrentTenant = $null
$script:GACL_TokenPath = $null # Disabled by default for security

function Initialize-GACL {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$TokenPath = "",
        [switch]$EnablePersistentStorage
    )

    if ($EnablePersistentStorage -and $TokenPath) {
        $script:GACL_TokenPath = $TokenPath
        if (Test-Path $script:GACL_TokenPath) {
            Write-Host "  [GACL] Loading cached Identity Registry from $($script:GACL_TokenPath)..." -ForegroundColor Magenta
            try {
                # Applying PR 11: Get-Content -Raw
                $cache = Get-Content $script:GACL_TokenPath -Raw | ConvertFrom-Json
                if ($cache.AuthTokens) {
                    foreach ($prop in $cache.AuthTokens.PSObject.Properties) {
                        try {
                            # Attempt to decrypt the token
                            $secureToken = $prop.Value | ConvertTo-SecureString
                            $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
                            $plaintext = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
                            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
                            $script:GACL_Registry[$prop.Name] = $plaintext
                        } catch {
                            # Security Fix: Do NOT fall back to plaintext. Skip the token if decryption fails.
                            Write-Warning "  [GACL] Security Alert: Skipping token for $($prop.Name). DPAPI decryption failed. This token cannot be used securely on this machine."
                        }
                    }
                }
            } catch {
                Write-Warning "  [GACL] Failed to load registry: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Host "  [GACL] Volatile Memory Mode Active. Session continuity is maintained in-memory only." -ForegroundColor Green
    }
}

function Save-GACLState {
    if ($null -ne $script:GACL_TokenPath) {
        $encryptedTokens = @{}
        foreach ($tenant in $script:GACL_Registry.Keys) {
            $token = $script:GACL_Registry[$tenant]
            $secureToken = ConvertTo-SecureString $token -AsPlainText -Force
            $encryptedTokens[$tenant] = ConvertFrom-SecureString -SecureString $secureToken
        }

        $state = @{
            AuthTokens  = $encryptedTokens
            LastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Version     = "1.1.0"
        }
        $state | ConvertTo-Json | Set-Content $script:GACL_TokenPath
    }
}

function Invoke-GACLInterception {
    [CmdletBinding()]
    param([string]$TenantName)

    try {
        # The core GACL logic: capture the session bearer token from the SDK's HTTP request
        $resp = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/organization?`$top=1" `
                                     -Method GET `
                                     -OutputType HttpResponseMessage `
                                     -ErrorAction SilentlyContinue

        if ($resp -and $resp.RequestMessage.Headers.Authorization) {
            $token = $resp.RequestMessage.Headers.Authorization.Parameter
            if ($token) {
                $script:GACL_Registry[$TenantName] = $token
                Save-GACLState
                return $true
            }
        }
    } catch {
        # Silent fallback if session propagation isn't possible in this context
    }
    return $false
}

function Set-GACLContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TenantName,
        [string]$TenantId = '',
        [string]$ConnectScript = ''
    )

    Write-Host "  [GACL] Context Shift: $TenantName..." -ForegroundColor Cyan

    # 1. Check Registry for valid token
    if ($script:GACL_Registry.ContainsKey($TenantName)) {
        Write-Host "    [+] Utilizing Registry Token (Identity Sync)..." -ForegroundColor DarkCyan
        try {
            Connect-MgGraph -AccessToken (ConvertTo-SecureString $script:GACL_Registry[$TenantName] -AsPlainText -Force) -NoWelcome -ErrorAction Stop
            $script:GACL_CurrentTenant = $TenantName
            return $true
        } catch {
            Write-Host "    [-] Registry Session Expired/Invalid." -ForegroundColor Yellow
        }
    }

    # 2. Check current SDK context
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if ($null -ne $ctx -and ($null -eq $TenantId -or $ctx.TenantId -eq $TenantId)) {
        Write-Host "    [+] Retaining active SDK session ($($ctx.Account))..." -ForegroundColor DarkCyan
        $script:GACL_CurrentTenant = $TenantName
        # Intercept to ensure registry is primed
        $null = Invoke-GACLInterception -TenantName $TenantName
        return $true
    }

    # 3. Connect Script Fallback
    if (-not [string]::IsNullOrEmpty($ConnectScript) -and (Test-Path $ConnectScript)) {
        try {
            $signature = Get-AuthenticodeSignature -FilePath $ConnectScript -ErrorAction Stop
            if ($signature.Status -eq 'Valid') {
                Write-Host "    [+] Executing External Connection: $ConnectScript" -ForegroundColor DarkCyan
                . $ConnectScript
                $null = Invoke-GACLInterception -TenantName $TenantName
                $script:GACL_CurrentTenant = $TenantName
                return $true
            } else {
                Write-Warning "Security Block: External script '$ConnectScript' failed signature validation (Status: $($signature.Status)). Execution aborted."
                Write-Host "    [-] Falling back to manual authentication..." -ForegroundColor Yellow
            }
        } catch {
            Write-Warning "Security Block: Failed to validate external script signature. Error: $($_.Exception.Message)"
            Write-Host "    [-] Falling back to manual authentication..." -ForegroundColor Yellow
        }
    }

    # 4. Manual/Interactive Fallback
    Write-Host "    [!] Manual/Interactive Authentication required for '$TenantName'..." -ForegroundColor Yellow

    $tenantDesc = if ([string]::IsNullOrEmpty($TenantId)) { "the Common/Default endpoint" } else { "Tenant ID: $TenantId" }
    Write-Host "    [!] Action: A browser window will open for authentication to $tenantDesc." -ForegroundColor Cyan
    Write-Host "    [!] Note: Ensure you complete MFA if prompted." -ForegroundColor DarkCyan

    $params = @{
        Scopes    = @('Chat.Read.All', 'User.Read.All', 'AuditLog.Read.All', 'Organization.Read.All', 'offline_access')
        NoWelcome = $true
    }
    if (-not [string]::IsNullOrEmpty($TenantId)) {
        $params['TenantId'] = $TenantId
    }

    try {
        Connect-MgGraph @params -ErrorAction Stop
        $null = Invoke-GACLInterception -TenantName $TenantName
        $script:GACL_CurrentTenant = $TenantName
        return $true
    } catch {
        Write-Host "    [-] Interactive Authentication Failed: $_" -ForegroundColor Red
        return $false
    }
}

function Prime-GACL {
    [CmdletBinding()]
    param(
        [hashtable[]]$ManualTenants = @()
    )

    Write-Host "`n[?] SETUP: How many Tenants/Sessions do we need to prime for this scan?" -ForegroundColor Yellow
    $countStr = Read-Host "Number of Tenants"
    $count = 0
    $TenantsToPrime = [System.Collections.Generic.List[hashtable]]::new()

    if ([int]::TryParse($countStr, [ref]$count) -and $count -gt 0) {
        for ($i = 1; $i -le $count; $i++) {
            Write-Host "`n--- Configuring Tenant #$i ---" -ForegroundColor Gray
            $name   = Read-Host "  Display Name (e.g., 'PrimaryTenant')"
            $tid    = Read-Host "  Tenant ID / GUID (optional, press Enter for manual/interactive)"
            $script = Read-Host "  Connect Script Path (optional, press Enter for manual/interactive)"

            $TenantsToPrime.Add(@{
                Name          = $name
                TenantId      = $tid
                ConnectScript = $script
            })
        }
    } elseif ($null -ne $ManualTenants -and $ManualTenants.Count -gt 0) {
        try {
            foreach ($mt in $ManualTenants) {
                if ($mt -is [hashtable]) {
                    $TenantsToPrime.Add($mt)
                }
            }
        } catch {
            Write-Warning "Failed to parse ManualTenants: $_"
        }
    } else {
        Write-Host "  [-] No tenants provided to prime. Continuing with existing session." -ForegroundColor Gray
        return $null
    }

    Write-Host "`n[!] GACL PRIMING PHASE: Capturing Authenticated Sessions..." -ForegroundColor Cyan
    foreach ($t in $TenantsToPrime) {
        $null = Set-GACLContext -TenantName $t.Name -TenantId $t.TenantId -ConnectScript $t.ConnectScript
    }

    if ($TenantsToPrime.Count -ge 2) {
        Write-Host "`n[!] GACL VERIFICATION: Testing seamless 1->2->1 switching..." -ForegroundColor Magenta
        $t1 = $TenantsToPrime[0]
        $t2 = $TenantsToPrime[1]

        Write-Host "  [Step 1] Switching back to $($t1.Name)..." -ForegroundColor DarkGray
        $null = Set-GACLContext -TenantName $t1.Name -TenantId $t1.TenantId -ConnectScript $t1.ConnectScript

        Write-Host "  [Step 2] Switching to $($t2.Name)..." -ForegroundColor DarkGray
        $null = Set-GACLContext -TenantName $t2.Name -TenantId $t2.TenantId -ConnectScript $t2.ConnectScript

        Write-Host "  [Step 3] Verification: Switching back to $($t1.Name)..." -ForegroundColor DarkGray
        $null = Set-GACLContext -TenantName $t1.Name -TenantId $t1.TenantId -ConnectScript $t1.ConnectScript
    }

    return $TenantsToPrime
}

# --------------------------------------------------------------------------------
# Auto-Initialize on dot-source
# --------------------------------------------------------------------------------
Initialize-GACL