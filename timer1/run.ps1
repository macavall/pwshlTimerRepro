param($Timer)

# URLs for the HTTP triggers in this function app.
$jobInitiatorUrl   = $env:JOB_INITIATOR_URL
$scaAccessUrl      = $env:SCA_ACCESS_URL
$fakeSharePointUrl = $env:FAKE_SHAREPOINT_URL

if ([string]::IsNullOrWhiteSpace($jobInitiatorUrl)) {
    $jobInitiatorUrl = "http://localhost:7071/api/HttpTrigger1-MYWJobInitiator"
}
if ([string]::IsNullOrWhiteSpace($scaAccessUrl)) {
    $scaAccessUrl = "http://localhost:7071/api/HttpTrigger2-DryvIQ-SCA"
}
if ([string]::IsNullOrWhiteSpace($fakeSharePointUrl)) {
    $fakeSharePointUrl = "http://localhost:7071/api/fakesharepoint"
}

# Number of simultaneous requests to send to each HTTP trigger.
$RequestCount = 10

function New-MigrationItem {
    [CmdletBinding()]
    param([int] $Index)
    # Stand-in for a list item pulled from SharePoint.
    [PSCustomObject]@{
        Index                = $Index
        SourceEmail          = "user$Index@contoso.com"
        SourcePath           = "/MyDrive/Folder$Index"
        DestinationSite      = "https://contoso.sharepoint.com/sites/target"
        DestinationPath      = "/Shared Documents"
        DestinationUserEmail = "user$Index@contoso.com"
        MigrationType        = "sharepoint"
    }
}

# Build a batch of items to drive the parallel calls.
$items = 1..$RequestCount | ForEach-Object { New-MigrationItem -Index $_ }

# Stage 1: fire all fakesharepoint requests in parallel.
Write-Host "Sending $RequestCount parallel requests to fakesharepoint: $fakeSharePointUrl"
$items | ForEach-Object -Parallel {
    $Item = $_
    $body = [PSCustomObject]@{
        SourceEmail          = $Item.SourceEmail
        SourcePath           = $Item.SourcePath
        DestinationSite      = $Item.DestinationSite
        DestinationPath      = $Item.DestinationPath
        DestinationUserEmail = $Item.DestinationUserEmail
        MigrationType        = $Item.MigrationType
    } | ConvertTo-Json

    Invoke-RestMethod -Uri $using:fakeSharePointUrl -Method Post -ContentType 'application/json' -Body $body | Out-Null
} -ThrottleLimit $RequestCount

# Stage 2: fire all SCA requests in parallel.
Write-Host "Sending $RequestCount parallel requests to SCA: $scaAccessUrl"
$items | ForEach-Object -Parallel {
    $Item = $_
    $body = [PSCustomObject]@{
        Action      = "Add"
        SiteUrl     = $Item.DestinationSite
        OneDriveUPN = $Item.DestinationUserEmail
    } | ConvertTo-Json

    Invoke-RestMethod -Uri $using:scaAccessUrl -Method Post -ContentType 'application/json' -Body $body | Out-Null
} -ThrottleLimit $RequestCount

# Stage 3: fire all Job Initiator requests in parallel and capture responses.
Write-Host "Sending $RequestCount parallel requests to Job Initiator: $jobInitiatorUrl"
$results = $items | ForEach-Object -Parallel {
    $Item = $_
    $body = [PSCustomObject]@{
        SourceEmail      = $Item.SourceEmail
        SourcePath       = $Item.SourcePath
        DestinationSite  = $Item.DestinationSite
        DestinationPath  = $Item.DestinationPath
        DestinationEmail = $Item.DestinationUserEmail
        MigrationType    = $Item.MigrationType
        Region           = "myw"
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri $using:jobInitiatorUrl -Method Post -ContentType 'application/json' -Body $body

    $Item |
        Add-Member -NotePropertyName JobID  -NotePropertyValue $response.JobID  -PassThru |
        Add-Member -NotePropertyName Status -NotePropertyValue $response.Status -PassThru
} -ThrottleLimit $RequestCount

foreach ($r in $results) {
    Write-Host "Migration submitted. Index=$($r.Index) JobID=$($r.JobID) Status=$($r.Status)"
}
