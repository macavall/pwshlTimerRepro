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

function New-MigrationItem {
    [CmdletBinding()]
    param()
    # Stand-in for a list item pulled from SharePoint.
    [PSCustomObject]@{
        SourceEmail          = "user@contoso.com"
        SourcePath           = "/MyDrive/Folder"
        DestinationSite      = "https://contoso.sharepoint.com/sites/target"
        DestinationPath      = "/Shared Documents"
        DestinationUserEmail = "user@contoso.com"
        MigrationType        = "sharepoint"
    }
}

function Invoke-FakeSharePoint {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)] $Item
    )
    process {
        $body = [PSCustomObject]@{
            SourceEmail          = $Item.SourceEmail
            SourcePath           = $Item.SourcePath
            DestinationSite      = $Item.DestinationSite
            DestinationPath      = $Item.DestinationPath
            DestinationUserEmail = $Item.DestinationUserEmail
            MigrationType        = $Item.MigrationType
        } | ConvertTo-Json

        Write-Host "Calling fakesharepoint HTTP trigger: $fakeSharePointUrl"
        Invoke-RestMethod -Uri $fakeSharePointUrl -Method Post -ContentType 'application/json' -Body $body | Out-Null

        # Pass the item down the pipeline to the next stage.
        $Item
    }
}

function Invoke-ScaAccess {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)] $Item
    )
    process {
        $body = [PSCustomObject]@{
            Action      = "Add"
            SiteUrl     = $Item.DestinationSite
            OneDriveUPN = $Item.DestinationUserEmail
        } | ConvertTo-Json

        Write-Host "Calling SCA HTTP trigger: $scaAccessUrl"
        Invoke-RestMethod -Uri $scaAccessUrl -Method Post -ContentType 'application/json' -Body $body | Out-Null

        # Pass the item down the pipeline to the next stage.
        $Item
    }
}

function Invoke-JobInitiator {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)] $Item
    )
    process {
        $body = [PSCustomObject]@{
            SourceEmail      = $Item.SourceEmail
            SourcePath       = $Item.SourcePath
            DestinationSite  = $Item.DestinationSite
            DestinationPath  = $Item.DestinationPath
            DestinationEmail = $Item.DestinationUserEmail
            MigrationType    = $Item.MigrationType
            Region           = "myw"
        } | ConvertTo-Json

        Write-Host "Calling Job Initiator HTTP trigger: $jobInitiatorUrl"
        $response = Invoke-RestMethod -Uri $jobInitiatorUrl -Method Post -ContentType 'application/json' -Body $body

        $Item |
            Add-Member -NotePropertyName JobID  -NotePropertyValue $response.JobID  -PassThru |
            Add-Member -NotePropertyName Status -NotePropertyValue $response.Status -PassThru
    }
}

# Pipeline-chained invocation: produce item -> fakesharepoint -> grant SCA -> initiate job.
New-MigrationItem |
    Invoke-FakeSharePoint |
    Invoke-ScaAccess |
    Invoke-JobInitiator |
    ForEach-Object {
        Write-Host "Migration submitted. JobID=$($_.JobID) Status=$($_.Status)"
    }
