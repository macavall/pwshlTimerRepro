using namespace System.Net

param($Request, $TriggerMetadata)

Write-Host "DryvIQ-SCA: received request."

$body = $Request.Body

# Simulated Site Collection Admin assignment. Replace with real SPO logic.
$responseBody = [PSCustomObject]@{
    Action      = $body.Action
    SiteUrl     = $body.SiteUrl
    OneDriveUPN = $body.OneDriveUPN
    Result      = "Success"
} | ConvertTo-Json

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = $responseBody
    Headers    = @{ "Content-Type" = "application/json" }
})
