<#
.SYNOPSIS
    Monitors and reports the sync/distribution status of all sensitivity label publishing policies in Microsoft Purview.

.DESCRIPTION
    This script connects to the Security & Compliance PowerShell endpoint using the
    ExchangeOnlineManagement module and retrieves all sensitivity label publishing policies
    along with their DistributionStatus property.

    It is designed to help Microsoft Purview / Information Protection administrators:
      - Confirm that policy changes have fully propagated across Microsoft 365 infrastructure.
      - Identify policies that are still in a Pending or failed state after a change.
      - Automate post-change validation as part of a change management or compliance workflow.

    The DistributionStatus field returns one of the following values:
      - Success   : Policy is fully distributed and live for all targeted users.
      - Pending   : Policy change is queued or propagation has not yet completed.
      - Failed    : An error occurred during distribution; immediate investigation recommended.

    This script is especially useful in regulated environments where you need to confirm
    that a sensitivity label policy is in force before closing a change management ticket
    or meeting a compliance deadline.

.NOTES
    Author:      Souhaiel Morhag
    Company:     MSEndpoint.com
    Blog:        https://msendpoint.com
    Academy:     https://app.msendpoint.com/academy
    LinkedIn:    https://linkedin.com/in/souhaiel-morhag
    GitHub:      https://github.com/Msendpoint
    License:     MIT

.PARAMETER UserPrincipalName
    The UPN of the admin account used to authenticate to Security & Compliance PowerShell.
    Must have Compliance Administrator or Global Administrator rights.

.PARAMETER ShowAllPolicies
    Switch parameter. When specified, the script outputs ALL policies regardless of status.
    By default, only policies that are NOT in a 'Success' state are highlighted.

.EXAMPLE
    # Run the script and show only non-successful (pending/failed) policies:
    .\Get-LabelPolicySyncStatus.ps1 -UserPrincipalName admin@yourtenant.onmicrosoft.com

.EXAMPLE
    # Run the script and show ALL policies including successfully synced ones:
    .\Get-LabelPolicySyncStatus.ps1 -UserPrincipalName admin@yourtenant.onmicrosoft.com -ShowAllPolicies
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = 'Enter the UPN of the compliance/global admin account.')]
    [ValidateNotNullOrEmpty()]
    [string]$UserPrincipalName,

    [Parameter(Mandatory = $false, HelpMessage = 'Show all policies, including successfully synced ones.')]
    [switch]$ShowAllPolicies
)

#region --- Module Check and Installation ---
Write-Host "[INFO] Checking for ExchangeOnlineManagement module..." -ForegroundColor Cyan

try {
    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Write-Host "[INFO] ExchangeOnlineManagement module not found. Installing for current user..." -ForegroundColor Yellow
        Install-Module -Name ExchangeOnlineManagement -Force -Scope CurrentUser -ErrorAction Stop
        Write-Host "[INFO] Module installed successfully." -ForegroundColor Green
    } else {
        Write-Host "[INFO] ExchangeOnlineManagement module is already installed." -ForegroundColor Green
    }
} catch {
    Write-Error "[ERROR] Failed to install ExchangeOnlineManagement module. Please install it manually. Details: $_"
    exit 1
}
#endregion

#region --- Connect to Security & Compliance PowerShell ---
Write-Host "[INFO] Connecting to Security & Compliance PowerShell as '$UserPrincipalName'..." -ForegroundColor Cyan

try {
    Connect-IPPSSession -UserPrincipalName $UserPrincipalName -ErrorAction Stop
    Write-Host "[INFO] Successfully connected to Security & Compliance PowerShell." -ForegroundColor Green
} catch {
    Write-Error "[ERROR] Failed to connect to Security & Compliance PowerShell. Details: $_"
    exit 1
}
#endregion

#region --- Retrieve Label Policies ---
Write-Host "[INFO] Retrieving all sensitivity label publishing policies..." -ForegroundColor Cyan

try {
    $allPolicies = Get-LabelPolicy -ErrorAction Stop | Select-Object -Property Name, Guid, DistributionStatus, LastModifiedTime, WhenCreated
} catch {
    Write-Error "[ERROR] Failed to retrieve label policies. Ensure the account has the required permissions. Details: $_"
    exit 1
}

if (-not $allPolicies) {
    Write-Warning "[WARN] No sensitivity label policies were found in this tenant."
    exit 0
}

Write-Host "[INFO] Total policies retrieved: $($allPolicies.Count)" -ForegroundColor Cyan
#endregion

#region --- Display All Policies (if requested) ---
if ($ShowAllPolicies) {
    Write-Host "`n=== ALL Sensitivity Label Policies ==="  -ForegroundColor White
    $allPolicies | Format-Table -AutoSize
}
#endregion

#region --- Identify Non-Successful Policies ---
Write-Host "`n[INFO] Checking for policies that are NOT in a 'Success' state..." -ForegroundColor Cyan

# Filter for any policy that has not fully synced
$pendingPolicies = $allPolicies | Where-Object { $_.DistributionStatus -ne 'Success' }

if ($pendingPolicies.Count -eq 0) {
    Write-Host "[SUCCESS] All sensitivity label policies have a DistributionStatus of 'Success'. No action required." -ForegroundColor Green
} else {
    Write-Warning "[WARN] The following $($pendingPolicies.Count) policy/policies have NOT completed distribution:"
    $pendingPolicies | Format-Table -AutoSize

    # Separate and call out any explicitly failed policies for immediate attention
    $failedPolicies = $pendingPolicies | Where-Object { $_.DistributionStatus -eq 'Failed' }
    if ($failedPolicies.Count -gt 0) {
        Write-Host "`n[CRITICAL] The following policies have a 'Failed' distribution status and require immediate investigation:" -ForegroundColor Red
        $failedPolicies | Format-Table -AutoSize
    }
}
#endregion

#region --- Summary Report ---
Write-Host "`n=== Sensitivity Label Policy Sync Status Summary ===" -ForegroundColor White
Write-Host "Total Policies      : $($allPolicies.Count)"
Write-Host "Successful          : $(($allPolicies | Where-Object { $_.DistributionStatus -eq 'Success' }).Count)" -ForegroundColor Green
Write-Host "Pending             : $(($allPolicies | Where-Object { $_.DistributionStatus -eq 'Pending' }).Count)" -ForegroundColor Yellow
Write-Host "Failed              : $(($allPolicies | Where-Object { $_.DistributionStatus -eq 'Failed' }).Count)" -ForegroundColor Red
Write-Host "Other/Unknown       : $(($allPolicies | Where-Object { $_.DistributionStatus -notin @('Success','Pending','Failed') }).Count)" -ForegroundColor Gray
Write-Host "===================================================`n" -ForegroundColor White
#endregion
