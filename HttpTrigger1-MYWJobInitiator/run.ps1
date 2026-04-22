using namespace System.Net

param($Request, $TriggerMetadata)

Write-Host "MYWJobInitiator: received request."

$body = $Request.Body

# Simulated DryvIQ job creation. Replace with a real call to the DryvIQ API.
$jobID = [guid]::NewGuid().ToString()

$responseBody = [PSCustomObject]@{
    JobID           = $jobID
    SourceEmail     = $body.SourceEmail
    DestinationSite = $body.DestinationSite
    Status          = "Submitted"
} | ConvertTo-Json

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = $responseBody
    Headers    = @{ "Content-Type" = "application/json" }
})
